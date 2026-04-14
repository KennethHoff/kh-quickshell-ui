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

  mkAppConfig =
    { name
    , extraBins ? {}
    , generatedFiles ? {}
    , extraPluginDirs ? []
    }:
    let
      appDir     = src + "/apps/${name}";
      pluginsDir = src + "/apps/${name}/plugins";
      nixBins    = import (src + "/ffi.nix") { inherit pkgs lib extraBins; };
    in
    pkgs.runCommandLocal "qs-kh-${name}" { } ''
      mkdir -p $out/lib
      cp ${src}/lib/*.qml $out/lib/
      cp ${src}/apps/kh-${name}.qml $out/shell.qml
      ${lib.optionalString (builtins.pathExists appDir)     "cp ${appDir}/*.qml $out/"}
      ${lib.optionalString (builtins.pathExists pluginsDir) "cp ${pluginsDir}/*.qml $out/"}
      ${lib.concatStrings (lib.mapAttrsToList (dest: path: "cp ${path} $out/${dest}\n") generatedFiles)}
      ${lib.concatMapStrings (d: "cp ${toString d}/*.qml $out/\n") extraPluginDirs}
      cp ${nixConfig} $out/NixConfig.qml
      cp ${nixBins}   $out/NixBins.qml
    '';

  mkBarConfig =
    { structure, extraPluginDirs ? [] }:
    mkAppConfig {
      name = "bar";
      generatedFiles = { "BarLayout.qml" = import (src + "/bar-config.nix") { inherit pkgs structure; }; };
      inherit extraPluginDirs;
    };
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

    view.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the file/image viewer (kh-view).";
    };

    bar = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable the status bar (kh-bar).";
      };
      structure = lib.mkOption {
        type = lib.types.str;
        default = ''
              BarRow {
                  Workspaces {}
                  MediaPlayer {}
                  BarSpacer {}
                  ControlCenter {}
                  Clock {}
                  Volume {}
                  Tray {}
              }
        '';
        description = ''
          QML structure for the bar layout. The string is placed verbatim
          inside the root BarLayout Item, which exposes <literal>barHeight</literal>
          and <literal>barWindow</literal> to all children via the parent chain.

          Use <literal>BarRow</literal> for a full-width row and
          <literal>BarSpacer</literal> to push items apart (CSS space-between
          equivalent). Any QML type available in $out/ can be used — built-in
          plugins, lib components, and types from extraPluginDirs.

          Built-in plugins: Workspaces, MediaPlayer, ControlCenter, Clock,
          Volume, Tray.

          Built-in layout / composition types:
          BarRow, BarSpacer, BarDropdown, ControlPanel, ControlTile,
          TailscalePanel, EthernetPanel, TailscalePeers,
          DropdownHeader, DropdownDivider, DropdownItem.

          Example — custom composition without ControlCenter:
          <programlisting>
          BarRow {
              Workspaces {}
              BarSpacer {}
              ControlPanel {
                  Row {
                      spacing: 8
                      EthernetPanel {}
                      TailscalePanel { id: ts }
                  }
                  TailscalePeers { source: ts }
              }
              Clock {}
              Volume {}
              Tray {}
          }
          </programlisting>
        '';
      };
      extraPluginDirs = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        description = ''
          Paths to directories containing extra bar plugin or component .qml files.
          All *.qml files from each directory are copied into the bar config root
          and auto-discovered by Quickshell, making their types available by name
          in the <option>structure</option> string.
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
            kh-cliphist = mkAppConfig {
              name = "cliphist";
              extraBins = { cliphistDecodeAll = toString cliphistDecodeAll; };
            };
          } //
          lib.optionalAttrs config.programs.kh-ui.bar.enable {
            kh-bar = mkBarConfig {
              inherit (config.programs.kh-ui.bar) structure extraPluginDirs;
            };
          } //
          lib.optionalAttrs config.programs.kh-ui.launcher.enable {
            kh-launcher = mkAppConfig {
              name = "launcher";
              extraBins = { scanApps = toString scanAppsScript; };
            };
          } //
          lib.optionalAttrs config.programs.kh-ui.view.enable {
            kh-view = mkAppConfig { name = "view"; };
          };
      };

      home.packages =
        lib.optionals config.programs.kh-ui.clipboard-history.enable [
          (pkgs.writeShellScriptBin "kh-cliphist" ''
            exec ${lib.getExe pkgs.quickshell} -c kh-cliphist "$@"
          '')
        ] ++
        lib.optionals config.programs.kh-ui.launcher.enable [
          (pkgs.writeShellScriptBin "kh-launcher" ''
            exec ${lib.getExe pkgs.quickshell} -c kh-launcher "$@"
          '')
        ] ++
        lib.optionals config.programs.kh-ui.bar.enable [
          (pkgs.writeShellScriptBin "kh-bar" ''
            exec ${lib.getExe pkgs.quickshell} -c kh-bar "$@"
          '')
        ] ++
        lib.optionals config.programs.kh-ui.view.enable [
          (pkgs.writeShellScriptBin "kh-view" ''
            exec ${lib.getExe pkgs.quickshell} -c kh-view "$@"
          '')
        ];
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
