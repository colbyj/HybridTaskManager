/*
    SPDX-FileCopyrightText: 2026 Colby Johanson

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

import "../code/labels.js" as Labels

// Text list of windows with per-window controls. Used for a grouped app's
// windows, an app's collapsed minimized windows, and the "+N" overflow.
// Shown inside a PlasmaCore.Dialog from main.qml.
Item {
    id: list

    property var tasksModel
    // [{ row, child, app }] -- child is -1 for a top-level row.
    property var entries: []
    // Show an app-name header whenever the app changes (for mixed lists).
    property bool showHeaders: false
    property string title: ""

    signal activateRequested(var modelIndex)
    // ids empty = stop highlighting. owner: the hovered row.
    signal highlightRequested(var ids, Item owner)

    // Whether the pointer is anywhere over the list.
    readonly property alias hovered: listHover.hovered
    HoverHandler { id: listHover }

    // Bumped whenever the model's data changes, so row state stays live.
    property int revision: 0
    Connections {
        target: list.tasksModel
        function onDataChanged() { list.revision++; }
    }

    readonly property int rowHeight: Math.round(Kirigami.Units.gridUnit * 1.8)
    readonly property int buttonsWidth: rowHeight * 3
    property int titleWidth: Kirigami.Units.gridUnit * 12

    width: Math.max(Kirigami.Units.gridUnit * 16,
                    Math.min(Kirigami.Units.gridUnit * 36,
                             titleWidth + buttonsWidth + Kirigami.Units.largeSpacing * 3))
    height: column.implicitHeight

    function indexOf(e) {
        return e.child >= 0 ? tasksModel.makeModelIndex(e.row, e.child) : tasksModel.makeModelIndex(e.row);
    }
    function titleOf(e) {
        return Labels.cleanTitle(tasksModel.data(indexOf(e), Qt.DisplayRole), e.app);
    }

    // Raise every window (restoring minimized ones). The focused one, if any,
    // goes last so it keeps focus.
    function showAll() {
        var R = TaskManager.AbstractTasksModel, last = null;
        entries.forEach(e => {
            var idx = indexOf(e);
            if (tasksModel.data(idx, R.IsActive)) last = e;
            else tasksModel.requestActivate(idx);
        });
        if (last) tasksModel.requestActivate(indexOf(last));
    }
    function minimizeAll() {
        entries.forEach(e => {
            var idx = indexOf(e);
            if (!tasksModel.data(idx, TaskManager.AbstractTasksModel.IsMinimized)) tasksModel.requestToggleMinimized(idx);
        });
    }

    FontMetrics { id: boldMetrics; font.bold: true }

    // Size to the longest title (bold, since the active one is bold).
    function updateTitleWidth() {
        var w = 0;
        for (var i = 0; i < entries.length; i++) w = Math.max(w, boldMetrics.advanceWidth(titleOf(entries[i])));
        titleWidth = Math.ceil(w) + Kirigami.Units.smallSpacing * 2;
    }

    ColumnLayout {
        id: column
        width: parent.width
        spacing: 0

        // Title, plus "show all" / "minimize all" when there's more than one window.
        RowLayout {
            visible: title.visible || list.entries.length > 1
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            spacing: 0

            PC3.Label {
                id: title
                visible: !list.showHeaders && list.title !== ""
                text: list.title
                opacity: 0.7
                font: Kirigami.Theme.smallFont
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Item { visible: !title.visible; Layout.fillWidth: true }

            Repeater {
                // [icon, label, action]
                model: list.entries.length > 1 ? [
                    ["window", "Show All", () => list.showAll()],
                    ["window-minimize", "Minimize All", () => list.minimizeAll()]
                ] : []
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
                    onClicked: modelData[2]()
                }
            }
        }

        Repeater {
            model: list.entries

            delegate: ColumnLayout {
                id: entry
                required property var modelData
                required property int index
                spacing: 0
                Layout.fillWidth: true

                PC3.Label {
                    visible: list.showHeaders
                             && (entry.index === 0 || list.entries[entry.index - 1].app !== entry.modelData.app)
                    text: entry.modelData.app
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.topMargin: entry.index === 0 ? 0 : Kirigami.Units.smallSpacing
                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                }

                Item {
                    id: row
                    Layout.fillWidth: true
                    Layout.preferredHeight: list.rowHeight

                    // Built fresh on each use: a stored QModelIndex dangles once the proxy
                    // model regroups/re-sorts, and data() on it segfaults plasmashell.
                    function modelIndex() { return list.indexOf(entry.modelData); }
                    function get(role) { list.revision; return list.tasksModel.data(modelIndex(), role); }
                    readonly property var roles: TaskManager.AbstractTasksModel
                    readonly property bool active: !!get(roles.IsActive)
                    readonly property bool minimized: !!get(roles.IsMinimized)
                    readonly property bool maximized: !!get(roles.IsMaximized)
                    readonly property string titleText: { list.revision; return list.titleOf(entry.modelData); }
                    readonly property bool hovered: rowHover.hovered

                    HoverHandler {
                        id: rowHover
                        onHoveredChanged: list.highlightRequested(hovered ? (row.get(row.roles.WinIdList) || []) : [], row)
                    }
                    TapHandler {
                        onTapped: list.activateRequested(row.modelIndex())
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
                            text: row.titleText
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
                                 () => list.tasksModel.requestToggleMinimized(row.modelIndex())],
                                [row.maximized ? "window-restore" : "window-maximize",
                                 row.maximized ? "Restore Size" : "Maximize",
                                 () => list.tasksModel.requestToggleMaximized(row.modelIndex())],
                                ["window-close", "Close",
                                 () => list.tasksModel.requestClose(row.modelIndex())]
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
        }
    }
}
