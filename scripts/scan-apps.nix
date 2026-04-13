{ pkgs, lib }:
pkgs.writeShellScript "kh-scan-apps" ''
  # Scan XDG data dirs for installed .desktop apps.
  # Output (one line per app, sorted by name case-insensitively):
  #   filepath TAB name TAB exec TAB comment TAB terminal TAB icon

  # Resolve a bare icon name to an absolute path.
  # Prefers SVG; falls back to PNG at the largest available size.
  # Searches hicolor XDG icon theme dirs, then /usr/share/pixmaps/.
  # Returns empty string if the icon cannot be found.
  _resolve_icon() {
    local _ic="$1"
    [ -z "$_ic" ] && { printf '''; return; }
    case "$_ic" in
      /*) [ -f "$_ic" ] && printf '%s' "$_ic" || printf '''; return ;;
    esac
    local _d _size _cat _p
    local _sizes="scalable 256x256 128x128 96x96 64x64 48x48 32x32 24x24 22x22 16x16"
    local _cats="apps applications"
    IFS=: read -ra _xdg <<< "''${XDG_DATA_DIRS:-/usr/share:/usr/local/share}:''${XDG_DATA_HOME:-$HOME/.local/share}"
    for _d in "''${_xdg[@]}"; do
      [ -d "$_d/icons" ] || continue
      for _size in $_sizes; do
        for _cat in $_cats; do
          _p="$_d/icons/hicolor/$_size/$_cat/$_ic.svg"
          [ -f "$_p" ] && { printf '%s' "$_p"; return; }
        done
      done
      for _size in $_sizes; do
        for _cat in $_cats; do
          _p="$_d/icons/hicolor/$_size/$_cat/$_ic.png"
          [ -f "$_p" ] && { printf '%s' "$_p"; return; }
        done
      done
    done
    for _ext in svg png xpm; do
      _p="/usr/share/pixmaps/$_ic.$_ext"
      [ -f "$_p" ] && { printf '%s' "$_p"; return; }
    done
    printf '''
  }

  _fallback_icon="$(_resolve_icon 'application-x-executable')"

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
      _icon_resolved="$(_resolve_icon "$_icon")"
      [ -z "$_icon_resolved" ] && _icon_resolved="$_fallback_icon"
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$_f" "$_name" "$_exec" "$_comment" "$_terminal" "$_icon_resolved"
    done
  done | sort -t$'\t' -k2 -f
''
