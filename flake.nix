{
  description = "Quickshell QML unit tests";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;

      stubColors = {
        base00 = "000000"; base01 = "111111"; base02 = "222222"; base03 = "333333";
        base04 = "444444"; base05 = "555555"; base06 = "666666"; base07 = "777777";
        base08 = "888888"; base09 = "999999"; base0A = "aaaaaa"; base0B = "bbbbbb";
        base0C = "cccccc"; base0D = "dddddd"; base0E = "eeeeee"; base0F = "ffffff";
      };

      # Named QML module directories for qmltestrunner / devShell.
      nixGenDir = pkgs.runCommand "nix-gen-dir" { } ''
        mkdir -p $out/NixConfig $out/NixBins

        printf '%s\n' "module NixConfig" "NixConfig 1.0 NixConfig.qml" \
          > $out/NixConfig/qmldir
        cp ${import ./config.nix {
          inherit pkgs;
          colors   = stubColors;
          fontName = "TestFont";
          fontSize = 12;
        }} $out/NixConfig/NixConfig.qml

        printf '%s\n' "module NixBins" "NixBins 1.0 NixBins.qml" \
          > $out/NixBins/qmldir
        cp ${import ./ffi.nix {
          inherit pkgs lib;
        }} $out/NixBins/NixBins.qml
      '';

      cliphistDecodeAllScript = import ./scripts/cliphist-decode-all.nix { inherit pkgs lib; };

      viewConfig = pkgs.runCommand "kh-view-config" { } ''
        mkdir -p $out/lib
        cp ${self}/lib/*.qml $out/lib/
        cp ${self}/qml/kh-view.qml $out/shell.qml
        cp ${import ./config.nix {
          inherit pkgs;
          colors = {
            base00 = "1e1e2e"; base01 = "181825"; base02 = "313244"; base03 = "45475a";
            base04 = "585b70"; base05 = "cdd6f4"; base06 = "f5c2e7"; base07 = "b4befe";
            base08 = "f38ba8"; base09 = "fab387"; base0A = "f9e2af"; base0B = "a6e3a1";
            base0C = "94e2d5"; base0D = "89b4fa"; base0E = "cba6f7"; base0F = "f2cdcd";
          };
          fontName = "monospace";
          fontSize = 14;
        }} $out/NixConfig.qml
        cp ${import ./ffi.nix {
          inherit pkgs lib;
        }} $out/NixBins.qml
      '';

      cliphistConfig = pkgs.runCommand "kh-cliphist-config" { } ''
        mkdir -p $out/lib
        cp ${self}/lib/*.qml $out/lib/
        cp ${self}/qml/kh-cliphist.qml $out/shell.qml
        cp ${self}/qml/ClipList.qml $out/
        cp ${self}/qml/ClipPreview.qml $out/
        cp ${import ./config.nix {
          inherit pkgs;
          colors = {
            base00 = "1e1e2e"; base01 = "181825"; base02 = "313244"; base03 = "45475a";
            base04 = "585b70"; base05 = "cdd6f4"; base06 = "f5c2e7"; base07 = "b4befe";
            base08 = "f38ba8"; base09 = "fab387"; base0A = "f9e2af"; base0B = "a6e3a1";
            base0C = "94e2d5"; base0D = "89b4fa"; base0E = "cba6f7"; base0F = "f2cdcd";
          };
          fontName = "monospace";
          fontSize = 14;
        }} $out/NixConfig.qml
        cp ${import ./ffi.nix {
          inherit pkgs lib;
          extraBins.cliphistDecodeAll = toString cliphistDecodeAllScript;
        }} $out/NixBins.qml
      '';
    in
    {
      homeModules.default = import ./hm-module.nix self;

      checks.${system}.tests = pkgs.runCommand "qml-tests" {
        src = self;
        nativeBuildInputs = [ pkgs.qt6.qtdeclarative ];
        QT_QPA_PLATFORM = "offscreen";
      } ''
        export HOME=$TMPDIR
        cp -r $src/tests .
        cp -r $src/lib .
        qmltestrunner \
          -import ${pkgs.qt6.qtdeclarative}/lib/qt-6/qml \
          -import lib \
          -import ${nixGenDir} \
          -input tests/
        touch $out
      '';

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.qt6.qtdeclarative ];
        shellHook = ''
          export QT_QPA_PLATFORM=offscreen
          export QML_IMPORT_PATH=${pkgs.qt6.qtdeclarative}/lib/qt-6/qml:$PWD/lib:${nixGenDir}
          echo "Run tests: qmltestrunner -input tests/"
        '';
      };

      packages.${system} = {
        kh-cliphist = cliphistConfig;
        cliphistDecodeAll = cliphistDecodeAllScript;
        kh-view = viewConfig;
      };

      apps.${system} = {
        # Headless screenshot(s) in a single run.
        # Usage: nix run .#screenshot -- <app> <name> [<ipc-call>...] [-- <name> [<ipc-call>...]]...
        # Multiple shots separated by -- share one sway instance and one run directory.
        # Each <ipc-call> is a function name with optional arg, e.g. "setView help" or "type Navigate".
        # The window is opened automatically via toggle before any calls are made.
        screenshot = {
          type = "app";
          program = toString (pkgs.writeShellScript "qs-screenshot" ''
            set -e
            run=/tmp/qs-screenshots/$(date +%Y%m%d-%H%M%S)
            if [[ "$1" == --run ]]; then run=$2; shift 2; fi
            app=$1; shift
            case "$app" in
              kh-cliphist) config=${cliphistConfig}; target=viewer   ;;
              kh-view)     config=${viewConfig};     target=""
                # Build the list file from KH_VIEW_FILE (or KH_VIEW_LIST if already set)
                if [[ -z "''${KH_VIEW_LIST:-}" && -n "''${KH_VIEW_FILE:-}" ]]; then
                  _kv_list=$(mktemp); printf '%s\n' "$KH_VIEW_FILE" > "$_kv_list"
                  export KH_VIEW_LIST="$_kv_list"
                fi
                ;;
              *) echo "usage: screenshot [--run <dir>] <app> <name> [<ipc-call>...] [-- <name> [<ipc-call>...]]..." >&2; exit 1 ;;
            esac
            qs=${lib.getExe' pkgs.quickshell "quickshell"}
            grim=${lib.getExe pkgs.grim}
            sway=${lib.getExe pkgs.sway}
            mkdir -p "$run"

            xdg_runtime=$(mktemp -d)
            export XDG_RUNTIME_DIR=$xdg_runtime
            export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_HEADLESS_OUTPUTS=1
            "$sway" --config /dev/null >/dev/null 2>&1 &
            SWAY_PID=$!
            for i in $(seq 40); do
              sleep 0.1
              socket=$(ls "$xdg_runtime"/wayland-* 2>/dev/null | grep -v lock | head -1)
              [[ -n "$socket" ]] && break
            done
            export WAYLAND_DISPLAY=$(basename "$socket")

            shoot() {
              local name=$1; shift
              local outfile=$run/$name.png
              WAYLAND_DISPLAY=$WAYLAND_DISPLAY "$qs" -p "$config" >/dev/null 2>&1 &
              local pid=$!
              if [[ -n "$target" ]]; then
                for i in $(seq 30); do
                  sleep 0.1
                  "$qs" ipc --pid "$pid" call "$target" toggle >/dev/null 2>&1 && break
                done
              else
                sleep 1.5
              fi
              for call in "$@"; do
                local fn="''${call%% *}"
                if [[ "$fn" == "$call" ]]; then
                  "$qs" ipc --pid "$pid" call "$target" "$fn" >/dev/null 2>&1 || true
                else
                  local arg="''${call#* }"
                  "$qs" ipc --pid "$pid" call "$target" "$fn" "$arg" >/dev/null 2>&1 || true
                fi
              done
              sleep 0.4
              WAYLAND_DISPLAY=$WAYLAND_DISPLAY "$grim" "$outfile"
              echo "$outfile"
              disown "$pid" 2>/dev/null; kill -9 "$pid" 2>/dev/null
            }

            # Split args on '--' and invoke shoot() for each group.
            group=()
            for arg in "$@" "--"; do
              if [[ "$arg" == "--" ]]; then
                [[ ''${#group[@]} -gt 0 ]] && shoot "''${group[@]}"
                group=()
              else
                group+=("$arg")
              fi
            done

            kill -9 "$SWAY_PID" 2>/dev/null
            rm -rf "$xdg_runtime"
          '');
        };
        kh-cliphist = {
          type = "app";
          program = toString (pkgs.writeShellScript "run-kh-cliphist" ''
            qs=${lib.getExe' pkgs.quickshell "quickshell"}
            "$qs" -p ${cliphistConfig} &
            QS_PID=$!
            for i in $(seq 30); do
              sleep 0.1
              "$qs" ipc --pid "$QS_PID" call viewer toggle 2>/dev/null && break
            done
            while [[ "$("$qs" ipc --pid "$QS_PID" prop get viewer showing 2>/dev/null)" == "true" ]]; do
              sleep 0.2
            done
            kill "$QS_PID" 2>/dev/null
            wait "$QS_PID" 2>/dev/null
          '');
        };
        kh-view = {
          type = "app";
          # Usage: nix run .#kh-view -- <file> [<file2> ...]
          #        <cmd> | nix run .#kh-view
          program = toString (pkgs.writeShellScript "run-kh-view" ''
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
          '');
        };
      };
    };
}
