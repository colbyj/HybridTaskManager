#!/usr/bin/env python3
"""Badge/progress bridge for Window Bar.

Apps report unread counts and progress with the Unity launcher API: a
com.canonical.Unity.LauncherEntry.Update(app_uri, props) signal sent from any
object path. Plasma's QML D-Bus watcher can't subscribe to "any sender, any
path", so this process does, keeps the latest state per app (apps send only
what changed), and re-emits the full state from a fixed name:

    service local.windowbar.Badges, path /Badges,
    signal  local.windowbar.Badges.Update(s app_uri, i count, d progress)

count is 0 when hidden; progress is -1 when hidden. One instance is enough for
all Window Bar widgets; extra instances exit. It exits with plasmashell.
"""
import ctypes
import signal
import sys

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

NAME = "local.windowbar.Badges"


def die_with_parent():
    try:
        ctypes.CDLL("libc.so.6").prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG
    except OSError:
        pass


class Bridge(dbus.service.Object):
    def __init__(self, bus):
        self.state = {}
        name = dbus.service.BusName(NAME, bus=bus, do_not_queue=True)
        super().__init__(name, "/Badges")

    @dbus.service.signal(NAME, signature="sid")
    def Update(self, app_uri, count, progress):
        pass

    def on_launcher_entry(self, app_uri, props, **_):
        s = self.state.setdefault(str(app_uri), {"count": 0, "count-visible": False,
                                                 "progress": 0.0, "progress-visible": False})
        for k in s:
            if k in props:
                s[k] = props[k]
        count = int(s["count"]) if s["count-visible"] else 0
        progress = float(s["progress"]) if s["progress-visible"] else -1.0
        self.Update(str(app_uri), count, progress)


def main():
    die_with_parent()
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    try:
        bridge = Bridge(bus)
    except dbus.exceptions.NameExistsException:
        return  # another Window Bar already runs the bridge
    bus.add_signal_receiver(bridge.on_launcher_entry, signal_name="Update",
                            dbus_interface="com.canonical.Unity.LauncherEntry")
    GLib.MainLoop().run()


if __name__ == "__main__":
    sys.exit(main())
