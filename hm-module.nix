# Home-manager module for kh-ui quickshell components.
#
# Requires Stylix (colors and fonts are read from config.lib.stylix / config.stylix).
#
# Usage (after importing this module):
#   programs.quickshell.kh-ui.enable = true;
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  src = self;
  system = pkgs.stdenv.hostPlatform.system;

  cliphistDecodeAll = import (src + "/scripts/cliphist-decode-all.nix") { inherit pkgs lib; };

  nixConfig = import (src + "/config.nix") {
    inherit pkgs;
    colors   = config.lib.stylix.colors;
    fontName = config.stylix.fonts.sansSerif.name;
    fontSize = config.stylix.fonts.sizes.applications;
  };

  nixBins = import (src + "/ffi.nix") {
    inherit pkgs lib;
    extraBins.cliphistDecodeAll = toString cliphistDecodeAll;
  };

  mkConfig =
    { name, qml }:
    pkgs.runCommandLocal "qs-${name}" { } ''
      mkdir -p $out/lib
      cp ${src}/lib/*.qml $out/lib/
      cp ${src}/qml/${qml} $out/shell.qml
      cp ${nixConfig} $out/NixConfig.qml
      cp ${nixBins}   $out/NixBins.qml
    '';
in
{
  options.programs.kh-ui.enable =
    lib.mkEnableOption "kh-ui shell UI (launcher + clipboard history)";

  config = lib.mkIf (config.programs.quickshell.enable && config.programs.kh-ui.enable) {
    programs.quickshell.configs = {
      kh-launcher = mkConfig { name = "kh-launcher"; qml = "kh-launcher.qml"; };
      kh-cliphist = mkConfig { name = "kh-cliphist"; qml = "kh-cliphist.qml"; };
    };
  };
}
