# Dev plumbing — pre-built configs (with hardcoded Catppuccin colours)
# plus the `nix run .#<name>` wrappers that launch them. flake.nix
# re-exports `packages` and `apps` from this attrset.
#
# Real consumers should reach for the home-manager module instead —
# these pre-built configs only exist so contributors can `nix run
# .#kh-bar` and so dev-tooling skills can `nix build .#kh-bar
# --print-out-paths` to introspect a generated config without spinning
# up a downstream consumer.
{
  pkgs,
  lib,
  self,
}:
let
  defaultColors = import ./themes/default-light.nix;

  nixConfigQml = import ./config.nix {
    inherit pkgs;
    colors = defaultColors;
    fontName = "monospace";
    fontSize = 14;
  };

  cliphistDecodeAllScript = import ./scripts/cliphist-decode-all.nix { inherit pkgs lib; };
  appsPlugin = import ./apps/launcher/plugins/apps.nix {
    inherit pkgs lib;
    terminal = pkgs.kitty;
  };
  hyprlandWindowsPlugin = import ./apps/launcher/plugins/hyprland-windows.nix {
    inherit pkgs lib;
  };
  emojiPlugin = import ./apps/launcher/plugins/emoji.nix {
    inherit pkgs lib;
  };

  # mkAppConfig builds a kh-{name} app derivation following the static layout:
  #   src/apps/kh-{name}.qml     → $out/shell.qml
  #   src/apps/{name}/**/*.qml   → $out/   (recursive — any subdir works: primitives/, plugins/, …)
  #   src/lib/*.qml              → $out/lib/
  # generatedFiles: { "Dest.qml" = <store-path>; } for eval-time generated files.
  # extraPluginDirs: list of paths whose *.qml files are copied into $out/.
  mkAppConfig =
    {
      name,
      extraBins ? { },
      generatedFiles ? { },
      extraPluginDirs ? [ ],
    }:
    let
      appDir = "${self}/src/apps/${name}";
      nixBins = import ./ffi.nix { inherit pkgs lib extraBins; };
    in
    pkgs.runCommand "kh-${name}-config" { } ''
      mkdir -p $out/lib
      cp ${self}/src/lib/*.qml $out/lib/
      cp ${self}/src/apps/kh-${name}.qml $out/shell.qml
      ${lib.optionalString (builtins.pathExists appDir) "find ${appDir} -name '*.qml' -exec cp -t $out/ {} +"}
      ${lib.concatStrings (lib.mapAttrsToList (dest: src: "cp ${src} $out/${dest}\n") generatedFiles)}
      ${lib.concatMapStrings (d: "cp ${toString d}/*.qml $out/\n") extraPluginDirs}
      cp ${nixConfigQml} $out/NixConfig.qml
      cp ${nixBins}      $out/NixBins.qml
    '';

  # mkBarConfig wraps mkAppConfig for the bar, which needs per-instance
  # BarLayout files plus a BarInstances registry generated at eval time.
  mkBarConfig =
    {
      instances,
      extraPluginDirs ? [ ],
      extraBins ? { },
    }:
    mkAppConfig {
      name = "bar";
      generatedFiles = import ./bar-config.nix { inherit pkgs lib instances; };
      extraBins = {
        df = lib.getExe' pkgs.coreutils "df";
        nmcli = lib.getExe' pkgs.networkmanager "nmcli";
        tailscale = lib.getExe pkgs.tailscale;
        swayncClient = lib.getExe' pkgs.swaynotificationcenter "swaync-client";
      }
      // extraBins;
      inherit extraPluginDirs;
    };

  viewConfig = mkAppConfig { name = "view"; };

  launcherPluginRegistry =
    let
      allPlugins = appsPlugin.plugins // hyprlandWindowsPlugin.plugins // emojiPlugin.plugins;
    in
    pkgs.writeText "PluginRegistry.qml" ''
      import QtQuick
      QtObject {
          readonly property var plugins: (${builtins.toJSON allPlugins})
      }
    '';

  launcherConfig = mkAppConfig {
    name = "launcher";
    generatedFiles = {
      "PluginRegistry.qml" = launcherPluginRegistry;
    }
    // (appsPlugin.generatedFiles or { })
    // (hyprlandWindowsPlugin.generatedFiles or { })
    // (emojiPlugin.generatedFiles or { });
  };

  barConfig = mkBarConfig {
    instances.devbar = {
      screen = "DP-1";
      structure = ''
        BarRow {
            Workspaces {}
            MediaPlayer {}
            BarSpacer {}
            BarGroup {
                label: "stats"
                ipcName: "stats"
                panelWidth: 320

                CpuUsage  { id: cpuUsage }
                RamUsage  { id: ramUsage }
                GpuUsage  { id: gpuUsage }
                DiskUsage { id: diskUsage }
                CpuTemp   { id: cpuTemp  }
                GpuTemp   { id: gpuTemp  }

                Column {
                    spacing: 8

                    Column {
                        spacing: 2
                        BarText { text: "usage"; color: mutedColor }
                        BarText { text: "  cpu · " + cpuUsage.usage   + "%" }
                        BarText { text: "  ram · " + ramUsage.percent + "%" }
                        BarText { text: "  gpu · " + gpuUsage.busy    + "% (" + gpuUsage.vramUsedMb + "M/" + gpuUsage.vramTotalMb + "M)" }
                    }

                    Column {
                        spacing: 2
                        BarText { text: "temperature"; color: mutedColor }
                        BarText {
                            text:  "  cpu · " + cpuTemp.temp + "°"
                            color: cpuTemp.temp >= 80 ? errorColor
                                 : cpuTemp.temp >= 60 ? warnColor
                                 :                      normalColor
                        }
                        BarText {
                            text:  "  gpu · " + gpuTemp.temp + "°"
                            color: gpuTemp.temp >= 80 ? errorColor
                                 : gpuTemp.temp >= 60 ? warnColor
                                 :                      normalColor
                        }
                    }

                    Column {
                        spacing: 2
                        BarText { text: "storage"; color: mutedColor }
                        Repeater {
                            model: diskUsage.results
                            BarText {
                                text: "  " + modelData.mount + " · "
                                    + Math.round(modelData.usedB  / 1e9) + "G/"
                                    + Math.round(modelData.totalB / 1e9) + "G"
                            }
                        }
                    }
                }
            }
            BarPipe {}
            Tray {}
            Notifications {}
            BarPipe {}
            Clock {}
            Volume {}
            BarPipe {}
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
        }
      '';
    };
  };

  cliphistConfig = mkAppConfig {
    name = "cliphist";
    extraBins = {
      cliphistDecodeAll = toString cliphistDecodeAllScript;
    };
  };

  osdConfig = mkAppConfig { name = "osd"; };

  windowInspectorConfig = mkAppConfig { name = "window-inspector"; };

  qs = lib.getExe' pkgs.quickshell "quickshell";

  mkApp = name: script: {
    type = "app";
    program = toString (pkgs.writeShellScript "run-${name}" script);
  };
in
{
  packages = {
    kh-bar = barConfig;
    kh-cliphist = cliphistConfig;
    cliphistDecodeAll = cliphistDecodeAllScript;
    kh-osd = osdConfig;
    kh-view = viewConfig;
    kh-launcher = launcherConfig;
    kh-window-inspector = windowInspectorConfig;
  };

  apps = {
    kh-bar = mkApp "kh-bar" ''
      exec ${qs} -p ${barConfig}
    '';

    kh-osd = mkApp "kh-osd" ''
      exec ${qs} -p ${osdConfig}
    '';

    # Start the OSD, fire showVolume (default 65), let it fade, exit.
    # Usage: nix run .#kh-osd-test                  # showVolume 65
    #        nix run .#kh-osd-test -- 30            # showVolume 30
    #        nix run .#kh-osd-test -- mute          # showMuted
    kh-osd-test = mkApp "kh-osd-test" ''
      ${qs} -p ${osdConfig} &
      pid=$!
      trap 'kill "$pid" 2>/dev/null' EXIT
      for i in $(seq 30); do
        sleep 0.1
        ${qs} ipc --pid "$pid" call osd showVolume 0 >/dev/null 2>&1 && break
      done
      arg=''${1:-65}
      if [[ "$arg" == "mute" ]]; then
        ${qs} ipc --pid "$pid" call osd showMuted
      else
        ${qs} ipc --pid "$pid" call osd showVolume "$arg"
      fi
      sleep 3
    '';

    kh-launcher = mkApp "kh-launcher" ''
      ${qs} -p ${launcherConfig} &
      QS_PID=$!
      for i in $(seq 30); do
        sleep 0.1
        ${qs} ipc --pid "$QS_PID" call launcher toggle 2>/dev/null && break
      done
      while [[ "$(${qs} ipc --pid "$QS_PID" prop get launcher showing 2>/dev/null)" == "true" ]]; do
        sleep 0.2
      done
      kill "$QS_PID" 2>/dev/null
      wait "$QS_PID" 2>/dev/null
    '';

    kh-launcher-daemon = mkApp "kh-launcher-daemon" ''
      exec ${qs} -p ${launcherConfig}
    '';

    # Runs the cliphist daemon without opening the overlay — useful during
    # development to keep wl-paste --watch active while copying from other apps.
    # Ctrl+C to stop. Open/close the overlay separately via IPC.
    kh-cliphist-daemon = mkApp "kh-cliphist-daemon" ''
      exec ${qs} -p ${cliphistConfig}
    '';

    kh-cliphist = mkApp "kh-cliphist" ''
      ${qs} -p ${cliphistConfig} &
      QS_PID=$!
      for i in $(seq 30); do
        sleep 0.1
        ${qs} ipc --pid "$QS_PID" call cliphist toggle 2>/dev/null && break
      done
      while [[ "$(${qs} ipc --pid "$QS_PID" prop get cliphist showing 2>/dev/null)" == "true" ]]; do
        sleep 0.2
      done
      kill "$QS_PID" 2>/dev/null
      wait "$QS_PID" 2>/dev/null
    '';

    kh-view = {
      type = "app";
      program = toString (
        import ./scripts/kh-view-wrapper.nix {
          inherit pkgs lib;
          viewConfigPath = viewConfig;
        }
      );
    };

    kh-window-inspector = mkApp "kh-window-inspector" ''
      ${qs} -p ${windowInspectorConfig} &
      QS_PID=$!
      for i in $(seq 30); do
        sleep 0.1
        ${qs} ipc --pid "$QS_PID" call window-inspector toggle 2>/dev/null && break
      done
      while [[ "$(${qs} ipc --pid "$QS_PID" prop get window-inspector showing 2>/dev/null)" == "true" ]]; do
        sleep 0.2
      done
      kill "$QS_PID" 2>/dev/null
      wait "$QS_PID" 2>/dev/null
    '';

    kh-window-inspector-daemon = mkApp "kh-window-inspector-daemon" ''
      exec ${qs} -p ${windowInspectorConfig}
    '';
  };
}
