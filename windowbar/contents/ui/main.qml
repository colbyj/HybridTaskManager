import QtQuick
import QtQuick.Layouts
import QtCore
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.components as PC3
import org.kde.ksvg as KSvg
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.workspace.dbus as DBus
import org.kde.plasma.private.volume as PlasmaPa
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
    readonly property int minLabelWidth: Plasmoid.configuration.minButtonWidth
    readonly property int maxLabelWidth: Math.max(minLabelWidth, Plasmoid.configuration.maxButtonWidth)

    // ---- layout pass ------------------------------------------------------------
    // Decides, in order, until everything fits:
    //   1. every button at its natural width
    //   2. labelled buttons capped at a shared width, as wide as still fits --
    //      short labels keep their full text, long ones shorten (down to the minimum)
    //   3. minimized windows collapsed into one stub per app (if enabled)
    //   4. the rightmost buttons moved into a "+N" list
    property int preferredLength: rowHeight
    property int labelCap: 100000     // max width for labelled buttons
    property var ownHidden: []      // per row: collapsed into a stub
    property var stubs: ({})        // row -> [rows collapsed after it]
    property var overflowRows: []   // rows moved into "+N"
    readonly property int overflowButtonWidth: Math.round(rowHeight * 1.4)

    Timer { id: layoutTimer; interval: 30; onTriggered: root.computeLayout() }
    onWidthChanged: layoutTimer.restart()
    onHeightChanged: layoutTimer.restart()
    onRowsChanged: layoutTimer.restart()

    function computeLayout() {
        var R = TaskManager.AbstractTasksModel;
        var n = repeater.count;
        var items = [], keys = [];
        for (var i = 0; i < n; i++) {
            var it = repeater.itemAt(i);
            if (!it) { layoutTimer.restart(); return; }   // delegates still being created
            items.push(it);
            keys.push(rowKey(i));
        }

        // Minimized windows of ungrouped apps, per cluster -> stub on the cluster's last row.
        function collapsePlan() {
            var hidden = [], st = {};
            for (var i = 0; i < n; i++) hidden.push(false);
            for (i = 0; i < n; ) {
                var e = i;
                while (e + 1 < n && keys[e + 1] === keys[i]) e++;
                var mins = [];
                for (var r = i; r <= e; r++) {
                    var idx = tasksModel.makeModelIndex(r);
                    if (tasksModel.data(idx, R.IsWindow) && !tasksModel.data(idx, R.IsGroupParent)
                        && !tasksModel.data(idx, R.IsGroupable) && tasksModel.data(idx, R.IsMinimized)) {
                        mins.push(r);
                        hidden[r] = true;
                    }
                }
                if (mins.length) st[e] = mins;
                i = e + 1;
            }
            return { hidden: hidden, stubs: st };
        }
        var none = { hidden: items.map(() => false), stubs: {} };

        function widths(plan, cap) {
            return items.map((it, i) => (plan.hidden[i] ? 0 : Math.max(it.compactWidth, Math.min(it.naturalWidth, cap)))
                                        + (plan.stubs[i] ? it.stubWidth : 0));
        }
        // Largest cap at which the plan fits, or -1 if even the minimum doesn't.
        function fitCap(plan, capacity) {
            if (total(widths(plan, 100000)) <= capacity) return 100000;
            if (total(widths(plan, 0)) > capacity) return -1;
            var lo = 0, hi = maxLabelWidth;
            while (hi - lo > 1) {
                var mid = Math.floor((lo + hi) / 2);
                if (total(widths(plan, mid)) <= capacity) lo = mid; else hi = mid;
            }
            return lo;
        }
        function total(ws) { return ws.reduce((a, b) => a + b, 0); }

        var mode = Plasmoid.configuration.collapseMinimized;   // 0 off, 1 when full, 2 always
        var basePlan = mode === 2 ? collapsePlan() : none;

        // What we ask the panel for: natural widths spread over our rows.
        var natural = widths(basePlan, 100000);
        var widest = Math.max(0, ...natural);
        preferredLength = Math.max(rowHeight, Math.ceil(total(natural) / rows) + (rows > 1 ? widest : 0));

        // What we actually have. Rows can't be packed perfectly, so allow for
        // one wasted button-width per extra row.
        var avail = (vertical ? flow.height : flow.width);
        var capacity = rows * avail - (rows > 1 ? (rows - 1) * widest : 0);

        var plan = basePlan;
        var cap = fitCap(plan, capacity);
        if (cap < 0 && mode === 1) { plan = collapsePlan(); cap = fitCap(plan, capacity); }
        var ws = widths(plan, Math.max(0, cap));

        var overflow = [];
        if (total(ws) > capacity) {
            var acc = 0, limit = capacity - overflowButtonWidth;
            for (i = 0; i < n; i++) {
                if (overflow.length || acc + ws[i] > limit) overflow.push(i);
                else acc += ws[i];
            }
        }

        labelCap = Math.max(0, cap);
        ownHidden = plan.hidden;
        stubs = plan.stubs;
        overflowRows = overflow;
    }

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

        onCountChanged: { labelTimer.restart(); adjacencyTimer.restart(); layoutTimer.restart(); }
        onDataChanged: { labelTimer.restart(); layoutTimer.restart(); }
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
                title: Labels.cleanTitle(tasksModel.data(idx, Qt.DisplayRole), tasksModel.data(idx, R.AppName)),
                screen: screenName(tasksModel.data(idx, R.ScreenGeometry))
            });
        }
        var out = {};
        for (var app in byApp) {
            var wins = byApp[app];
            if (wins.length < 2) continue;
            var ls = Labels.distinguish(wins.map(w => w.title));
            ls = Labels.disambiguate(ls, wins.map(w => w.screen));
            wins.forEach((w, i) => out[w.id] = ls[i]);
        }
        labels = out;
        layoutTimer.restart();
    }

    function screenName(rect) {
        if (!rect) return "";
        var ss = Qt.application.screens;
        for (var i = 0; i < ss.length; i++)
            if (ss[i].virtualX === rect.x && ss[i].virtualY === rect.y) return ss[i].name;
        return "";
    }

    // ---- activating windows -----------------------------------------------------
    // Clicking a window on the bar focuses it (or minimizes it if it's already
    // focused). On another monitor a focus change is easy to miss, so briefly
    // highlight the window -- everything else dims for a moment.
    function activateIndex(idx, toggleIfActive) {
        var R = TaskManager.AbstractTasksModel;
        if (toggleIfActive && tasksModel.data(idx, R.IsActive) && !tasksModel.data(idx, R.IsMinimized)) {
            highlightWindows([]);
            tasksModel.requestToggleMinimized(idx);
            return;
        }
        tasksModel.requestActivate(idx);
        var mode = Plasmoid.configuration.focusFlash;   // 0 off, 1 other monitors, 2 always
        var geo = tasksModel.data(idx, R.ScreenGeometry);
        var mine = Plasmoid.containment.screenGeometry;
        var elsewhere = !geo || !mine || geo.x !== mine.x || geo.y !== mine.y;
        if (mode === 2 || (mode === 1 && elsewhere)) {
            highlightWindows(tasksModel.data(idx, R.WinIdList) || []);
            flashTimer.restart();
        } else {
            highlightWindows([]);
        }
    }
    Timer { id: flashTimer; interval: 700; onTriggered: root.highlightWindows([]) }

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

    // ---- drag to reorder ------------------------------------------------------
    // Rules: a window dragged within its app's cluster reorders inside the
    // cluster; dragged outside it, the whole cluster moves. Drop targets inside
    // another app's cluster snap to that cluster's edge so clusters never mix.
    function clusterAt(keys, i) {
        var s = i, e = i;
        while (s > 0 && keys[s - 1] === keys[i]) s--;
        while (e + 1 < keys.length && keys[e + 1] === keys[i]) e++;
        return [s, e];
    }
    // After a move, wait for the layout to catch up before deciding again;
    // otherwise stale positions cause double moves.
    property bool movePending: false
    property real pendingX: 0
    Timer { id: moveSettle; interval: 120; onTriggered: root.movePending = false }
    // Once the whole cluster has moved, keep moving the cluster for the rest
    // of the drag instead of reordering inside it.
    property bool clusterLocked: false
    function didMove(item) { movePending = true; pendingX = item.x; moveSettle.restart(); }

    function dragMoved(item, x, y, pressX) {
        if (movePending && item.x === pendingX) return;
        movePending = false;
        if (rows > 1 || vertical) return dragMovedGrid(item, x, y);

        // d = how far the dragged button "wants" to be from where it sits.
        var d = x - pressX;
        var keys = [];
        for (var r = 0; r < tasksModel.count; r++) keys.push(rowKey(r));
        var from = item.index;
        var own = clusterAt(keys, from);
        var it = i => repeater.itemAt(i);
        var spanCenter = (s, e) => (it(s).x + it(e).x + it(e).width) / 2;
        var cursor = item.mapToItem(flow, x, y).x;
        var over = i => cursor >= it(i).x && cursor < it(i).x + it(i).width;
        // A little extra distance before a whole cluster jumps.
        var slack = Kirigami.Units.smallSpacing * 2;

        if (d > 0) {
            if (from < own[1] && !clusterLocked) {
                // Reorder within the cluster: the button's right edge passes the
                // next sibling's middle, and the cursor is over that sibling.
                var n = from + 1;
                if (item.x + item.width + d > spanCenter(n, n) && over(n)) { tasksModel.move(from, n); didMove(item); }
            } else if (own[1] + 1 < keys.length) {
                // Move the whole cluster right past the next cluster.
                var next = clusterAt(keys, own[1] + 1);
                if (it(own[1]).x + it(own[1]).width + d > spanCenter(next[0], next[1]) + slack) {
                    for (var i = 0; i <= own[1] - own[0]; i++) tasksModel.move(own[0], next[1]);
                    didMove(item);
                    clusterLocked = true;
                }
            }
        } else if (d < 0) {
            if (from > own[0] && !clusterLocked) {
                n = from - 1;
                if (item.x + d < spanCenter(n, n) && over(n)) { tasksModel.move(from, n); didMove(item); }
            } else if (own[0] - 1 >= 0) {
                var prev = clusterAt(keys, own[0] - 1);
                if (it(own[0]).x + d < spanCenter(prev[0], prev[1]) - slack) {
                    for (i = 0; i <= own[1] - own[0]; i++) tasksModel.move(own[0] + i, prev[0] + i);
                    didMove(item);
                    clusterLocked = true;
                }
            }
        }
    }

    // Multi-row / vertical fallback: act on the button under the cursor.
    function dragMovedGrid(item, x, y) {
        var p = item.mapToItem(flow, x, y);
        var target = flow.childAt(p.x, p.y);
        if (!target || target === item || target.index === undefined) return;
        var from = item.index, t = target.index;
        var keys = [];
        for (var r = 0; r < tasksModel.count; r++) keys.push(rowKey(r));
        var own = clusterAt(keys, from);
        if (t >= own[0] && t <= own[1]) { tasksModel.move(from, t); didMove(item); return; }
        var other = clusterAt(keys, t);
        var n = own[1] - own[0] + 1;
        if (t < own[0]) { for (var i = 0; i < n; i++) tasksModel.move(own[0] + i, other[0] + i); }
        else { for (i = 0; i < n; i++) tasksModel.move(own[0], other[1]); }
        didMove(item);
    }

    function dragFinished() {
        clusterLocked = false;
        tasksModel.syncLaunchers();   // persist pinned-launcher order
    }

    // ---- audio --------------------------------------------------------------------
    // PulseAudio/PipeWire streams, matched to windows by process id (or by
    // name as a fallback). All windows of a process share its streams.
    property var audioByPid: ({})
    property var audioByName: ({})
    Timer { id: audioTimer; interval: 50; onTriggered: root.rebuildAudio() }

    Instantiator {
        id: audioStreams
        model: PlasmaPa.PulseObjectFilterModel {
            filters: [ { role: "VirtualStream", value: false } ]
            sourceModel: PlasmaPa.SinkInputModel {}
        }
        delegate: QtObject {
            required property var model
            readonly property int pid: parseInt(model.Client?.properties["application.process.id"] ?? "0")
            readonly property string binary: model.Client?.properties["application.process.binary"] ?? ""
            readonly property string appName: model.Client?.properties["application.name"] ?? ""
            readonly property bool muted: !!model.Muted
            readonly property bool corked: !!model.Corked
            onMutedChanged: audioTimer.restart()
            onCorkedChanged: audioTimer.restart()
            function setMuted(m) { model.Muted = m; }
        }
        onObjectAdded: audioTimer.restart()
        onObjectRemoved: audioTimer.restart()
    }

    function rebuildAudio() {
        var byPid = {}, byName = {};
        function add(map, key, s) {
            if (!key) return;
            var e = map[key] || (map[key] = { playing: false, muted: true, streams: [] });
            e.playing = e.playing || !s.corked;
            e.muted = e.muted && s.muted;
            e.streams.push(s);
        }
        for (var i = 0; i < audioStreams.count; i++) {
            var s = audioStreams.objectAt(i);
            if (!s || s.binary === "plasmashell") continue;   // notification sounds
            add(byPid, s.pid, s);
            add(byName, s.binary.toLowerCase(), s);
            add(byName, s.appName.toLowerCase(), s);
        }
        audioByPid = byPid;
        audioByName = byName;
    }
    function audioFor(pid, appId) {
        if (pid && audioByPid[pid]) return audioByPid[pid];
        var id = String(appId || "").toLowerCase();
        return audioByName[id] || audioByName[id.split(".").pop()] || audioByName[id.split("_")[0]] || null;
    }
    function toggleMute(pid, appId) {
        var a = audioFor(pid, appId);
        if (!a) return;
        var mute = !a.muted;
        a.streams.forEach(s => s.setMuted(mute));
    }

    // ---- badges and progress (Unity launcher API) -------------------------------------
    // Apps broadcast com.canonical.Unity.LauncherEntry.Update(app_uri, props);
    // badges.py turns that into (app_uri, count or 0, progress or -1).
    property var badges: ({})
    function desktopId(s) {
        return String(s || "").replace(/^application:\/\//, "").replace(/^applications:/, "")
                              .replace(/\.desktop$/, "").toLowerCase();
    }
    function updateBadge(appUri, count, progress) {
        var next = Object.assign({}, badges);
        next[desktopId(appUri)] = { count: count, progress: progress };
        badges = next;
    }
    function badgeFor(launcherUrl, appId) {
        return badges[desktopId(launcherUrl)] || badges[desktopId(appId)] || null;
    }
    // code/badges.py listens for the Unity signal from any app and re-emits it
    // from a fixed name we can watch. It's started here and exits with plasmashell.
    P5Support.DataSource {
        id: badgeBridge
        engine: "executable"
        Component.onCompleted: connectSource("exec python3 -I " + root.shq(root.codeDir + "badges.py"))
    }
    DBus.SignalWatcher {
        service: "local.windowbar.Badges"
        path: "/Badges"
        iface: "local.windowbar.Badges"
        function dbusUpdate(appUri, count, progress) { root.updateBadge(appUri, count, progress); }
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

    // Text list of windows (WindowList.qml): a grouped app's windows, an app's
    // collapsed minimized windows, or the "+N" overflow.
    property string listKey: ""
    PlasmaCore.Dialog {
        id: listDialog
        location: Plasmoid.location
        type: PlasmaCore.Dialog.PopupMenu
        hideOnWindowDeactivate: true
        flags: Qt.WindowStaysOnTopHint
        backgroundHints: PlasmaCore.Dialog.SolidBackground
        onVisibleChanged: if (!visible) { root.highlightWindows([]); root.listKey = ""; }

        mainItem: WindowList {
            id: windowList
            tasksModel: root.tasks
            onActivateRequested: idx => { listDialog.visible = false; root.activateIndex(idx, false); }
            onHighlightRequested: ids => root.highlightWindows(ids)
        }
    }

    function openWindowList(key, entries, title, headers, visualParent) {
        if (listDialog.visible && listKey === key) { listDialog.visible = false; return; }
        listKey = key;
        windowList.entries = entries;
        windowList.title = title;
        windowList.showHeaders = headers;
        windowList.updateTitleWidth();
        listDialog.visualParent = visualParent;
        listDialog.visible = true;
    }
    function appNameOf(row) {
        return tasksModel.data(tasksModel.makeModelIndex(row), TaskManager.AbstractTasksModel.AppName) || "";
    }
    function entriesFor(row) {
        var idx = tasksModel.makeModelIndex(row), app = appNameOf(row);
        if (!tasksModel.data(idx, TaskManager.AbstractTasksModel.IsGroupParent)) return [{ row: row, child: -1, app: app }];
        var out = [];
        for (var c = 0; c < tasksModel.rowCount(idx); c++) out.push({ row: row, child: c, app: app });
        return out;
    }

    function openGroupMenu(row, visualParent) {
        openWindowList("group:" + row, entriesFor(row), appNameOf(row), false, visualParent);
    }
    function openStub(rows, visualParent) {
        if (rows.length === 1) { activateIndex(tasksModel.makeModelIndex(rows[0]), false); return; }
        openWindowList("stub:" + rows.join(","), rows.map(r => ({ row: r, child: -1, app: appNameOf(r) })),
                       appNameOf(rows[0]) + " — minimized", false, visualParent);
    }
    function openOverflow(visualParent) {
        var entries = [];
        overflowRows.forEach(r => {
            if (!ownHidden[r]) entries = entries.concat(entriesFor(r));
            (stubs[r] || []).forEach(m => entries.push({ row: m, child: -1, app: appNameOf(m) }));
        });
        openWindowList("overflow", entries, "", true, visualParent);
    }

    // Rows shift when windows open or close, so close rather than show the
    // wrong windows.
    Connections {
        target: tasksModel
        function onCountChanged() { listDialog.visible = false; }
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
            onItemAdded: (i, item) => {
                item.naturalWidthChanged.connect(layoutTimer.restart);
                layoutTimer.restart();
            }
            onItemRemoved: layoutTimer.restart()
            delegate: Task {
                tasksModel: root.tasks
                rowHeight: root.rowHeight
                iconSize: root.iconSize
                minLabelWidth: root.minLabelWidth
                maxLabelWidth: root.maxLabelWidth
                vertical: root.vertical
                labels: root.labels
                labelCap: root.labelCap
                ownHidden: !!root.ownHidden[index]
                stubRows: root.stubs[index] || []
                overflowHidden: root.overflowRows.indexOf(index) !== -1
                onActivateRequested: row => root.activateIndex(root.tasks.makeModelIndex(row), true)
                onStubRequested: (rows, item) => root.openStub(rows, item)
                audio: root.audioFor(model.AppPid, model.AppId)
                badge: root.badgeFor(model.LauncherUrlWithoutIcon, model.AppId)
                onMuteToggled: root.toggleMute(model.AppPid, model.AppId)
                onGroupMenuRequested: (row, item) => root.openGroupMenu(row, item)
                onContextMenuRequested: (row, item) => root.openContextMenu(row, item)
                onHighlightRequested: ids => root.highlightWindows(ids)
                onNewInstanceRequested: row => root.newInstance(root.tasks.makeModelIndex(row))
                onDragMoved: (item, x, y, pressX) => root.dragMoved(item, x, y, pressX)
                onDragFinished: root.dragFinished()
            }
        }

        // "+N": everything that didn't fit.
        Item {
            id: overflowButton
            visible: root.overflowRows.length > 0
            width: root.overflowButtonWidth
            height: root.rowHeight
            readonly property int hiddenWindows: {
                var n = 0;
                root.overflowRows.forEach(r => {
                    var idx = root.tasks.makeModelIndex(r);
                    if (!root.ownHidden[r]) n += root.tasks.data(idx, TaskManager.AbstractTasksModel.IsGroupParent)
                                               ? root.tasks.rowCount(idx) : 1;
                    n += (root.stubs[r] || []).length;
                });
                return n;
            }
            KSvg.FrameSvgItem {
                anchors.fill: parent
                anchors.margins: 1
                imagePath: "widgets/tasks"
                prefix: overflowMouse.containsMouse ? ["hover", "normal"] : ["normal"]
            }
            PC3.Label {
                anchors.centerIn: parent
                text: "+" + overflowButton.hiddenWindows
                font.bold: true
            }
            MouseArea {
                id: overflowMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.openOverflow(overflowButton)
            }
        }
    }
}
