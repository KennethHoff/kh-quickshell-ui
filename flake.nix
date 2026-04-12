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

      cliphistDecodeAllScript = pkgs.writeShellScript "kh-cliphist-decode-all" ''
        ${lib.getExe pkgs.cliphist} list | while IFS=$'\t' read -r id preview; do
            [[ "$preview" == "[[binary"* ]] && continue
            [[ ''${#preview} -lt 100 ]] && continue
            text=$(printf '%s\t%s\n' "$id" "$preview" | ${lib.getExe pkgs.cliphist} decode)
            json=$(printf '%s' "$text" | ${lib.getExe pkgs.jq} -Rs .)
            printf '%s\t%s\n' "$id" "$json"
        done
      '';

      cliphistConfig = pkgs.runCommand "kh-cliphist-config" { } ''
        mkdir -p $out/lib
        cp ${self}/lib/*.qml $out/lib/
        cp ${self}/qml/kh-cliphist.qml $out/shell.qml
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

      packages.${system}.kh-cliphist = cliphistConfig;

      apps.${system}.kh-cliphist = {
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
    };
}
