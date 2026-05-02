# Host-side CLI for the kh-test VM. One binary, one operation per call.
# Drops a request into /tmp/khtest-current/cmd/, polls for the .done
# sentinel, prints stdout, exits non-zero on .err.
#
# Usage:
#   kh-test load <config-store-path>     boot quickshell with that config
#   kh-test kill                         stop quickshell
#   kh-test call <target> <method> [args...]
#   kh-test prop <target> <prop> [<value>]
#   kh-test show [<target>]              introspect IPC surface
#   kh-test list                         list active IPC targets
#   kh-test grim "<x,y wxh>" [name]      capture region; PNG saved to
#                                         /tmp/khtest-current/out/<name>
#                                         (default <uuid>.png), printed on
#                                         stdout as an absolute path
#   kh-test status                       running <config> | idle
#
# Agent flow ("screenshot kh-bar with volume muted"):
#   $ cfg=$(nix build .#kh-bar-vm-test --no-link --print-out-paths)
#   $ kh-test load "$cfg"
#   $ kh-test list                       # discover testbar.* targets
#   $ kh-test show testbar.volume        # see methods
#   $ kh-test call testbar.volume setMuted true
#   $ kh-test grim "0,0 3840x32" muted-bar.png
{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "kh-test";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.util-linux
  ];
  text = ''
    set -eu

    SHARE=/tmp/khtest-current
    READY="$SHARE/state/ready"

    if [[ ! -f "$READY" ]]; then
      cat >&2 <<EOF
    kh-test: daemon not ready (no $READY).
      Start it first:  nix run .#kh-test-vm-daemon
    EOF
      exit 2
    fi

    if [[ $# -lt 1 ]]; then
      cat >&2 <<EOF
    usage: kh-test <op> [args...]
      ops: load <config> | kill | call <target> <method> [args] |
           prop <target> <prop> [value] | show [target] | list |
           grim "<x,y wxh>" [name] | status
    EOF
      exit 2
    fi

    op="$1"
    shift

    uuid="$(uuidgen)"
    req=$(mktemp "$SHARE/cmd/$uuid.req.XXXXXX")
    {
      echo "uuid=$uuid"
      echo "op=$op"
      # One arg per line — preserves whitespace/special chars verbatim,
      # which matters for things like grim's "X,Y WxH" geometry string.
      for a in "$@"; do
        echo "arg=$a"
      done
    } > "$req"
    mv "$req" "$SHARE/cmd/$uuid.req"

    deadline=$(( $(date +%s) + 30 ))
    while [[ ! -f "$SHARE/out/$uuid.done" ]]; do
      if (( $(date +%s) > deadline )); then
        echo "kh-test: timeout (no $SHARE/out/$uuid.done after 30s)" >&2
        exit 1
      fi
      sleep 0.1
    done

    rc=0
    if [[ -f "$SHARE/out/$uuid.err" ]]; then
      cat "$SHARE/out/$uuid.err" >&2
      rc=1
    fi

    if [[ "$op" == "grim" && $rc -eq 0 ]]; then
      # grim returns the basename written under /shared/out; rewrite to host
      # absolute path so the agent can open it directly.
      name="$(cat "$SHARE/out/$uuid.out")"
      echo "$SHARE/out/$name"
    elif [[ -f "$SHARE/out/$uuid.out" ]]; then
      cat "$SHARE/out/$uuid.out"
    fi

    rm -f "$SHARE/out/$uuid.out" "$SHARE/out/$uuid.err" "$SHARE/out/$uuid.done"
    exit $rc
  '';
}
