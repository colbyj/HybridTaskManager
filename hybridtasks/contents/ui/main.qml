/*
    SPDX-FileCopyrightText: 2026 Colby Johanson

    The audio-stream handling (the "audio" section) is adapted from
    Fancy Tasks NG's AudioStreams.qml -- https://github.com/daydve/FancyTasksNG
    SPDX-FileCopyrightText: 2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-FileCopyrightText: 2024 ivan tkachenko <me@ratijas.tk>
    SPDX-FileCopyrightText: 2022-2023 Alexandra <alexankitty@gmail.com>
    SPDX-FileCopyrightText: 2017 Kai Uwe Broulik <kde@privat.broulik.de>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

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
import org.kde.notificationmanager as NotificationManager
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

        onCountChanged: { labelTimer.restart(); adjacencyTimer.restart(); layoutTimer.restart(); notifTimer.restart(); appActionsTimer.restart(); }
        onDataChanged: { labelTimer.restart(); layoutTimer.restart(); notifTimer.restart(); }
    }

    // Pick up config changes made from outside (e.g. scripting, other instances).
    Connections {
        target: Plasmoid.configuration
        function onShowLabelsChanged() { root.computeLabels(); }
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
        if (!Plasmoid.configuration.showLabels) { labels = {}; layoutTimer.restart(); return; }
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
    // draw an outline around the window -- nothing else on screen changes.
    function activateIndex(idx, toggleIfActive) {
        var R = TaskManager.AbstractTasksModel;
        if (toggleIfActive && tasksModel.data(idx, R.IsActive) && !tasksModel.data(idx, R.IsMinimized)) {
            clearHighlight();
            tasksModel.requestToggleMinimized(idx);
            return;
        }
        tasksModel.requestActivate(idx);
        var mode = Plasmoid.configuration.focusFlash;   // 0 off, 1 other monitors, 2 always
        var geo = tasksModel.data(idx, R.ScreenGeometry);
        var mine = Plasmoid.containment.screenGeometry;
        var elsewhere = !geo || !mine || geo.x !== mine.x || geo.y !== mine.y;
        clearHighlight();   // drop the hover highlight
        if (mode === 2 || (mode === 1 && elsewhere)) showOutline(tasksModel.data(idx, R.Geometry));
    }

    // The outline is a frameless, click-through Plasma dialog placed at the
    // window's global position (the shell may position its own dialogs), with
    // a rounded accent frame that fades in and out and then removes itself.
    function showOutline(windowGeo) {
        if (!windowGeo || windowGeo.width <= 0) return;
        var d = outlineComponent.createObject(root, {
            target: Qt.rect(windowGeo.x, windowGeo.y, windowGeo.width, windowGeo.height)
        });
        d.visible = true;
    }
    Component {
        id: outlineComponent
        PlasmaCore.Dialog {
            id: overlay
            property rect target
            readonly property int total: Math.max(150, Plasmoid.configuration.outlineDuration)
            x: target.x
            y: target.y
            type: PlasmaCore.Dialog.OnScreenDisplay
            location: PlasmaCore.Types.Floating
            backgroundHints: PlasmaCore.Dialog.NoBackground
            outputOnly: true
            flags: Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus | Qt.WindowTransparentForInput

            mainItem: Item {
                width: overlay.target.width
                height: overlay.target.height
                Rectangle {
                    id: frame
                    anchors.fill: parent
                    color: "transparent"
                    radius: Kirigami.Units.cornerRadius * 2
                    border.width: Plasmoid.configuration.outlineWidth
                    border.color: Plasmoid.configuration.outlineUseAccent ? Kirigami.Theme.highlightColor
                                                                          : Plasmoid.configuration.outlineColor
                    opacity: 0
                    SequentialAnimation {
                        running: overlay.visible
                        // Total time = outlineDuration: quick fade in, hold, slower fade out.
                        NumberAnimation { target: frame; property: "opacity"; to: 1; duration: Math.round(overlay.total * 0.12) }
                        PauseAnimation { duration: Math.round(overlay.total * 0.38) }
                        NumberAnimation { target: frame; property: "opacity"; to: 0; duration: Math.round(overlay.total * 0.5); easing.type: Easing.InQuad }
                        ScriptAction { script: { overlay.visible = false; overlay.destroy(); } }
                    }
                }
            }
        }
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

    // App-specific menu entries (apps.py): the .desktop file's actions, e.g.
    // Firefox's "New Private Window", and Dolphin's places. Fetched in the
    // background when apps appear, so the menu can show them straight away.
    property var appActions: ({})   // launcher url -> { actions: [...], places: [...] }
    property var appActionsPending: ({})
    Timer { id: appActionsTimer; interval: 500; onTriggered: root.fetchAppActions() }
    function fetchAppActions() {
        var urls = [];
        for (var r = 0; r < tasksModel.count; r++) {
            var url = String(tasksModel.data(tasksModel.makeModelIndex(r), TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon) || "");
            if (url && !(url in appActions) && !(url in appActionsPending) && urls.indexOf(url) === -1) urls.push(url);
        }
        if (!urls.length) return;
        urls.forEach(u => appActionsPending[u] = true);
        appActionsSource.connectSource(["python3", "-I", codeDir + "apps.py", "actions"].concat(urls).map(shq).join(" "));
    }
    P5Support.DataSource {
        id: appActionsSource
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source);
            var found = {};
            try { found = JSON.parse(data.stdout); } catch (e) {
                // Let the next change in the task list try again.
                console.warn("hybridtasks: apps.py:", data.stderr);
                root.appActionsPending = {};
                return;
            }
            var all = Object.assign({}, root.appActions, found);
            for (var u in found) delete root.appActionsPending[u];
            root.appActions = all;
        }
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
        service: "local.hybridtasks.Badges"
        path: "/Badges"
        iface: "local.hybridtasks.Badges"
        function dbusUpdate(appUri, count, progress) { root.updateBadge(appUri, count, progress); }
    }

    // ---- desktop notifications -------------------------------------------------------
    // An app "has unseen notifications" when its notifications in Plasma's
    // history are newer than both the tray's last-read time (opening the tray's
    // notification list clears them, like Plasma's bell) and the last time one
    // of the app's windows was focused. Low-urgency and transient ones are ignored.
    property var notifications: ({})   // desktop id -> { count, titles }
    property var seenAt: ({})          // desktop id -> ms; app was focused at/after this
    Timer { id: notifTimer; interval: 100; onTriggered: root.rebuildNotifications() }

    NotificationManager.Notifications {
        id: notifModel
        showNotifications: true
        showJobs: false
        showExpired: true
        showDismissed: true
        urgencies: NotificationManager.Notifications.NormalUrgency | NotificationManager.Notifications.CriticalUrgency
        groupMode: NotificationManager.Notifications.GroupDisabled
        onCountChanged: notifTimer.restart()
        onDataChanged: notifTimer.restart()
        onLastReadChanged: notifTimer.restart()
    }

    function rebuildNotifications() {
        var R = TaskManager.AbstractTasksModel;
        var N = NotificationManager.Notifications;
        var now = Date.now();
        var seen = Object.assign({}, seenAt);
        // Last focus time per app, from every window (including grouped ones).
        function noteWindow(idx) {
            var keys = [desktopId(tasksModel.data(idx, R.LauncherUrlWithoutIcon)), desktopId(tasksModel.data(idx, R.AppId))];
            var t = tasksModel.data(idx, R.IsActive) ? now : new Date(tasksModel.data(idx, R.LastActivated) || 0).getTime();
            keys.forEach(k => { if (k) seen[k] = Math.max(seen[k] || 0, t || 0); });
        }
        for (var r = 0; r < tasksModel.count; r++) {
            var idx = tasksModel.makeModelIndex(r);
            if (tasksModel.data(idx, R.IsGroupParent)) {
                for (var c = 0; c < tasksModel.rowCount(idx); c++) noteWindow(tasksModel.makeModelIndex(r, c));
            } else if (tasksModel.data(idx, R.IsWindow)) {
                noteWindow(idx);
            }
        }
        seenAt = seen;

        var lastRead = notifModel.lastRead ? new Date(notifModel.lastRead).getTime() || 0 : 0;
        var out = {};
        for (var i = 0; i < notifModel.count; i++) {
            var ni = notifModel.index(i, 0);
            if (notifModel.data(ni, N.TypeRole) !== N.NotificationType) continue;
            if (notifModel.data(ni, N.ReadRole) || notifModel.data(ni, N.TransientRole)) continue;
            var app = desktopId(notifModel.data(ni, N.DesktopEntryRole) || notifModel.data(ni, N.ApplicationNameRole));
            if (!app) continue;
            var when = Math.max(new Date(notifModel.data(ni, N.CreatedRole) || 0).getTime() || 0,
                                new Date(notifModel.data(ni, N.UpdatedRole) || 0).getTime() || 0);
            if (when <= lastRead || when <= (seen[app] || 0)) continue;
            var e = out[app] || (out[app] = { count: 0, titles: [], newest: 0 });
            e.count++;
            e.titles.push({ when: when, text: notifModel.data(ni, N.SummaryRole) || "" });
        }
        for (var a in out) {
            out[a].titles = out[a].titles.sort((x, y) => y.when - x.when).slice(0, 3).map(t => t.text);
        }
        notifications = out;
    }
    function notificationsFor(launcherUrl, appId) {
        return notifications[desktopId(launcherUrl)] || notifications[desktopId(appId)] || null;
    }

    // ---- KWin window highlight ------------------------------------------------
    // Hover highlights go through hoverHighlight(). Each request names the item
    // that was hovered; a "stop" only counts if that item still owns the
    // highlight. Moving between two rows/buttons can deliver the new item's
    // "start" before the old one's "stop", which used to wipe the highlight.
    // Requests are also coalesced, so stop+start doesn't make KWin flicker.
    property var hlOwner: null
    property var hlIds: []
    Timer { id: hlTimer; interval: 30; onTriggered: root.highlightWindows(root.hlIds) }
    function hoverHighlight(ids, owner) {
        if (ids.length) {
            if (!Plasmoid.configuration.highlightOnHover) return;
            hlOwner = owner;
            hlIds = ids;
        } else {
            if (hlOwner !== owner) return;   // something else has taken over
            hlOwner = null;
            hlIds = [];
        }
        hlTimer.restart();
    }
    function clearHighlight() {
        hlTimer.stop();
        hlOwner = null;
        hlIds = [];
        highlightWindows([]);
    }
    // Drop the highlight if it belongs to a row of a list that is going away.
    function clearHighlightFrom(container) {
        for (var it = hlOwner; it; it = it.parent)
            if (it === container) { clearHighlight(); return; }
    }
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
        onVisibleChanged: if (!visible) { root.clearHighlightFrom(windowList); root.listKey = ""; }

        mainItem: WindowList {
            id: windowList
            tasksModel: root.tasks
            onActivateRequested: idx => { listDialog.visible = false; root.activateIndex(idx, false); }
            onHighlightRequested: (ids, owner) => root.hoverHighlight(ids, owner)
        }
    }

    // The same list, shown while hovering a grouped app (or a minimized stub)
    // when "show a list on hover" is on. It doesn't take focus, and closes
    // shortly after the pointer has left both the button and the list.
    property string hoverKey: ""
    property bool hoverSourceHovered: false
    PlasmaCore.Dialog {
        id: hoverDialog
        location: Plasmoid.location
        type: PlasmaCore.Dialog.Tooltip
        hideOnWindowDeactivate: false
        flags: Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
        backgroundHints: PlasmaCore.Dialog.SolidBackground
        onVisibleChanged: if (!visible) { root.clearHighlightFrom(hoverList); root.hoverKey = ""; }

        mainItem: WindowList {
            id: hoverList
            tasksModel: root.tasks
            onActivateRequested: idx => { hoverDialog.visible = false; root.activateIndex(idx, false); }
            onHighlightRequested: (ids, owner) => root.hoverHighlight(ids, owner)
            onHoveredChanged: if (!hovered) hoverCloseTimer.restart()
        }
    }
    Timer {
        id: hoverCloseTimer
        interval: 350
        onTriggered: if (!root.hoverSourceHovered && !hoverList.hovered) hoverDialog.visible = false
    }
    function openHoverList(key, entries, title, visualParent) {
        hoverSourceHovered = true;
        hoverCloseTimer.stop();
        if (!Plasmoid.configuration.hoverList || listDialog.visible) return;
        if (hoverDialog.visible && hoverKey === key) return;
        hoverKey = key;
        hoverList.entries = entries;
        hoverList.title = title;
        hoverList.showHeaders = false;
        hoverList.updateTitleWidth();
        hoverDialog.visualParent = visualParent;
        hoverDialog.visible = true;
    }
    function hoverEnded() {
        hoverSourceHovered = false;
        if (hoverDialog.visible) hoverCloseTimer.restart();
    }

    function openWindowList(key, entries, title, headers, visualParent) {
        hoverDialog.visible = false;
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
    // Left-click on a grouped app: its window list, or the next of its windows.
    function groupClicked(row, visualParent) {
        if (Plasmoid.configuration.groupedClick === 1) cycleGroup(row);
        else openGroupMenu(row, visualParent);
    }
    // Activates the window after the focused one; if none of the app's windows
    // has focus, the one used most recently.
    function cycleGroup(row) {
        var R = TaskManager.AbstractTasksModel;
        var n = tasksModel.rowCount(tasksModel.makeModelIndex(row));
        if (!n) return;
        var active = -1, recent = 0, recentAt = -1;
        for (var c = 0; c < n; c++) {
            var idx = tasksModel.makeModelIndex(row, c);
            if (tasksModel.data(idx, R.IsActive)) active = c;
            var t = new Date(tasksModel.data(idx, R.LastActivated) || 0).getTime() || 0;
            if (t > recentAt) { recentAt = t; recent = c; }
        }
        var next = active >= 0 ? (active + 1) % n : recent;
        // A single focused window minimizes, like an ungrouped button.
        activateIndex(tasksModel.makeModelIndex(row, next), n === 1);
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
        function onCountChanged() { listDialog.visible = false; hoverDialog.visible = false; }
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
        var newWindowShown = !!d(R.CanLaunchNewInstance) || isLauncher;
        if (newWindowShown) {
            add({ text: isLauncher ? "Start" : "Open New Window", icon: "window-new" },
                () => isLauncher ? tasksModel.requestActivate(idx) : root.newInstance(idx));
        }
        var extra = (url && appActions[String(url)]) || { actions: [], places: [] };
        var menuText = s => String(s).replace(/&/g, "&&");
        extra.actions.forEach(a => {
            // Most apps' "New Window" action duplicates the entry above.
            if (newWindowShown && a.id.toLowerCase().replace(/[^a-z]/g, "") === "newwindow") return;
            const launcher = String(url), action = a.id;
            add({ text: menuText(a.name), icon: a.icon || "" },
                () => root.runCommand(["python3", "-I", root.codeDir + "apps.py", "run", launcher, action]));
        });
        if (extra.places.length) {
            var placesMenu = addSubMenu({ text: "Places", icon: "folder" });
            extra.places.forEach(p => {
                const place = p.url;
                addTo(placesMenu, { text: menuText(p.name), icon: p.icon || "folder" },
                      () => root.runCommand(["dolphin", "--new-window", place]));
            });
        }
        if (newWindowShown || extra.actions.length || extra.places.length) add({ separator: true });
        if (!isLauncher) {
            add({ text: "Allow this program to be grouped", checkable: true, checked: !!d(R.IsGroupable) },
                () => tasksModel.requestToggleGrouping(idx));
        }
        if (url) {
            add({ text: pinned ? "Unpin from Task Manager" : "Pin to Task Manager", icon: pinned ? "window-unpin" : "window-pin" },
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
            var wins = [];
            if (d(R.IsGroupParent)) {
                for (c = 0; c < tasksModel.rowCount(idx); c++) wins.push([row, c]);
            } else {
                wins.push([row, -1]);
            }
            addWindowActions(add, wins);
        }
        contextMenu.visualParent = visualParent;
        contextMenu.openRelative();
    }

    // Minimize / restore / maximize / close for one window or a set of them
    // ("... All" when there's more than one). wins: [row, child] pairs
    // (child -1 for a top-level row), turned into model indexes when used.
    function addWindowActions(add, pairs) {
        var R = TaskManager.AbstractTasksModel;
        var wins = pairs.map(p => ({ row: p[0], child: p[1] }));
        var ix = w => w.child < 0 ? tasksModel.makeModelIndex(w.row) : tasksModel.makeModelIndex(w.row, w.child);
        var get = (w, r) => tasksModel.data(ix(w), r);
        var many = wins.length > 1, all = many ? " All" : "";
        var minimized = wins.filter(w => get(w, R.IsMinimized));
        var shown = wins.filter(w => !get(w, R.IsMinimized));
        var allMax = wins.every(w => get(w, R.IsMaximized));

        if (many) {
            // Raise every window; the focused one last so it keeps focus.
            add({ text: "Show All", icon: "window" }, () => {
                var active = wins.filter(w => get(w, R.IsActive));
                wins.filter(w => !get(w, R.IsActive)).concat(active).forEach(w => tasksModel.requestActivate(ix(w)));
            });
        }
        if (shown.length) {
            add({ text: "Minimize" + all, icon: "window-minimize" },
                () => shown.forEach(w => tasksModel.requestToggleMinimized(ix(w))));
        }
        if (minimized.length) {
            add({ text: "Restore" + all, icon: "window-restore" },
                () => minimized.forEach(w => tasksModel.requestToggleMinimized(ix(w))));
        }
        if (allMax) {
            add({ text: "Unmaximize" + all, icon: "window-restore" },
                () => wins.forEach(w => tasksModel.requestToggleMaximized(ix(w))));
        } else {
            // Maximizing a minimized window should also bring it back.
            add({ text: "Maximize" + all, icon: "window-maximize" }, () => wins.forEach(w => {
                if (get(w, R.IsMinimized)) tasksModel.requestToggleMinimized(ix(w));
                if (!get(w, R.IsMaximized)) tasksModel.requestToggleMaximized(ix(w));
            }));
        }
        add({ separator: true });
        add({ text: "Close" + all, icon: "window-close" },
            () => wins.forEach(w => tasksModel.requestClose(ix(w))));
    }

    // Right-click on a collapsed-minimized button.
    function openStubMenu(rows, visualParent) {
        contextMenu.clearMenuItems();
        subMenus.forEach(m => m.destroy());
        subMenus = [];
        var add = function (props, action) {
            var item = menuItemComponent.createObject(contextMenu, props);
            if (action) item.clicked.connect(action);
            contextMenu.addMenuItem(item);
            return item;
        };
        add({ text: appNameOf(rows[0]) + " — " + rows.length + " minimized", section: true });
        addWindowActions(add, rows.map(r => [r, -1]));
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
                hoverList: Plasmoid.configuration.hoverList
                labels: root.labels
                labelCap: root.labelCap
                ownHidden: !!root.ownHidden[index]
                stubRows: root.stubs[index] || []
                overflowHidden: root.overflowRows.indexOf(index) !== -1
                onActivateRequested: row => root.activateIndex(root.tasks.makeModelIndex(row), true)
                onStubRequested: (rows, item) => root.openStub(rows, item)
                onStubMenuRequested: (rows, item) => root.openStubMenu(rows, item)
                audio: root.audioFor(model.AppPid, model.AppId)
                badge: root.badgeFor(model.LauncherUrlWithoutIcon, model.AppId)
                notification: root.notificationsFor(model.LauncherUrlWithoutIcon, model.AppId)
                onMuteToggled: root.toggleMute(model.AppPid, model.AppId)
                onGroupMenuRequested: (row, item) => root.openGroupMenu(row, item)
                onGroupClicked: (row, item) => root.groupClicked(row, item)
                onHoverListRequested: (row, item) => root.openHoverList("group:" + row, root.entriesFor(row), root.appNameOf(row), item)
                onStubHoverRequested: (rows, item) => root.openHoverList("stub:" + rows.join(","),
                    rows.map(r => ({ row: r, child: -1, app: root.appNameOf(r) })), root.appNameOf(rows[0]) + " — minimized", item)
                onHoverEnded: root.hoverEnded()
                onContextMenuRequested: (row, item) => root.openContextMenu(row, item)
                onHighlightRequested: (ids, owner) => root.hoverHighlight(ids, owner)
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
