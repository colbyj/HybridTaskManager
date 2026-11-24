import QtQuick
import QtQuick.Layouts
import QtCore
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.workspace.dbus as DBus
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

import "../code/labels.js" as Labels

PlasmoidItem {
    id: root

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    preferredRepresentation: fullRepresentation
    Plasmoid.constraintHints: Plasmoid.CanFillArea

    Layout.fillWidth: !vertical
    Layout.fillHeight: vertical
    // Ask the panel for enough room to fit every button across our rows.
    Layout.preferredWidth: vertical ? -1 : preferredLength
    Layout.preferredHeight: vertical ? preferredLength : -1
    Layout.minimumWidth: vertical ? 0 : rowHeight
    Layout.minimumHeight: vertical ? rowHeight * 3 : 0

    // ---- sizing -----------------------------------------------------------
    // rows setting: 0 = automatic (as many rows as fit with comfortably sized
    // icons), otherwise a fixed count (reduced if the panel is too thin).
    readonly property int minRowHeight: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
    readonly property int autoRowHeight: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing * 2
    readonly property int rows: vertical ? 1
        : Plasmoid.configuration.rows > 0
          ? Math.max(1, Math.min(Plasmoid.configuration.rows, Math.floor(height / minRowHeight)))
          : Math.max(1, Math.floor(height / autoRowHeight))
    readonly property int rowHeight: vertical ? Kirigami.Units.iconSizes.medium : Math.floor(height / rows)
    readonly property int iconSize: Math.min(Kirigami.Units.iconSizes.medium,
                                             rowHeight - Kirigami.Units.smallSpacing * 2)
    readonly property int maxLabelWidth: Plasmoid.configuration.maxLabelWidth * Kirigami.Units.gridUnit

    // Sum of button lengths spread over the rows, plus the widest button as
    // slack because rows can't be packed perfectly.
    property int preferredLength: rowHeight
    Timer { id: sizeTimer; interval: 50; onTriggered: root.updatePreferredLength() }
    function updatePreferredLength() {
        var total = 0, widest = 0;
        for (var i = 0; i < repeater.count; i++) {
            var it = repeater.itemAt(i);
            if (!it) continue;
            var len = root.vertical ? it.height : it.width;
            total += len; widest = Math.max(widest, len);
        }
        preferredLength = Math.max(rowHeight, Math.ceil(total / rows) + (rows > 1 ? widest : 0));
    }
    onRowsChanged: sizeTimer.restart()

    // ---- the window list ---------------------------------------------------
    TaskManager.VirtualDesktopInfo { id: virtualDesktopInfo }
    TaskManager.ActivityInfo { id: activityInfo }

    readonly property alias tasks: tasksModel
    TaskManager.TasksModel {
        id: tasksModel

        groupMode: TaskManager.TasksModel.GroupApplications
        groupInline: false
        groupingWindowTasksThreshold: -1
        sortMode: TaskManager.TasksModel.SortManual
        separateLaunchers: false
        launchInPlace: true
        hideActivatedLaunchers: true

        filterByVirtualDesktop: Plasmoid.configuration.showOnlyCurrentDesktop
        filterByActivity: true
        filterByScreen: false
        virtualDesktop: virtualDesktopInfo.currentDesktop
        activity: activityInfo.currentActivity
        screenGeometry: Plasmoid.containment.screenGeometry

        // Persist launchers and the "don't group" list in our own config.
        onLauncherListChanged: if (root.loaded) Plasmoid.configuration.launchers = launcherList
        onGroupingAppIdBlacklistChanged: if (root.loaded) Plasmoid.configuration.groupingAppIdBlacklist = groupingAppIdBlacklist
        onGroupingLauncherUrlBlacklistChanged: if (root.loaded) Plasmoid.configuration.groupingLauncherUrlBlacklist = groupingLauncherUrlBlacklist

        onCountChanged: { labelTimer.restart(); adjacencyTimer.restart(); }
        onDataChanged: labelTimer.restart()
    }

    // Pick up config changes made from outside (e.g. scripting, other instances).
    Connections {
        target: Plasmoid.configuration
        function onLaunchersChanged() {
            if (String(tasksModel.launcherList) !== String(Plasmoid.configuration.launchers))
                tasksModel.launcherList = Plasmoid.configuration.launchers;
        }
        function onGroupingAppIdBlacklistChanged() {
            if (String(tasksModel.groupingAppIdBlacklist) !== String(Plasmoid.configuration.groupingAppIdBlacklist))
                tasksModel.groupingAppIdBlacklist = Plasmoid.configuration.groupingAppIdBlacklist;
        }
        function onGroupingLauncherUrlBlacklistChanged() {
            if (String(tasksModel.groupingLauncherUrlBlacklist) !== String(Plasmoid.configuration.groupingLauncherUrlBlacklist))
                tasksModel.groupingLauncherUrlBlacklist = Plasmoid.configuration.groupingLauncherUrlBlacklist;
        }
    }

    property bool loaded: false
    Component.onCompleted: {
        tasksModel.launcherList = Plasmoid.configuration.launchers;
        tasksModel.groupingAppIdBlacklist = Plasmoid.configuration.groupingAppIdBlacklist;
        tasksModel.groupingLauncherUrlBlacklist = Plasmoid.configuration.groupingLauncherUrlBlacklist;
        loaded = true;
        computeLabels();
    }

    // ---- labels -------------------------------------------------------------
    // Map from window id -> short label. Only windows of ungrouped apps that
    // have more than one window open get an entry.
    property var labels: ({})
    Timer { id: labelTimer; interval: 100; onTriggered: root.computeLabels() }

    function computeLabels() {
        var R = TaskManager.AbstractTasksModel;
        var byApp = {};
        for (var row = 0; row < tasksModel.count; row++) {
            var idx = tasksModel.makeModelIndex(row);
            if (!tasksModel.data(idx, R.IsWindow) || tasksModel.data(idx, R.IsGroupParent)) continue;
            if (tasksModel.data(idx, R.IsGroupable)) continue;
            var appId = tasksModel.data(idx, R.AppId) || "";
            var ids = tasksModel.data(idx, R.WinIdList) || [];
            if (!ids.length) continue;
            (byApp[appId] = byApp[appId] || []).push({
                id: String(ids[0]),
                title: Labels.cleanTitle(tasksModel.data(idx, Qt.DisplayRole), tasksModel.data(idx, R.AppName))
            });
        }
        var out = {};
        for (var app in byApp) {
            var wins = byApp[app];
            if (wins.length < 2) continue;
            var ls = Labels.distinguish(wins.map(w => w.title));
            wins.forEach((w, i) => out[w.id] = ls[i]);
        }
        labels = out;
    }

    // ---- running helper commands ---------------------------------------------
    readonly property string codeDir: Qt.resolvedUrl("../code/").toString().replace(/^file:\/\//, "")
    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function runCommand(args) {
        // Unique suffix so the executable engine runs it even if repeated.
        exec.connectSource("setsid -f " + args.map(shq).join(" ") + " >/dev/null 2>&1 #" + Date.now());
    }
    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (source) => disconnectSource(source)
    }

    // Middle-click / "Open New Window". Dolphin restores its last session when
    // started without a folder, which looks like a copy of an existing window,
    // so give it the home folder explicitly.
    function newInstance(idx) {
        var appId = tasksModel.data(idx, TaskManager.AbstractTasksModel.AppId) || "";
        if (appId === "org.kde.dolphin") runCommand(["dolphin", "--new-window",
            StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace(/^file:\/\//, "")]);
        else tasksModel.requestNewInstance(idx);
    }

    // ---- keep an app's windows next to each other ------------------------------
    // New windows are appended at the end of the bar; move each one back next
    // to the other windows (or the pinned launcher) of the same app.
    Timer { id: adjacencyTimer; interval: 150; onTriggered: root.enforceAdjacency() }
    function rowKey(r) {
        var idx = tasksModel.makeModelIndex(r);
        var R = TaskManager.AbstractTasksModel;
        return String(tasksModel.data(idx, R.AppId) || tasksModel.data(idx, R.LauncherUrlWithoutIcon) || ("row" + r));
    }
    function enforceAdjacency() {
        for (var guard = 0; guard < 100; guard++) {
            var keys = [];
            for (var r = 0; r < tasksModel.count; r++) keys.push(rowKey(r));
            var moved = false;
            for (r = 1; r < keys.length && !moved; r++) {
                var f = keys.indexOf(keys[r]);
                if (f === r || keys[r - 1] === keys[r]) continue;
                var e = f;
                while (e + 1 < keys.length && keys[e + 1] === keys[r]) e++;
                if (r > e + 1) { tasksModel.move(r, e + 1); moved = true; }
            }
            if (!moved) return;
        }
    }

    // ---- KWin window highlight ------------------------------------------------
    function highlightWindows(ids) {
        DBus.SessionBus.asyncCall({
            service: "org.kde.KWin.HighlightWindow",
            path: "/org/kde/KWin/HighlightWindow",
            iface: "org.kde.KWin.HighlightWindow",
            member: "highlightWindows",
            arguments: [ids.map(String)],
            signature: "(as)"
        });
    }

    // ---- menus --------------------------------------------------------------
    Component {
        id: menuItemComponent
        PlasmaExtras.MenuItem {}
    }
    Component {
        id: subMenuComponent
        PlasmaExtras.Menu {}
    }
    property var subMenus: []

    // Text-only list of a grouped app's windows.
    PlasmaExtras.Menu {
        id: groupMenu
        placement: PlasmaExtras.Menu.TopPosedLeftAlignedPopup
    }

    function openGroupMenu(row, visualParent) {
        var R = TaskManager.AbstractTasksModel;
        var parentIdx = tasksModel.makeModelIndex(row);
        var appName = tasksModel.data(parentIdx, R.AppName);
        groupMenu.clearMenuItems();
        var n = tasksModel.rowCount(parentIdx);
        for (var c = 0; c < n; c++) {
            const idx = tasksModel.makeModelIndex(row, c);
            var title = Labels.cleanTitle(tasksModel.data(idx, Qt.DisplayRole), appName);
            if (tasksModel.data(idx, R.IsMinimized)) title += "  (minimized)";
            if (tasksModel.data(idx, R.IsActive)) title = "● " + title;
            var item = menuItemComponent.createObject(groupMenu, {
                text: title,
                icon: tasksModel.data(idx, Qt.DecorationRole)
            });
            item.clicked.connect(() => tasksModel.requestActivate(idx));
            groupMenu.addMenuItem(item);
        }
        groupMenu.visualParent = visualParent;
        groupMenu.openRelative();
    }

    PlasmaExtras.Menu {
        id: contextMenu
        placement: PlasmaExtras.Menu.TopPosedLeftAlignedPopup
    }

    function openContextMenu(row, visualParent) {
        var R = TaskManager.AbstractTasksModel;
        var idx = tasksModel.makeModelIndex(row);
        var d = r => tasksModel.data(idx, r);
        var isLauncher = !!d(R.IsLauncher);
        var url = d(R.LauncherUrlWithoutIcon);
        var pinned = url && tasksModel.launcherPosition(url) !== -1;

        contextMenu.clearMenuItems();
        subMenus.forEach(m => m.destroy());
        subMenus = [];
        function addTo(menu, props, action) {
            var item = menuItemComponent.createObject(menu, props);
            if (action) item.clicked.connect(action);
            menu.addMenuItem(item);
            return item;
        }
        function add(props, action) { return addTo(contextMenu, props, action); }
        function addSubMenu(props) {
            var item = add(props);
            var sub = subMenuComponent.createObject(contextMenu, { visualParent: item.action });
            subMenus.push(sub);
            return sub;
        }
        add({ text: d(R.AppName) || d(Qt.DisplayRole), section: true });
        if (d(R.CanLaunchNewInstance) || isLauncher) {
            add({ text: isLauncher ? "Start" : "Open New Window", icon: "window-new" },
                () => isLauncher ? tasksModel.requestActivate(idx) : root.newInstance(idx));
        }
        if (!isLauncher) {
            add({ text: "Allow this program to be grouped", checkable: true, checked: !!d(R.IsGroupable) },
                () => tasksModel.requestToggleGrouping(idx));
        }
        if (url) {
            add({ text: pinned ? "Unpin from Window Bar" : "Pin to Window Bar", icon: pinned ? "window-unpin" : "window-pin" },
                () => pinned ? tasksModel.requestRemoveLauncher(url) : tasksModel.requestAddLauncher(url));
        }
        if (!isLauncher) {
            add({ separator: true });

            // Move to Desktop
            if (d(R.IsVirtualDesktopsChangeable)) {
                var deskMenu = addSubMenu({ text: "Move to Desktop", icon: "virtual-desktops" });
                var onDesks = d(R.VirtualDesktops) || [];
                var onAll = !!d(R.IsOnAllVirtualDesktops);
                addTo(deskMenu, { text: "All Desktops", checkable: true, checked: onAll },
                      () => tasksModel.requestVirtualDesktops(idx, []));
                addTo(deskMenu, { separator: true });
                var ids = virtualDesktopInfo.desktopIds, names = virtualDesktopInfo.desktopNames;
                for (var i = 0; i < ids.length; i++) {
                    const id = ids[i];
                    addTo(deskMenu, { text: (i + 1) + "  " + names[i], checkable: true,
                                      checked: !onAll && onDesks.indexOf(id) !== -1 },
                          () => tasksModel.requestVirtualDesktops(idx, [id]));
                }
                addTo(deskMenu, { separator: true });
                addTo(deskMenu, { text: "New Desktop", icon: "list-add" },
                      () => tasksModel.requestNewVirtualDesktop(idx));
            }

            // Move to Monitor
            var screens = Qt.application.screens;
            if (screens.length > 1) {
                var winIds = [];
                if (d(R.IsGroupParent)) {
                    for (var c = 0; c < tasksModel.rowCount(idx); c++)
                        winIds = winIds.concat(tasksModel.data(tasksModel.makeModelIndex(row, c), R.WinIdList) || []);
                } else {
                    winIds = d(R.WinIdList) || [];
                }
                winIds = winIds.map(String);
                var geo = d(R.ScreenGeometry);
                var monMenu = addSubMenu({ text: "Move to Monitor", icon: "monitor" });
                var sorted = Array.from(screens).sort((a, b) => a.virtualX - b.virtualX || a.virtualY - b.virtualY);
                sorted.forEach(scr => {
                    const name = scr.name;
                    var here = geo && geo.x === scr.virtualX && geo.y === scr.virtualY;
                    addTo(monMenu, { text: name + "  (" + scr.width + "×" + scr.height + ")",
                                     checkable: true, checked: !d(R.IsGroupParent) && here },
                          () => root.runCommand(["python3", "-I", root.codeDir + "kwin.py", "to-screen", name].concat(winIds)));
                });
            }

            add({ separator: true });
            if (!d(R.IsGroupParent)) {
                add({ text: d(R.IsMinimized) ? "Restore" : "Minimize", icon: "window-minimize" },
                    () => tasksModel.requestToggleMinimized(idx));
            }
            add({ text: d(R.IsGroupParent) ? "Close All" : "Close", icon: "window-close" },
                () => tasksModel.requestClose(idx));
        }
        contextMenu.visualParent = visualParent;
        contextMenu.openRelative();
    }

    // ---- layout -------------------------------------------------------------
    Flow {
        id: flow
        anchors.fill: parent
        flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight
        clip: true

        Repeater {
            id: repeater
            model: tasksModel
            onItemAdded: (i, item) => { item.widthChanged.connect(sizeTimer.restart); sizeTimer.restart(); }
            onItemRemoved: sizeTimer.restart()
            delegate: Task {
                tasksModel: root.tasks
                rowHeight: root.rowHeight
                iconSize: root.iconSize
                maxLabelWidth: root.maxLabelWidth
                vertical: root.vertical
                labels: root.labels
                onGroupMenuRequested: (row, item) => root.openGroupMenu(row, item)
                onContextMenuRequested: (row, item) => root.openContextMenu(row, item)
                onHighlightRequested: ids => root.highlightWindows(ids)
                onNewInstanceRequested: row => root.newInstance(root.tasks.makeModelIndex(row))
            }
        }
    }
}
