{ pkgs, lib }:
pkgs.writeShellScript "kh-scan-apps" ''
  # Scan XDG data dirs for installed .desktop apps.
  # Output (one line per app, sorted by name case-insensitively):
  #   filepath TAB name TAB exec TAB comment TAB terminal TAB icon
  declare -A _seen
  IFS=: read -ra _dirs <<< "''${XDG_DATA_DIRS:-/usr/share:/usr/local/share}:''${XDG_DATA_HOME:-$HOME/.local/share}"
  for _d in "''${_dirs[@]}"; do
    _adir="$_d/applications"
    [ -d "$_adir" ] || continue
    for _f in "$_adir"/*.desktop; do
      [ -f "$_f" ] || continue
      _in=0; _name=; _exec=; _comment=; _terminal=; _icon=; _nd=; _hid=; _type=
      while IFS= read -r _l; do
        case "$_l" in
          "[Desktop Entry]") _in=1 ;;
          "["*) [ "$_in" = 1 ] && break ;;
          "Name="*)      [ "$_in" = 1 ] && _name="''${_l#Name=}" ;;
          "Exec="*)      [ "$_in" = 1 ] && _exec="''${_l#Exec=}" ;;
          "Comment="*)   [ "$_in" = 1 ] && _comment="''${_l#Comment=}" ;;
          "Terminal="*)  [ "$_in" = 1 ] && _terminal="''${_l#Terminal=}" ;;
          "Icon="*)      [ "$_in" = 1 ] && _icon="''${_l#Icon=}" ;;
          "NoDisplay="*) [ "$_in" = 1 ] && _nd="''${_l#NoDisplay=}" ;;
          "Hidden="*)    [ "$_in" = 1 ] && _hid="''${_l#Hidden=}" ;;
          "Type="*)      [ "$_in" = 1 ] && _type="''${_l#Type=}" ;;
        esac
      done < "$_f"
      [ "$_nd" = "true" ] && continue
      [ "$_hid" = "true" ] && continue
      [ -n "$_type" ] && [ "$_type" != "Application" ] && continue
      [ -z "$_name" ] && continue
      [ -z "$_exec" ] && continue
      _id="''${_f##*/}"; _id="''${_id%.desktop}"
      [ -n "''${_seen[$_id]:-}" ] && continue
      _seen[$_id]=1
      for _fc in '%f' '%F' '%u' '%U' '%d' '%D' '%n' '%N' '%i' '%c' '%k'; do
        _exec="''${_exec//$_fc/}"
      done
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$_f" "$_name" "$_exec" "$_comment" "$_terminal" "$_icon"
    done
  done | sort -t$'\t' -k2 -f
''
