{
  description = "Quickshell QML unit tests";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    microvm.url = "github:astro/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      microvm,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;

      dev = import ./src/dev.nix { inherit pkgs lib self; };

      test = import ./src/test {
        inherit
          pkgs
          lib
          self
          nixpkgs
          microvm
          dev
          ;
      };
    in
    {
      formatter.${system} = pkgs.nixfmt-tree;

      homeModules.default = {
        imports = [
          (import ./src/hm-module.nix self)
          ./src/stylix-integration.nix
        ];
      };

      packages.${system} = dev.packages // {
        kh-test-vm = test.runner;
        kh-bar-vm-test = test.barConfig;
      };

      apps.${system} = dev.apps // {
        kh-test-vm-daemon = test.daemonApp;
        screenshot-bar-vm = test.screenshotApp;
      };

      nixosConfigurations.kh-test-vm = test.nixosConfig;
    };
}
