# Launcher plugin: kh-view gallery history.
#
# Lists recent kh-view sessions from $XDG_DATA_HOME/kh-view/meta/history,
# newest first.  Each row shows the session's date + first-item label and
# the total item count.  Enter launches kh-view via --recall-ts <epoch> so
# the callback stays stable regardless of how many sessions have landed
# since the launcher scanned.
#
# After kh-view exits, the callback re-opens the launcher with the
# Galleries plugin active so Esc in the viewer feels like "back to the
# gallery" rather than "close everything".  On a fresh install with no
# launcher daemon running the IPC call is a silent no-op.
#
# History persistence lives in the kh-view wrapper — the plugin only
# reads.  If the file is missing (fresh install) the script exits cleanly
# and the plugin stays registered but empty.
#
# Returns: { plugins :: AttrSet }
{
  pkgs,
  lib,
  khViewWrapper,
}:
let
  scanScript = pkgs.writeShellScript "kh-scan-kh-view-history" ''
    # Scan kh-view session history and emit launcher items.
    # Usage: kh-scan-kh-view-history
    # Output (one line per session, newest first):
    #   label TAB description TAB icon TAB callback TAB id
    #
    # - label:       "YYYY-MM-DD HH:MM"  ("  ·  <first label>" appended when present)
    # - description: "<N> item(s)"       (+ first path when no label exists)
    # - icon:        first item's path when it is an image, else empty (→ letter tile)
    # - callback:    kh-view --recall-ts <ts>; launcher activatePlugin
    # - id:          <ts>  (stable; MetaStore key for this entry)

    set -eu

    _jq=${lib.getExe pkgs.jq}
    _date=${lib.getExe' pkgs.coreutils "date"}
    _sort=${lib.getExe' pkgs.coreutils "sort"}
    _kh_view=${khViewWrapper}
    _qs=${lib.getExe pkgs.quickshell}

    # When kh-view exits, re-open the launcher on the Galleries plugin so
    # Esc in the viewer returns to the gallery list (rather than closing
    # everything).  `|| true` keeps the pipeline resilient if no launcher
    # daemon is listening.
    _reopen="$_qs ipc call launcher activatePlugin kh-view-history || true"

    history="''${XDG_DATA_HOME:-$HOME/.local/share}/kh-view/meta/history"
    [ -f "$history" ] || exit 0

    _is_image() {
      case "''${1,,}" in
        *.png|*.jpg|*.jpeg|*.gif|*.webp|*.bmp|*.svg) return 0 ;;
        *) return 1 ;;
      esac
    }

    # MetaStore row: <ts>\t<compact JSON items array>.  Sort newest-first.
    "$_sort" -t$'\t' -k1,1nr "$history" | while IFS=$'\t' read -r ts items_json; do
      [ -z "$ts" ] && continue

      # Extract count + first item's label/path in one jq call.
      info=$(printf '%s' "$items_json" | "$_jq" -r '
        (length) as $count |
        (.[0] // {}) as $first |
        ($first.label // "") as $label |
        ($first.path // "") as $path |
        "\($count)\t\($label)\t\($path)"
      ')
      count=$(printf '%s' "$info" | cut -f1)
      first_label=$(printf '%s' "$info" | cut -f2)
      first_path=$(printf '%s' "$info" | cut -f3)

      when=$("$_date" -d "@$ts" '+%Y-%m-%d %H:%M')

      # Label: date + first session label (if any) — this is the haystack
      # for fuzzy search.
      if [ -n "$first_label" ]; then
        label="$when  ·  $first_label"
      else
        label="$when"
      fi

      # Description: item count, plus first path for context when there is
      # no session label.
      if [ "$count" = "1" ]; then
        desc="1 item"
      else
        desc="$count items"
      fi
      if [ -z "$first_label" ] && [ -n "$first_path" ]; then
        desc="$desc  ·  $first_path"
      fi

      icon=""
      if _is_image "$first_path"; then
        icon="$first_path"
      fi

      callback="$_kh_view --recall-ts $ts; $_reopen"

      printf '%s\t%s\t%s\t%s\t%s\n' \
        "$label" "$desc" "$icon" "$callback" "$ts"
    done
  '';
in
{
  plugins = {
    kh-view-history = {
      script = toString scanScript;
      frecency = false;
      hasActions = false;
      placeholder = "Search galleries...";
      label = "Galleries";
      default = false;
      # Icon column is either a file path or empty; reuse the shared image
      # primitive so the letter-tile fallback kicks in when the first item
      # is text (no displayable icon).
      iconDelegate = "LauncherIconFile.qml";
      hintText = "Enter open";
      keybindings = [
        {
          key = "Return";
          mode = "normal";
          run = "{callback}";
          helpKey = "Enter";
          helpDesc = "open gallery";
        }
      ];
    };
  };
}
