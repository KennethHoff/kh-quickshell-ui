# Home-manager module for kh-ui quickshell components.
#
# Requires Stylix (colors and fonts are read from config.lib.stylix / config.stylix).
#
# Usage (after importing this module):
#   programs.kh-ui.enable = true;
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

  scanAppsScript    = import (src + "/scripts/scan-apps.nix")           { inherit pkgs lib; };

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

  mkBarConfig =
    { leftPlugins, rightPlugins, extraPluginDirs }:
    let
      resolvePlugin = name:
        let extraSrc = lib.findFirst
          (d: builtins.pathExists (d + "/${name}.qml"))
          null
          extraPluginDirs;
        in { inherit name; src = if extraSrc != null then extraSrc + "/${name}.qml" else src + "/qml/bar/${name}.qml"; };
      barLayoutQml = import (src + "/bar-layout.nix") {
        inherit pkgs lib;
        leftPlugins  = map resolvePlugin leftPlugins;
        rightPlugins = map resolvePlugin rightPlugins;
      };
    in
    pkgs.runCommandLocal "qs-kh-bar" { } ''
      mkdir -p $out/lib
      cp ${src}/lib/*.qml $out/lib/
      cp ${src}/qml/kh-bar.qml $out/shell.qml
      cp ${barLayoutQml} $out/BarLayout.qml
      cp ${nixConfig} $out/NixConfig.qml
      cp ${nixBins}   $out/NixBins.qml
    '';

  mkConfig =
    {
      name,
      qml,
      extraQml ? [ ],
    }:
    pkgs.runCommandLocal "qs-${name}" { } ''
      mkdir -p $out/lib
      cp ${src}/lib/*.qml $out/lib/
      cp ${src}/qml/${qml} $out/shell.qml
      ${lib.concatMapStrings (f: "cp ${src}/qml/${f} $out/\n") extraQml}cp ${nixConfig} $out/NixConfig.qml
      cp ${nixBins}   $out/NixBins.qml
    '';
in
{
  options.programs.kh-ui = {
    enable = lib.mkEnableOption "kh-ui shell UI";

    clipboard-history.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the clipboard history viewer (kh-cliphist).";
    };

    launcher.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the application launcher (kh-launcher).";
    };

    bar = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable the status bar (kh-bar).";
      };
      leftPlugins = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "Workspaces" "MediaPlayer" ];
        description = ''
          QML type names to render in the left slot, left-to-right.
          Built-in types: Workspaces, MediaPlayer.
          Add custom types by placing their .qml files in a directory
          listed in <option>extraPluginDirs</option>.
        '';
      };
      rightPlugins = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "Tailscale" "Clock" "Volume" "Tray" ];
        description = ''
          QML type names to render in the right slot, right-to-left.
          Built-in types: Tailscale, Clock, Volume, Tray.
          Add custom types by placing their .qml files in a directory
          listed in <option>extraPluginDirs</option>.
        '';
      };
      extraPluginDirs = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        description = ''
          Paths to directories containing extra bar plugin .qml files.
          Each file must define a type extending BarWidget with the same
          filename as the type name (e.g. MyWidget.qml for MyWidget).
          These are merged into the bar build alongside the built-in plugins.
        '';
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf config.programs.kh-ui.enable {
      programs.quickshell = {
        enable = lib.mkDefault true;
        configs =
          lib.optionalAttrs config.programs.kh-ui.clipboard-history.enable {
            kh-cliphist = mkConfig {
              name = "kh-cliphist";
              qml = "kh-cliphist.qml";
              extraQml = [ "ClipList.qml" "ClipPreview.qml" "MetaStore.qml" ];
            };
          } //
          lib.optionalAttrs config.programs.kh-ui.bar.enable {
            kh-bar = mkBarConfig {
              inherit (config.programs.kh-ui.bar) leftPlugins rightPlugins extraPluginDirs;
            };
          } //
          lib.optionalAttrs config.programs.kh-ui.launcher.enable {
            kh-launcher =
              let
                nixBins = import (src + "/ffi.nix") {
                  inherit pkgs lib;
                  extraBins = {
                    scanApps = toString scanAppsScript;
                  };
                };
              in
              pkgs.runCommandLocal "qs-kh-launcher" { } ''
                mkdir -p $out/lib
                cp ${src}/lib/*.qml $out/lib/
                cp ${src}/qml/kh-launcher.qml $out/shell.qml
                cp ${src}/qml/AppList.qml $out/
                cp ${nixConfig} $out/NixConfig.qml
                cp ${nixBins}   $out/NixBins.qml
              '';
          };
      };
    })

    (lib.mkIf (config.programs.kh-ui.enable && config.wayland.windowManager.hyprland.enable) {
      wayland.windowManager.hyprland.settings.exec-once =
        lib.optionals config.programs.kh-ui.clipboard-history.enable [
          "${lib.getExe pkgs.quickshell} -c kh-cliphist"
          "${lib.getExe' pkgs.wl-clipboard "wl-paste"} --watch ${lib.getExe pkgs.cliphist} store"
        ] ++
        lib.optionals config.programs.kh-ui.launcher.enable [
          "${lib.getExe pkgs.quickshell} -c kh-launcher"
        ] ++
        lib.optionals config.programs.kh-ui.bar.enable [
          "${lib.getExe pkgs.quickshell} -c kh-bar"
        ];
    })
  ];
}
