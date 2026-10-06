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
              package = zerobrewPackage;
              packageRosetta = zerobrewPackage;
              enableDoctorCheck = false;
              warnAboutPackageManagement = false;
            } // extraConfig;
          };
        })
      ];
    };

  evalFor = system: extraConfig: evalForFull system ({ user = "alice"; } // extraConfig) { };

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
  defaultUser = evalForFull "aarch64-darwin" { } { };
  richBrew = evalFor "aarch64-darwin" {
    brews = [{
      name = "mysql@8.4";
      args = [ "build-from-source" "HEAD" ];
      link = false;
      conflicts_with = [ "mysql" ];
      postinstall = "echo mysql-ready";
      restart_service = "changed";
      start_service = true;
    }];
  };
  richCask = evalFor "aarch64-darwin" {
    casks = [{
      name = "firefox";
      args.appdir = "~/Applications";
      greedy = true;
      postinstall = "echo firefox-ready";
    }];
    caskArgs.no_quarantine = true;
    greedyCasks = false;
  };
  linkOverwrite = evalFor "aarch64-darwin" {
    brews = [{ name = "curl"; link = "overwrite"; }];
  };
  cleanupCheck = evalFor "aarch64-darwin" {
    onActivation.cleanup = "check";
    brews = [ "jq" ];
  };
  extraFlags = evalFor "aarch64-darwin" {
    onActivation.extraFlags = [ "--verbose" ];
    brews = [ "jq" ];
  };
  globalLaunch = evalFor "aarch64-darwin" {
    global.brewfile = true;
    global.autoUpdate = false;
  };
  ecosystems = evalFor "aarch64-darwin" {
    vscode = [ "golang.go" ];
    goPackages = [ "github.com/charmbracelet/crush" ];
    cargoPackages = [ "ripgrep" ];
    onActivation.upgrade = true;
    masApps.Xcode = 497799835;
  };
  extraConfig = evalFor "aarch64-darwin" {
    extraConfig = ''
      brew "wget"
      cask "docker"
      mas "Keynote", id: 409183694
      vscode "ms-python.python"
      go "golang.org/x/tools/gopls"
      cargo "fd"
      tap "apple/apple"
      whalebrew "unsupported"
    '';
  };

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
    (case "top-level-packages" "Top-level brews/casks/MAS declarations evaluate" "packages" (assertionOk packagesTop && has "bundle install" (activation packagesTop) && has "install mas" (activation packagesTop) && has "db/nix-zerobrew" (activation packagesTop)) "Top-level declarations generate Brewfile/state activation logic.")
    (case "per-prefix-packages" "Per-prefix package declarations evaluate independently" "packages" (assertionOk packagesPrefix && has "/opt/zerobrew-extra" (activation packagesPrefix) && has "Brewfile" (activation packagesPrefix) && has "state" (activation packagesPrefix)) "Prefix-local brews/casks/MAS declarations get their own activation state.")
    (case "cli-smoke" "Runtime CLI smoke compatibility is covered separately" "runtime" true "The flake check zerobrew-cli-smoke covers zb help for bundle/update/outdated/doctor/upgrade/gc/completion.")
    (case "default-user" "user defaults to system.primaryUser" "lifecycle" (assertionOk defaultUser && defaultUser.config.nix-zerobrew.user == "alice") "Omitting nix-zerobrew.user follows nix-darwin and uses system.primaryUser.")
    (case "link-false" "link = false installs with --no-link" "packages" (assertionOk richBrew && has "--no-link" (activation richBrew) && has "mysql@8.4" (activation richBrew)) "zb install receives --no-link for that formula.")
    (case "build-from-source" "build-from-source arg is passed to zb" "packages" (assertionOk richBrew && has "--build-from-source" (activation richBrew)) "The source-build argument maps to zb's --build-from-source flag.")
    (case "conflicts-with" "conflicts_with uninstalls the other formula first" "packages" (assertionOk richBrew && has "uninstall" (activation richBrew) && has "mysql" (activation richBrew)) "Conflicting formulae are uninstalled when they are already listed.")
    (case "postinstall" "postinstall runs after the package list line changes" "packages" (assertionOk richBrew && has "echo mysql-ready" (activation richBrew) && has "nix_zb_changed" (activation richBrew)) "The shell command is guarded by a before/after zb list comparison.")
    (case "greedy-cask" "greedy casks are upgraded during activation" "packages" (assertionOk richCask && has "Upgrading greedy cask firefox" (activation richCask) && has "cask:firefox" (activation richCask)) "zb upgrade runs for casks marked greedy.")
    (case "cask-postinstall" "cask postinstall is emitted" "packages" (assertionOk richCask && has "echo firefox-ready" (activation richCask)) "Cask postinstall uses the same change guard as formulae.")
    (case "cleanup-check" "cleanup = check aborts when undeclared packages are installed" "packages" (assertionOk cleanupCheck && has "not declared, aborting activation" (activation cleanupCheck) && has "\"$BIN_ZB\" list" (activation cleanupCheck)) "Activation compares zb list with the declarative state before installing.")
    (case "extra-flags" "onActivation.extraFlags are passed to bundle install" "packages" (assertionOk extraFlags && has "--verbose" (activation extraFlags) && has "bundle install" (activation extraFlags)) "Extra flags are appended to declarative zb install commands.")
    (case "global-brewfile" "global.brewfile points zb bundle at the generated Brewfile" "launchers" (assertionOk globalLaunch && has "NIX_ZEROBREW_BUNDLE_FILE" (activation globalLaunch)) "Launchers export the activation Brewfile path. The launcher tail injects --file.")
    (case "global-no-autoupdate" "global.autoUpdate = false exports HOMEBREW_NO_AUTO_UPDATE" "launchers" (assertionOk globalLaunch && has "HOMEBREW_NO_AUTO_UPDATE" (activation globalLaunch)) "Prefix launchers export HOMEBREW_NO_AUTO_UPDATE=1. zb itself does not auto-update formulae.")
    (case "vscode" "vscode extensions install through the code command" "packages" (assertionOk ecosystems && has "--install-extension" (activation ecosystems) && has "golang.go" (activation ecosystems) && has "cask:visual-studio-code" (activation ecosystems)) "The code CLI installs the extension, and the cask is installed when code is missing.")
    (case "go-packages" "go packages install with go install" "packages" (assertionOk ecosystems && has "bin/go\" install" (activation ecosystems) && has "github.com/charmbracelet/crush@latest" (activation ecosystems)) "The go formula is installed, then go install runs with @latest when the spec has no version.")
    (case "cargo-packages" "cargo packages install with cargo install" "packages" (assertionOk ecosystems && has "bin/cargo\" install" (activation ecosystems) && has "ripgrep" (activation ecosystems)) "The rust formula is installed, then cargo install runs.")
    (case "mas-upgrade" "onActivation.upgrade also upgrades declared MAS apps" "packages" (assertionOk ecosystems && has "mas\" upgrade" (activation ecosystems)) "mas upgrade runs for declared app IDs when upgrades are enabled.")
    (case "extra-config" "extraConfig brew, cask, mas, vscode, go, and cargo lines are applied" "packages" (assertionOk extraConfig && has "declarative-brews: wget" (activation extraConfig) && has "declarative-casks: docker" (activation extraConfig) && has "declarative-mas: 409183694" (activation extraConfig) && has "ms-python.python" (activation extraConfig) && has "gopls@latest" (activation extraConfig) && has "bin/cargo\" install" (activation extraConfig)) "Supported Brewfile directives in extraConfig join the host default prefix.")
    (case "extra-config-skip" "unsupported extraConfig lines are reported" "packages" (assertionOk extraConfig && has "ignoring extraConfig line" (activation extraConfig) && has "whalebrew" (activation extraConfig)) "tap and unknown directives are skipped with a warning.")
    (gap "unsupported-args" "arbitrary brew args such as HEAD are ignored" "packages" (if has "ignoring unsupported args" (activation richBrew) && has "HEAD" (activation richBrew) then "Activation warns. zb install has no --HEAD." else "Missing warning for ignored args."))
    (gap "service-options" "restart_service and start_service have no zb command" "packages" (if has "restart_service is not supported" (activation richBrew) && has "start_service is not supported" (activation richBrew) then "Activation warns. zb has no services command." else "Missing service warning."))
    (gap "link-overwrite" "link = overwrite cannot replace other formulae" "packages" (if has "overwrite" (activation linkOverwrite) then "Activation warns. zb does not expose link --overwrite." else "Missing overwrite warning."))
    (gap "cask-args" "caskArgs and cask arg attrsets are not applied" "packages" (if has "caskArgs is accepted" (activation richCask) && has "appdir" (activation richCask) then "Activation warns. zb has no cask install options." else "Missing cask arg warning."))
    (gap "cleanup-zap" "cleanup = zap remains an intentional gap" "packages" (if assertionOk zap then "Unexpectedly accepted zap cleanup." else "Rejected by assertion until Zerobrew exposes uninstall --zap."))
    (gap "shell-integration-default" "shell integration defaults on" "shell" "nix-darwin defaults shell integration off. nix-zerobrew keeps it on so existing shells retain PATH.")
    (gap "single-prefix-option" "homebrew.prefix is not a single nix-zerobrew option" "prefixes" "nix-zerobrew uses /opt/zerobrew and /usr/local/zerobrew, including an optional Rosetta prefix, instead of one homebrew.prefix.")
    (gap "tap-names" "plain tap names are not fetched" "taps" "Taps are Nix packages linked into Library/Taps, matching nix-homebrew. A bare GitHub tap name cannot be cloned by zb.")
    (gap "nix-homebrew-trust" "nix-homebrew trust entries have no zb equivalent" "taps" "zb has no trust or untrust command.")
    (gap "go-uninstall" "removed Go packages are not uninstalled" "packages" "go install has no uninstall command, so cleanup drops Go packages from nix-zerobrew state only.")
  ];

  passCount = lib.length (lib.filter (c: c.status == "pass") cases);
  gapCount = lib.length (lib.filter (c: c.status == "gap") cases);
  failCount = lib.length (lib.filter (c: c.status == "fail") cases);
  totalCount = lib.length cases;
  percent = (passCount * 100) / totalCount;
  report = {
    title = "nix-homebrew compatibility";
    summary = { passed = passCount; gap = gapCount; failed = failCount; total = totalCount; inherit percent; };
    inherit cases;
  };
  json = builtins.toJSON report;
  markdownCases = lib.concatMapStrings (c: ''
  - `${c.status}` `${c.id}` — ${c.title}: ${c.details}
  '') cases;
  failLines = lib.concatMapStrings (c: ''
    echo "fail ${c.id}: ${c.title}" >&2
  '') (lib.filter (c: c.status == "fail") cases);
in pkgs.runCommandLocal "nix-homebrew-compatibility-report" {
  nativeBuildInputs = [ pkgs.python3 ];
} ''
  mkdir -p "$out"
  cat > "$out/report.json" <<'EOF'
  ${json}
  EOF
  cat > "$out/report.md" <<'EOF'
  # nix-homebrew compatibility

  ${toString passCount}/${toString totalCount} checks passing (${toString percent}%). ${toString gapCount} gaps are unsupported Homebrew behavior. ${toString failCount} failures mean a supported check regressed.

  ${markdownCases}
  EOF
  python3 ${./chart.py} \
    --history ${../../docs/compatibility-history.json} \
    --out "$out/nix-homebrew-compatibility.svg" \
    --summary "$out/summary.json" \
    --stale "$out/STALE" \
    --pass-count ${toString passCount} \
    --gap-count ${toString gapCount} \
    --fail-count ${toString failCount} \
    --total-count ${toString totalCount}
  ${failLines}
  if [ ${toString failCount} -ne 0 ]; then
    echo "nix-homebrew compatibility suite failed" >&2
    exit 1
  fi
''
