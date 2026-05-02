#!/usr/bin/env bash
# Spawn fake Wayland clients on workspaces 1 and 2 so the bar's Workspaces
# plugin renders multiple non-empty workspaces, ScreencopyView has
# something to capture in tooltips, and the launcher's hyprland-windows
# plugin produces a non-empty list. Also makes the live preview less
# desolate.
#
# Each client is `foot -a <AppId> -T <Title> -- sleep infinity`. The
# app-id is the Wayland app_id (== Hyprland's `class`), and the launcher's
# app fixture has matching `StartupWMClass=<AppId>` entries so window
# rows resolve to the same curated icon shown in the Apps list.
#
# Run by Hyprland's exec-once. WAYLAND_DISPLAY is set by the compositor
# before exec-once fires, but the IPC socket may not be accepting yet —
# retry hyprctl until it succeeds before trusting the dispatch.
#
# All output goes to /shared/state/fake-clients.log so we can see whether
# the spawn actually came up.

LOG=/shared/state/fake-clients.log
mkdir -p /shared/state
: > "$LOG"
exec >>"$LOG" 2>&1
set -x

# Wait until hyprctl can talk to the running Hyprland instance.
for _ in $(seq 50); do
  hyprctl version >/dev/null 2>&1 && break
  sleep 0.1
done

dispatch() {
  for _ in $(seq 10); do
    hyprctl dispatch "$@" && return 0
    sleep 0.1
  done
  return 1
}

# Two named windows on workspace 1 (so the launcher's Windows plugin has
# variety) and one on workspace 2 (so the Workspaces plugin shows >1
# populated workspace).
dispatch workspace 1
foot -a Files -T Files -- sleep infinity &
ws1a_pid=$!
sleep 0.4
foot -a Browser -T Browser -- sleep infinity &
ws1b_pid=$!
sleep 0.4

dispatch workspace 2
foot -a Terminal -T Terminal -- sleep infinity &
ws2_pid=$!
sleep 0.4

# Park back on workspace 1 so the bar shows it as focused.
dispatch workspace 1

echo "fake-clients: ws1a=$ws1a_pid ws1b=$ws1b_pid ws2=$ws2_pid"

# Stay alive so the systemd unit (or just the exec-once entry) doesn't
# get reaped early. The child clients are already detached.
exec sleep infinity
