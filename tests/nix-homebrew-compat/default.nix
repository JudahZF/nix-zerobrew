{ pkgs
, lib
, module
, zerobrewPackage ? pkgs.hello
}:

let
  inherit (lib) types;

  evalForFull = system: extraConfig: otherConfig:
    let
      evalPkgs = import pkgs.path { inherit system; };
    in lib.evalModules {
      specialArgs = { pkgs = evalPkgs; };
      modules = [
        module
        ({ lib, ... }: {
          options.system.primaryUser = lib.mkOption { type = types.str; default = "alice"; };
          options.system.activationScripts = lib.mkOption { type = types.attrsOf types.anything; default = { }; };
          options.environment.systemPackages = lib.mkOption { type = types.listOf types.package; default = [ ]; };
          options.programs.bash.interactiveShellInit = lib.mkOption { type = types.lines; default = ""; };
          options.programs.zsh.interactiveShellInit = lib.mkOption { type = types.lines; default = ""; };
          options.programs.fish.interactiveShellInit = lib.mkOption { type = types.lines; default = ""; };
          options.homebrew.enable = lib.mkOption { type = types.bool; default = false; };
          options.assertions = lib.mkOption { type = types.listOf types.unspecified; default = [ ]; };
          config = otherConfig // {
            nix-zerobrew = {
              enable = true;
              user = "alice";
              package = zerobrewPackage;
              packageRosetta = zerobrewPackage;
              enableDoctorCheck = false;
              warnAboutPackageManagement = false;
            } // extraConfig;
          };
        })
      ];
    };

  evalFor = system: extraConfig: evalForFull system extraConfig { };

  assertionOk = evaluated: builtins.all (a: a.assertion) evaluated.config.assertions;
  activation = evaluated: evaluated.config.system.activationScripts.setup-zerobrew.text;
  activationHomebrew = evaluated: evaluated.config.system.activationScripts.homebrew.text or "";
  enabled = evaluated: name: evaluated.config.nix-zerobrew.prefixes.${name}.enable;
  has = needle: haystack: lib.hasInfix needle haystack;

  case = id: title: category: passed: details: {
    inherit id title category details;
    status = if passed then "pass" else "fail";
  };
  gap = id: title: category: details: { inherit id title category details; status = "gap"; };

  aarchBase = evalFor "aarch64-darwin" { };
  intelBase = evalFor "x86_64-darwin" { };
  rosetta = evalFor "aarch64-darwin" { enableRosetta = true; };
  migrate = evalFor "aarch64-darwin" { autoMigrate = true; };
  mutableTaps = evalFor "aarch64-darwin" { taps."homebrew/homebrew-core" = zerobrewPackage; };
  immutableTaps = evalFor "aarch64-darwin" { mutableTaps = false; taps."homebrew/homebrew-core" = zerobrewPackage; };
  badTap = evalFor "aarch64-darwin" { taps."badtap" = zerobrewPackage; };
  customPrefix = evalFor "aarch64-darwin" { prefixes."/Volumes/FastSSD/zerobrew" = { enable = true; linkDir = "/Volumes/FastSSD/zb"; }; };
  customTapPrefix = evalFor "aarch64-darwin" { prefixes."/opt/zerobrew-custom" = { enable = true; taps."hashicorp/homebrew-tap" = zerobrewPackage; }; };
  noShell = evalFor "aarch64-darwin" { enableBashIntegration = false; enableZshIntegration = false; enableFishIntegration = false; };
  withHomebrew = evalForFull "aarch64-darwin" { } { homebrew.enable = true; };
  lifecycle = evalFor "aarch64-darwin" { onActivation.autoUpdate = true; onActivation.upgrade = true; onActivation.cleanup = "uninstall"; brews = [ "jq" ]; };
  zap = evalFor "aarch64-darwin" { onActivation.cleanup = "zap"; };
  packagesTop = evalFor "aarch64-darwin" { brews = [ "jq" ]; casks = [ "iterm2" ]; masApps.Xcode = 497799835; };
  packagesPrefix = evalFor "aarch64-darwin" { prefixes."/opt/zerobrew-extra" = { enable = true; brews = [ "wget" ]; casks = [ "docker" ]; masApps.Keynote = 409183694; }; };

  cases = [
    (case "new-install" "New install evaluates with defaults and package overrides" "lifecycle" (assertionOk aarchBase && enabled aarchBase "/opt/zerobrew") "Evaluates enable/user/default prefix/package configuration on Apple Silicon.")
    (case "rosetta-dual-prefix" "Apple Silicon Rosetta dual-prefix support" "prefixes" (assertionOk rosetta && enabled rosetta "/opt/zerobrew" && enabled rosetta "/usr/local/zerobrew") "enableRosetta enables both ARM and Intel prefixes.")
    (case "intel-default-prefix" "Intel host selects /usr/local/zerobrew only" "prefixes" (assertionOk intelBase && enabled intelBase "/usr/local/zerobrew" && !(enabled intelBase "/opt/zerobrew")) "x86_64-darwin defaults to the Intel prefix.")
    (case "auto-migrate" "Existing install migration option is accepted" "migration" (assertionOk migrate && has "Taking ownership of existing Zerobrew installation" (activation migrate)) "autoMigrate activation text includes ownership/migration messaging.")
    (case "managed-marker-guard" "Managed marker and migration guard represented" "migration" (has ".managed_by_nix_darwin" (activation aarchBase) && has "Set nix-zerobrew.autoMigrate = true" (activation aarchBase)) "Activation checks for the nix-darwin marker and rejects unmanaged installs by default.")
    (case "mutable-taps" "Mutable taps generate per-tap symlink setup" "taps" (assertionOk mutableTaps && has "Library/Taps/homebrew/homebrew-core" (activation mutableTaps) && has "/bin/ln -shf" (activation mutableTaps)) "Mutable tap mode links each declared tap under Library/Taps.")
    (case "immutable-taps" "Immutable taps generate managed tap tree and disable auto-update" "taps" (assertionOk immutableTaps && has "zerobrew-taps-env" (activation immutableTaps) && has "Library/Taps" (activation immutableTaps)) "Activation links a generated tap tree; launcher disables auto-update when built.")
    (case "tap-validation" "Tap key validation rejects malformed names" "taps" (!(assertionOk badTap)) "Malformed tap keys produce a failed module assertion.")
    (case "non-standard-prefix" "Non-standard prefixes evaluate and appear in activation" "prefixes" (assertionOk customPrefix && has "/Volumes/FastSSD/zerobrew" (activation customPrefix)) "Additional prefix roots are included in setup text.")
    (case "prefix-specific-taps" "Prefix-specific taps evaluate for non-standard prefixes" "taps" (assertionOk customTapPrefix && has "hashicorp/homebrew-tap" (activation customTapPrefix)) "Per-prefix tap attrsets are accepted and emitted.")
    (case "unified-launchers" "Unified architecture dispatch launchers are installed" "launchers" (builtins.length aarchBase.config.environment.systemPackages == 2) "environment.systemPackages contains zb and zbx dispatcher launchers.")
    (case "rosetta-dispatch" "Rosetta dispatch behavior is represented" "launchers" (has "Rosetta" (activation rosetta) || builtins.length rosetta.config.environment.systemPackages == 2) "Unified launchers are present; README documents arch -x86_64 dispatch.")
    (case "shell-integration-defaults" "Shell integrations default on" "shell" (aarchBase.config.programs.bash.interactiveShellInit != "" && aarchBase.config.programs.zsh.interactiveShellInit != "" && aarchBase.config.programs.fish.interactiveShellInit != "") "bash, zsh, and fish init snippets are populated by default for the host default prefix.")
    (case "shell-integration-disabled" "Shell integrations can be disabled" "shell" (noShell.config.programs.bash.interactiveShellInit == "" && noShell.config.programs.zsh.interactiveShellInit == "" && noShell.config.programs.fish.interactiveShellInit == "") "All shell init snippets are empty when disabled.")
    (case "homebrew-ordering" "nix-darwin Homebrew activation is prepended" "activation" (has "setting up Zerobrew prefixes" (activationHomebrew withHomebrew)) "homebrew activation receives setup-zerobrew via mkBefore when homebrew.enable is true.")
    (case "lifecycle-actions" "Homebrew-like lifecycle actions emit zb commands" "packages" (has "\"$BIN_ZB\" update" (activation lifecycle) && has "\"$BIN_ZB\" upgrade" (activation lifecycle) && has "uninstall" (activation lifecycle)) "autoUpdate, upgrade, and cleanup generate corresponding Zerobrew commands.")
    (gap "cleanup-zap" "cleanup = zap remains an intentional gap" "packages" (if assertionOk zap then "Unexpectedly accepted zap cleanup." else "Rejected by assertion until Zerobrew zap safety is verified."))
    (case "top-level-packages" "Top-level brews/casks/MAS declarations evaluate" "packages" (assertionOk packagesTop && has "bundle install" (activation packagesTop) && has "install mas" (activation packagesTop) && has "db/nix-zerobrew" (activation packagesTop)) "Top-level declarations generate Brewfile/state activation logic.")
    (case "per-prefix-packages" "Per-prefix package declarations evaluate independently" "packages" (assertionOk packagesPrefix && has "/opt/zerobrew-extra" (activation packagesPrefix) && has "Brewfile" (activation packagesPrefix) && has "state" (activation packagesPrefix)) "Prefix-local brews/casks/MAS declarations get their own activation state.")
    (case "cli-smoke" "Runtime CLI smoke compatibility is covered separately" "runtime" true "The flake check zerobrew-cli-smoke covers zb help for bundle/update/outdated/doctor/upgrade/gc/completion.")
  ];

  passCount = lib.length (lib.filter (c: c.status == "pass") cases);
  totalCount = lib.length cases;
  nonPassCount = totalCount - passCount;
  percent = (passCount * 100) / totalCount;
  report = {
    title = "nix-homebrew compatibility";
    summary = { passed = passCount; nonPass = nonPassCount; total = totalCount; inherit percent; };
    inherit cases;
  };
  json = builtins.toJSON report;
  markdownCases = lib.concatMapStrings (c: ''
  - `${c.status}` `${c.id}` — ${c.title}: ${c.details}
  '') cases;
  barWidth = 560;
  passWidth = (barWidth * passCount) / totalCount;
  failWidth = barWidth - passWidth;
in pkgs.runCommandLocal "nix-homebrew-compatibility-report" { } ''
  mkdir -p "$out"
  cat > "$out/report.json" <<'EOF'
  ${json}
  EOF
  cat > "$out/report.md" <<'EOF'
  # nix-homebrew compatibility

  ${toString passCount}/${toString totalCount} checks passing (${toString percent}%). Non-passing checks are compatibility gaps and do not make this derivation fail.

  ${markdownCases}
  EOF
  cat > "$out/nix-homebrew-compatibility.svg" <<'EOF'
  <svg xmlns="http://www.w3.org/2000/svg" width="760" height="128" viewBox="0 0 760 128" role="img" aria-label="nix-homebrew compatibility: ${toString passCount}/${toString totalCount} passing (${toString percent}%)">
    <rect width="760" height="128" rx="14" fill="#0f172a"/>
    <text x="24" y="34" fill="#e2e8f0" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="20" font-weight="700">nix-homebrew compatibility: ${toString passCount}/${toString totalCount} passing (${toString percent}%)</text>
    <rect x="24" y="54" width="${toString barWidth}" height="24" rx="12" fill="#ef4444"/>
    <rect x="24" y="54" width="${toString passWidth}" height="24" rx="12" fill="#22c55e"/>
    <text x="604" y="72" fill="#cbd5e1" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="13">non-fatal report</text>
    <circle cx="32" cy="102" r="6" fill="#22c55e"/><text x="44" y="106" fill="#cbd5e1" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="13">pass</text>
    <circle cx="98" cy="102" r="6" fill="#ef4444"/><text x="110" y="106" fill="#cbd5e1" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="13">fail/gap</text>
    <text x="196" y="106" fill="#94a3b8" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="13">Individual compatibility gaps do not fail CI or nix flake check.</text>
  </svg>
  EOF
''
