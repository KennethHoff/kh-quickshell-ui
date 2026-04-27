# Generates per-instance BarLayout files plus a BarInstances registry.
#
# Input: an attrset keyed by ipcName, each value { screen; structure }.
# Output: attrset of { filename = <store-path>; } suitable for mkAppConfig's
# generatedFiles, containing:
#
#   BarInstances.qml              — registry listing { ipcName, screen }
#                                   entries; read by src/apps/kh-bar.qml
#   BarLayout_<ipcName>.qml       — one per instance; carries its structure
#                                   and root IPC handler
#
# The structure string for each instance is inserted verbatim as children of
# the layout Item, which exposes barHeight, barWindow, and ipcPrefix.
# Plugin types (BarRow, BarGroup, Clock, …) resolve from the other files
# copied into $out/.
{
  pkgs,
  lib,
  instances,
}:
let
  mkLayoutFile =
    ipcName: structure:
    pkgs.writeText "BarLayout_${ipcName}.qml" ''
      // Generated from programs.kh-ui.bar.instances.${ipcName} — do not edit by hand.
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
          anchors.fill: parent

          property int barHeight: parent.barHeight
          property var barWindow: parent.barWindow

          readonly property string ipcPrefix: "${ipcName}"

          // PopupWindows live in a parent's `data` (Item's `children` is
          // Items-only) and have an `anchor` property plain Items don't —
          // spot them by that, so BarDropdown needs no cooperation.
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

              function getHeight(): int {
                  return layout.barHeight + layout._maxVisiblePopupHeight(layout)
              }
              function getWidth(): int  { return layout.width }
              function getScreen(): string { return layout.barWindow.screen.name }
          }

      ${structure}
      }
    '';

  instanceList = lib.mapAttrsToList (ipcName: spec: {
    inherit ipcName;
    inherit (spec) screen;
  }) instances;

  instancesRegistry = pkgs.writeText "BarInstances.qml" ''
    // Generated registry of configured bar instances — read by src/apps/kh-bar.qml
    // to know which PanelWindow delegates to create.
    import QtQuick

    QtObject {
        readonly property var instances: (${builtins.toJSON instanceList})
    }
  '';

  layoutFiles = lib.mapAttrs' (ipcName: spec: {
    name = "BarLayout_${ipcName}.qml";
    value = mkLayoutFile ipcName spec.structure;
  }) instances;
in
layoutFiles // { "BarInstances.qml" = instancesRegistry; }
