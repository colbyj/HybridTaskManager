import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
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
    readonly property int minRowHeight: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
    readonly property int rows: vertical ? 1
        : Math.max(1, Math.min(Plasmoid.configuration.maxRows, Math.floor(height / minRowHeight)))
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

        onCountChanged: labelTimer.restart()
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
            var item = menuItemComponent.createObject(groupMenu, {
                text: title,
                icon: tasksModel.data(idx, Qt.DecorationRole),
                checkable: true,
                checked: !!tasksModel.data(idx, R.IsActive)
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
        function add(props, action) {
            var item = menuItemComponent.createObject(contextMenu, props);
            if (action) item.clicked.connect(action);
            contextMenu.addMenuItem(item);
        }
        add({ text: d(R.AppName) || d(Qt.DisplayRole), section: true });
        if (d(R.CanLaunchNewInstance) || isLauncher) {
            add({ text: isLauncher ? "Start" : "Open New Window", icon: "window-new" },
                () => isLauncher ? tasksModel.requestActivate(idx) : tasksModel.requestNewInstance(idx));
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
            }
        }
    }
}
