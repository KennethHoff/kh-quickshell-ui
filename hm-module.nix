# Home-manager module for kh-ui quickshell components.
#
# Theme-agnostic: colors and fonts are set via programs.kh-ui.theme options.
# Integrations (e.g. Stylix) set those options from outside — this module
# never references any theming system directly.
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

  themeCfg = config.programs.kh-ui.theme;

  nixConfig = import (src + "/config.nix") {
    inherit pkgs;
    colors = themeCfg.colors;
    fontName = themeCfg.fontName;
    fontSize = themeCfg.fontSize;
    inherit (config.programs.kh-ui) volumeMax;
  };

  mkAppConfig =
    {
      name,
      extraBins ? { },
      generatedFiles ? { },
      extraPluginDirs ? [ ],
    }:
    let
      appDir = src + "/apps/${name}";
      pluginsDir = src + "/apps/${name}/plugins";
      nixBins = import (src + "/ffi.nix") { inherit pkgs lib extraBins; };
    in
    pkgs.runCommandLocal "qs-kh-${name}" { } ''
      mkdir -p $out/lib
      cp ${src}/lib/*.qml $out/lib/
      cp ${src}/apps/kh-${name}.qml $out/shell.qml
      ${lib.optionalString (builtins.pathExists appDir) "cp ${appDir}/*.qml $out/"}
      ${lib.optionalString (builtins.pathExists pluginsDir) "cp ${pluginsDir}/*.qml $out/ 2>/dev/null || true"}
      ${lib.concatStrings (lib.mapAttrsToList (dest: path: "cp ${path} $out/${dest}\n") generatedFiles)}
      ${lib.concatMapStrings (d: "cp ${toString d}/*.qml $out/\n") extraPluginDirs}
      cp ${nixConfig} $out/NixConfig.qml
      cp ${nixBins}   $out/NixBins.qml
    '';

  mkBarConfig =
    {
      structure,
      ipcName ? "bar",
      extraPluginDirs ? [ ],
      extraBins ? { },
    }:
    mkAppConfig {
      name = "bar";
      generatedFiles = {
        "BarLayout.qml" = import (src + "/bar-config.nix") { inherit pkgs structure ipcName; };
      };
      extraBins = {
        nmcli = lib.getExe' pkgs.networkmanager "nmcli";
        tailscale = lib.getExe pkgs.tailscale;
      }
      // extraBins;
      inherit extraPluginDirs;
    };
in
{
  options.programs.kh-ui = {
    enable = lib.mkEnableOption "kh-ui shell UI — prerequisite for all kh-ui options; activates nothing on its own. Enable individual components via their own enable options.";

    theme = {
      colors = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = import (src + "/themes/default-light.nix");
        description = ''
          Base16 color palette (hex strings without #). Defaults to a
          neutral dark palette. Theming integrations (e.g. Stylix) can
          set these from outside.
        '';
      };
      fontName = lib.mkOption {
        type = lib.types.str;
        default = "monospace";
        description = ''
          Font family name.
        '';
      };
      fontSize = lib.mkOption {
        type = lib.types.int;
        default = 14;
        description = ''
          Font size in pixels.
        '';
      };
    };

    volumeMax = lib.mkOption {
      type = lib.types.float;
      default = 1.5;
      description = ''
        Maximum volume level as a multiplier (1.0 = 100%). Applied as the
        ceiling in the volume bar plugin and the OSD progress bar. Match this
        to the <literal>-l</literal> flag you pass to <literal>wpctl set-volume</literal>.
      '';
    };

    clipboard-history.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the clipboard history viewer (kh-cliphist).";
    };

    launcher = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable the launcher (kh-launcher) — built-in apps plugin plus user-defined script plugins.";
      };
      terminal = lib.mkOption {
        type = lib.types.package;
        default = pkgs.kitty;
        defaultText = lib.literalExpression "pkgs.kitty";
        description = "Terminal emulator used to launch apps with Terminal=true in their .desktop entry.";
      };
      scriptPlugins = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              script = lib.mkOption {
                type = lib.types.path;
                description = ''
                  Executable that outputs items as 4- or 5-field TSV to stdout:
                  <literal>label\tdescription\ticon\tcallback[\tid]</literal>.
                  The id field is optional and defaults to label; it is used for
                  frecency tracking and desktop-action parsing when enabled.
                '';
              };
              frecency = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Track launch frequency and boost frequently-used items in search results.";
              };
              hasActions = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Enable desktop-action sub-mode (l/Tab) — parses [Desktop Action] sections from the item's id field (must be a .desktop file path).";
              };
              placeholder = lib.mkOption {
                type = lib.types.str;
                default = "Search...";
                description = "Placeholder text shown in the search field when this plugin is active.";
              };
              label = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = ''
                  Display name shown on the plugin chip in the launcher.
                  Defaults to the plugin key (the attribute name under
                  <option>scriptPlugins</option>) when empty, so e.g. a plugin
                  keyed <literal>hyprland-windows</literal> can present itself
                  as <literal>Windows</literal> without changing its stable
                  IPC identifier.
                '';
              };
            };
          }
        );
        default = { };
        description = ''
          Named script plugins that appear alongside the built-in apps plugin.
          Each plugin is backed by an executable that outputs items as TSV.
          Activate via IPC: <literal>qs ipc call launcher activatePlugin &lt;name&gt;</literal>.
        '';
      };
    };

    view.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the file/image viewer (kh-view).";
    };

    osd.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable the on-screen display daemon (kh-osd).

        Reacts automatically to PipeWire volume and mute changes.
        IPC is available for testing: qs ipc call osd showVolume <0–150>
      '';
    };

    bar = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable the status bar (kh-bar).";
      };
      structure = lib.mkOption {
        type = lib.types.str;
        description = ''
          QML structure for the bar layout. The string is placed verbatim
          inside the root BarLayout Item, which exposes <literal>barHeight</literal>,
          <literal>barWindow</literal>, and <literal>ipcPrefix</literal> to all
          children via the parent chain.

          Use <literal>BarRow</literal> for a full-width row and
          <literal>BarSpacer</literal> to push items apart (CSS space-between
          equivalent). Any QML type available in $out/ can be used — built-in
          plugins, lib components, and types from extraPluginDirs.

          Built-in plugins: Workspaces, MediaPlayer, Clock, Volume, Tray.

          Built-in layout / composition types:
          BarRow, BarSpacer, BarGroup, BarDropdown, ControlTile,
          TailscalePanel, EthernetPanel, TailscalePeers,
          DropdownHeader, DropdownDivider, DropdownItem.

          Example — network + audio grouped behind one button:
          <programlisting>
          BarRow {
              Workspaces {}
              BarSpacer {}
              BarGroup {
                  label: "●●●"
                  ipcName: "controlcenter"
                  panelWidth: 300
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

  config =
    let
      qsConfigs =
        lib.optionalAttrs config.programs.kh-ui.clipboard-history.enable {
          kh-cliphist = mkAppConfig {
            name = "cliphist";
            extraBins = {
              cliphistDecodeAll = toString cliphistDecodeAll;
            };
          };
        }
        // lib.optionalAttrs config.programs.kh-ui.bar.enable {
          kh-bar = mkBarConfig {
            inherit (config.programs.kh-ui.bar) structure extraPluginDirs;
          };
        }
        // lib.optionalAttrs config.programs.kh-ui.launcher.enable (
          let
            launcherCfg = config.programs.kh-ui.launcher;
            appsPlugin = import (src + "/apps/launcher/plugins/apps.nix") {
              inherit pkgs lib;
              terminal = launcherCfg.terminal;
            };
            hyprlandWindowsPlugin = import (src + "/apps/launcher/plugins/hyprland-windows.nix") {
              inherit pkgs lib;
            };
            userPlugins = lib.mapAttrs (_: cfg: {
              script = toString cfg.script;
              inherit (cfg) frecency hasActions placeholder label;
              default = false;
            }) launcherCfg.scriptPlugins;
            allPlugins = appsPlugin.plugins // hyprlandWindowsPlugin.plugins // userPlugins;
            pluginRegistryQml = pkgs.writeText "PluginRegistry.qml" ''
              import QtQuick
              QtObject {
                  readonly property var plugins: (${builtins.toJSON allPlugins})
              }
            '';
          in
          {
            kh-launcher = mkAppConfig {
              name = "launcher";
              generatedFiles = {
                "PluginRegistry.qml" = pluginRegistryQml;
              };
            };
          }
        )
        // lib.optionalAttrs config.programs.kh-ui.view.enable {
          kh-view = mkAppConfig { name = "view"; };
        }
        // lib.optionalAttrs config.programs.kh-ui.osd.enable {
          kh-osd = mkAppConfig { name = "osd"; };
        };
    in
    lib.mkMerge [
      (lib.mkIf config.programs.kh-ui.enable {
        programs.quickshell = {
          enable = lib.mkDefault true;
          configs = qsConfigs;
        };

        home.packages =
          lib.optionals config.programs.kh-ui.clipboard-history.enable [
            (pkgs.writeShellScriptBin "kh-cliphist" ''
              exec ${lib.getExe pkgs.quickshell} -c kh-cliphist "$@"
            '')
          ]
          ++ lib.optionals config.programs.kh-ui.launcher.enable [
            (pkgs.writeShellScriptBin "kh-launcher" ''
              exec ${lib.getExe pkgs.quickshell} -c kh-launcher "$@"
            '')
          ]
          ++ lib.optionals config.programs.kh-ui.bar.enable [
            (pkgs.writeShellScriptBin "kh-bar" ''
              exec ${lib.getExe pkgs.quickshell} -c kh-bar "$@"
            '')
          ]
          ++ lib.optionals config.programs.kh-ui.view.enable [
            (pkgs.writeShellScriptBin "kh-view" ''
              exec ${lib.getExe pkgs.quickshell} -c kh-view "$@"
            '')
          ]
          ++ lib.optionals config.programs.kh-ui.osd.enable [
            (pkgs.writeShellScriptBin "kh-osd" ''
              exec ${lib.getExe pkgs.quickshell} -c kh-osd "$@"
            '')
          ];
      })

      (lib.mkIf config.programs.kh-ui.enable {
        systemd.user.services =
          let
            mkQsService = configName: {
              Unit = {
                Description = "Quickshell instance: ${configName}";
                PartOf = [ "graphical-session.target" ];
                After = [ "graphical-session.target" ];
              };
              Service = {
                # -p <store-path> instead of -c <name> so each QML change produces a
                # new ExecStart, which sd-switch diffs to trigger a restart. With
                # -c <name>, ExecStart only changes on a quickshell version bump.
                ExecStart = "${lib.getExe pkgs.quickshell} -p ${qsConfigs.${configName}}";
                Restart = "on-failure";
                RestartSec = 2;
              };
              Install.WantedBy = [ "graphical-session.target" ];
            };
          in
          lib.optionalAttrs config.programs.kh-ui.clipboard-history.enable {
            kh-cliphist = mkQsService "kh-cliphist";
            kh-cliphist-store = {
              Unit = {
                Description = "Clipboard history store (wl-paste -> cliphist)";
                PartOf = [ "graphical-session.target" ];
                After = [ "graphical-session.target" ];
              };
              Service = {
                ExecStart = "${lib.getExe' pkgs.wl-clipboard "wl-paste"} --watch ${lib.getExe pkgs.cliphist} store";
                Restart = "on-failure";
                RestartSec = 2;
              };
              Install.WantedBy = [ "graphical-session.target" ];
            };
          }
          // lib.optionalAttrs config.programs.kh-ui.launcher.enable {
            kh-launcher = mkQsService "kh-launcher";
          }
          // lib.optionalAttrs config.programs.kh-ui.bar.enable {
            kh-bar = mkQsService "kh-bar";
          }
          // lib.optionalAttrs config.programs.kh-ui.osd.enable {
            kh-osd = mkQsService "kh-osd";
          };
      })
    ];
}
