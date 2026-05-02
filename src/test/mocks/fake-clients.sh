#!/usr/bin/env bash
# Spawn fake Wayland clients on workspaces 1 and 2 so the bar's Workspaces
# plugin renders multiple non-empty workspaces and ScreencopyView has
# something to capture in tooltips. Also makes the live preview less
# desolate.
#
# Run by Hyprland's exec-once. WAYLAND_DISPLAY is set by the compositor
# before exec-once fires, but the IPC socket may not be accepting yet —
# retry hyprctl until it succeeds before trusting the dispatch.
#
# All output goes to /shared/state/fake-clients.log so we can see whether
# weston-simple-shm actually came up.

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

dispatch workspace 1
weston-simple-shm &
ws1_pid=$!
sleep 0.5

dispatch workspace 2
weston-simple-shm &
ws2_pid=$!
sleep 0.5

# Park back on workspace 1 so the bar shows it as focused.
dispatch workspace 1

echo "fake-clients: ws1=$ws1_pid ws2=$ws2_pid"

# Stay alive so the systemd unit (or just the exec-once entry) doesn't
# get reaped early. The child clients are already detached.
exec sleep infinity
