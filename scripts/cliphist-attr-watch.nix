{ pkgs, lib }:
pkgs.writeShellScript "kh-cliphist-attr-watch" ''
  # Clipboard change handler for wl-paste --watch.
  # Discards stdin (raw clipboard content), waits for cliphist to record
  # the new entry, queries the active Hyprland window, and prints
  # id<TAB>app_class to stdout.
  exec 0</dev/null
  sleep 0.4
  entry=$(${lib.getExe pkgs.cliphist} list 2>/dev/null \
    | { IFS= read -r l; printf '%s' "$l"; })
  IFS=$'\t' read -r id _ <<< "$entry"
  test -z "$id" && exit 0
  app=$(${lib.getExe' pkgs.hyprland "hyprctl"} activewindow -j 2>/dev/null \
    | ${lib.getExe pkgs.jq} -r ".class // empty" 2>/dev/null)
  test -n "$app" && printf '%s\t%s\n' "$id" "$app"
''
