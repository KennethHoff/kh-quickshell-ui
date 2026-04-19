# Shell wrapper for kh-view with label + history support.
# Usage:
#   kh-view <file-or-dir> [<file-or-dir2> ...]                  # View files without labels
#   kh-view --label <file> <label> <desc> [--label <file> ...]  # View files with labels
#   kh-view --recall [N]                                         # Recall Nth-from-newest session (default 1)
#   kh-view --list-history                                       # Print recent sessions
#
# Directory args are expanded to their image files (png/jpg/jpeg/gif/
# webp/bmp/svg, non-recursive) sorted by filename.
#
# Normal invocations append a session entry to the MetaStore-format file
#   $XDG_DATA_HOME/kh-view/meta/history (one line per session:
#   <epoch><TAB><compact JSON items array>).  MetaStore in QML reads the
#   same file; --recall reads without appending so recalls don't rewrite
#   history.
#
# Examples:
#   nix run .#kh-view -- image1.png image2.png
#   nix run .#kh-view -- --label image1.png "Before" "Initial" --label image2.png "After" "Final"
#   nix run .#kh-view -- --label ./screenshots/ "All" "Screenshot batch"
#   nix run .#kh-view -- --recall          # Reopen the most recent gallery
#   nix run .#kh-view -- --recall 3        # Reopen the third-most-recent gallery
#   nix run .#kh-view -- --list-history    # Print recent sessions
{
  pkgs,
  lib,
  viewConfigPath ? null,
}:
pkgs.writeShellScript "kh-view-wrapper" ''
  set -e
  qs=${lib.getExe pkgs.quickshell}
  find=${lib.getExe' pkgs.findutils "find"}
  sort=${lib.getExe' pkgs.coreutils "sort"}
  date=${lib.getExe' pkgs.coreutils "date"}
  jq=${lib.getExe pkgs.jq}

  data_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/kh-view/meta"
  history="$data_dir/history"
  mkdir -p "$data_dir"

  recall_n=""
  list_history=false
  list=$(mktemp)
  trap 'rm -f "$list"' EXIT

  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--list-history" ]]; then
      list_history=true
      shift
    elif [[ "$1" == "--recall" ]]; then
      shift
      if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
        recall_n="$1"
        shift
      else
        recall_n=1
      fi
    elif [[ "$1" == "--label" ]]; then
      shift
      if [[ $# -lt 3 ]]; then
        echo "Error: --label requires <file> <label> <description>" >&2
        exit 1
      fi
      file="$1"
      label="$2"
      desc="$3"
      shift 3
      if [[ -d "$file" ]]; then
        "$find" "$file" -maxdepth 1 -type f \
          \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
             -o -iname '*.gif' -o -iname '*.webp' -o -iname '*.bmp' \
             -o -iname '*.svg' \) | "$sort" | while read -r fpath; do
          printf '%s\t%s\t%s\n' "$fpath" "$label" "$desc" >> "$list"
        done
      else
        printf '%s\t%s\t%s\n' "$file" "$label" "$desc" >> "$list"
      fi
    elif [[ -d "$1" ]]; then
      "$find" "$1" -maxdepth 1 -type f \
        \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
           -o -iname '*.gif' -o -iname '*.webp' -o -iname '*.bmp' \
           -o -iname '*.svg' \) | "$sort" >> "$list"
      shift
    else
      printf '%s\n' "$1" >> "$list"
      shift
    fi
  done

  if [[ "$list_history" == true ]]; then
    if [[ ! -s "$history" ]]; then
      echo "(no history)"
      exit 0
    fi
    # MetaStore rows: <ts>\t<json-items>.  Sort newest-first and format.
    idx=0
    while IFS=$'\t' read -r ts items_json; do
      idx=$((idx + 1))
      summary=$(printf '%s' "$items_json" | "$jq" -r '
        (length) as $count |
        (.[0] // {}) as $first |
        ($first.label // "") as $label |
        ($first.path // "") as $path |
        "\($count)\t\($label)\t\($path)"
      ')
      count=$(printf '%s' "$summary" | cut -f1)
      label=$(printf '%s' "$summary" | cut -f2)
      first_path=$(printf '%s' "$summary" | cut -f3)
      when=$("$date" -d "@$ts" '+%Y-%m-%d %H:%M')
      head="$label"
      [[ -z "$head" ]] && head="$first_path"
      printf '%3d  %s  (%d item%s)  %s\n' "$idx" "$when" "$count" \
        "$( [[ "$count" == "1" ]] || echo s )" "$head"
    done < <(sort -t$'\t' -k1,1nr -- "$history")
    exit 0
  fi

  if [[ -n "$recall_n" ]]; then
    if [[ ! -s "$history" ]]; then
      echo "Error: no history to recall" >&2
      exit 1
    fi
    total=$(wc -l < "$history")
    if [[ $recall_n -lt 1 || $recall_n -gt $total ]]; then
      echo "Error: no session at position $recall_n (history has $total entr$( [[ "$total" == "1" ]] && echo y || echo ies ))" >&2
      exit 1
    fi
    # History rows are unordered w.r.t. time; sort newest-first, then pick Nth.
    sort -t$'\t' -k1,1nr -- "$history" \
      | sed -n "''${recall_n}p" \
      | cut -f2- \
      | "$jq" -r '.[] | "\(.path)\t\(.label)\t\(.desc)"' > "$list"
    if [[ ! -s "$list" ]]; then
      echo "Error: recalled session has no items" >&2
      exit 1
    fi
  else
    if [[ ! -s "$list" ]]; then
      echo "Usage: kh-view <file-or-dir> [...]  |  --label <file> <label> <desc> ..." >&2
      echo "       kh-view --recall [N]  |  --list-history" >&2
      exit 1
    fi
    ts=$("$date" +%s)
    items_json=$("$jq" -c -R -s '
      split("\n")
      | map(select(length > 0))
      | map(split("\t"))
      | map({ path: .[0], label: (.[1] // ""), desc: (.[2] // "") })
    ' < "$list")
    printf '%s\t%s\n' "$ts" "$items_json" >> "$history"
  fi

  export KH_VIEW_LIST="$list"
  export KH_VIEW_HISTORY="$history"
  ${if viewConfigPath != null then "exec \"$qs\" -p ${viewConfigPath}" else "exec \"$qs\" -c kh-view"}
''
