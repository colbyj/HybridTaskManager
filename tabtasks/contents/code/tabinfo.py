#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Colby Johanson
# SPDX-License-Identifier: GPL-2.0-or-later
"""Helper for the Tab Tasks widget.

  tabinfo.py list                         -> JSON of Konsole windows/tabs and Dolphin windows
  tabinfo.py konsole-switch SERVICE WIN SESSION
  tabinfo.py konsole-newtab SERVICE WIN
  tabinfo.py dolphin-newtab SERVICE
"""
import json
import os
import re
import sys

import dbus

HOME = os.path.expanduser("~")


def short_path(p):
    if p == HOME:
        return "~"
    if p.startswith(HOME + "/"):
        return "~" + p[len(HOME):]
    return p


def proc_info(pid):
    cwd, comm = "", ""
    try:
        cwd = os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        pass
    try:
        with open(f"/proc/{pid}/comm") as f:
            comm = f.read().strip()
    except OSError:
        pass
    return cwd, comm


def child_nodes(bus, service, path):
    xml = dbus.Interface(bus.get_object(service, path),
                         "org.freedesktop.DBus.Introspectable").Introspect()
    return re.findall(r'<node name="([^"]+)"', xml)


def konsole(bus, service):
    pid = int(service.rsplit("-", 1)[1])
    windows = []
    for w in child_nodes(bus, service, "/Windows"):
        win = dbus.Interface(bus.get_object(service, "/Windows/" + w), "org.kde.konsole.Window")
        current = str(win.currentSession())
        tabs = []
        for s in win.sessionList():
            se = dbus.Interface(bus.get_object(service, "/Sessions/" + s), "org.kde.konsole.Session")
            title = raw = str(se.title(1))
            fg = int(se.foregroundProcessId()) or int(se.processId())
            cwd, comm = proc_info(fg)
            # A bare shell's title is just "user@host: path" -- show the folder instead.
            shellish = re.match(r"^[^@\s]+@[^:\s]+:\s*(.*)$", title)
            if shellish:
                title = shellish.group(1) or short_path(cwd)
            tabs.append({
                "session": str(s),
                "title": title,
                "rawTitle": raw,
                "cwd": short_path(cwd),
                "program": comm,
                "current": str(s) == current,
            })
        windows.append({"service": service, "pid": pid, "window": w,
                        "rawCurrentTitle": next((t["rawTitle"] for t in tabs if t["current"]), ""),
                        "tabs": tabs})
    return windows


def dolphin(bus, service):
    pid = int(service.rsplit("-", 1)[1])
    return [{"service": service, "pid": pid, "path": "/dolphin/" + n}
            for n in child_nodes(bus, service, "/dolphin") if re.match(r"Dolphin_\d+$", n)]


def cmd_list(bus):
    out = {"konsole": [], "dolphin": []}
    for name in bus.list_names():
        try:
            if name.startswith("org.kde.konsole-"):
                out["konsole"] += konsole(bus, name)
            elif name.startswith("org.kde.dolphin-"):
                out["dolphin"] += dolphin(bus, name)
        except dbus.DBusException:
            pass  # app closed mid-query; skip it
    print(json.dumps(out))


def main():
    bus = dbus.SessionBus()
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "list":
        cmd_list(bus)
    elif cmd == "konsole-switch":
        service, win, session = args
        dbus.Interface(bus.get_object(service, "/Windows/" + win),
                       "org.kde.konsole.Window").setCurrentSession(int(session))
    elif cmd == "konsole-newtab":
        service, win = args
        dbus.Interface(bus.get_object(service, "/Windows/" + win),
                       "org.kde.konsole.Window").newSession()
    elif cmd == "dolphin-newtab":
        service, path = args
        dbus.Interface(bus.get_object(service, path),
                       "org.kde.dolphin.MainWindow").openDirectories([HOME], False)


if __name__ == "__main__":
    main()
