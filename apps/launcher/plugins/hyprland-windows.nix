# Launcher plugin: Hyprland window switcher.
#
# HYPRLAND-ONLY — driven entirely by `hyprctl clients -j` and
# `hyprctl dispatch focuswindow`, so it only produces items inside a
# Hyprland session.  Under any other compositor the script exits cleanly
# with no output and the plugin stays registered but empty.
#
# Lists every open Hyprland window, sorted by most-recently-focused, so the
# user can fuzzy-search and focus one.  Enter runs
# `hyprctl dispatch focuswindow address:<addr>`, which focuses the window and
# switches to its workspace automatically.
#
# Returns: { plugins :: AttrSet }
{
  pkgs,
  lib,
}:
let
  scanScript = pkgs.writeShellScript "kh-scan-hyprland-windows" ''
    # Scan open Hyprland windows and emit launcher items.
    # Usage: kh-scan-hyprland-windows
    # Output (one line per open window, sorted by most-recently-focused first):
    #   label TAB description TAB icon TAB callback TAB id
    #
    # - label:       window title (falls back to class, then "(untitled)")
    # - description: class · workspace <name>
    # - icon:        absolute icon path resolved from the window's WM class
    # - callback:    hyprctl dispatch focuswindow address:<addr>
    # - id:          Hyprland window address (stable while the window is alive)

    set -eu

    _hyprctl=${lib.getExe' pkgs.hyprland "hyprctl"}
    _jq=${lib.getExe pkgs.jq}

    # Fail silently when Hyprland IPC isn't reachable — the plugin stays
    # registered but empty so the launcher can still show "No results".
    _dump="$("$_hyprctl" clients -j 2>/dev/null || true)"
    [ -z "$_dump" ] && exit 0

    # Resolve a bare icon name to an absolute path; same lookup order as the
    # apps plugin so built-in apps and window rows stay visually consistent.
    # Prefers SVG; falls back to PNG at the largest available hicolor size.
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

    # Windows report their WM class (e.g. "firefox", "org.kde.dolphin") but
    # .desktop files name icons via Icon=, which often diverges from the class;
    # StartupWMClass= bridges the two.  Build a class → icon-name map once so
    # per-window lookup is O(1).
    declare -A _class_icon
    IFS=: read -ra _dirs <<< "''${XDG_DATA_DIRS:-/usr/share:/usr/local/share}:''${XDG_DATA_HOME:-$HOME/.local/share}"
    for _d in "''${_dirs[@]}"; do
      _adir="$_d/applications"
      [ -d "$_adir" ] || continue
      for _f in "$_adir"/*.desktop; do
        [ -f "$_f" ] || continue
        _in=0; _class=""; _icon=""
        while IFS= read -r _l; do
          case "$_l" in
            "[Desktop Entry]") _in=1 ;;
            "["*) [ "$_in" = 1 ] && break ;;
            "StartupWMClass="*) [ "$_in" = 1 ] && _class="''${_l#StartupWMClass=}" ;;
            "Icon="*)           [ "$_in" = 1 ] && _icon="''${_l#Icon=}" ;;
          esac
        done < "$_f"
        if [ -n "$_class" ] && [ -n "$_icon" ] && [ -z "''${_class_icon[$_class]:-}" ]; then
          _class_icon[$_class]="$_icon"
        fi
      done
    done

    _fallback_icon="$(_resolve_icon 'application-x-executable')"

    # focusHistoryID ascending: 0 = currently focused, 1 = previous, etc.
    printf '%s' "$_dump" | "$_jq" -r '
      sort_by(.focusHistoryID) | .[] |
      [.address, (.class // ""), (.title // ""), (.workspace.name // "")] |
      @tsv' | while IFS=$'\t' read -r _addr _class _title _wsname; do
      [ -z "$_addr" ] && continue

      _label="$_title"
      [ -z "$_label" ] && _label="$_class"
      [ -z "$_label" ] && _label="(untitled)"

      if [ -n "$_class" ] && [ -n "$_wsname" ]; then
        _desc="$_class · workspace $_wsname"
      elif [ -n "$_wsname" ]; then
        _desc="workspace $_wsname"
      else
        _desc="$_class"
      fi

      _icon_name="''${_class_icon[$_class]:-$_class}"
      _icon_path="$(_resolve_icon "$_icon_name")"
      [ -z "$_icon_path" ] && _icon_path="$_fallback_icon"

      _callback="$_hyprctl dispatch focuswindow address:$_addr"

      # Icon is a bare absolute path; HyprlandWindowIcon.qml wraps it in
      # file:// for its Image element.
      printf '%s\t%s\t%s\t%s\t%s\n' \
        "$_label" "$_desc" "$_icon_path" "$_callback" "$_addr"
    done
  '';
in
{
  plugins = {
    hyprland-windows = {
      script = toString scanScript;
      frecency = false;
      hasActions = false;
      placeholder = "Switch Hyprland window...";
      label = "Windows";
      default = false;
      # Icon column carries an absolute path; shared image primitive with a
      # letter-tile fallback covers the shape cleanly.
      iconDelegate = "LauncherIconFile.qml";
      hintText = "Enter focus window";
      keybindings = [
        {
          key = "Return";
          mode = "normal";
          run = "{callback}";
          helpKey = "Enter";
          helpDesc = "focus window";
        }
      ];
    };
  };
}
