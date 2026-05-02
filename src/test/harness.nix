# In-guest harness daemon. Run by Hyprland's exec-once after the compositor
# is up. Lifecycle:
#
#   1. Spawn quickshell with the default test bar config baked in.
#   2. Wait for `testbar getHeight` IPC to respond.
#   3. Write /shared/state/ready so the host driver knows we're live.
#   4. Watch /shared/cmd for *.req files. Per request:
#        - Optionally respawn quickshell with a new config path (hot-reload).
#        - Drive the requested variant (chrome / stats / cc / all).
#        - grim → /shared/out/<out-filename>
#        - Touch /shared/out/<uuid>.done
#
# Request file format (KEY=VALUE per line):
#   uuid=<id>
#   variant=chrome|stats|cc|all
#   out=<filename, written under /shared/out>
#   reload=true|false
#   config=<store path of bar config>   # optional; only honoured with reload=true
#
# For variant=all, the harness writes three files: kh-bar-chrome.png,
# kh-bar-stats.png, kh-bar-cc.png — and ignores `out`.
{
  pkgs,
  defaultBarConfig,
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
    set -u
    # Trace harness execution into /shared/state/harness.log via the
    # caller's redirection from hyprland.conf.
    exec 2>&1
    set -x

    SHARED=/shared
    DEFAULT_CONFIG=${defaultBarConfig}

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
      echo "$cfg" > "$SHARED/state/qs.config"
    }

    wait_ready() {
      for _ in $(seq 100); do
        if quickshell ipc --pid "$QS_PID" call testbar getHeight >/dev/null 2>&1; then
          return 0
        fi
        sleep 0.1
      done
      echo "harness: timed out waiting for testbar IPC" >&2
      return 1
    }

    poll_height_stable() {
      local prev="" cur=""
      for _ in $(seq 40); do
        cur="$(quickshell ipc --pid "$QS_PID" call testbar getHeight 2>/dev/null || echo)"
        if [[ -n "$cur" && "$cur" == "$prev" ]]; then return 0; fi
        prev="$cur"
        sleep 0.1
      done
      return 0
    }

    capture() {
      local out="$1"
      local h w
      h="$(quickshell ipc --pid "$QS_PID" call testbar getHeight)"
      w="$(quickshell ipc --pid "$QS_PID" call testbar getWidth)"
      grim -g "0,0 ''${w}x''${h}" "$SHARED/out/$out"
    }

    drive_variant() {
      local v="$1" out="$2"
      case "$v" in
        chrome)
          # Ensure both dropdowns are closed before capture.
          quickshell ipc --pid "$QS_PID" call testbar.stats         close >/dev/null 2>&1 || true
          quickshell ipc --pid "$QS_PID" call testbar.controlcenter close >/dev/null 2>&1 || true
          poll_height_stable
          capture "$out"
          ;;
        stats)
          quickshell ipc --pid "$QS_PID" call testbar.controlcenter close >/dev/null 2>&1 || true
          quickshell ipc --pid "$QS_PID" call testbar.stats open
          poll_height_stable
          capture "$out"
          ;;
        cc)
          quickshell ipc --pid "$QS_PID" call testbar.stats close >/dev/null 2>&1 || true
          quickshell ipc --pid "$QS_PID" call testbar.controlcenter open
          poll_height_stable
          capture "$out"
          ;;
        all)
          drive_variant chrome kh-bar-chrome.png
          drive_variant stats  kh-bar-stats.png
          drive_variant cc     kh-bar-cc.png
          ;;
        *)
          echo "harness: unknown variant '$v'" >&2
          return 1
          ;;
      esac
    }

    process_request() {
      local req="$1"
      # Parse KEY=VALUE lines into local vars.
      local uuid="" variant="chrome" out="kh-bar.png" reload="false" config=""
      while IFS='=' read -r k v; do
        case "$k" in
          uuid)    uuid="$v" ;;
          variant) variant="$v" ;;
          out)     out="$v" ;;
          reload)  reload="$v" ;;
          config)  config="$v" ;;
        esac
      done < "$req"

      if [[ "$reload" == "true" && -n "$config" && "$config" != "$CURRENT_CONFIG" ]]; then
        spawn_qs "$config"
        wait_ready || { echo "FAIL reload" > "$SHARED/out/$uuid.err"; touch "$SHARED/out/$uuid.done"; return; }
      fi

      if ! drive_variant "$variant" "$out"; then
        echo "FAIL variant=$variant" > "$SHARED/out/$uuid.err"
      fi
      touch "$SHARED/out/$uuid.done"
      rm -f "$req"
    }

    # ── Boot ──────────────────────────────────────────────────────────────
    spawn_qs "$DEFAULT_CONFIG"
    if ! wait_ready; then
      echo "harness: initial readiness failed" >&2
      exit 1
    fi
    touch "$SHARED/state/ready"

    # ── Request loop ──────────────────────────────────────────────────────
    # Poll instead of inotify: virtiofs doesn't reliably propagate inotify
    # events from the host, so the harness would never see new .req files.
    while true; do
      shopt -s nullglob
      for req in "$SHARED"/cmd/*.req; do
        process_request "$req"
      done
      shopt -u nullglob
      sleep 0.5
    done
  '';
}
