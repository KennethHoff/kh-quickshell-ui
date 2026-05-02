# In-guest harness daemon. Run by Hyprland's exec-once after the compositor
# is up. Generic primitive dispatcher driven by request files dropped into
# /shared/cmd by the host-side `kh-test` CLI.
#
# Request file format (KEY=VALUE per line):
#   uuid=<id>
#   op=<load|call|prop|show|list|grim|status|kill>
#   args=<space-separated args>
#
# Per request the harness writes:
#   /shared/out/<uuid>.out   — stdout from the operation
#   /shared/out/<uuid>.err   — stderr; presence ⇒ failure
#   /shared/out/<uuid>.png   — for `grim` ops, the captured image
#   /shared/out/<uuid>.done  — sentinel: must be written last
#
# Operations:
#   load <config>           kill+respawn quickshell with the given store path
#   kill                    stop quickshell (no-op if not running)
#   call <target> <method> [args...]
#   prop <target> <prop> [<value>]   read (no value) or write a prop
#   show [<target>]         qs ipc show output (introspection)
#   list                    qs ipc list output (active targets)
#   grim "<x,y wxh>" [name]  capture region. name defaults to <uuid>.png; the
#                            harness always writes to <uuid>.png and returns
#                            the path on stdout
#   status                  prints "running <config>" or "idle"
{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "kh-test-harness";
  runtimeInputs = [
    pkgs.quickshell
    pkgs.grim
    pkgs.coreutils
    pkgs.gawk
  ];
  text = ''
    # Note: nounset (set -u) intentionally OFF — op_* helpers reference
    # positional args that may be empty; rather than guarding every one
    # with ''${1:-}, we accept the looser shell mode for the dispatcher.
    #
    # No set -x: per-op stderr is redirected to <uuid>.err and the client
    # treats a non-empty .err as failure. xtrace would always populate it.
    # If you need to debug the harness, run `bash -x` against the script
    # by hand inside the VM — don't put `set -x` here.
    exec 2>&1

    SHARED=/shared
    mkdir -p "$SHARED/state" "$SHARED/cmd" "$SHARED/out"

    QS_PID=""
    CURRENT_CONFIG=""

    spawn_qs() {
      local cfg="$1"
      if [[ -n "$QS_PID" ]] && kill -0 "$QS_PID" 2>/dev/null; then
        kill "$QS_PID" 2>/dev/null || true
        wait "$QS_PID" 2>/dev/null || true
      fi
      quickshell -p "$cfg" >>"$SHARED/state/qs.log" 2>&1 &
      QS_PID=$!
      CURRENT_CONFIG="$cfg"
      # Wait for IPC to come up — `qs ipc show` returns nothing while the
      # socket isn't listening and exits 0 with output once it is.
      local _i
      for _i in $(seq 100); do
        if quickshell ipc --pid "$QS_PID" show 2>/dev/null | grep -q .; then
          return 0
        fi
        sleep 0.1
      done
      return 1
    }

    qs_running() { [[ -n "$QS_PID" ]] && kill -0 "$QS_PID" 2>/dev/null; }

    require_qs() {
      if ! qs_running; then
        echo "no qs running — issue 'load <config>' first" >&2
        return 1
      fi
    }

    op_load() {
      local cfg="''${1:-}"
      if [[ -z "$cfg" ]]; then echo "load: missing config arg" >&2; return 2; fi
      if ! spawn_qs "$cfg"; then
        echo "load: qs IPC never came up (see $SHARED/state/qs.log)" >&2
        return 1
      fi
      echo "loaded $cfg"
    }

    op_kill() {
      if qs_running; then
        kill "$QS_PID" 2>/dev/null || true
        wait "$QS_PID" 2>/dev/null || true
      fi
      QS_PID=""
      CURRENT_CONFIG=""
      echo "killed"
    }

    op_call() {
      require_qs || return $?
      quickshell ipc --pid "$QS_PID" call "$@"
    }

    op_prop() {
      require_qs || return $?
      local target="$1" prop="$2"
      shift 2 || true
      if [[ $# -eq 0 ]]; then
        quickshell ipc --pid "$QS_PID" prop get "$target" "$prop"
      else
        quickshell ipc --pid "$QS_PID" prop set "$target" "$prop" "$@"
      fi
    }

    op_show() {
      # `quickshell ipc show` doesn't take a target arg — it dumps every
      # target. Filter to the requested one (and its indented function
      # lines) when supplied.
      require_qs || return $?
      if [[ $# -eq 0 ]]; then
        quickshell ipc --pid "$QS_PID" show
      else
        local target="$1"
        quickshell ipc --pid "$QS_PID" show \
          | awk -v t="$target" '
              /^target / { current=$2; if (current==t) print; else current=""; next }
              /^[[:space:]]/ && current==t { print }
            '
      fi
    }

    op_list() {
      # quickshell has no `ipc list` — derive target names from `show`.
      require_qs || return $?
      quickshell ipc --pid "$QS_PID" show 2>/dev/null \
        | awk '/^target / {print $2}'
    }

    op_grim() {
      require_qs || return $?
      local geom="$1" out_name="''${2:-}"
      if [[ -z "$geom" ]]; then echo "grim: missing geometry" >&2; return 2; fi
      [[ -z "$out_name" ]] && out_name="$_UUID.png"
      grim -g "$geom" "$SHARED/out/$out_name"
      echo "$out_name"
    }

    op_status() {
      if qs_running; then echo "running $CURRENT_CONFIG"; else echo "idle"; fi
    }

    process_request() {
      local req="$1"
      local uuid="" op=""
      local -a request_args=()
      while IFS='=' read -r k v; do
        case "$k" in
          uuid) uuid="$v" ;;
          op)   op="$v" ;;
          arg)  request_args+=("$v") ;;
        esac
      done < "$req"

      _UUID="$uuid"
      local out_file="$SHARED/out/$uuid.out"
      local err_file="$SHARED/out/$uuid.err"

      set -- "''${request_args[@]+"''${request_args[@]}"}"
      local rc=0
      case "$op" in
        load)   op_load   "$@" >"$out_file" 2>"$err_file" || rc=$? ;;
        kill)   op_kill   >"$out_file" 2>"$err_file" || rc=$? ;;
        call)   op_call   "$@" >"$out_file" 2>"$err_file" || rc=$? ;;
        prop)   op_prop   "$@" >"$out_file" 2>"$err_file" || rc=$? ;;
        show)   op_show   "$@" >"$out_file" 2>"$err_file" || rc=$? ;;
        list)   op_list   >"$out_file" 2>"$err_file" || rc=$? ;;
        grim)   op_grim   "$@" >"$out_file" 2>"$err_file" || rc=$? ;;
        status) op_status >"$out_file" 2>"$err_file" || rc=$? ;;
        *)      echo "unknown op: $op" >"$err_file"; rc=2 ;;
      esac

      # Drop empty .err so client can presence-check it.
      [[ ! -s "$err_file" ]] && rm -f "$err_file"
      [[ "$rc" -ne 0 ]] && [[ ! -f "$err_file" ]] && echo "rc=$rc" >"$err_file"

      touch "$SHARED/out/$uuid.done"
      rm -f "$req"
    }

    touch "$SHARED/state/ready"

    while true; do
      shopt -s nullglob
      for req in "$SHARED"/cmd/*.req; do
        process_request "$req"
      done
      shopt -u nullglob
      sleep 0.2
    done
  '';
}
