{ pkgs, lib }:
pkgs.writeShellScript "kh-cliphist-attr-watch" ''
  # Clipboard change handler for wl-paste --watch.
  # Discards stdin (raw clipboard content), waits for cliphist to record
  # the new entry, queries the active Hyprland window, and prints
  # id<TAB>app_class to stdout.
  # Query the active window immediately — before the sleep — so we capture
  # the app that was focused at the moment of the copy, not 0.4 s later.
  exec 0</dev/null
  app=$(${lib.getExe' pkgs.hyprland "hyprctl"} activewindow -j 2>/dev/null \
    | ${lib.getExe pkgs.jq} -r ".class // empty" 2>/dev/null)
  test -z "$app" && exit 0
  # Wait for cliphist to record the new entry, then read the latest ID.
  sleep 0.4
  entry=$(${lib.getExe pkgs.cliphist} list 2>/dev/null \
    | { IFS= read -r l; printf '%s' "$l"; })
  IFS=$'\t' read -r id _ <<< "$entry"
  test -n "$id" && printf '%s\t%s\n' "$id" "$app"
''
