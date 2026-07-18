{
  description = "Bobrshot development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {nixpkgs, ...}: let
    systems = ["aarch64-darwin" "x86_64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    devShells = forAllSystems (system: let
      packages = nixpkgs.legacyPackages.${system};
    in {
      default = packages.mkShellNoCC {
        packages = [packages.zig];
      };
    });
  };
}
