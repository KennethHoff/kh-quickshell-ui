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

  # Patch the env shebang to the package-pinned interpreter so each script
  # runs under a store-stable binary.
  install =
    shebang: interp: mocks:
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: src: ''
        install -Dm755 ${src} $out/bin/${name}
        substituteInPlace $out/bin/${name} \
          --replace-fail '${shebang}' '${interp}'
      '') mocks
    );
in
pkgs.runCommand "kh-test-mocks" { } ''
  mkdir -p $out/bin
  ${install "#!/usr/bin/env bash" "#!${lib.getExe' pkgs.bash "bash"}" shellMocks}
  ${install "#!/usr/bin/env python3" "#!${lib.getExe' py "python3"}" pythonMocks}
''
