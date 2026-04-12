{ pkgs, lib }:
pkgs.writeShellScript "kh-scan-actions" ''
  # Read a .desktop file path from $1 and output its Desktop Actions.
  # Output (one line per action): name TAB exec
  f="$1"
  _in=0; _aname=; _aexec=
  while IFS= read -r _l; do
    case "$_l" in
      "[Desktop Action "*)
        _in=1; _aname=; _aexec=
        ;;
      "["*)
        [ "$_in" = 1 ] && {
          [ -n "$_aname" ] && [ -n "$_aexec" ] && printf '%s\t%s\n' "$_aname" "$_aexec"
        }
        _in=0; _aname=; _aexec=
        ;;
      "Name="*)  [ "$_in" = 1 ] && _aname="''${_l#Name=}" ;;
      "Exec="*)
        if [ "$_in" = 1 ]; then
          _aexec="''${_l#Exec=}"
          for _fc in '%f' '%F' '%u' '%U' '%d' '%D' '%n' '%N' '%i' '%c' '%k'; do
            _aexec="''${_aexec//$_fc/}"
          done
        fi
        ;;
    esac
  done < "$f"
  [ "$_in" = 1 ] && [ -n "$_aname" ] && [ -n "$_aexec" ] && printf '%s\t%s\n' "$_aname" "$_aexec"
''
