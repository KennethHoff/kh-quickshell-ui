{
  description = "Quickshell QML unit tests";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;

      nixffiDir = pkgs.runCommand "nixffi-dir" { } ''
        mkdir -p $out/NixFFI
        echo "module NixFFI"          > $out/NixFFI/qmldir
        echo "NixFFI 1.0 NixFFI.qml" >> $out/NixFFI/qmldir
        cp ${import ./ffi.nix {
          inherit pkgs lib;
          colors = {
            base00 = "000000"; base01 = "111111"; base02 = "222222"; base03 = "333333";
            base04 = "444444"; base05 = "555555"; base06 = "666666"; base07 = "777777";
            base08 = "888888"; base09 = "999999"; base0A = "aaaaaa"; base0B = "bbbbbb";
            base0C = "cccccc"; base0D = "dddddd"; base0E = "eeeeee"; base0F = "ffffff";
          };
          fontName = "TestFont";
          fontSize = 12;
        }} $out/NixFFI/NixFFI.qml
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
        qmltestrunner \
          -import ${pkgs.qt6.qtdeclarative}/lib/qt-6/qml \
          -import $src/lib \
          -import ${nixffiDir} \
          -input tests/
        touch $out
      '';

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.qt6.qtdeclarative ];
        shellHook = ''
          export QT_QPA_PLATFORM=offscreen
          export QML_IMPORT_PATH=${pkgs.qt6.qtdeclarative}/lib/qt-6/qml:$PWD/lib:${nixffiDir}
          echo "Run tests: qmltestrunner -input tests/"
        '';
      };
    };
}
