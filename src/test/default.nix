# Test infrastructure entry point. Wires the test bar config, mocks,
# Hyprland config, harness, NixOS test VM, and host-side daemon/client into
# a single attrset consumed by flake.nix.
#
# Returns:
#   nixosConfig      — nixosSystem result (declares the test VM)
#   runner           — the microvm runner derivation (boot-the-VM script)
#   barConfig        — kh-bar-vm-test config derivation (consumed by client)
#   daemonApp        — flake `app` for kh-test-vm-daemon (boot+hold)
#   screenshotApp    — flake `app` for screenshot-bar-vm (one-shot client)
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

  barConfig = import ./test-bar.nix { inherit dev mocks; };

  harness = import ./harness.nix {
    inherit pkgs;
    defaultBarConfig = barConfig;
  };

  hyprConfigPath = import ./hypr-config.nix { inherit pkgs mocks harness; };

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

  mkApp = name: program: {
    type = "app";
    inherit program;
  };

  daemonApp = mkApp "kh-test-vm-daemon" (
    let
      pkg = import ./daemon.nix {
        inherit pkgs;
        vmRunner = runner;
        virtiofsd = nixosConfig.config.microvm.virtiofsd.package;
      };
    in
    "${pkg}/bin/kh-test-vm-daemon"
  );

  screenshotApp = mkApp "screenshot-bar-vm" (
    let
      pkg = import ./client.nix {
        inherit pkgs;
        defaultBarConfig = barConfig;
      };
    in
    "${pkg}/bin/screenshot-bar-vm"
  );
in
{
  inherit
    nixosConfig
    runner
    barConfig
    daemonApp
    screenshotApp
    ;
}
