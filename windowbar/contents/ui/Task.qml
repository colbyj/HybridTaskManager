import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.ksvg as KSvg
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

import "../code/labels.js" as Labels

// One slot on the bar: a launcher, a single window, or a grouped app.
// It can also carry a "stub" after it: the collapsed minimized windows of the
// app's cluster (only on the cluster's last slot).
Item {
    id: task

    required property var model
    required property int index

    property var tasksModel
    property var labels: ({})
    property int rowHeight
    property int iconSize
    property int minLabelWidth
    property int maxLabelWidth
    property bool vertical

    // Set by main.qml's layout pass.
    property int labelCap: 100000       // shared max width for labelled buttons
    property bool ownHidden: false      // this window is collapsed into a stub
    property bool overflowHidden: false // moved into the "+N" list
    property var stubRows: []           // minimized windows collapsed after this slot

    signal activateRequested(int row)
    signal groupMenuRequested(int row, Item item)
    signal stubRequested(var rows, Item item)
    signal contextMenuRequested(int row, Item item)
    signal highlightRequested(var ids)
    signal newInstanceRequested(int row)
    signal dragMoved(Item item, real x, real y, real pressX)
    signal dragFinished()

    property bool dragging: false

    readonly property bool isLauncher: !!model.IsLauncher
    readonly property bool isGroup: !!model.IsGroupParent
    readonly property var winIds: model.WinIdList || []
    readonly property string shortLabel: !isGroup && winIds.length ? (labels[String(winIds[0])] || "") : ""
    readonly property bool showLabel: shortLabel !== "" && !vertical
    readonly property var modelIndex: tasksModel.makeModelIndex(index)

    // Widths main.qml uses to plan the layout. They don't depend on the layout
    // state, so planning can't feed back into itself.
    readonly property int hPad: Math.max(Kirigami.Units.smallSpacing * 2,
                                         frame.margins.left, frame.margins.right) + 1
    readonly property int iconOnlyWidth: rowHeight + Kirigami.Units.smallSpacing
    readonly property int naturalWidth: showLabel
        ? Math.max(minLabelWidth, Math.min(maxLabelWidth,
                   hPad + iconSize + content.spacing + Math.ceil(labelMetrics.advanceWidth) + hPad))
        : iconOnlyWidth
    readonly property int compactWidth: showLabel ? Math.min(naturalWidth, minLabelWidth) : iconOnlyWidth
    readonly property int stubWidth: iconOnlyWidth

    readonly property int ownWidth: ownHidden ? 0 : Math.max(compactWidth, Math.min(naturalWidth, labelCap))
    width: overflowHidden ? 0 : ownWidth + (stubRows.length ? stubWidth : 0)
    height: rowHeight
    visible: width > 0

    // ---- the window's own button ---------------------------------------------
    Item {
        id: own
        width: task.ownWidth
        height: parent.height
        visible: !task.ownHidden
        opacity: task.dragging ? 0.5 : 1

        readonly property bool hovered: mouse.containsMouse

        // Breeze task-button background (same SVG the stock task manager uses).
        KSvg.FrameSvgItem {
            id: frame
            anchors.fill: parent
            anchors.margins: 1
            imagePath: "widgets/tasks"
            visible: !task.isLauncher || own.hovered
            prefix: task.model.IsDemandingAttention ? ["attention", "normal"]
                  : task.model.IsActive ? (own.hovered ? ["hover", "focus"] : ["focus"])
                  : own.hovered ? ["hover", "normal"]
                  : task.model.IsMinimized ? ["minimized", "normal"]
                  : ["normal"]
        }

        // Measure the full label text. (A Label's implicitWidth shrinks once
        // it has been elided, so it can't be used to size the button.)
        TextMetrics {
            id: labelMetrics
            font: label.font
            text: task.shortLabel
        }

        RowLayout {
            id: content
            anchors.fill: parent
            anchors.leftMargin: task.hPad
            anchors.rightMargin: task.hPad
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: task.model.decoration
                Layout.preferredWidth: task.iconSize
                Layout.preferredHeight: task.iconSize
                Layout.alignment: task.showLabel ? (Qt.AlignLeft | Qt.AlignVCenter) : Qt.AlignCenter
                opacity: task.model.IsMinimized ? 0.6 : 1
            }
            PC3.Label {
                id: label
                visible: task.showLabel
                text: task.shortLabel
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                // Paths are most recognisable by their end ("…/robot/firmware");
                // other titles by their start.
                elide: /^\S*\/\S*$/.test(task.shortLabel) ? Text.ElideLeft : Text.ElideRight
                maximumLineCount: 1
                opacity: task.model.IsMinimized ? 0.7 : 1
            }
        }

        // Window count for grouped apps.
        PC3.Label {
            visible: task.isGroup
            text: task.model.ChildCount || ""
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 2
            font.pixelSize: Math.max(8, task.rowHeight * 0.32)
            font.bold: true
        }

        PlasmaCore.ToolTipArea {
            anchors.fill: parent
            active: !task.dragging
            mainText: task.isLauncher ? (task.model.AppName || task.model.display)
                    : task.isGroup ? task.model.AppName
                    : Labels.cleanTitle(task.model.display, task.model.AppName)
            subText: task.isLauncher ? "Not running"
                   : task.isGroup ? task.model.ChildCount + " windows"
                   : task.model.AppName
            location: PlasmaCore.Types.Floating
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            cursorShape: task.dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor

            property point pressPos
            onPressed: (m) => { pressPos = Qt.point(m.x, m.y); }
            onPositionChanged: (m) => {
                if (!(m.buttons & Qt.LeftButton)) return;
                if (!task.dragging && Math.hypot(m.x - pressPos.x, m.y - pressPos.y) < Qt.styleHints.startDragDistance) return;
                if (!task.dragging) { task.dragging = true; highlightTimer.stop(); task.highlightRequested([]); }
                task.dragMoved(task, m.x, m.y, pressPos.x);
            }
            onReleased: {
                if (task.dragging) { task.dragging = false; task.dragFinished(); }
            }
            onCanceled: {
                if (task.dragging) { task.dragging = false; task.dragFinished(); }
            }

            onContainsMouseChanged: {
                if (containsMouse && !task.isLauncher && !task.dragging) highlightTimer.start();
                else { highlightTimer.stop(); task.highlightRequested([]); }
            }

            onClicked: (m) => {
                if (task.dragging) return;
                highlightTimer.stop();
                if (m.button === Qt.MiddleButton) {
                    task.highlightRequested([]);
                    task.newInstanceRequested(task.index);
                } else if (m.button === Qt.RightButton) {
                    task.highlightRequested([]);
                    task.contextMenuRequested(task.index, own);
                } else if (task.isGroup) {
                    task.groupMenuRequested(task.index, own);
                } else {
                    // main.qml decides between activate and minimize, and
                    // whether to flash the window.
                    task.activateRequested(task.index);
                }
            }
        }

        // Short delay so sweeping the mouse along the bar doesn't flash windows.
        Timer {
            id: highlightTimer
            interval: 250
            onTriggered: {
                var ids = task.winIds;
                if (task.isGroup) {
                    ids = [];
                    var n = task.tasksModel.rowCount(task.modelIndex);
                    for (var c = 0; c < n; c++) {
                        var cids = task.tasksModel.data(task.tasksModel.makeModelIndex(task.index, c),
                                                        TaskManager.AbstractTasksModel.WinIdList) || [];
                        ids = ids.concat(cids);
                    }
                }
                task.highlightRequested(ids);
            }
        }
    }

    // ---- collapsed minimized windows ---------------------------------------------
    Item {
        id: stub
        x: task.ownWidth
        width: task.stubWidth
        height: parent.height
        visible: task.stubRows.length > 0

        KSvg.FrameSvgItem {
            anchors.fill: parent
            anchors.margins: 1
            imagePath: "widgets/tasks"
            prefix: stubMouse.containsMouse ? ["hover", "normal"] : ["minimized", "normal"]
        }
        Kirigami.Icon {
            anchors.centerIn: parent
            width: task.iconSize
            height: task.iconSize
            source: task.model.decoration
            opacity: 0.5
        }
        PC3.Label {
            text: task.stubRows.length
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 2
            font.pixelSize: Math.max(8, task.rowHeight * 0.32)
            font.bold: true
        }
        PlasmaCore.ToolTipArea {
            anchors.fill: parent
            mainText: task.model.AppName || ""
            subText: task.stubRows.length === 1 ? "1 minimized window"
                                                : task.stubRows.length + " minimized windows"
            location: PlasmaCore.Types.Floating
        }
        MouseArea {
            id: stubMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: task.stubRequested(task.stubRows, stub)
        }
    }
}
