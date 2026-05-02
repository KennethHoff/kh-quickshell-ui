# Generates a hyprland.conf for the test VM. Single 4K virtual output via
# vkms; gaps/borders/animations off so screenshots are pixel-stable.
#
# exec-once chains:
#   1. dbus-update-activation-environment — propagate WAYLAND_DISPLAY etc.
#      so dbus-activated services (mock-tray, mock-mpris) inherit them.
#   2. mock-mpris, mock-tray — fake session bus services.
#   3. fake-clients — populates workspaces 1 + 2 with a weston-simple-shm
#      window each so the Workspaces plugin renders something.
#   4. harness — long-lived daemon that spawns quickshell and processes shot
#      requests off /shared/cmd.
{
  pkgs,
  lib,
  mocks,
  harness,
}:
pkgs.writeText "hyprland.conf" ''
  monitor=Virtual-1,3840x2160@60,0x0,1

  input {
      kb_layout = us
  }

  general {
      gaps_in     = 0
      gaps_out    = 0
      border_size = 0
  }

  decoration {
      rounding = 0
  }

  animations {
      enabled = false
  }

  misc {
      disable_hyprland_logo     = true
      disable_splash_rendering  = true
      vfr                       = true
  }

  debug {
      disable_logs = false
  }

  exec-once = ${lib.getExe' pkgs.dbus "dbus-update-activation-environment"} --systemd WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP
  exec-once = ${mocks}/bin/mock-mpris
  exec-once = ${mocks}/bin/mock-tray
  exec-once = ${mocks}/bin/fake-clients
  exec-once = sh -c '${lib.getExe harness} > /shared/state/harness.log 2>&1'
  # Continuous full-output grim into /shared/state/live.png so a host-side
  # viewer (`kh-headless-view`) can show what Hyprland is rendering on
  # Virtual-1 in (near) real time. ~5 fps. Cheaper than wiring up wayvnc
  # over a guest network — and adding a network interface broke logind's
  # seat assignment, which Aquamarine needs to open /dev/dri/card0.
  exec-once = sh -c 'while ${lib.getExe' pkgs.coreutils "sleep"} 0.2; do ${lib.getExe pkgs.grim} -t png /shared/state/live.png.tmp 2>/dev/null && mv /shared/state/live.png.tmp /shared/state/live.png; done'
''
