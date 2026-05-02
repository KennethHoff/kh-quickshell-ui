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

      packages.${system} =
        dev.packages
        // test.testConfigs
        // {
          kh-headless-vm = test.runner;
        };

      apps.${system} = dev.apps // {
        kh-headless-daemon = test.daemonApp;
        kh-headless = test.khTestApp;
      };

      nixosConfigurations.kh-headless-vm = test.nixosConfig;
    };
}
