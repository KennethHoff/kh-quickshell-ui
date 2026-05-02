# Host-side live view of the VM's Virtual-1 output. The harness writes a
# fresh PNG to /shared/state/live.png ~5×/second; feh's --reload watches
# the file and refreshes when it changes. Not VNC — no networking, no
# extra services in the VM.
{
  pkgs,
  lib,
}:
pkgs.writeShellApplication {
  name = "kh-headless-view";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.feh
  ];
  text = ''
    set -eu

    SHARE=/tmp/kh-headless
    LIVE="$SHARE/state/live.png"

    if [[ ! -f "$SHARE/state/ready" ]]; then
      cat >&2 <<EOF
    kh-headless-view: daemon not ready (no $SHARE/state/ready).
      Start it first:  nix run .#kh-headless-daemon
    EOF
      exit 2
    fi

    # The grim loop starts via Hyprland exec-once a few hundred ms after
    # ready. Wait briefly for the first frame.
    for _ in $(seq 50); do
      [[ -f "$LIVE" ]] && break
      sleep 0.2
    done

    if [[ ! -f "$LIVE" ]]; then
      echo "kh-headless-view: $LIVE never appeared — is Hyprland up?" >&2
      exit 1
    fi

    # --scale-down keeps 1:1 when the image fits the window; downscales to
    # fit only when the image is bigger. --geometry sets a sane initial
    # window size; the user can resize and feh re-fits live frames as the
    # grim loop overwrites $LIVE every ~200 ms.
    exec ${lib.getExe pkgs.feh} \
      --reload 0.2 \
      --scale-down \
      --auto-zoom \
      --geometry 2560x1440 \
      --title 'kh-headless live (Virtual-1)' \
      "$LIVE"
  '';
}
