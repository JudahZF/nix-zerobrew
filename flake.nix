{
  description = "Zerobrew installation manager for nix-darwin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zerobrew-src = {
      type = "github";
      owner = "lucasgelfond";
      repo = "zerobrew";
      ref = "v0.3.2";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, rust-overlay, zerobrew-src, }:
    let
      # Systems supported by zerobrew (macOS only)
      systems = [ "aarch64-darwin" "x86_64-darwin" ];

      pkgsFor = system:
        import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f system (pkgsFor system));
    in {
      packages = forAllSystems (system: pkgs: {
        zerobrew = let zerobrewRust = pkgs.rust-bin.stable."1.95.0".default;
        in pkgs.callPackage ./pkgs/zerobrew {
          inherit zerobrew-src;
          rustPlatform = pkgs.makeRustPlatform {
            cargo = zerobrewRust;
            rustc = zerobrewRust;
          };
        };

        nix-homebrew-compatibility-report =
          self.checks.${system}.nix-homebrew-compatibility;

        default = self.packages.${system}.zerobrew;
      });

      checks = forAllSystems (system: pkgs: {
        zerobrew-cli-smoke = pkgs.runCommandLocal "zerobrew-cli-smoke" {
          nativeBuildInputs = [ self.packages.${system}.zerobrew ];
        } ''
          zb --help > "$out"
          zb install --help >/dev/null
          zb update --help >/dev/null
          zb outdated --help >/dev/null
          zb doctor --help >/dev/null
          zb upgrade --help >/dev/null
          zb bundle --help >/dev/null
          zb bundle install --help > bundle-install-help.out
          grep -Eq -- '(-f|--file)' bundle-install-help.out
          zb bundle dump --help > bundle-dump-help.out
          grep -Eq -- '(-f|--file)' bundle-dump-help.out
          zb gc --help >/dev/null
          zb completion bash >/dev/null
          zbx > zbx.out 2>&1 || [ "$?" -eq 1 ]
          grep -q "Usage: zbx" zbx.out
        '';

        nix-homebrew-compatibility = import ./tests/nix-homebrew-compat {
          inherit pkgs;
          lib = nixpkgs.lib;
          module = ./modules;
          zerobrewPackage = pkgs.hello;
        };

        module-eval = pkgs.runCommandLocal "nix-zerobrew-module-eval" {
          nativeBuildInputs = [ pkgs.nix ];
        } ''
          nix-instantiate --eval --strict --expr '
            let
              pkgs = import ${pkgs.path} { system = "${system}"; };
              lib = pkgs.lib;
              evaluated = lib.evalModules {
                specialArgs = { inherit pkgs; };
                modules = [
                  ${./modules}
                  ({ lib, ... }: {
                    options.system.primaryUser = lib.mkOption {
                      type = lib.types.str;
                      default = "alice";
                    };
                    options.system.activationScripts = lib.mkOption {
                      type = lib.types.attrsOf lib.types.anything;
                      default = {};
                    };
                    options.environment.systemPackages = lib.mkOption {
                      type = lib.types.listOf lib.types.package;
                      default = [];
                    };
                    options.programs.bash.interactiveShellInit = lib.mkOption {
                      type = lib.types.lines;
                      default = "";
                    };
                    options.programs.zsh.interactiveShellInit = lib.mkOption {
                      type = lib.types.lines;
                      default = "";
                    };
                    options.programs.fish.interactiveShellInit = lib.mkOption {
                      type = lib.types.lines;
                      default = "";
                    };
                    options.homebrew.enable = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                    };
                    options.assertions = lib.mkOption {
                      type = lib.types.listOf lib.types.unspecified;
                      default = [ ];
                    };
                    config.nix-zerobrew = {
                      enable = true;
                      user = "alice";
                      package = pkgs.hello;
                      enableRosetta = pkgs.stdenv.hostPlatform.isAarch64;
                      onActivation.autoUpdate = true;
                      onActivation.upgrade = true;
                      brews = [ "jq" { name = "ripgrep"; args = [ "HEAD" ]; } ];
                      casks = [ "iterm2" { name = "visual-studio-code"; args = [ "no_quarantine" ]; } ];
                      masApps.Xcode = 497799835;
                      taps."homebrew/homebrew-core" = pkgs.emptyDirectory;
                      mutableTaps = false;
                      enableDoctorCheck = false;
                      warnAboutPackageManagement = false;
                      prefixes."/opt/zerobrew".extraLinkDirs = [ "custom" ];
                      prefixes."/opt/zerobrew-custom" = {
                        enable = true;
                        package = pkgs.hello;
                        taps."hashicorp/homebrew-tap" = pkgs.emptyDirectory;
                        brews = [ { name = "hashicorp/homebrew-tap/terraform"; args = [ "HEAD" ]; } ];
                        casks = [ { name = "docker"; args = [ "no_quarantine" ]; } ];
                      };
                    };
                  })
                ];
              };
              emptyEvaluated = lib.evalModules {
                specialArgs = { inherit pkgs; };
                modules = [
                  ${./modules}
                  ({ lib, ... }: {
                    options.system.primaryUser = lib.mkOption {
                      type = lib.types.str;
                      default = "alice";
                    };
                    options.system.activationScripts = lib.mkOption {
                      type = lib.types.attrsOf lib.types.anything;
                      default = {};
                    };
                    options.environment.systemPackages = lib.mkOption {
                      type = lib.types.listOf lib.types.package;
                      default = [];
                    };
                    options.programs.bash.interactiveShellInit = lib.mkOption {
                      type = lib.types.lines;
                      default = "";
                    };
                    options.programs.zsh.interactiveShellInit = lib.mkOption {
                      type = lib.types.lines;
                      default = "";
                    };
                    options.programs.fish.interactiveShellInit = lib.mkOption {
                      type = lib.types.lines;
                      default = "";
                    };
                    options.homebrew.enable = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                    };
                    options.assertions = lib.mkOption {
                      type = lib.types.listOf lib.types.unspecified;
                      default = [ ];
                    };
                    config.nix-zerobrew = {
                      enable = true;
                      user = "alice";
                      package = pkgs.hello;
                      enableDoctorCheck = false;
                      warnAboutPackageManagement = false;
                    };
                  })
                ];
              };
              noCleanupEvaluated = lib.evalModules {
                specialArgs = { inherit pkgs; };
                modules = [
                  ${./modules}
                  ({ lib, ... }: {
                    options.system.primaryUser = lib.mkOption { type = lib.types.str; default = "alice"; };
                    options.system.activationScripts = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = {}; };
                    options.environment.systemPackages = lib.mkOption { type = lib.types.listOf lib.types.package; default = []; };
                    options.programs.bash.interactiveShellInit = lib.mkOption { type = lib.types.lines; default = ""; };
                    options.programs.zsh.interactiveShellInit = lib.mkOption { type = lib.types.lines; default = ""; };
                    options.programs.fish.interactiveShellInit = lib.mkOption { type = lib.types.lines; default = ""; };
                    options.homebrew.enable = lib.mkOption { type = lib.types.bool; default = false; };
                    options.assertions = lib.mkOption { type = lib.types.listOf lib.types.unspecified; default = [ ]; };
                    config.nix-zerobrew = {
                      enable = true;
                      user = "alice";
                      package = pkgs.hello;
                      brews = [ "jq" ];
                      onActivation.cleanup = "none";
                      enableDoctorCheck = false;
                    };
                  })
                ];
              };
              activationText = evaluated.config.system.activationScripts.setup-zerobrew.text;
              emptyActivationText = emptyEvaluated.config.system.activationScripts.setup-zerobrew.text;
              noCleanupActivationText = noCleanupEvaluated.config.system.activationScripts.setup-zerobrew.text;
            in
              assert lib.assertMsg (builtins.elem "jq" (map (entry: if builtins.isString entry then entry else entry.name) evaluated.config.nix-zerobrew.brews)) "string brews option did not evaluate";
              assert lib.assertMsg (builtins.elem "ripgrep" (map (entry: if builtins.isString entry then entry else entry.name) evaluated.config.nix-zerobrew.brews)) "attr brews option did not evaluate";
              assert lib.assertMsg (builtins.elem "iterm2" (map (entry: if builtins.isString entry then entry else entry.name) evaluated.config.nix-zerobrew.casks)) "string casks option did not evaluate";
              assert lib.assertMsg (builtins.elem "visual-studio-code" (map (entry: if builtins.isString entry then entry else entry.name) evaluated.config.nix-zerobrew.casks)) "attr casks option did not evaluate";
              assert lib.assertMsg (evaluated.config.nix-zerobrew.masApps.Xcode == 497799835) "masApps option did not evaluate";
              assert lib.assertMsg (lib.hasInfix "bundle install" activationText) "activation text missing bundle install";
              assert lib.assertMsg (lib.hasInfix "Brewfile" activationText) "activation text missing generated Brewfile path";
              assert lib.assertMsg (lib.hasInfix "install mas" activationText) "activation text missing mas install through zb";
              assert lib.assertMsg (lib.hasInfix "mas\" install" activationText) "activation text missing mas install";
              assert lib.assertMsg (lib.hasInfix "\"$BIN_ZB\" update" activationText) "onActivation.autoUpdate missing zb update";
              assert lib.assertMsg (lib.hasInfix "\"$BIN_ZB\" upgrade" activationText) "onActivation.upgrade missing zb upgrade";
              assert lib.assertMsg (lib.hasInfix "/opt/zerobrew-custom" activationText && lib.hasInfix "Brewfile" activationText && lib.hasInfix "state" activationText) "per-prefix activation text missing prefix-specific Brewfile/state references";
              assert lib.assertMsg ((builtins.head evaluated.config.nix-zerobrew.prefixes."/opt/zerobrew-custom".brews).name == "hashicorp/homebrew-tap/terraform") "per-prefix attr brew did not evaluate";
              assert lib.assertMsg ((builtins.head evaluated.config.nix-zerobrew.prefixes."/opt/zerobrew-custom".casks).name == "docker") "per-prefix attr cask did not evaluate";
              assert lib.assertMsg (!(lib.hasInfix "bundle install" emptyActivationText)) "empty package lists emitted bundle install";
              assert lib.assertMsg (!(lib.hasInfix "install mas" emptyActivationText)) "empty package lists emitted mas install";
              assert lib.assertMsg (lib.hasInfix "db/nix-zerobrew" activationText && lib.hasInfix "state" activationText) "activation text missing nix-zerobrew state file";
              assert lib.assertMsg (lib.hasInfix "uninstall" activationText) "cleanup uninstall missing removed package reconcile logic";
              assert lib.assertMsg (!(lib.hasInfix "Removing declarative Zerobrew brew no longer configured" noCleanupActivationText)) "cleanup none emitted uninstall reconciliation";
              {
                extraLinkDirs = evaluated.config.nix-zerobrew.prefixes."/opt/zerobrew".extraLinkDirs;
                defaultTaps = builtins.attrNames evaluated.config.nix-zerobrew.prefixes."/opt/zerobrew".taps;
                customTaps = builtins.attrNames evaluated.config.nix-zerobrew.prefixes."/opt/zerobrew-custom".taps;
                immutable = evaluated.config.nix-zerobrew.mutableTaps;
                activationHasDeclarativePackageNotice = lib.hasInfix "Declarative package activation" activationText;
              }
          ' > module-eval.out
          grep -q custom module-eval.out
          grep -q homebrew-core module-eval.out
          grep -q homebrew-tap module-eval.out
          grep -q 'immutable = false' module-eval.out
          touch "$out"
        '';
      });

      darwinModules = rec {
        nix-zerobrew = { lib, pkgs, ... }: {
          imports = [ ./modules ];
          nix-zerobrew.package = lib.mkOptionDefault
            self.packages.${pkgs.stdenv.hostPlatform.system}.zerobrew;
          nix-zerobrew.packageRosetta =
            lib.mkOptionDefault self.packages.x86_64-darwin.zerobrew;
        };

        default = nix-zerobrew;
      };

      devShells = forAllSystems (system: pkgs: {
        default = pkgs.mkShell {
          buildInputs = with pkgs;
            [ rustc cargo openssl pkg-config ]
            ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
              pkgs.apple-sdk_15
              (pkgs.darwinMinVersionHook "10.15")
            ];
        };
      });
    };
}
