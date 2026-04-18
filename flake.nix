{
  description = "Quickshell QML unit tests";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;

      defaultColors = import ./themes/default-light.nix;

      # Named QML module directories for qmltestrunner / devShell.
      nixGenDir = pkgs.runCommand "nix-gen-dir" { } ''
        mkdir -p $out/NixConfig $out/NixBins

        printf '%s\n' "module NixConfig" "NixConfig 1.0 NixConfig.qml" \
          > $out/NixConfig/qmldir
        cp ${
          import ./config.nix {
            inherit pkgs;
            colors = defaultColors;
            fontName = "monospace";
            fontSize = 14;
          }
        } $out/NixConfig/NixConfig.qml

        printf '%s\n' "module NixBins" "NixBins 1.0 NixBins.qml" \
          > $out/NixBins/qmldir
        cp ${
          import ./ffi.nix {
            inherit pkgs lib;
          }
        } $out/NixBins/NixBins.qml
      '';

      cliphistDecodeAllScript = import ./scripts/cliphist-decode-all.nix { inherit pkgs lib; };
      appsPlugin = import ./apps/launcher/plugins/apps.nix {
        inherit pkgs lib;
        terminal = pkgs.kitty;
      };
      hyprlandWindowsPlugin = import ./apps/launcher/plugins/hyprland-windows.nix {
        inherit pkgs lib;
      };

      nixConfigQml = import ./config.nix {
        inherit pkgs;
        colors = defaultColors;
        fontName = "monospace";
        fontSize = 14;
      };

      # mkAppConfig builds a kh-{name} app derivation following the static layout:
      #   apps/kh-{name}.qml        → $out/shell.qml
      #   apps/{name}/*.qml         → $out/          (if the directory exists)
      #   apps/{name}/plugins/*.qml → $out/          (if the directory exists)
      #   lib/*.qml                 → $out/lib/
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
          appDir = "${self}/apps/${name}";
          pluginsDir = "${self}/apps/${name}/plugins";
          nixBins = import ./ffi.nix { inherit pkgs lib extraBins; };
        in
        pkgs.runCommand "kh-${name}-config" { } ''
          mkdir -p $out/lib
          cp ${self}/lib/*.qml $out/lib/
          cp ${self}/apps/kh-${name}.qml $out/shell.qml
          ${lib.optionalString (builtins.pathExists appDir) "cp ${appDir}/*.qml $out/"}
          ${lib.optionalString (builtins.pathExists pluginsDir) "cp ${pluginsDir}/*.qml $out/ 2>/dev/null || true"}
          ${lib.concatStrings (lib.mapAttrsToList (dest: src: "cp ${src} $out/${dest}\n") generatedFiles)}
          ${lib.concatMapStrings (d: "cp ${toString d}/*.qml $out/\n") extraPluginDirs}
          cp ${nixConfigQml} $out/NixConfig.qml
          cp ${nixBins}      $out/NixBins.qml
        '';

      # mkBarConfig wraps mkAppConfig for the bar, which needs a generated
      # BarLayout.qml and supports user-supplied extraPluginDirs.
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
            "BarLayout.qml" = import ./bar-config.nix { inherit pkgs structure ipcName; };
          };
          extraBins = {
            df = lib.getExe' pkgs.coreutils "df";
            nmcli = lib.getExe' pkgs.networkmanager "nmcli";
            tailscale = lib.getExe pkgs.tailscale;
          }
          // extraBins;
          inherit extraPluginDirs;
        };

      viewConfig = mkAppConfig { name = "view"; };
      launcherPluginRegistry =
        let
          allPlugins = appsPlugin.plugins // hyprlandWindowsPlugin.plugins;
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
        };
      };

      barConfig = mkBarConfig {
        ipcName = "dev-bar";
        structure = ''
          BarRow {
              Workspaces {}
              MediaPlayer {}
              BarSpacer {}
              BarGroup {
                  label: "stats"
                  ipcName: "stats"
                  panelWidth: 320

                  // Data sources — plugins declared up top so the presentation
                  // below is uncluttered. Each exposes readable properties for
                  // the BarText bindings to pick up.
                  CpuUsage  { id: cpuUsage }
                  RamUsage  { id: ramUsage }
                  GpuUsage  { id: gpuUsage }
                  DiskUsage { id: diskUsage }
                  CpuTemp   { id: cpuTemp  }
                  GpuTemp   { id: gpuTemp  }

                  // Presentation — three labelled sections; each row uses a
                  // middle-dot infix ( · ) to separate key from value so
                  // identifiers like the "/" mount path read clearly.
                  Column {
                      spacing: 8

                      Column {
                          spacing: 2
                          BarText { text: "usage";                                       color: mutedColor }
                          BarText { text: "  cpu · " + cpuUsage.usage   + "%" }
                          BarText { text: "  ram · " + ramUsage.percent + "%" }
                          BarText { text: "  gpu · " + gpuUsage.busy    + "% (" + gpuUsage.vramUsedMb + "M/" + gpuUsage.vramTotalMb + "M)" }
                      }

                      Column {
                          spacing: 2
                          BarText { text: "temperature";                                 color: mutedColor }
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
                          BarText { text: "storage";                                     color: mutedColor }
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

      cliphistConfig = mkAppConfig {
        name = "cliphist";
        extraBins = {
          cliphistDecodeAll = toString cliphistDecodeAllScript;
        };
      };

      osdConfig = mkAppConfig { name = "osd"; };
    in
    {
      formatter.${system} = pkgs.nixfmt-tree;

      homeModules.default = {
        imports = [
          (import ./hm-module.nix self)
          ./stylix-integration.nix
        ];
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.qt6.qtdeclarative ];
        shellHook = ''
          export QT_QPA_PLATFORM=offscreen
          export QML_IMPORT_PATH=${pkgs.qt6.qtdeclarative}/lib/qt-6/qml:$PWD/lib:${nixGenDir}
          echo "Run tests: qmltestrunner -input tests/"
        '';
      };

      packages.${system} = {
        kh-bar = barConfig;
        kh-cliphist = cliphistConfig;
        cliphistDecodeAll = cliphistDecodeAllScript;
        kh-osd = osdConfig;
        kh-view = viewConfig;
        kh-launcher = launcherConfig;
      };

      apps.${system} = {
        kh-bar = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "run-kh-bar" ''
              qs=${lib.getExe' pkgs.quickshell "quickshell"}
              exec "$qs" -p ${barConfig}
            ''
          );
        };
        kh-osd = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "run-kh-osd" ''
              qs=${lib.getExe' pkgs.quickshell "quickshell"}
              exec "$qs" -p ${osdConfig}
            ''
          );
        };
        # Start the OSD, fire showVolume (default 65), let it fade, exit.
        # Usage: nix run .#kh-osd-test                  # showVolume 65
        #        nix run .#kh-osd-test -- 30            # showVolume 30
        #        nix run .#kh-osd-test -- mute          # showMuted
        kh-osd-test = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "run-kh-osd-test" ''
              qs=${lib.getExe' pkgs.quickshell "quickshell"}
              "$qs" -p ${osdConfig} &
              pid=$!
              trap 'kill "$pid" 2>/dev/null' EXIT
              for i in $(seq 30); do
                sleep 0.1
                "$qs" ipc --pid "$pid" call osd showVolume 0 >/dev/null 2>&1 && break
              done
              arg=''${1:-65}
              if [[ "$arg" == "mute" ]]; then
                "$qs" ipc --pid "$pid" call osd showMuted
              else
                "$qs" ipc --pid "$pid" call osd showVolume "$arg"
              fi
              sleep 3
            ''
          );
        };
        kh-launcher = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "run-kh-launcher" ''
              qs=${lib.getExe' pkgs.quickshell "quickshell"}
              "$qs" -p ${launcherConfig} &
              QS_PID=$!
              for i in $(seq 30); do
                sleep 0.1
                "$qs" ipc --pid "$QS_PID" call launcher toggle 2>/dev/null && break
              done
              while [[ "$("$qs" ipc --pid "$QS_PID" prop get launcher showing 2>/dev/null)" == "true" ]]; do
                sleep 0.2
              done
              kill "$QS_PID" 2>/dev/null
              wait "$QS_PID" 2>/dev/null
            ''
          );
        };
        kh-launcher-daemon = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "run-kh-launcher-daemon" ''
              qs=${lib.getExe' pkgs.quickshell "quickshell"}
              exec "$qs" -p ${launcherConfig}
            ''
          );
        };
        kh-cliphist-daemon = {
          type = "app";
          # Runs the cliphist daemon without opening the overlay — useful during
          # development to keep wl-paste --watch active while copying from other apps.
          # Ctrl+C to stop. Open/close the overlay separately via IPC.
          program = toString (
            pkgs.writeShellScript "run-kh-cliphist-daemon" ''
              qs=${lib.getExe' pkgs.quickshell "quickshell"}
              exec "$qs" -p ${cliphistConfig}
            ''
          );
        };
        kh-cliphist = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "run-kh-cliphist" ''
              qs=${lib.getExe' pkgs.quickshell "quickshell"}
              "$qs" -p ${cliphistConfig} &
              QS_PID=$!
              for i in $(seq 30); do
                sleep 0.1
                "$qs" ipc --pid "$QS_PID" call cliphist toggle 2>/dev/null && break
              done
              while [[ "$("$qs" ipc --pid "$QS_PID" prop get cliphist showing 2>/dev/null)" == "true" ]]; do
                sleep 0.2
              done
              kill "$QS_PID" 2>/dev/null
              wait "$QS_PID" 2>/dev/null
            ''
          );
        };
        kh-view = {
          type = "app";
          # Usage: nix run .#kh-view -- <file> [<file2> ...]
          #        <cmd> | nix run .#kh-view
          program = toString (
            pkgs.writeShellScript "run-kh-view" ''
              set -e
              qs=${lib.getExe' pkgs.quickshell "quickshell"}
              list=$(mktemp)
              trap 'rm -f "$list"' EXIT
              if [[ $# -ge 1 ]]; then
                for f in "$@"; do printf '%s\n' "$f" >> "$list"; done
                export KH_VIEW_LIST="$list"
                exec "$qs" -p ${viewConfig}
              else
                tmp=$(mktemp)
                trap 'rm -f "$tmp"' EXIT
                cat > "$tmp"
                printf '%s\n' "$tmp" >> "$list"
                export KH_VIEW_LIST="$list"
                "$qs" -p ${viewConfig}
              fi
            ''
          );
        };
      };
    };
}
