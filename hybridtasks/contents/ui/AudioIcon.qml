/*
    SPDX-FileCopyrightText: 2026 Colby Johanson

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami

// Small speaker icon; click to mute/unmute the app's audio.
Kirigami.Icon {
    id: icon
    property bool muted: false
    signal toggled()

    source: muted ? "audio-volume-muted" : "audio-volume-high"
    active: mouse.containsMouse

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -2
        hoverEnabled: true
        onClicked: icon.toggled()
    }
}
