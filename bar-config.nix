# Generates BarLayout.qml from a user-provided QML structure string.
#
# The structure string is inserted verbatim as children of the top-level
# layout Item, which exposes barHeight and barWindow as required properties.
# All layout and plugin types (BarLeft, BarRight, ControlCenter, Clock, …)
# are resolved at runtime from the files copied into $out/ — no imports
# or inlining needed here.
#
# Usage:
#   import ./bar-config.nix { inherit pkgs; structure = "..."; }
#
# Typical structure string:
#   BarLeft {
#       Workspaces {}
#       MediaPlayer {}
#   }
#   BarRight {
#       ControlCenter {}
#       Clock {}
#       Volume {}
#       Tray {}
#   }
{ pkgs, structure }:
pkgs.writeText "BarLayout.qml" ''
  // Generated from bar structure — do not edit by hand.
  // To change the bar layout set programs.kh-ui.bar.structure in your
  // home-manager configuration.
  import QtQuick
  import Quickshell
  import Quickshell.Hyprland
  import Quickshell.Io
  import Quickshell.Services.Pipewire
  import Quickshell.Services.Mpris
  import Quickshell.Services.SystemTray
  import Quickshell.Wayland

  Item {
      id: layout
      required property int barHeight
      required property var barWindow

  ${structure}
  }
''
