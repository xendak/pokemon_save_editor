{
  description = "HGSS Save Editor - Zig Project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zig.url = "github:mitchellh/zig-overlay";
    zls.url = "github:zigtools/zls";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      zig,
      zls,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        zigPackage = zig.packages.${system}.master;
        zlsPackage = zls.packages.${system}.default;
        pkgs = import nixpkgs {
          inherit system;
          nativeBuildInputs = [
            zigPackage
            zlsPackage
          ];
          overlays = [
            (final: prev: {
              inherit zigPackage zlsPackage;
            })
          ];
        };
        hexa = pkgs.writeShellScriptBin "hexa" ''
          hexyl ./saves/AAAAAAA.sav $@
        '';
        hexb = pkgs.writeShellScriptBin "hexb" ''
          hexyl ./saves/BBBBBBB.sav $@
        '';
      in
      {
        packages.default = pkgs.callPackage ./default.nix { inherit zigPackage; };

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [
            zigPackage
            zlsPackage
          ];
          packages = with pkgs; [
            raylib

            # for save dumps
            hexyl
            hexa
            hexb
          ];

          shellHook = ''
            if [ -f ./init.sh ]; then
              echo "Initializing project..."
              chmod +x ./init.sh
              ./init.sh
              rm ./init.sh
              echo "Project initialized successfully!
              using Zig ${zigPackage.version} environment"
            else
              echo "HGSS Save Editor
              using Zig ${zigPackage.version} environment"
            fi
          '';
        };
      }
    );
}
