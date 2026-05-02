#!/usr/bin/env bash
# Spawn two fake Wayland clients and place them on workspaces 1 and 2 so the
# bar's Workspaces plugin has multiple non-empty workspaces to render and
# ScreencopyView has something to capture in tooltips.
#
# Run by Hyprland's exec-once after the compositor is up.

set -e

# Workspace 1
hyprctl dispatch workspace 1 >/dev/null
weston-simple-shm >/dev/null 2>&1 &
sleep 0.3

# Workspace 2
hyprctl dispatch workspace 2 >/dev/null
weston-simple-shm >/dev/null 2>&1 &
sleep 0.3

# Park back on workspace 1 so the bar shows it as focused.
hyprctl dispatch workspace 1 >/dev/null

# Stay alive so systemd doesn't mark the unit failed; child clients are
# already detached above.
exec sleep infinity
