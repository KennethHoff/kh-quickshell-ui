{
  description = "Quickshell QML unit tests";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;

      dev = import ./src/dev.nix { inherit pkgs lib self; };
    in
    {
      formatter.${system} = pkgs.nixfmt-tree;

      homeModules.default = {
        imports = [
          (import ./src/hm-module.nix self)
          ./src/stylix-integration.nix
        ];
      };

      packages.${system} = dev.packages;
      apps.${system} = dev.apps;
      devShells.${system}.default = dev.devShell;
    };
}
