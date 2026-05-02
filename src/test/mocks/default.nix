# Bundles every mock binary into a single derivation exposing $out/bin/<name>.
# Consumers (test bar's extraBins, hyprland.conf exec-once, harness) can take
# `${mocks}/bin/<name>` knowing the path is store-stable.
{
  pkgs,
  lib,
}:
let
  py = pkgs.python3.withPackages (ps: [ ps.dbus-next ]);

  shellMocks = {
    "df" = ./df.sh;
    "nmcli" = ./nmcli.sh;
    "tailscale" = ./tailscale.sh;
    "swaync-client" = ./swaync-client.sh;
    "fake-clients" = ./fake-clients.sh;
  };

  pythonMocks = {
    "mock-mpris" = ./mock-mpris.py;
    "mock-tray" = ./mock-tray.py;
  };

  installShell = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: src: ''
      install -Dm755 ${src} $out/bin/${name}
      # Patch shebang so the script runs against the package's bash.
      substituteInPlace $out/bin/${name} \
        --replace-fail '#!/usr/bin/env bash' '#!${pkgs.bash}/bin/bash'
    '') shellMocks
  );

  installPython = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: src: ''
      install -Dm755 ${src} $out/bin/${name}
      substituteInPlace $out/bin/${name} \
        --replace-fail '#!/usr/bin/env python3' '#!${py}/bin/python3'
    '') pythonMocks
  );
in
pkgs.runCommand "kh-test-mocks" { } ''
  mkdir -p $out/bin
  ${installShell}
  ${installPython}
''
