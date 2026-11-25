/*
    SPDX-FileCopyrightText: 2026 Colby Johanson

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.ksvg as KSvg

// Marks a button that stands for several windows. Fills its parent button.
// mode: 0 = nothing, 1 = the window count in the bottom-right corner,
// 2 = the theme's small arrow on the panel-side edge, like
// Plasma's icons-only task manager.
Item {
    id: indicator

    property int mode: 1
    property int count: 0
    property int location: PlasmaCore.Types.BottomEdge
    property int rowHeight
    property int iconSize

    anchors.fill: parent
    visible: mode > 0 && count > 0

    PC3.Label {
        visible: indicator.mode === 1
        text: indicator.count
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 2
        font.pixelSize: Math.max(8, indicator.rowHeight * 0.32)
        font.bold: true
    }

    KSvg.SvgItem {
        visible: indicator.mode === 2
        imagePath: "widgets/tasks"
        elementId: indicator.location === PlasmaCore.Types.TopEdge ? "group-expander-top"
                 : indicator.location === PlasmaCore.Types.LeftEdge ? "group-expander-left"
                 : indicator.location === PlasmaCore.Types.RightEdge ? "group-expander-right"
                 : "group-expander-bottom"
        // Like the stock task manager: the theme's natural size (capped to
        // the icon), on the button's panel-side edge, centred on the icon.
        readonly property real iconSize: indicator.iconSize
        width: Math.min(naturalSize.width, iconSize)
        height: Math.min(naturalSize.height, iconSize)
        x: indicator.location === PlasmaCore.Types.LeftEdge ? 0
         : indicator.location === PlasmaCore.Types.RightEdge ? parent.width - width
         : (parent.width - width) / 2
        y: indicator.location === PlasmaCore.Types.TopEdge ? 0
         : indicator.location === PlasmaCore.Types.LeftEdge || indicator.location === PlasmaCore.Types.RightEdge
           ? (parent.height - height) / 2
         : parent.height - height
    }
}
