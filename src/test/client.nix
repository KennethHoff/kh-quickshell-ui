# Host-side shot client. Talks to a running kh-test-vm-daemon by dropping
# request files into /tmp/khtest-current/cmd/ and waiting for sentinels in
# /tmp/khtest-current/out/.
#
# Usage:
#   screenshot-bar-vm                    # default: --all (chrome+stats+cc)
#   screenshot-bar-vm --variant chrome   # one PNG
#   screenshot-bar-vm --variant stats
#   screenshot-bar-vm --variant cc
#   screenshot-bar-vm --reload           # rebuild + respawn qs in daemon
#   screenshot-bar-vm --out FILE         # only with --variant; renames PNG
{
  pkgs,
  defaultBarConfig,
}:
pkgs.writeShellApplication {
  name = "screenshot-bar-vm";
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
    screenshot-bar-vm: daemon not ready (no $READY).
      Start it first:  nix run .#kh-test-vm-daemon
      Then re-run this command in another terminal.
    EOF
      exit 2
    fi

    variant="all"
    out_arg=""
    reload="false"
    config="${defaultBarConfig}"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --variant) variant="$2"; shift 2 ;;
        --out)     out_arg="$2"; shift 2 ;;
        --reload)  reload="true"; shift ;;
        --config)  config="$2"; shift 2 ;;
        -h|--help)
          sed -n '2,15p' "$0" | sed 's/^# \?//'
          exit 0
          ;;
        *)
          echo "unknown arg: $1" >&2
          exit 2
          ;;
      esac
    done

    case "$variant" in
      chrome|stats|cc|all) ;;
      *) echo "invalid --variant: $variant (chrome|stats|cc|all)" >&2; exit 2 ;;
    esac

    if [[ -n "$out_arg" && "$variant" == "all" ]]; then
      echo "--out is only valid with a single --variant (not --variant all)" >&2
      exit 2
    fi

    uuid="$(uuidgen)"
    ts="$(date +%Y%m%d-%H%M%S)"
    dest=/tmp/qs-screenshots/$ts
    mkdir -p "$dest"

    if [[ "$variant" == "all" ]]; then
      out_filename="(ignored)"
    else
      out_filename="''${out_arg:-kh-bar-$variant.png}"
    fi

    req=$(mktemp "$SHARE/cmd/$uuid.req.XXXXXX")
    cat > "$req" <<EOF
    uuid=$uuid
    variant=$variant
    out=$out_filename
    reload=$reload
    config=$config
    EOF
    # Atomic move so inotifywait sees a complete file via moved_to.
    mv "$req" "$SHARE/cmd/$uuid.req"

    # Poll for the done sentinel — give Hyprland's first cold layout time.
    deadline=$(( $(date +%s) + 30 ))
    while [[ ! -f "$SHARE/out/$uuid.done" ]]; do
      if (( $(date +%s) > deadline )); then
        echo "screenshot-bar-vm: timeout (no $SHARE/out/$uuid.done after 30s)" >&2
        echo "  inspect $SHARE/state/qs.log for clues" >&2
        exit 1
      fi
      sleep 0.1
    done

    if [[ -f "$SHARE/out/$uuid.err" ]]; then
      echo "screenshot-bar-vm: harness reported error:" >&2
      cat "$SHARE/out/$uuid.err" >&2
      rm -f "$SHARE/out/$uuid.err" "$SHARE/out/$uuid.done"
      exit 1
    fi

    rm -f "$SHARE/out/$uuid.done"

    if [[ "$variant" == "all" ]]; then
      moved=()
      for v in chrome stats cc; do
        src="$SHARE/out/kh-bar-$v.png"
        if [[ -f "$src" ]]; then
          mv "$src" "$dest/kh-bar-$v.png"
          moved+=("$dest/kh-bar-$v.png")
        else
          echo "screenshot-bar-vm: missing $src" >&2
        fi
      done
      printf '%s\n' "''${moved[@]}"
    else
      mv "$SHARE/out/$out_filename" "$dest/$out_filename"
      echo "$dest/$out_filename"
    fi
  '';
}
