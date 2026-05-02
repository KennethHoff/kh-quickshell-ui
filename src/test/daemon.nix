# Host-side daemon launcher. Prepares the share dir, spawns one virtiofsd
# per microvm.shares entry as the current user, waits for the sockets, then
# execs the qemu microvm runner in the foreground. Ctrl-C cleanly tears
# down the VM and the virtiofsd processes.
#
# The share path is hardcoded at /tmp/khtest-current to match what's baked
# into the VM's microvm.shares config.
#
# Why we don't use the runner's bundled `virtiofsd-run`: that wrapper is a
# supervisord script with `user=root`, so it refuses to start as a normal
# user. Spawning the virtiofsd binary directly works because virtiofsd's
# privilege-drop path branches on `id -u`.
{
  pkgs,
  vmRunner,
  virtiofsd,
}:
pkgs.writeShellApplication {
  name = "kh-test-vm-daemon";
  runtimeInputs = [ pkgs.coreutils ];
  text = ''
    set -eu

    if [[ ! -r /dev/kvm ]]; then
      cat >&2 <<'EOF'
    kh-test-vm-daemon: /dev/kvm not available.
      The VM is built for KVM acceleration. On NixOS, ensure the host has:
        boot.kernelModules = [ "kvm-amd" ];   # or kvm-intel
      and that your user is in the 'kvm' group.
      Then reboot or 'sudo modprobe kvm-amd' and re-run.
    EOF
      exit 2
    fi

    SHARE=/tmp/khtest-current
    mkdir -p "$SHARE/cmd" "$SHARE/out" "$SHARE/state"

    # Wipe any stale request/done/sentinel files from a previous run so the
    # client never reads a result the new daemon didn't produce.
    rm -f "$SHARE/cmd"/*.req "$SHARE/out"/*.done "$SHARE/out"/*.err "$SHARE/state/ready" "$SHARE/state/qs.config" "$SHARE/state/qs.log"

    WORKDIR=$(mktemp -d -t khtest-vm-XXXXXX)
    cd "$WORKDIR"

    declare -a VFPIDS=()
    cleanup() {
      local pid
      for pid in "''${VFPIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
      done
      cd /
      rm -rf "$WORKDIR"
    }
    trap cleanup EXIT INT TERM

    # Spawn virtiofsd per share entry exposed by the runner.
    local_log="$SHARE/state/virtiofsd.log"
    : > "$local_log"
    for shared in ${vmRunner}/share/microvm/virtiofs/*/; do
      src=$(cat "$shared/source")
      sock=$(cat "$shared/socket")
      # No --socket-group: as a non-root user we can't chgrp the socket to
      # 'kvm'. Default ownership (user-only) is fine because qemu runs as
      # the same user.
      ${virtiofsd}/bin/virtiofsd \
        --socket-path="$sock" \
        --shared-dir="$src" \
        --thread-pool-size "$(nproc)" \
        --posix-acl --xattr \
        --cache=auto \
        --inode-file-handles=prefer \
        >>"$local_log" 2>&1 &
      VFPIDS+=($!)
    done

    # Wait for every socket to materialise.
    for shared in ${vmRunner}/share/microvm/virtiofs/*/; do
      sock=$(cat "$shared/socket")
      for _ in $(seq 50); do
        [[ -S "$sock" ]] && break
        sleep 0.1
      done
      if [[ ! -S "$sock" ]]; then
        echo "kh-test-vm-daemon: virtiofsd socket $sock never appeared (see $local_log)" >&2
        exit 1
      fi
    done

    echo "kh-test-vm-daemon: share at $SHARE — booting VM (Ctrl-C to stop)" >&2
    ${vmRunner}/bin/microvm-run
  '';
}
