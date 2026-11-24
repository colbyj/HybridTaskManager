# Hybrid Task Manager

A task manager widget for KDE Plasma 6, for people who keep a lot of windows open.

Plasma's icons-only task manager groups each app's windows under one icon,
which makes it hard to pick the right window (and easy to open a duplicate
because you didn't spot the one already open). Hybrid Task Manager keeps
grouping for most apps, but for the apps you choose it gives **every window its
own button, labelled with just the part of the title that tells the windows
apart** (e.g. `shop/api` rather than `user@host: ~/src/shop/api — Konsole`).

Other features:

- Clicking a grouped app opens a text list of its windows, with minimize,
  maximize and close buttons on each
- An app's windows stay next to each other; drag to reorder them or the whole app
- When the bar is full, labels shrink, minimized windows can collapse into one
  button, and anything left over goes into a "+N" list
- A brief outline around the window you focused, if it's on another monitor
- Right-click: the app's own actions (e.g. Firefox's "New Private Window",
  Konsole's "Open a New Tab", Dolphin's Places); move to another desktop or
  monitor; minimize, maximize or close all
- Audio indicator (click to mute), unread-count and progress badges, and a bell
  for unseen notifications

## Requirements

- KDE Plasma 6 (developed on Plasma 6.6, Wayland)
- Python 3 with `dbus` and `gi` (on Debian/Ubuntu: `python3-dbus`, `python3-gi`;
  both ship with Kubuntu). Used for moving windows between monitors, for the
  right-click menu's app actions, and for badges.

There's nothing to build: it's a QML/JavaScript widget plus small Python helpers.

## Install

**From a release:** download the `.plasmoid` file from the latest
[release](https://github.com/colbyj/HybridTaskManager/releases), then either
run

```sh
kpackagetool6 -t Plasma/Applet -i HybridTaskManager-0.1.plasmoid
```

or right-click your panel → **Add or Manage Widgets** → **Get New Widgets** →
**Install Widget From Local File…** and pick the file.

**From source:**

```sh
git clone https://github.com/colbyj/HybridTaskManager.git
cd HybridTaskManager
kpackagetool6 -t Plasma/Applet -i hybridtasks
```

Then right-click your panel → **Add or Manage Widgets** → search for
**Hybrid Task Manager** and drag it onto the panel (usually replacing the
existing task manager).

## Use

- **Give an app one button per window:** right-click it → untick
  **Allow this program to be grouped**. Tick it again to go back to one grouped icon.
- **Settings:** right-click the task manager → **Configure Hybrid Task Manager…**
  (rows, button widths, labels, collapsing minimized windows, the focus outline).

## Update

**From a release:** download the new `.plasmoid` and run
`kpackagetool6 -t Plasma/Applet -u <file>.plasmoid`, then restart Plasma as below.

**From source:** from the cloned folder (skip `git pull` if you're testing your own edits):

```sh
git pull
kpackagetool6 -t Plasma/Applet -u hybridtasks
systemctl --user restart plasma-plasmashell   # widgets already on a panel only reload on restart
```

## Making a release

1. Bump `Version` in `hybridtasks/metadata.json`, commit, and tag it (`git tag v0.2`).
2. Build the package from the tag:
   `git archive --format=zip -o dist/HybridTaskManager-0.2.plasmoid v0.2:hybridtasks`
3. Push the tag, create a GitHub release from it, and attach the `.plasmoid`.

## Uninstall

Remove it from your panel, then:

```sh
kpackagetool6 -t Plasma/Applet -r local.hybridtasks
```

## Repository layout

- `hybridtasks/` — the widget
  - `contents/ui/` — QML (`main.qml` is the entry point; `Task.qml` is one button)
  - `contents/code/` — title-label logic (`labels.js`) and Python helpers
    (`kwin.py` moves windows between monitors, `badges.py` relays app badges)
  - `contents/config/` — settings schema (`main.xml`) and the settings page entry
  - `metadata.json` — widget ID (`local.hybridtasks`), name and version

## Issues

Bug reports and suggestions are welcome on the
[issue tracker](https://github.com/colbyj/HybridTaskManager/issues). It helps to
include your Plasma version, X11 or Wayland, and — for label problems — the
full window title and what you expected the button to say.

## License

GPL-2.0-or-later — see [LICENSE](LICENSE). Copyright 2026 Colby Johanson.

## Credits

Draws on [Fancy Tasks NG](https://github.com/daydve/FancyTasksNG) by Vitaliy
Elin and contributors (itself derived from KDE Plasma's task manager):

- The audio-stream handling in `hybridtasks/contents/ui/main.qml` is adapted
  from its `AudioStreams.qml`; the original copyright notices are kept in that
  file's header.
- The badge relay (`hybridtasks/contents/code/badges.py`) follows the approach
  of its `unity_bridge.py`.

It also uses the same Breeze task-button artwork and KDE window-management APIs
as Plasma's own task manager.
