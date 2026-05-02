# Host-side daemon launcher. Prepares the share dir, spawns one virtiofsd
# per microvm.shares entry as the current user, waits for the sockets, then
# runs the qemu microvm runner. Cleanup trap kills both virtiofsd and qemu
# children so SIGTERM teardown is leak-free.
#
# Refuses to start a second daemon while one is already running — a lock
# file under /tmp/khtest-current/state/daemon.pid encodes the live PID.
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
  lib,
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

    PIDFILE="$SHARE/state/daemon.pid"
    if [[ -f "$PIDFILE" ]]; then
      old_pid=$(cat "$PIDFILE" 2>/dev/null || echo)
      if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
        echo "kh-test-vm-daemon: already running (pid $old_pid)" >&2
        echo "  stop it first with: kill $old_pid" >&2
        exit 1
      fi
      # Stale pidfile — previous daemon died without cleanup.
      rm -f "$PIDFILE"
    fi
    echo $$ > "$PIDFILE"

    # Wipe stale state files so a client never reads a result this daemon
    # didn't produce.
    rm -f "$SHARE/cmd"/*.req "$SHARE/out"/*.done "$SHARE/out"/*.err \
          "$SHARE/state/ready" "$SHARE/state/qs.config" "$SHARE/state/qs.log" \
          "$SHARE/state/harness.log" "$SHARE/state/hypr.log" \
          "$SHARE/state/probe.log" "$SHARE/state/virtiofsd.log"

    WORKDIR=$(mktemp -d -t khtest-vm-XXXXXX)
    cd "$WORKDIR"

    declare -a VFPIDS=()
    QEMU_PID=""

    cleanup() {
      local pid
      if [[ -n "$QEMU_PID" ]]; then
        kill "$QEMU_PID" 2>/dev/null || true
        # qemu's SIGTERM handler is fast; give it 2s before SIGKILL.
        for _ in $(seq 20); do
          kill -0 "$QEMU_PID" 2>/dev/null || break
          sleep 0.1
        done
        kill -9 "$QEMU_PID" 2>/dev/null || true
      fi
      for pid in "''${VFPIDS[@]+"''${VFPIDS[@]}"}"; do
        kill "$pid" 2>/dev/null || true
        sleep 0.05
        kill -9 "$pid" 2>/dev/null || true
      done
      cd /
      rm -rf "$WORKDIR"
      rm -f "$PIDFILE"
    }
    trap cleanup EXIT INT TERM

    # Spawn virtiofsd per share entry exposed by the runner.
    local_log="$SHARE/state/virtiofsd.log"
    : > "$local_log"
    for shared in ${vmRunner}/share/microvm/virtiofs/*/; do
      src=$(cat "$shared/source")
      sock=$(cat "$shared/socket")
      # No --socket-group: as a non-root user we can't chgrp to 'kvm'.
      # Default user-only ownership is fine because qemu runs as us.
      ${lib.getExe virtiofsd} \
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
    ${lib.getExe' vmRunner "microvm-run"} &
    QEMU_PID=$!
    wait "$QEMU_PID"
  '';
}
