# Generates BarLayout.qml from a user-provided QML structure string.
#
# The structure string is inserted verbatim as children of the top-level
# layout Item, which exposes barHeight and barWindow as required properties.
# All layout and plugin types (BarRow, BarGroup, Clock, …) are resolved
# at runtime from the files copied into $out/ — no imports or inlining
# needed here.
#
# Usage:
#   import ./bar-config.nix { inherit pkgs; structure = "..."; }
#
# Typical structure string:
#   BarRow {
#       Workspaces {}
#       MediaPlayer {}
#       BarSpacer {}
#       BarGroup { label: "●●●"; ipcName: "controlcenter"; EthernetPanel {} }
#       Clock {}
#       Volume {}
#       Tray {}
#   }
{
  pkgs,
  structure,
  ipcName ? "bar",
}:
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
      property string ipcPrefix: "${ipcName}"

      // Walk the layout's object tree and return the tallest currently-
      // visible PopupWindow. Popups live in a parent's `data` (Item's
      // `children` is Items-only; PopupWindow is a Window), and have an
      // `anchor` property plain Items don't — checking for that is enough
      // to spot them without BarDropdown having to cooperate.
      function _maxVisiblePopupHeight(item) {
          let max = 0
          if (item && item.anchor !== undefined && item.visible === true && item.height > 0) {
              max = item.height
          }
          const d = (item && item.data) ? item.data : []
          for (let i = 0; i < (d.length || 0); i++) {
              const h = layout._maxVisiblePopupHeight(d[i])
              if (h > max) max = h
          }
          return max
      }

      IpcHandler {
          target: layout.ipcPrefix
          // Visible bar footprint in px: the bar plus the tallest currently-
          // open popup (popups are anchored flush to the bar's bottom edge,
          // so multiple open popups don't stack — max wins).
          function getHeight(): int {
              return layout.barHeight + layout._maxVisiblePopupHeight(layout)
          }
          // Bar width in px (follows the screen since the bar anchors left+right).
          function getWidth(): int { return layout.width }
      }

  ${structure}
  }
''
