#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Colby Johanson
# SPDX-License-Identifier: GPL-2.0-or-later
"""Run small one-off KWin scripts for Window Bar.

  kwin.py to-screen OUTPUT_NAME WINDOW_UUID [WINDOW_UUID...]
  kwin.py find WINDOW_UUID            (dry run: logs the match to KWin's journal)

KWin has no D-Bus call for "send this window to that monitor", but it can load
a script over D-Bus. We write a throwaway script, run it, then unload it.
"""
import json
import os
import sys
import tempfile
import time

import dbus

SCRIPT = """
const wanted = %(ids)s;
const outputName = %(output)s;
const dryRun = %(dry)s;
const out = workspace.screens.find(s => s.name === outputName);
for (const w of workspace.windowList()) {
    if (!wanted.includes(w.internalId.toString())) continue;
    if (dryRun) { print("windowbar: found", w.caption, "on", w.output.name); continue; }
    if (out) workspace.sendClientToScreen(w, out);
}
"""


def run(ids, output, dry):
    src = SCRIPT % {"ids": json.dumps(ids), "output": json.dumps(output), "dry": "true" if dry else "false"}
    fd, path = tempfile.mkstemp(prefix="windowbar-", suffix=".js")
    with os.fdopen(fd, "w") as f:
        f.write(src)
    name = "windowbar-oneoff-%d" % os.getpid()
    bus = dbus.SessionBus()
    scripting = dbus.Interface(bus.get_object("org.kde.KWin", "/Scripting"), "org.kde.kwin.Scripting")
    try:
        sid = int(scripting.loadScript(path, name, signature="ss"))
        script = bus.get_object("org.kde.KWin", "/Scripting/Script%d" % sid)
        dbus.Interface(script, "org.kde.kwin.Script").run()
        time.sleep(0.2)
    finally:
        scripting.unloadScript(name)
        os.unlink(path)


def main():
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "to-screen":
        run(args[1:], args[0], dry=False)
    elif cmd == "find":
        run(args, "", dry=True)


if __name__ == "__main__":
    main()
