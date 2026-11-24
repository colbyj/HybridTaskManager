import QtQuick
import QtQuick.Layouts
import QtQml.Models
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

import "../code/labels.js" as Labels

// Text list of a grouped app's windows, with per-window controls.
// Shown inside a PlasmaCore.Dialog from main.qml.
Item {
    id: list

    property var tasksModel
    property int groupRow: -1
    property string appName: ""

    signal activated()
    signal highlightRequested(var ids)

    readonly property int rowHeight: Math.round(Kirigami.Units.gridUnit * 1.8)
    readonly property int buttonsWidth: rowHeight * 3
    property int titleWidth: Kirigami.Units.gridUnit * 12

    width: Math.max(Kirigami.Units.gridUnit * 16,
                    Math.min(Kirigami.Units.gridUnit * 36,
                             titleWidth + buttonsWidth + Kirigami.Units.largeSpacing * 3))
    height: column.implicitHeight

    FontMetrics { id: boldMetrics; font.bold: true }

    // Size to the longest title (bold, since the active one is bold).
    function updateTitleWidth() {
        var w = 0;
        for (var i = 0; i < windows.count; i++) {
            var t = Labels.cleanTitle(tasksModel.data(tasksModel.makeModelIndex(groupRow, i), Qt.DisplayRole), appName);
            w = Math.max(w, boldMetrics.advanceWidth(t));
        }
        titleWidth = Math.ceil(w) + Kirigami.Units.smallSpacing * 2;
    }

    DelegateModel {
        id: windows
        model: list.groupRow >= 0 ? list.tasksModel : null
        rootIndex: list.groupRow >= 0 ? list.tasksModel.makeModelIndex(list.groupRow) : undefined
        onCountChanged: list.updateTitleWidth()

        delegate: Item {
            id: row
            required property var model
            required property int index

            readonly property var modelIndex: list.tasksModel.makeModelIndex(list.groupRow, index)
            readonly property bool active: !!model.IsActive
            readonly property bool minimized: !!model.IsMinimized
            readonly property bool hovered: rowHover.hovered

            width: list.width
            height: list.rowHeight

            HoverHandler {
                id: rowHover
                onHoveredChanged: list.highlightRequested(hovered ? (row.model.WinIdList || []) : [])
            }
            TapHandler {
                onTapped: {
                    list.tasksModel.requestActivate(row.modelIndex);
                    list.activated();
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Kirigami.Theme.highlightColor
                opacity: row.hovered ? 0.18 : 0
                radius: Kirigami.Units.cornerRadius
            }
            // Accent bar marks the active window.
            Rectangle {
                visible: row.active
                width: 3
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: Kirigami.Units.smallSpacing
                radius: 1.5
                color: Kirigami.Theme.highlightColor
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Kirigami.Units.largeSpacing
                anchors.rightMargin: Kirigami.Units.smallSpacing
                spacing: 0

                PC3.Label {
                    Layout.fillWidth: true
                    text: Labels.cleanTitle(row.model.display, list.appName)
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.bold: row.active
                    opacity: row.minimized ? 0.6 : 1
                }

                Repeater {
                    // [icon, tooltip, action]
                    model: [
                        [row.minimized ? "window-restore" : "window-minimize",
                         row.minimized ? "Restore" : "Minimize",
                         () => list.tasksModel.requestToggleMinimized(row.modelIndex)],
                        [row.model.IsMaximized ? "window-restore" : "window-maximize",
                         row.model.IsMaximized ? "Restore Size" : "Maximize",
                         () => list.tasksModel.requestToggleMaximized(row.modelIndex)],
                        ["window-close", "Close",
                         () => list.tasksModel.requestClose(row.modelIndex)]
                    ]
                    delegate: PC3.ToolButton {
                        required property var modelData
                        icon.name: modelData[0]
                        display: PC3.AbstractButton.IconOnly
                        text: modelData[1]
                        PC3.ToolTip.text: modelData[1]
                        PC3.ToolTip.visible: hovered
                        PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
                        Layout.preferredWidth: list.rowHeight
                        Layout.preferredHeight: list.rowHeight
                        // Faint until the row is hovered, so the list reads as text first.
                        opacity: row.hovered ? 1 : 0.35
                        onClicked: modelData[2]()
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: column
        width: parent.width
        spacing: 0

        PC3.Label {
            text: list.appName
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
        }
        Repeater { model: windows }
    }
}
