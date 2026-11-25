/*
    SPDX-FileCopyrightText: 2026 Colby Johanson

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls

KCM.SimpleKCM {
    property alias cfg_rows: rowsCombo.currentIndex
    property alias cfg_minButtonWidth: minWidth.value
    property alias cfg_maxButtonWidth: maxWidth.value
    property alias cfg_showOnlyCurrentDesktop: currentDesktop.checked
    property alias cfg_showLabels: showLabels.checked
    property alias cfg_focusFlash: flashCombo.currentIndex
    property alias cfg_collapseMinimized: collapseCombo.currentIndex
    property alias cfg_outlineWidth: outlineWidth.value
    property alias cfg_outlineUseAccent: outlineAccent.checked
    property alias cfg_outlineColor: outlineColor.color
    property alias cfg_outlineDuration: outlineDuration.value
    property alias cfg_groupedClick: groupedClickCombo.currentIndex
    property alias cfg_highlightOnHover: highlightOnHover.checked
    property alias cfg_hoverList: hoverList.checked

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: showLabels
            Kirigami.FormData.label: "Ungrouped apps:"
            text: "Show window titles on buttons"
        }
        QQC2.ComboBox {
            id: rowsCombo
            Kirigami.FormData.label: "Rows:"
            // Index == config value: 0 = automatic.
            model: ["Automatic", "1", "2", "3"]
        }
        QQC2.SpinBox {
            id: minWidth
            Kirigami.FormData.label: "Labelled button width, minimum:"
            from: 40; to: 600; stepSize: 10
            textFromValue: (v) => v + " px"
            valueFromText: (t) => parseInt(t)
        }
        QQC2.SpinBox {
            id: maxWidth
            Kirigami.FormData.label: "maximum:"
            from: 40; to: 800; stepSize: 10
            textFromValue: (v) => v + " px"
            valueFromText: (t) => parseInt(t)
        }
        QQC2.ComboBox {
            id: groupedClickCombo
            Kirigami.FormData.label: "Clicking a grouped app:"
            // Index == config value.
            model: ["Shows a list of its windows", "Cycles through its windows"]
        }
        QQC2.CheckBox {
            id: highlightOnHover
            Kirigami.FormData.label: "Hovering a button:"
            text: "Highlights its windows (dims all others)"
        }
        QQC2.CheckBox {
            id: hoverList
            text: "Shows a list of a grouped app's windows"
        }
        QQC2.ComboBox {
            id: collapseCombo
            Kirigami.FormData.label: "Collapse minimized windows:"
            // Index == config value.
            model: ["Never", "When the bar is full", "Always"]
        }
        QQC2.ComboBox {
            id: flashCombo
            Kirigami.FormData.label: "Outline window when focused:"
            model: ["Never", "When it's on another monitor", "Always"]
        }
        QQC2.SpinBox {
            id: outlineWidth
            enabled: flashCombo.currentIndex > 0
            Kirigami.FormData.label: "Outline thickness:"
            from: 1; to: 24
            textFromValue: (v) => v + " px"
            valueFromText: (t) => parseInt(t)
        }
        Row {
            enabled: flashCombo.currentIndex > 0
            Kirigami.FormData.label: "Outline colour:"
            spacing: Kirigami.Units.smallSpacing
            QQC2.CheckBox {
                id: outlineAccent
                text: "Accent colour"
                anchors.verticalCenter: parent.verticalCenter
            }
            KQuickControls.ColorButton {
                id: outlineColor
                enabled: !outlineAccent.checked
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        QQC2.SpinBox {
            id: outlineDuration
            enabled: flashCombo.currentIndex > 0
            Kirigami.FormData.label: "Outline duration:"
            from: 200; to: 5000; stepSize: 50
            textFromValue: (v) => v + " ms"
            valueFromText: (t) => parseInt(t)
        }
        // Preview of the outline's look (thickness, colour and corners).
        Item {
            enabled: flashCombo.currentIndex > 0
            opacity: enabled ? 1 : 0.4
            Kirigami.FormData.label: "Preview:"
            implicitWidth: Kirigami.Units.gridUnit * 10
            implicitHeight: Kirigami.Units.gridUnit * 6
            Rectangle {
                anchors.fill: parent
                color: Kirigami.Theme.backgroundColor
                border.color: Kirigami.Theme.disabledTextColor
                border.width: 1
                radius: Kirigami.Units.cornerRadius
                QQC2.Label {
                    anchors.centerIn: parent
                    text: "Window"
                    opacity: 0.6
                }
            }
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                radius: Kirigami.Units.cornerRadius * 2
                border.width: outlineWidth.value
                border.color: outlineAccent.checked ? Kirigami.Theme.highlightColor : outlineColor.color
            }
        }
        QQC2.CheckBox {
            id: currentDesktop
            Kirigami.FormData.label: "Show:"
            text: "Only windows on the current desktop"
        }
    }
}
