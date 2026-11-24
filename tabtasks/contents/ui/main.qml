import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    // ---- app definitions -------------------------------------------------
    readonly property var apps: ({
        konsole: { name: "Konsole", icon: "utilities-terminal", match: "konsole", launch: "konsole" },
        dolphin: { name: "Dolphin", icon: "system-file-manager", match: "dolphin", launch: "dolphin" },
        firefox: { name: "Firefox", icon: "firefox", match: "firefox", launch: "firefox" }
    })
    readonly property var appOrder: ["dolphin", "konsole", "firefox"]

    property string currentApp: "konsole"
    property var tabData: ({ konsole: [], dolphin: [] })   // from tabinfo.py
    property var windows: ({ konsole: [], dolphin: [], firefox: [] }) // from TasksModel
    property int nowTick: 0  // bumps to refresh "x min ago" labels

    preferredRepresentation: compactRepresentation
    switchWidth: Kirigami.Units.gridUnit * 10
    switchHeight: Kirigami.Units.gridUnit * 10

    // ---- helper script ---------------------------------------------------
    readonly property string helper: {
        var u = Qt.resolvedUrl("../code/tabinfo.py").toString();
        return u.replace(/^file:\/\//, "");
    }
    readonly property string listCmd: "python3 -I '" + helper + "' list"

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function runHelper(args) {
        exec.connectSource("python3 -I " + shq(helper) + " " + args.map(shq).join(" ")
                           + " #" + Date.now());   // unique source => always runs
    }
    function launch(cmd) { exec.connectSource("setsid -f " + cmd + " >/dev/null 2>&1 #" + Date.now()); }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (source, data) => {
            if (source === root.listCmd) {
                try { root.tabData = JSON.parse(data["stdout"]); } catch (e) {}
            }
            disconnectSource(source);
        }
    }

    function refresh() {
        exec.connectSource(listCmd);
        snapshotWindows();
    }

    Timer {
        interval: root.expanded ? 2000 : 5000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: { root.refresh(); root.nowTick++; }
    }
    onExpandedChanged: if (root.expanded) root.refresh()

    // ---- window list -----------------------------------------------------
    TaskManager.TasksModel {
        id: tasks
        groupMode: TaskManager.TasksModel.GroupDisabled
        filterByVirtualDesktop: false
        filterByScreen: false
        filterByActivity: false
        filterNotMinimized: false
        sortMode: TaskManager.TasksModel.SortLastActivated
        onCountChanged: root.snapshotWindows()
        onDataChanged: snapTimer.restart()
    }
    Timer { id: snapTimer; interval: 150; onTriggered: root.snapshotWindows() }

    function role(row, r) { return tasks.data(tasks.makeModelIndex(row), r); }

    function screenName(rect) {
        var ss = Qt.application.screens;
        for (var i = 0; i < ss.length; i++) {
            if (ss[i].virtualX === rect.x && ss[i].virtualY === rect.y) return ss[i].name;
        }
        return "";
    }

    function snapshotWindows() {
        var R = TaskManager.AbstractTasksModel;
        var out = { konsole: [], dolphin: [], firefox: [] };
        for (var row = 0; row < tasks.count; row++) {
            if (!role(row, R.IsWindow)) continue;
            var appId = String(role(row, R.AppId) || "").toLowerCase();
            for (var key in apps) {
                if (appId.indexOf(apps[key].match) === -1) continue;
                var last = role(row, R.LastActivated);
                out[key].push({
                    row: row,
                    pid: role(row, R.AppPid),
                    title: String(role(row, Qt.DisplayRole) || ""),
                    active: !!role(row, R.IsActive),
                    minimized: !!role(row, R.IsMinimized),
                    last: last ? new Date(last).getTime() : 0,
                    screen: screenName(role(row, R.ScreenGeometry))
                });
            }
        }
        for (var k in out) out[k].sort((a, b) => b.last - a.last);
        windows = out;
    }

    function activateRow(row) { tasks.requestActivate(tasks.makeModelIndex(row)); }

    function cleanTitle(key, t) {
        return t.replace(/\s+[—–-]\s+(Konsole|Dolphin|Mozilla Firefox|Firefox)$/, "");
    }

    // Find the TasksModel window for a Konsole D-Bus window.
    function konsoleTask(kw) {
        var c = windows.konsole.filter(w => w.pid === kw.pid);
        if (c.length > 1) {
            var m = c.filter(w => w.title.indexOf(kw.rawCurrentTitle) === 0);
            if (m.length) c = m;
        }
        return c.length ? c[0] : null;
    }
    function dolphinTask(dw) {
        var c = windows.dolphin.filter(w => w.pid === dw.pid);
        return c.length ? c[0] : null;
    }

    function ago(ms) {
        void nowTick;
        if (!ms) return "";
        var s = (Date.now() - ms) / 1000;
        if (s < 60) return "just now";
        if (s < 3600) return Math.floor(s / 60) + " min ago";
        if (s < 86400) return Math.floor(s / 3600) + " h ago";
        return Math.floor(s / 86400) + " d ago";
    }

    // Popup rows for the current app: headers and items, newest window first.
    function buildRows(key) {
        var rows = [];
        if (key === "konsole") {
            var ks = (tabData.konsole || []).map(kw => ({ kw: kw, task: konsoleTask(kw) }));
            ks.sort((a, b) => (b.task ? b.task.last : 0) - (a.task ? a.task.last : 0));
            ks.forEach((e, i) => {
                rows.push({ kind: "header", text: "Window " + (i + 1),
                            meta: e.task ? [e.task.screen, e.task.active ? "active" : ago(e.task.last)].filter(x => x).join(" · ") : "",
                            count: e.kw.tabs.length });
                e.kw.tabs.forEach(t => rows.push({
                    kind: "item", text: t.title, current: t.current,
                    sub: [t.title === t.cwd ? "" : t.cwd, t.program].filter(x => x).join(" · "),
                    act: { type: "konsole", service: e.kw.service, window: e.kw.window, session: t.session,
                           row: e.task ? e.task.row : -1 }
                }));
            });
        } else {
            windows[key].forEach((w, i) => {
                rows.push({ kind: "item", text: cleanTitle(key, w.title), current: w.active,
                            sub: [w.screen, w.active ? "active" : ago(w.last), w.minimized ? "minimized" : ""].filter(x => x).join(" · "),
                            act: { type: "window", row: w.row } });
            });
        }
        return rows;
    }

    function tabCount(key) {
        if (key === "konsole") return (tabData.konsole || []).reduce((n, w) => n + w.tabs.length, 0);
        return -1;
    }

    function openItem(act) {
        if (act.type === "konsole") runHelper(["konsole-switch", act.service, act.window, act.session]);
        if (act.row >= 0) activateRow(act.row);
        root.expanded = false;
    }

    function newTab(key) {
        if (key === "konsole") {
            var ks = (tabData.konsole || []).map(kw => ({ kw: kw, task: konsoleTask(kw) }))
                .sort((a, b) => (b.task ? b.task.last : 0) - (a.task ? a.task.last : 0));
            if (ks.length) {
                runHelper(["konsole-newtab", ks[0].kw.service, ks[0].kw.window]);
                if (ks[0].task) activateRow(ks[0].task.row);
            } else launch("konsole");
        } else if (key === "dolphin") {
            var w = windows.dolphin[0];
            var dw = w ? (tabData.dolphin || []).find(d => d.pid === w.pid) : null;
            if (dw) { runHelper(["dolphin-newtab", dw.service, dw.path]); activateRow(w.row); }
            else launch("dolphin");
        } else {
            if (windows.firefox.length) activateRow(windows.firefox[0].row);
            launch("firefox --new-tab about:newtab");
        }
        root.expanded = false;
    }
    function newWindow(key) {
        launch(key === "dolphin" ? "dolphin --new-window" : key === "firefox" ? "firefox --new-window" : "konsole");
        root.expanded = false;
    }

    // ---- panel chips -----------------------------------------------------
    compactRepresentation: RowLayout {
        spacing: Kirigami.Units.smallSpacing
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth

        Repeater {
            model: root.appOrder
            delegate: MouseArea {
                id: chip
                required property string modelData
                readonly property int nWin: root.windows[modelData].length
                readonly property int nTabs: root.tabCount(modelData)
                readonly property bool anyActive: root.windows[modelData].some(w => w.active)
                Layout.fillHeight: true
                Layout.preferredWidth: chipRow.implicitWidth + Kirigami.Units.smallSpacing * 2
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                opacity: nWin ? 1 : 0.5
                onClicked: (mouse) => {
                    if (mouse.button === Qt.MiddleButton) { root.newWindow(modelData); return; }
                    if (root.expanded && root.currentApp === modelData) root.expanded = false;
                    else { root.currentApp = modelData; root.expanded = true; }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Kirigami.Units.cornerRadius
                    color: Kirigami.Theme.highlightColor
                    opacity: (root.expanded && root.currentApp === chip.modelData) ? 0.35
                           : chip.containsMouse ? 0.2 : chip.anyActive ? 0.12 : 0
                }
                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon {
                        source: root.apps[chip.modelData].icon
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    }
                    PC3.Label {
                        text: chip.nWin === 0 ? "" : chip.nTabs >= 0 ? chip.nWin + "·" + chip.nTabs : String(chip.nWin)
                        visible: text !== ""
                    }
                }
                PC3.ToolTip.text: chip.nWin === 0 ? root.apps[modelData].name + ": nothing open"
                    : root.apps[modelData].name + ": " + chip.nWin + (chip.nWin === 1 ? " window" : " windows")
                      + (chip.nTabs >= 0 ? ", " + chip.nTabs + " tabs" : "")
                PC3.ToolTip.visible: containsMouse && !root.expanded
                PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
    }

    // ---- popup -----------------------------------------------------------
    fullRepresentation: ColumnLayout {
        id: popup
        Layout.preferredWidth: Kirigami.Units.gridUnit * 30
        Layout.preferredHeight: Math.min(Kirigami.Units.gridUnit * 34,
                                         listCol.implicitHeight + header.implicitHeight + footer.implicitHeight + Kirigami.Units.gridUnit * 2)
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        spacing: Kirigami.Units.smallSpacing

        readonly property var rows: root.buildRows(root.currentApp)

        RowLayout {
            id: header
            Layout.fillWidth: true
            Repeater {
                model: root.appOrder
                delegate: PC3.TabButton {
                    required property string modelData
                    icon.name: root.apps[modelData].icon
                    text: root.apps[modelData].name
                    checked: root.currentApp === modelData
                    onClicked: root.currentApp = modelData
                }
            }
        }

        PC3.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            ColumnLayout {
                id: listCol
                width: parent.width
                spacing: 0

                PC3.Label {
                    visible: popup.rows.length === 0
                    Layout.fillWidth: true
                    Layout.margins: Kirigami.Units.gridUnit
                    horizontalAlignment: Text.AlignHCenter
                    opacity: 0.7
                    text: "No " + root.apps[root.currentApp].name + " windows open"
                }

                Repeater {
                    model: popup.rows
                    delegate: Loader {
                        required property var modelData
                        Layout.fillWidth: true
                        sourceComponent: modelData.kind === "header" ? headerRow : itemRow
                        Component {
                            id: headerRow
                            RowLayout {
                                Kirigami.Heading {
                                    level: 5
                                    text: modelData.text
                                    Layout.topMargin: Kirigami.Units.smallSpacing
                                    Layout.leftMargin: Kirigami.Units.smallSpacing
                                }
                                PC3.Label {
                                    text: modelData.count + (modelData.count === 1 ? " tab" : " tabs")
                                          + (modelData.meta ? "  ·  " + modelData.meta : "")
                                    opacity: 0.6
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        Component {
                            id: itemRow
                            PC3.ItemDelegate {
                                onClicked: root.openItem(modelData.act)
                                contentItem: ColumnLayout {
                                    spacing: 0
                                    PC3.Label {
                                        Layout.fillWidth: true
                                        text: (modelData.current ? "● " : "") + modelData.text
                                        elide: Text.ElideMiddle
                                        font.bold: modelData.current
                                    }
                                    PC3.Label {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: modelData.sub
                                        opacity: 0.6
                                        font: Kirigami.Theme.smallFont
                                        elide: Text.ElideMiddle
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            id: footer
            Layout.fillWidth: true
            PC3.Label {
                visible: root.currentApp !== "konsole"
                text: root.currentApp === "dolphin" ? "Only the active tab of each window is visible"
                                                    : "Tabs need Plasma Browser Integration (coming)"
                opacity: 0.6
                font: Kirigami.Theme.smallFont
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Item { Layout.fillWidth: root.currentApp === "konsole" }
            PC3.Button {
                icon.name: "tab-new"
                text: "New tab"
                onClicked: root.newTab(root.currentApp)
            }
            PC3.Button {
                icon.name: "window-new"
                text: "New window"
                onClicked: root.newWindow(root.currentApp)
            }
        }
    }
}
