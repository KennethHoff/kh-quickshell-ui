# Shell wrapper for kh-view that handles file/directory args and stdin.
# Usage:
#   kh-view <file-or-dir> [<file-or-dir2> ...]  # View specific files
#   <cmd> | kh-view                              # View stdin
#
# Directory args are expanded to their image files (png/jpg/jpeg/gif/
# webp/bmp/svg, non-recursive) sorted by filename.
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
  if [[ $# -ge 1 ]]; then
    for arg in "$@"; do
      if [[ -d "$arg" ]]; then
        "$find" "$arg" -maxdepth 1 -type f \
          \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
             -o -iname '*.gif' -o -iname '*.webp' -o -iname '*.bmp' \
             -o -iname '*.svg' \) | "$sort" >> "$list"
      else
        printf '%s\n' "$arg" >> "$list"
      fi
    done
    export KH_VIEW_LIST="$list"
    ${
      if viewConfigPath != null then "exec \"$qs\" -p ${viewConfigPath}" else "exec \"$qs\" -c kh-view"
    }
  else
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp"
    printf '%s\n' "$tmp" >> "$list"
    export KH_VIEW_LIST="$list"
    ${if viewConfigPath != null then "\"$qs\" -p ${viewConfigPath}" else "\"$qs\" -c kh-view"}
  fi
''
