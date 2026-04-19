# Shell wrapper for kh-view with label support.
# Usage:
#   kh-view <file-or-dir> [<file-or-dir2> ...]                  # View files without labels
#   kh-view --label <file> <label> <desc> [--label <file> ...]  # View files with labels
#
# Directory args are expanded to their image files (png/jpg/jpeg/gif/
# webp/bmp/svg, non-recursive) sorted by filename.
#
# Examples:
#   nix run .#kh-view -- image1.png image2.png
#   nix run .#kh-view -- --label image1.png "Before" "Initial" --label image2.png "After" "Final"
#   nix run .#kh-view -- --label ./screenshots/ "All" "Screenshot batch"
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
  list=$(mktemp)
  trap 'rm -f "$list"' EXIT

  # Process args: mix of --label file label desc and positional files/dirs.
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--label" ]]; then
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

  if [[ ! -s "$list" ]]; then
    echo "Usage: kh-view <file-or-dir> [...]  |  --label <file> <label> <desc> ..." >&2
    exit 1
  fi

  export KH_VIEW_LIST="$list"
  ${if viewConfigPath != null then "exec \"$qs\" -p ${viewConfigPath}" else "exec \"$qs\" -c kh-view"}
''
