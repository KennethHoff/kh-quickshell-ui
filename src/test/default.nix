# Test infrastructure entry point. Wires the test qs configs, mocks,
# Hyprland config, harness, NixOS test VM, and host-side daemon + kh-headless
# CLI into a single attrset consumed by flake.nix.
#
# Returns:
#   nixosConfig    — nixosSystem result (declares the test VM)
#   runner         — the microvm runner derivation
#   testConfigs    — { kh-bar-headless = <derivation>; ... }
#   daemonApp      — flake `app` for kh-headless-daemon
#   khTestApp      — flake `app` for kh-headless (single primitive CLI)
{
  pkgs,
  lib,
  self,
  nixpkgs,
  microvm,
  dev,
}:
let
  system = "x86_64-linux";

  mocks = import ./mocks { inherit pkgs lib; };

  testConfigs = import ./configs.nix {
    inherit
      pkgs
      lib
      dev
      mocks
      ;
  };

  harness = import ./harness.nix { inherit pkgs; };

  hyprConfigPath = import ./hypr-config.nix {
    inherit
      pkgs
      lib
      mocks
      harness
      ;
  };

  nixosConfig = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      microvm.nixosModules.microvm
      (
        { ... }:
        import ./vm.nix {
          inherit pkgs lib hyprConfigPath;
          fakeFs = ./fake-fs.nix;
        }
      )
    ];
  };

  runner = nixosConfig.config.microvm.declaredRunner;

  mkApp = program: {
    type = "app";
    inherit program;
  };

  daemonApp = mkApp (
    let
      pkg = import ./daemon.nix {
        inherit pkgs lib;
        vmRunner = runner;
        virtiofsd = nixosConfig.config.microvm.virtiofsd.package;
      };
    in
    lib.getExe pkg
  );

  khTestApp = mkApp (
    let
      pkg = import ./kh-headless.nix { inherit pkgs; };
    in
    lib.getExe pkg
  );
in
{
  inherit
    nixosConfig
    runner
    testConfigs
    daemonApp
    khTestApp
    ;
}
