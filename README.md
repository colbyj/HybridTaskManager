# Hybrid Task Manager

A KDE Plasma 6 task manager for people with many windows open. Apps you mark
"don't group" get one button per window, labelled with just the part of the
title that tells the windows apart; everything else stays grouped as icons.
It also keeps each app's windows together, collapses minimized windows,
overflows into a "+N" list, and can move windows between desktops and monitors.

- `hybridtasks/` — the widget (install with `kpackagetool6 -t Plasma/Applet -i hybridtasks`)
- `tabtasks/` — an earlier prototype listing Konsole/Dolphin tabs, kept for reference

## License

GPL-2.0-or-later — see [LICENSE](LICENSE).

Copyright 2026 Colby Johanson.

## Credits

Hybrid Task Manager draws on [Fancy Tasks NG](https://github.com/daydve/FancyTasksNG)
by Vitaliy Elin and contributors (itself derived from KDE Plasma's task
manager):

- The audio-stream handling in `hybridtasks/contents/ui/main.qml` is adapted
  from its `AudioStreams.qml`; the original copyright notices are kept in that
  file's header.
- The badge bridge (`hybridtasks/contents/code/badges.py`) follows the approach
  of its `unity_bridge.py`.

It also uses the same Breeze task-button artwork and KDE window-management
APIs as Plasma's own task manager.
