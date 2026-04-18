{
  description = "Quickshell QML unit tests";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
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
            nmcli = lib.getExe' pkgs.networkmanager "nmcli";
            tailscale = lib.getExe pkgs.tailscale;
          }
          // extraBins;
          inherit extraPluginDirs;
        };

      viewConfig = mkAppConfig { name = "view"; };
      launcherPluginRegistry =
        let
          allPlugins = appsPlugin.plugins;
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
              Tray {}
              Notifications {}
              Clock {}
              Volume {}
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
        # Headless screenshot(s) in a single run.
        # Usage: nix run .#screenshot -- [--show] <app> <name> [<ipc-call>...] [-- <name> [<ipc-call>...]]...
        # Multiple shots separated by -- share one sway instance and one output directory
        # (/tmp/qs-screenshots/<timestamp>/).
        # Each <ipc-call> is a function name with optional args, space-separated in a single string.
        # The window is opened automatically via toggle before any calls are made.
        # --show opens the captured PNGs in kh-view on the caller's Wayland session after all shots complete.
        screenshot = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "qs-screenshot" ''
                            set -e
                            run=/tmp/qs-screenshots/$(date +%Y%m%d-%H%M%S)
                            show=0
                            orig_wayland_display=''${WAYLAND_DISPLAY:-}
                            while [[ $# -gt 0 ]]; do
                              case "$1" in
                                --show) show=1; shift ;;
                                *) break ;;
                              esac
                            done
                            # set_app_config sets: config, target, crop. Returns non-zero if the
                            # argument is not a recognised app name, so callers can use it to
                            # test whether a group's first token is an app-switch marker.
                            # crop geometry (grim -g "X,Y WxH") auto-trims to each app's chrome
                            # on a 3840x2160 output.
                            set_app_config() {
                              case "$1" in
                                kh-bar)      config=${barConfig};      target="";         crop="0,0 3840x40" ;;
                                kh-cliphist) config=${cliphistConfig}; target=cliphist;   crop="" ;;
                                kh-launcher) config=${launcherConfig}; target=launcher;   crop="" ;;
                                kh-osd)      config=${osdConfig};      target="";         crop="1720,2000 400x100" ;;
                                kh-view)     config=${viewConfig};     target="";         crop=""
                                  if [[ -z "''${KH_VIEW_LIST:-}" && -n "''${KH_VIEW_FILE:-}" ]]; then
                                    _kv_list=$(mktemp); printf '%s\n' "$KH_VIEW_FILE" > "$_kv_list"
                                    export KH_VIEW_LIST="$_kv_list"
                                  fi
                                  ;;
                                *) return 1 ;;
                              esac
                            }
                            if ! set_app_config "$1"; then
                              echo "usage: screenshot [--show] <app> <name> [<ipc-call>...] [-- [<app>] <name> [<ipc-call>...]]..." >&2
                              echo "       groups starting with a kh-* token switch config; otherwise they reuse the previous app." >&2
                              exit 1
                            fi
                            shift
                            qs=${lib.getExe' pkgs.quickshell "quickshell"}
                            grim=${lib.getExe pkgs.grim}
                            sway=${lib.getExe pkgs.sway}
                            mkdir -p "$run"

                            # Hermetic fontconfig: no system fonts, only what we ship.
                            # DejaVu covers text (mapped as the monospace generic family);
                            # Symbols Nerd Font provides icon glyph fallback.
                            # Cache is keyed by a hash of the font store paths — it stays valid
                            # across invocations until the packaged fonts themselves change,
                            # saving the ~0.5s fc-cache pass on repeat runs.
                            font_cache=$HOME/.cache/kh-screenshot/fonts-${
                              builtins.substring 0 16 (
                                builtins.hashString "sha256" "${pkgs.dejavu_fonts}${pkgs.nerd-fonts.symbols-only}"
                              )
                            }
                            mkdir -p "$font_cache/fc-cache"
                            fonts_conf=$font_cache/fonts.conf
                            if [[ ! -f "$fonts_conf" ]]; then
                              cat > "$fonts_conf" << FONTSEOF
              <?xml version="1.0"?>
              <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
              <fontconfig>
                <dir>${pkgs.dejavu_fonts}/share/fonts</dir>
                <dir>${pkgs.nerd-fonts.symbols-only}/share/fonts</dir>
                <alias>
                  <family>monospace</family>
                  <prefer><family>DejaVu Sans Mono</family></prefer>
                </alias>
                <cachedir>$font_cache/fc-cache</cachedir>
              </fontconfig>
              FONTSEOF
                            fi
                            export FONTCONFIG_FILE=$fonts_conf
                            if [[ -z "$(ls -A "$font_cache/fc-cache" 2>/dev/null)" ]]; then
                              ${lib.getExe' pkgs.fontconfig "fc-cache"} 2>/dev/null || true
                            fi

                            xdg_runtime=$(mktemp -d)
                            export XDG_RUNTIME_DIR=$xdg_runtime
                            export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_HEADLESS_OUTPUTS=1
                            sway_config=$(mktemp)
                            echo 'output HEADLESS-1 resolution 3840x2160' > "$sway_config"
                            "$sway" --config "$sway_config" >/dev/null 2>&1 &
                            SWAY_PID=$!
                            for i in $(seq 40); do
                              sleep 0.1
                              socket=$(ls "$xdg_runtime"/wayland-* 2>/dev/null | grep -v lock | head -1)
                              [[ -n "$socket" ]] && break
                            done
                            export WAYLAND_DISPLAY=$(basename "$socket")

                            # Reuse a single quickshell process across consecutive shots of the
                            # same app. Readiness is detected by retrying the first IPC call
                            # until it succeeds — quickshell returns non-zero until the handler
                            # is registered — so we don't need a blind sleep after spawn.
                            current_pid=""
                            current_config=""

                            ensure_daemon() {
                              if [[ "$current_config" == "$config" && -n "$current_pid" ]] && kill -0 "$current_pid" 2>/dev/null; then
                                return 1  # reused
                              fi
                              if [[ -n "$current_pid" ]]; then
                                kill -9 "$current_pid" 2>/dev/null || true
                                wait "$current_pid" 2>/dev/null || true
                              fi
                              WAYLAND_DISPLAY=$WAYLAND_DISPLAY "$qs" -p "$config" >/dev/null 2>&1 &
                              current_pid=$!
                              current_config=$config
                              return 0  # fresh spawn
                            }

                            shoot() {
                              local name=$1; shift
                              local outfile=$run/$name.png
                              local fresh=0
                              ensure_daemon && fresh=1

                              # On fresh spawn, use the first available action as the ready-probe.
                              # Retry until IPC succeeds, replacing the old blind 1.5s sleep.
                              if [[ $fresh -eq 1 ]]; then
                                if [[ -n "$target" ]]; then
                                  for i in $(seq 30); do
                                    sleep 0.05
                                    "$qs" ipc --pid "$current_pid" call "$target" toggle >/dev/null 2>&1 && break
                                  done
                                elif [[ $# -gt 0 ]]; then
                                  # Use the first IPC call as the probe; consume it from "$@".
                                  local probe=$1; shift
                                  for i in $(seq 30); do
                                    sleep 0.05
                                    eval "set -- $probe"
                                    "$qs" ipc --pid "$current_pid" call "$@" >/dev/null 2>&1 && break
                                  done
                                else
                                  # No probe available (e.g. kh-bar has no IPC) — short fallback.
                                  sleep 0.4
                                fi
                              fi
                              for call in "$@"; do
                                if [[ -z "$target" ]]; then
                                  # No fixed target — call string is "target function [args...]"
                                  eval "set -- $call"
                                  "$qs" ipc --pid "$current_pid" call "$@" >/dev/null 2>&1 || true
                                else
                                  eval "set -- $call"
                                  "$qs" ipc --pid "$current_pid" call "$target" "$@" >/dev/null 2>&1 || true
                                fi
                              done
                              sleep 0.25
                              if [[ -n "$crop" ]]; then
                                WAYLAND_DISPLAY=$WAYLAND_DISPLAY "$grim" -g "$crop" "$outfile"
                              else
                                WAYLAND_DISPLAY=$WAYLAND_DISPLAY "$grim" "$outfile"
                              fi
                              echo "$outfile"
                            }

                            # Split args on '--' and invoke shoot() for each group.
                            # If a group's first token is a recognised app name, switch
                            # the active config before shooting; otherwise reuse the previous app.
                            group=()
                            for arg in "$@" "--"; do
                              if [[ "$arg" == "--" ]]; then
                                if [[ ''${#group[@]} -gt 0 ]]; then
                                  if set_app_config "''${group[0]}" 2>/dev/null; then
                                    shoot "''${group[@]:1}"
                                  else
                                    shoot "''${group[@]}"
                                  fi
                                fi
                                group=()
                              else
                                group+=("$arg")
                              fi
                            done

                            if [[ -n "$current_pid" ]]; then
                              kill -9 "$current_pid" 2>/dev/null || true
                              wait "$current_pid" 2>/dev/null || true
                            fi
                            kill -9 "$SWAY_PID" 2>/dev/null
                            rm -rf "$xdg_runtime"

                            # --show: hand captured PNGs off to kh-view on the caller's session.
                            if [[ "$show" == 1 ]]; then
                              list=$(mktemp)
                              ls -1tr "$run"/*.png > "$list"
                              WAYLAND_DISPLAY=$orig_wayland_display KH_VIEW_LIST=$list "$qs" -p ${viewConfig}
                            fi
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
