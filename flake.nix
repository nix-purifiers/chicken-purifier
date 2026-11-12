{
  description = "Locked, Nix-resolved CHICKEN dependencies";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.purifier = {
    url = "github:nix-purifiers/purifier";
    flake = false;
  };
  outputs =
    {
      self,
      nixpkgs,
      purifier,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = nixpkgs.lib.genAttrs systems;
      overlay = final: prev: {
        chicken-purifier = final.lib.makeScope final.newScope (scope: {
          nativeChicken = scope.callPackage ./pkgs/build-chicken-project/native.nix { };
          toolchain = scope.callPackage ./pkgs/build-chicken-project/toolchain.nix { };
          sdkVersion = import ./pkgs/build-chicken-project/sdk-version.nix { nixpkgsSrc = nixpkgs; };
          cli = scope.callPackage ./pkgs/cli/default.nix {
            nixpkgsSrc = nixpkgs;
            purifierSrc = purifier;
          };
          buildChickenProject = scope.callPackage ./pkgs/build-chicken-project/default.nix {
            purifier = import (purifier + "/nix/lib") { inherit (final) lib; };
          };
        });
      };
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ overlay ];
        };
    in
    {
      overlays.default = overlay;
      packages = forAll (system: {
        default = (pkgsFor system).chicken-purifier.cli;
        cli = self.packages.${system}.default;
        sdk = (pkgsFor system).chicken-purifier.toolchain;
      });
      lib.chicken-purifier = (nixpkgs.lib.extend (import ./lib-overlays/default)).chicken-purifier;
      apps = forAll (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/chicken-purifier";
          meta.description = "Lock native CHICKEN eggs";
        };
      });
      checks = forAll (
        system:
        let
          pkgs = pkgsFor system;
          build = pkgs.chicken-purifier.buildChickenProject { src = ./examples/minimal; };
        in
        {
          inherit (build.packages) environment project;
          release = build.release;
          cli = self.packages.${system}.default;
          installed = pkgs.runCommand "chicken-installed-consumer" { } ''
            ${build.packages.project}/bin/csi -quiet -e '(import purifier-example) (assert (= (answer) 42))'
            mkdir "$out"
          '';
        }
      );
      formatter = forAll (system: (pkgsFor system).nixfmt-tree);
    };
}
