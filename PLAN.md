# nix-zerobrew Parity Plan with nix-homebrew

## Summary

This plan tracks feature-parity work focused on behavior and operations rather than Homebrew-specific semantics.

Parity target:

- Comparable install/activation lifecycle safety
- Comparable migration and ownership behavior
- Comparable shell and launcher ergonomics
- Optional Rosetta workflow on Apple Silicon

Non-goals:

- Homebrew tap semantics (`taps`, mutable/declarative tap models)
- Declarative management of all installed package formulas

## Current Status

- [x] Prefix lifecycle management is activation-driven and migration-safe.
- [x] Multi-prefix configuration model is implemented (`nix-zerobrew.prefixes`).
- [x] Unified architecture-aware launcher is implemented (`zb` in system profile).
- [x] Optional Rosetta prefix support is implemented (`enableRosetta`).
- [x] Shell integration toggles are implemented (bash/zsh/fish).
- [x] Flake smoke checks validate CLI execution (`checks.<system>.zerobrew-help`).
- [x] Docs updated for parity-oriented workflows.

## Public Interface Additions

### New options

- `nix-zerobrew.enableRosetta`
- `nix-zerobrew.packageRosetta`
- `nix-zerobrew.prefixes.<name>.enable`
- `nix-zerobrew.prefixes.<name>.prefix`
- `nix-zerobrew.prefixes.<name>.storeDir`
- `nix-zerobrew.prefixes.<name>.dbDir`
- `nix-zerobrew.prefixes.<name>.cacheDir`
- `nix-zerobrew.prefixes.<name>.locksDir`
- `nix-zerobrew.prefixes.<name>.linkDir`
- `nix-zerobrew.prefixes.<name>.package`

### Internal defaults

- `nix-zerobrew.defaultArm64Prefix = "/opt/zerobrew"`
- `nix-zerobrew.defaultIntelPrefix = "/usr/local/zerobrew"`

## Validation Matrix

### Green checks

- `nix flake check`
- `nix flake check --all-systems`
- `nix build .#zerobrew`
- `./result/bin/zb --help`
- nix-darwin module evaluation with `enableRosetta = true`

### Runtime scenarios to verify on real hosts

1. Fresh install on Apple Silicon (`enable = true`, default prefix)
2. Fresh install on Intel (`enable = true`, default prefix)
3. Existing unmanaged prefix with `autoMigrate = false` fails with actionable error
4. Existing unmanaged prefix with `autoMigrate = true` takes ownership without clobbering managed paths
5. `arch -x86_64 zb --help` on Apple Silicon with `enableRosetta = true`

## Assumptions and Defaults

- Behavioral parity is preferred over strict option-name parity.
- Rosetta remains optional and off by default.
- Zerobrew remains Darwin-only.
- Existing minimal configs remain valid (`enable`, `user`, optional `autoMigrate`).

## Follow-up Work (Nice to Have)

1. Add host-level integration tests for migration scenarios using darwin VM automation.
2. Add CI matrix that executes `checks` on both Darwin architectures.
3. Track upstream Zerobrew release updates with a documented bump workflow.
