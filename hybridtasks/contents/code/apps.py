#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Colby Johanson
# SPDX-License-Identifier: GPL-2.0-or-later
"""App-specific context-menu entries for Hybrid Task Manager.

  apps.py actions LAUNCHER_URL [LAUNCHER_URL...]
      Print JSON: {launcher_url: {"actions": [{"id", "name", "icon"}...],
                                  "places": [{"url", "name", "icon"}...]}}
      "actions" are the .desktop file's [Desktop Action ...] entries (Firefox's
      "New Private Window", Konsole's "Open a New Tab", ...). "places" is
      Dolphin's Places panel, only for Dolphin.
  apps.py run LAUNCHER_URL ACTION_ID
      Run one of those actions.

Launcher URLs are what the task manager calls LauncherUrlWithoutIcon:
"applications:firefox_firefox.desktop" or "file:///path/to/app.desktop".
Plasma's own task manager gets these from a private C++ backend that other
widgets can't load, hence this helper.
"""
import json
import os
import sys
import xml.etree.ElementTree as ET
from urllib.parse import unquote, urlparse

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

try:  # GLib >= 2.86 moved DesktopAppInfo to GioUnix
    gi.require_version("GioUnix", "2.0")
    from gi.repository import GioUnix  # noqa: E402
    DesktopAppInfo = GioUnix.DesktopAppInfo
except (ValueError, ImportError):
    DesktopAppInfo = Gio.DesktopAppInfo


def app_info(url):
    try:
        if url.startswith("applications:"):
            return DesktopAppInfo.new(url[len("applications:"):])
        if url.startswith("file://"):
            return DesktopAppInfo.new_from_filename(unquote(urlparse(url).path))
    except (TypeError, GLib.Error):
        pass
    return None


def actions(info):
    keyfile = GLib.KeyFile()
    try:
        keyfile.load_from_file(info.get_filename(), GLib.KeyFileFlags.NONE)
    except GLib.Error:
        keyfile = None
    out = []
    for action in info.list_actions():
        icon = ""
        if keyfile:
            try:
                icon = keyfile.get_string("Desktop Action " + action, "Icon")
            except GLib.Error:
                pass
        out.append({"id": action, "name": info.get_action_name(action), "icon": icon})
    return out


def places():
    path = os.path.join(GLib.get_user_data_dir(), "user-places.xbel")
    try:
        root = ET.parse(path).getroot()
    except (OSError, ET.ParseError):
        return []
    out = []
    for bookmark in root.iter("bookmark"):
        meta = {e.tag.split("}")[-1]: e for e in bookmark.iter()}
        if "IsHidden" in meta and (meta["IsHidden"].text or "").strip() == "true":
            continue
        only = meta.get("OnlyInApp")
        if only is not None and (only.text or "").strip() not in ("", "org.kde.dolphin", "dolphin"):
            continue
        icon = meta["icon"].get("name", "") if "icon" in meta else ""
        out.append({"url": bookmark.get("href"), "name": bookmark.findtext("title") or "", "icon": icon})
    return out


def main(argv):
    if len(argv) >= 2 and argv[0] == "actions":
        result = {}
        for url in argv[1:]:
            info = app_info(url)
            if not info:
                result[url] = {"actions": [], "places": []}
                continue
            is_dolphin = info.get_id() == "org.kde.dolphin.desktop"
            result[url] = {"actions": actions(info), "places": places() if is_dolphin else []}
        print(json.dumps(result))
        return 0
    if len(argv) == 3 and argv[0] == "run":
        info = app_info(argv[1])
        if info and argv[2] in info.list_actions():
            info.launch_action(argv[2], None)
            return 0
        return 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
