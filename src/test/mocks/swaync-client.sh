#!/usr/bin/env bash
# Fake swaync-client. The bar's Notifications plugin spawns
# `swaync-client --subscribe-waybar` and parses one JSON object per line.
# We emit a single fixed line then sleep forever so the plugin treats us as
# the live daemon.
case "$*" in
  *"--subscribe-waybar"*)
    echo '{"count":2,"visible":false,"inhibited":false,"dnd":false}'
    exec sleep infinity
    ;;
  *"--close-all"*)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
