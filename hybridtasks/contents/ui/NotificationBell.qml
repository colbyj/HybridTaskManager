/*
    SPDX-FileCopyrightText: 2026 Colby Johanson

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// Orange pill with a bell, plus a count when there's more than one
// notification. Placed in a button's top-right corner.
Rectangle {
    id: bell
    property int count: 0
    property int size: 14

    height: size
    width: row.implicitWidth + size * 0.4
    radius: size / 2
    color: Kirigami.Theme.neutralTextColor

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 1
        Kirigami.Icon {
            width: bell.size * 0.75
            height: width
            anchors.verticalCenter: parent.verticalCenter
            source: "notifications-symbolic"
            color: "white"
            isMask: true
        }
        PC3.Label {
            visible: bell.count > 1
            anchors.verticalCenter: parent.verticalCenter
            text: bell.count > 99 ? "99+" : bell.count
            color: "white"
            font.pixelSize: bell.size * 0.72
            font.bold: true
        }
    }
}
