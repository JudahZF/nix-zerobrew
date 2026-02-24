{
  description = "Zerobrew installation manager for nix-darwin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zerobrew-src = {
      url = "github:lucasgelfond/zerobrew";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, rust-overlay, zerobrew-src }: let
    # Systems supported by zerobrew (macOS only)
    systems = [ "aarch64-darwin" "x86_64-darwin" ];

    pkgsFor = system: import nixpkgs {
      inherit system;
      overlays = [ rust-overlay.overlays.default ];
    };

    forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
      f system (pkgsFor system)
    );
  in {
    packages = forAllSystems (system: pkgs: {
      zerobrew = let
        zerobrewRust = pkgs.rust-bin.stable."1.90.0".default;
      in pkgs.callPackage ./pkgs/zerobrew {
        inherit zerobrew-src;
        rustPlatform = pkgs.makeRustPlatform {
          cargo = zerobrewRust;
          rustc = zerobrewRust;
        };
      };

      default = self.packages.${system}.zerobrew;
    });

    checks = forAllSystems (system: pkgs: {
      zerobrew-help = pkgs.runCommandLocal "zerobrew-help" {
        nativeBuildInputs = [ self.packages.${system}.zerobrew ];
      } ''
        zb --help > "$out"
      '';
    });

    darwinModules = rec {
      nix-zerobrew = { lib, pkgs, ... }: {
        imports = [
          ./modules
        ];
        nix-zerobrew.package = lib.mkOptionDefault self.packages.${pkgs.stdenv.hostPlatform.system}.zerobrew;
        nix-zerobrew.packageRosetta = lib.mkOptionDefault self.packages.x86_64-darwin.zerobrew;
      };

      default = nix-zerobrew;
    };

    devShells = forAllSystems (system: pkgs: {
      default = pkgs.mkShell {
        buildInputs = with pkgs; [
          rustc
          cargo
          openssl
          pkg-config
        ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
          pkgs.apple-sdk_15
          (pkgs.darwinMinVersionHook "10.15")
        ];
      };
    });
  };
}
