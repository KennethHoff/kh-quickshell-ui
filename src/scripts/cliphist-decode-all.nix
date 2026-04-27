{ pkgs, lib }:
pkgs.writeShellScript "kh-cliphist-decode-all" ''
  ${lib.getExe pkgs.cliphist} list | while IFS=$'\t' read -r id preview; do
      [[ "$preview" == "[[binary"* ]] && continue
      [[ ''${#preview} -lt 100 ]] && continue
      text=$(printf '%s\t%s\n' "$id" "$preview" | ${lib.getExe pkgs.cliphist} decode)
      json=$(printf '%s' "$text" | ${lib.getExe pkgs.jq} -Rs .)
      printf '%s\t%s\n' "$id" "$json"
  done
''
