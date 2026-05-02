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
  src = self + "/src";
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
      ${lib.optionalString (builtins.pathExists appDir) "find ${appDir} -name '*.qml' -exec cp -t $out/ {} +"}
      ${lib.optionalString (builtins.pathExists pluginsDir) "find ${pluginsDir} -name '*.qml' -exec cp -t $out/ {} + 2>/dev/null || true"}
      ${lib.concatStrings (lib.mapAttrsToList (dest: path: "cp ${path} $out/${dest}\n") generatedFiles)}
      ${lib.concatMapStrings (
        d: "find ${toString d} -name '*.qml' -exec cp -t $out/ {} + 2>/dev/null || true\n"
      ) extraPluginDirs}
      cp ${nixConfig} $out/NixConfig.qml
      cp ${nixBins}   $out/NixBins.qml
    '';

  mkBarConfig =
    {
      instances,
      extraPluginDirs ? [ ],
      extraBins ? { },
    }:
    mkAppConfig {
      name = "bar";
      generatedFiles = import (src + "/bar-config.nix") { inherit pkgs lib instances; };
      extraBins = {
        df = lib.getExe' pkgs.coreutils "df";
        nmcli = lib.getExe' pkgs.networkmanager "nmcli";
        tailscale = lib.getExe pkgs.tailscale;
        swayncClient = lib.getExe' pkgs.swaynotificationcenter "swaync-client";
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
              keybindings = lib.mkOption {
                type = lib.types.listOf (
                  lib.types.submodule {
                    options = {
                      key = lib.mkOption {
                        type = lib.types.str;
                        description = ''
                          Key name — either a single lowercase letter/digit
                          (<literal>a</literal>, <literal>1</literal>) or one of
                          the named specials: <literal>Return</literal>,
                          <literal>Tab</literal>, <literal>Escape</literal>,
                          <literal>Space</literal>, <literal>Backspace</literal>.
                        '';
                      };
                      mods = lib.mkOption {
                        type = lib.types.listOf (
                          lib.types.enum [
                            "Ctrl"
                            "Shift"
                            "Alt"
                          ]
                        );
                        default = [ ];
                        description = "Required modifier keys.  Empty list means no modifiers.";
                      };
                      mode = lib.mkOption {
                        type = lib.types.enum [
                          "normal"
                          "actions"
                        ];
                        default = "normal";
                        description = "Launcher input mode in which this binding applies.";
                      };
                      run = lib.mkOption {
                        type = lib.types.str;
                        default = "";
                        description = ''
                          Shell template executed when this combo fires.
                          <literal>{callback}</literal> is substituted with the
                          selected item's callback (or the selected action's exec,
                          in actions mode) and the result piped through bash.
                          Example: <literal>"hyprctl dispatch exec [workspace 1] {callback}"</literal>.
                          Set this for item-launching bindings; leave empty for
                          mode-transition bindings that use <option>action</option>.
                        '';
                      };
                      action = lib.mkOption {
                        type = lib.types.enum [
                          ""
                          "enterActionsMode"
                          "enterNormalMode"
                          "close"
                        ];
                        default = "";
                        description = ''
                          Mode/lifecycle transition fired when the combo is pressed:
                          <itemizedlist>
                            <listitem><para><literal>enterActionsMode</literal> — switch to the desktop-actions sub-mode (no-op unless <option>hasActions</option> is true).</para></listitem>
                            <listitem><para><literal>enterNormalMode</literal> — return from actions mode to the main item list.</para></listitem>
                            <listitem><para><literal>close</literal> — close the launcher window.</para></listitem>
                          </itemizedlist>
                          Mutually exclusive with <option>run</option>.
                        '';
                      };
                      helpKey = lib.mkOption {
                        type = lib.types.str;
                        default = "";
                        description = ''
                          Display string for this binding in the <literal>?</literal>
                          help overlay (e.g. <literal>"Enter"</literal>,
                          <literal>"Ctrl+1–9"</literal>).  Defaults to the raw
                          <option>key</option> when <option>helpDesc</option> is
                          set but this field is empty.
                        '';
                      };
                      helpDesc = lib.mkOption {
                        type = lib.types.str;
                        default = "";
                        description = ''
                          Description shown beside <option>helpKey</option> in the
                          <literal>?</literal> overlay.  Leave empty to hide this
                          binding from help (use for aliases like <literal>l</literal>
                          when another binding already covers the row).
                        '';
                      };
                    };
                  }
                );
                default = [
                  {
                    key = "Return";
                    run = "{callback}";
                    helpKey = "Enter";
                    helpDesc = "run";
                  }
                ];
                description = ''
                  Keybindings this plugin owns.  Core handles only navigation
                  (j/k, gg, G, Ctrl+D/U, [, ], /, ?, Esc, q); every action
                  key (Enter, Tab, Ctrl+1–9, …) must be declared here.
                  Help for each binding is inline via <option>helpKey</option> /
                  <option>helpDesc</option>.
                  Default is a single <literal>Return → {callback}</literal>
                  binding so Enter runs the selected item's callback verbatim.
                '';
              };
              hintText = lib.mkOption {
                type = lib.types.str;
                default = "Enter run";
                description = "Plugin-specific footer hint shown in normal mode alongside core navigation hints.";
              };
              hintTextActions = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Plugin-specific footer hint shown in actions mode.  Empty to omit.";
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

    window-inspector.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable the window inspector (kh-window-inspector) — a pick-first
        overlay over open Hyprland windows. Toggle via:
        qs ipc -c kh-window-inspector call window-inspector toggle
      '';
    };

    bar = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable the status bar (kh-bar).";
      };
      instances = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              screen = lib.mkOption {
                type = lib.types.strMatching ".+";
                description = ''
                  Wayland output name the bar appears on (e.g.
                  <literal>DP-1</literal>, <literal>HDMI-A-2</literal>). There
                  is no "primary" concept in Wayland, so this is required.
                  If the output isn't connected at launch — or gets unplugged
                  later — the bar silently hides and reappears on reconnect.
                '';
              };
              structure = lib.mkOption {
                type = lib.types.str;
                description = ''
                  QML structure for this bar's layout. Inserted verbatim
                  inside the generated BarLayout Item, which exposes
                  <literal>barHeight</literal>, <literal>barWindow</literal>,
                  and <literal>ipcPrefix</literal> to all children via the
                  parent chain.

                  Use <literal>BarRow</literal> for a full-width row and
                  <literal>BarSpacer</literal> to push items apart. Built-in
                  plugins: Workspaces, MediaPlayer, Clock, Volume, Tray,
                  Notifications, CpuUsage, RamUsage, GpuUsage, DiskUsage,
                  CpuTemp, GpuTemp. The *Usage / *Temp plugins are data-only
                  — compose with BarText to render their values.

                  Built-in layout / composition types:
                  BarRow, BarSpacer, BarPipe, BarGroup, BarDropdown, BarText,
                  BarIcon, BarTooltip, BarControlTile, BarDropdownHeader,
                  BarHorizontalDivider, BarDropdownItem, TailscalePanel,
                  EthernetPanel, TailscalePeers.
                '';
              };
            };
          }
        );
        default = { };
        example = lib.literalExpression ''
          {
            main = {
              screen = "DP-1";
              structure = '''
                BarRow {
                    Workspaces {}
                    BarSpacer {}
                    Clock {}
                    Volume {}
                    Tray {}
                }
              ''';
            };
          }
        '';
        description = ''
          Bar instances keyed by <literal>ipcName</literal>. Each attribute
          name becomes the root IPC target for that bar (e.g.
          <literal>main</literal> → <literal>qs ipc call main getHeight</literal>),
          so names must start with a lowercase letter and contain only
          lowercase letters and digits (<literal>^[a-z][a-z0-9]*$</literal>).

          Two instances may not target the same screen — enforced via
          assertion.
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
      environment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Environment variables passed to the kh-bar service with direct values.
          Use for non-secret configuration values. Secret values should be passed
          via <option>environmentFiles</option> instead.
        '';
      };
      environmentFiles = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        description = ''
          Paths to files containing environment variables to source for the kh-bar service.
          Use this to pass secret values (e.g., API keys from sops/agenix).
          Each file should contain VAR=value lines that will be sourced by systemd.
        '';
      };
      notifications.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable the bar's notification bell, backed by swaync.

          Activates <option>services.swaync.enable</option> (via
          <literal>lib.mkDefault</literal>, so external overrides win) and
          points the bell plugin at <literal>swaync-client --subscribe-waybar</literal>
          for live count updates. swaync becomes the sole owner of
          <literal>org.freedesktop.Notifications</literal> on the session bus,
          which means kh-bar restarts no longer drop the notification daemon
          out from under apps mid-Notify (the previous setup crashed
          Firefox/Zen on every <literal>home-manager switch</literal>).

          Disable to opt out of the bell entirely or to wire your own
          notification daemon — the <literal>Notifications {}</literal> plugin
          will be non-functional in that case, so omit it from
          <option>bar.instances.&lt;name&gt;.structure</option> too.
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
            inherit (config.programs.kh-ui.bar) instances extraPluginDirs;
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
            emojiPlugin = import (src + "/apps/launcher/plugins/emoji.nix") {
              inherit pkgs lib;
            };
            userPlugins = lib.mapAttrs (_: cfg: {
              script = toString cfg.script;
              inherit (cfg)
                frecency
                hasActions
                placeholder
                label
                keybindings
                hintText
                hintTextActions
                ;
              default = false;
            }) launcherCfg.scriptPlugins;
            allPlugins =
              appsPlugin.plugins // hyprlandWindowsPlugin.plugins // emojiPlugin.plugins // userPlugins;
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
              }
              // (appsPlugin.generatedFiles or { })
              // (hyprlandWindowsPlugin.generatedFiles or { })
              // (emojiPlugin.generatedFiles or { });
            };
          }
        )
        // lib.optionalAttrs config.programs.kh-ui.view.enable {
          kh-view = mkAppConfig { name = "view"; };
        }
        // lib.optionalAttrs config.programs.kh-ui.osd.enable {
          kh-osd = mkAppConfig { name = "osd"; };
        }
        // lib.optionalAttrs config.programs.kh-ui.window-inspector.enable {
          kh-window-inspector = mkAppConfig { name = "window-inspector"; };
        };
      barCfg = config.programs.kh-ui.bar;
      barInstanceList = lib.mapAttrsToList (name: spec: {
        inherit name;
        inherit (spec) screen;
      }) barCfg.instances;
      duplicateScreenGroups =
        let
          byScreen = lib.groupBy (i: i.screen) barInstanceList;
        in
        lib.filterAttrs (_: entries: builtins.length entries > 1) byScreen;
    in
    lib.mkMerge [
      (lib.mkIf
        (
          config.programs.kh-ui.enable
          && config.programs.kh-ui.bar.enable
          && config.programs.kh-ui.bar.notifications.enable
        )
        {
          # swaync owns org.freedesktop.Notifications on the session bus.
          # mkDefault so a user already running swaync (or a downstream
          # override) wins. Lifetime is independent of kh-bar — sd-switch
          # only restarts swaync on its own ExecStart change, which only
          # moves on a swaync version bump.
          services.swaync.enable = lib.mkDefault true;
        }
      )

      (lib.mkIf config.programs.kh-ui.enable {
        programs.quickshell = {
          enable = lib.mkDefault true;
          configs = qsConfigs;
        };

        home.packages = lib.optionals config.programs.kh-ui.view.enable [
          (pkgs.writeShellScriptBin "kh-view" (
            toString (import (src + "/scripts/kh-view-wrapper.nix") { inherit pkgs lib; })
          ))
        ];

        assertions = lib.optionals (config.programs.kh-ui.enable && barCfg.enable) (
          (lib.mapAttrsToList (name: _spec: {
            assertion = builtins.match "[a-z][a-z0-9]*" name != null;
            message = ''
              programs.kh-ui.bar.instances.${name}: ipcName must match ^[a-z][a-z0-9]*$
              (lowercase letter followed by lowercase letters or digits). It becomes the
              root IPC target for this bar, so it must be a legal identifier.
            '';
          }) barCfg.instances)
          ++ (lib.mapAttrsToList (screen: entries: {
            assertion = false;
            message =
              let
                names = lib.concatMapStringsSep ", " (e: e.name) entries;
              in
              ''
                programs.kh-ui.bar.instances: multiple bars target screen
                ${screen}: ${names}. Each screen may host at most one bar.
              '';
          }) duplicateScreenGroups)
        );

        warnings =
          lib.optional (config.programs.kh-ui.enable && barCfg.enable && barCfg.instances == { })
            ''
              programs.kh-ui.bar.enable is true but bar.instances is empty — the
              kh-bar service will start but render no bars. Add at least one entry
              under programs.kh-ui.bar.instances.<name> = { screen; structure; }
              or set bar.enable = false to silence this warning.
            '';
      })

      (lib.mkIf config.programs.kh-ui.enable {
        systemd.user.services =
          let
            mkQsService = configName: serviceOpts: {
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
              }
              // serviceOpts;
              Install.WantedBy = [ "graphical-session.target" ];
            };
          in
          lib.optionalAttrs config.programs.kh-ui.clipboard-history.enable {
            kh-cliphist = mkQsService "kh-cliphist" { };
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
            kh-launcher = mkQsService "kh-launcher" { };
          }
          // lib.optionalAttrs config.programs.kh-ui.bar.enable {
            kh-bar = mkQsService "kh-bar" {
              Environment = lib.mapAttrsToList (k: v: "${k}=${v}") config.programs.kh-ui.bar.environment;
              EnvironmentFiles = config.programs.kh-ui.bar.environmentFiles;
            };
          }
          // lib.optionalAttrs config.programs.kh-ui.osd.enable {
            kh-osd = mkQsService "kh-osd" { };
          }
          // lib.optionalAttrs config.programs.kh-ui.window-inspector.enable {
            kh-window-inspector = mkQsService "kh-window-inspector" { };
          };
      })
    ];
}
