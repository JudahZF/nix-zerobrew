# nix-zerobrew Compatibility Notes

## Summary

`nix-zerobrew` follows `nix-homebrew` operational patterns where they are tool-agnostic, while exposing only features that exist in Zerobrew.

## Compatibility Targets

- Comparable install/activation lifecycle safety
- Comparable migration and ownership behavior
- Comparable shell and launcher ergonomics
- Optional Rosetta workflow on Apple Silicon

## Explicit Non-Goals

- Homebrew tap semantics (`taps`, mutable/declarative tap models)
- Homebrew code patching (`patchBrew`)
- Declarative management of all installed package formulas

## Current Interface

### Top-level options

- `nix-zerobrew.enable`
- `nix-zerobrew.enableRosetta`
- `nix-zerobrew.package`
- `nix-zerobrew.packageRosetta`
- `nix-zerobrew.autoMigrate`
- `nix-zerobrew.user`
- `nix-zerobrew.group`
- `nix-zerobrew.prefixes`
- `nix-zerobrew.extraEnv`
- `nix-zerobrew.enableBashIntegration`
- `nix-zerobrew.enableZshIntegration`
- `nix-zerobrew.enableFishIntegration`

### Prefix options

- `nix-zerobrew.prefixes.<name>.enable`
- `nix-zerobrew.prefixes.<name>.prefix`
- `nix-zerobrew.prefixes.<name>.linkDir`
- `nix-zerobrew.prefixes.<name>.package`

### Internal defaults

- `nix-zerobrew.defaultArm64Prefix = "/opt/zerobrew"`
- `nix-zerobrew.defaultIntelPrefix = "/usr/local/zerobrew"`

## Validation Matrix

### Build and checks

- `nix flake check`
- `nix flake check --all-systems`
- `nix build .#zerobrew`
- `./result/bin/zb --help`

### Runtime scenarios

1. Fresh install on Apple Silicon (`enable = true`, default prefix)
2. Fresh install on Intel (`enable = true`, default prefix)
3. Existing unmanaged prefix with `autoMigrate = false` fails with actionable error
4. Existing unmanaged prefix with `autoMigrate = true` takes ownership safely
5. `arch -x86_64 zb --help` on Apple Silicon with `enableRosetta = true`

## Assumptions and Defaults

- Behavioral parity is preferred over strict option-name parity.
- Zerobrew-only feature truth is preferred over compatibility shims.
- Rosetta remains optional and off by default.
- Zerobrew remains Darwin-only.
