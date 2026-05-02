# NixOS module for the kh-headless-vm. Brings up a minimal microvm running
# Hyprland on a vkms virtual DRM device. The harness daemon, mocks and
# quickshell all run as the autologin user `test`.
#
# Host ↔ guest: virtiofs share, /tmp/kh-headless ↔ /shared.
{
  pkgs,
  lib,
  hyprConfigPath,
  fakeFs,
  launcherFixture,
  ...
}:
{
  imports = [ fakeFs ];

  # ── Boot / kernel ─────────────────────────────────────────────────────
  # vkms must be loaded in the initrd, not lazily by systemd-modules-load:
  # Hyprland and Aquamarine probe /dev/dri/card0 very early; if vkms isn't
  # there yet, backend init fails with `CBackend::create() failed!`.
  boot.initrd.availableKernelModules = [ "vkms" ];
  boot.initrd.kernelModules = [ "vkms" ];
  boot.kernelModules = [ "vkms" ];
  boot.kernelParams = [ "vkms.enable_cursor=1" ];

  # ── microvm config ────────────────────────────────────────────────────
  microvm = {
    hypervisor = "qemu";
    # microvm/qemu hangs at exactly 2048 — see microvm-nix/microvm.nix#171.
    mem = 4096;
    vcpu = 2;

    shares = [
      {
        tag = "kh-headless-share";
        source = "/tmp/kh-headless";
        mountPoint = "/shared";
        proto = "virtiofs";
      }
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        proto = "virtiofs";
      }
    ];

    # No virtio-gpu — Hyprland renders directly into vkms's framebuffer
    # using llvmpipe. Adding a virtio-gpu would let Hyprland prefer that
    # over the vkms output and break the deterministic monitor name.
    graphics.enable = false;
  };

  # ── Networking off ────────────────────────────────────────────────────
  networking.firewall.enable = false;
  networking.useDHCP = false;
  systemd.services.systemd-udev-settle.enable = false;

  # ── Time pinning ──────────────────────────────────────────────────────
  # Disable timesyncd so screenshots are time-stable. A oneshot service
  # sets the wall clock to a fixed timestamp before harness starts.
  services.timesyncd.enable = false;

  systemd.services.clock-pin = {
    description = "Pin VM wall clock to a fixed timestamp for deterministic screenshots";
    wantedBy = [ "multi-user.target" ];
    before = [ "getty.target" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    # 2026-01-15T14:23:00Z = 1768537380
    script = ''
      ${lib.getExe' pkgs.coreutils "date"} -s '@1768537380'
    '';
  };

  # ── Users + login ─────────────────────────────────────────────────────
  users.mutableUsers = false;
  users.users.test = {
    isNormalUser = true;
    extraGroups = [
      "video"
      "input"
      "audio"
      "render"
    ];
    password = "";
    uid = 1000;
  };
  users.users.root.password = "";

  services.getty.autologinUser = "test";

  # Replace the autologin shell with Hyprland. The VM's getty autologins
  # land on ttyS0 (serial console) since `-nographic` makes it the primary
  # console — checking specifically for tty1 would never match. There's
  # only one user and one login path so an unconditional exec is safe.
  environment.loginShellInit = ''
    if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$SSH_CONNECTION" ]; then
      mkdir -p /shared/state
      # Diagnostics — captured before Hyprland starts so we can see the
      # backend's view of /dev/dri etc. when boot fails.
      {
        echo "=== /dev/dri ==="
        ls -la /dev/dri 2>&1 || true
        echo "=== lsmod | grep -E 'drm|vkms' ==="
        ${lib.getExe' pkgs.kmod "lsmod"} | grep -E 'drm|vkms' 2>&1 || true
        echo "=== modprobe vkms ==="
        ${lib.getExe' pkgs.kmod "modprobe"} vkms 2>&1 || true
        echo "=== /dev/dri after modprobe ==="
        ls -la /dev/dri 2>&1 || true
      } > /shared/state/probe.log 2>&1
      # start-hyprland is the upstream watchdog wrapper. Launching the
      # `Hyprland` binary directly trips the on-screen "started without
      # start-hyprland" CHyprError overlay, which obscures the right
      # half of the bar in screenshots.
      ${lib.getExe' pkgs.hyprland "start-hyprland"} -- --config ${hyprConfigPath} \
        > /shared/state/hypr.log 2>&1
      # If Hyprland died, salvage its runtime log + crash report so we can
      # see what happened from the host.
      cp -f /run/user/1000/hypr/*/hyprland.log /shared/state/hypr-runtime.log 2>/dev/null || true
      cp -f /home/test/.cache/hyprland/hyprlandCrashReport*.txt /shared/state/ 2>/dev/null || true
      ${lib.getExe' pkgs.coreutils "sleep"} infinity
    fi
  '';

  # ── Hyprland prerequisites ────────────────────────────────────────────
  programs.hyprland.enable = true;
  hardware.graphics.enable = true;

  # Force Mesa's llvmpipe (software) driver. With no virtio-gpu and only
  # vkms in the VM, neither Hyprland nor Quickshell have a real GPU to
  # talk to — without these env vars EGL fails to find a driver and qs
  # crashes during surface creation.
  environment.sessionVariables = {
    LIBGL_ALWAYS_SOFTWARE = "1";
    MESA_LOADER_DRIVER_OVERRIDE = "llvmpipe";
    WLR_RENDERER = "pixman";
    WLR_NO_HARDWARE_CURSORS = "1";
    # Curated app fixture — gives the launcher's Apps plugin a deterministic
    # set of .desktop entries, and the hyprland-windows plugin matching
    # icons via StartupWMClass when fake-clients spawns weston-terminal.
    XDG_DATA_DIRS = "${launcherFixture}/share:/run/current-system/sw/share:/usr/share";
  };

  # ── Audio (PipeWire) ──────────────────────────────────────────────────
  # Volume plugin reads Pipewire.defaultAudioSink. With no real audio
  # hardware, pipewire still runs and wireplumber creates a dummy sink.
  # Volume readout will be whatever wireplumber sets by default; the bar
  # renders the plugin in either case.
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = false;
    wireplumber.enable = true;
  };

  # PipeWire + wireplumber need a session bus. Autostart via user systemd.
  systemd.user.services.pipewire.wantedBy = [ "default.target" ];
  systemd.user.services.wireplumber.wantedBy = [ "default.target" ];
  systemd.user.services.pipewire-pulse.wantedBy = [ "default.target" ];

  # ── Packages available in $PATH ───────────────────────────────────────
  environment.systemPackages = with pkgs; [
    hyprland
    quickshell
    grim
    foot # tiny Wayland terminal for fake-clients.sh — supports -a/-T
    inotify-tools
    coreutils
    bash
    dbus
  ];

  # ── Filesystem overrides for ro-store (microvm.nix expects this) ──────
  fileSystems."/" = lib.mkForce {
    device = "rootfs";
    fsType = "tmpfs";
    options = [
      "size=512M"
      "mode=755"
    ];
  };

  # ── Misc ──────────────────────────────────────────────────────────────
  documentation.enable = false;
  services.openssh.enable = false;

  system.stateVersion = "25.05";
}
