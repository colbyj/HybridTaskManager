/*
    SPDX-FileCopyrightText: 2026 Colby Johanson

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_rows: rowsCombo.currentIndex
    property alias cfg_minButtonWidth: minWidth.value
    property alias cfg_maxButtonWidth: maxWidth.value
    property alias cfg_showOnlyCurrentDesktop: currentDesktop.checked
    property alias cfg_showLabels: showLabels.checked
    property alias cfg_focusFlash: flashCombo.currentIndex
    property alias cfg_collapseMinimized: collapseCombo.currentIndex

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
        QQC2.CheckBox {
            id: currentDesktop
            Kirigami.FormData.label: "Show:"
            text: "Only windows on the current desktop"
        }
    }
}
