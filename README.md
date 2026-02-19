# nix-zerobrew

`nix-zerobrew` manages [Zerobrew](https://github.com/lucasgelfond/zerobrew) installations on macOS with [nix-darwin](https://github.com/LnL7/nix-darwin).

It pins the Zerobrew binary through Nix and manages prefix lifecycle (creation, migration, permissions, launchers, and shell integration) in a way that is operationally similar to `nix-homebrew`.

Like `nix-homebrew`, this project manages the package manager itself, not the full set of installed packages.

## Highlights

- Declarative Zerobrew installation via nix-darwin
- Prefix lifecycle management with migration safeguards
- Multi-prefix support with sensible defaults
- Optional Rosetta prefix setup on Apple Silicon
- Unified `zb` launcher that picks the correct prefix by architecture
- Shell integration for bash, zsh, and fish

## Installation

Add `nix-zerobrew` to your flake inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    nix-zerobrew.url = "github:yourusername/nix-zerobrew";
    nix-zerobrew.inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

## Quick Start

### New Installation

```nix
{
  modules = [
    nix-zerobrew.darwinModules.default
    {
      nix-zerobrew = {
        enable = true;
        user = "yourusername";
      };
    }
  ];
}
```

### Existing Zerobrew Installation

```nix
{
  modules = [
    nix-zerobrew.darwinModules.default
    {
      nix-zerobrew = {
        enable = true;
        user = "yourusername";
        autoMigrate = true;
      };
    }
  ];
}
```

## Rosetta (Apple Silicon)

Enable an Intel prefix and architecture-aware launcher behavior:

```nix
{
  nix-zerobrew = {
    enable = true;
    user = "yourusername";
    enableRosetta = true;
  };
}
```

Then use `arch -x86_64 zb ...` when targeting Intel binaries.

## Configuration Options

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | `bool` | `false` | Enable Zerobrew management |
| `enableRosetta` | `bool` | `false` | Set up Intel prefix for Rosetta on Apple Silicon |
| `package` | `package` | flake default | Native Zerobrew package |
| `packageRosetta` | `null or package` | x86_64 package default | Zerobrew package for Intel launchers on Apple Silicon |
| `user` | `string` | required | Owner of managed directories |
| `group` | `string` | `"admin"` | Group owner of managed directories |
| `autoMigrate` | `bool` | `false` | Allow taking over existing installations |
| `extraEnv` | `attrsOf string` | `{}` | Additional environment variables for launchers |
| `prefixes` | `attrsOf submodule` | auto defaults | Prefix map (advanced) |
| `enableBashIntegration` | `bool` | `true` | PATH integration for bash |
| `enableZshIntegration` | `bool` | `true` | PATH integration for zsh |
| `enableFishIntegration` | `bool` | `true` | PATH integration for fish |

### `prefixes.<name>` options

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | `bool` | none | Whether this prefix is active |
| `prefix` | `string` | attribute key | Zerobrew root directory |
| `storeDir` | `string` | `${prefix}/store` | Content-addressable store |
| `dbDir` | `string` | `${prefix}/db` | Metadata DB directory |
| `cacheDir` | `string` | `${prefix}/cache` | Download cache directory |
| `locksDir` | `string` | `${prefix}/locks` | Lock directory |
| `linkDir` | `string` | `${prefix}/prefix` | Link prefix (`bin`, `Cellar`, `opt`, ...) |
| `package` | `null or package` | `null` | Override launcher package for this prefix |

## Advanced Prefix Example

```nix
{
  nix-zerobrew = {
    enable = true;
    user = "alice";

    prefixes = {
      "/opt/zerobrew" = {
        enable = true;
      };

      "/Volumes/FastSSD/zerobrew" = {
        enable = true;
        linkDir = "/Volumes/FastSSD/zerobrew/prefix";
      };
    };
  };
}
```

## Usage

After activation, use `zb`:

```bash
zb --help
zb install jq
zb search ripgrep
zb list
zb uninstall jq
```

## Parity Notes vs nix-homebrew

`nix-zerobrew` intentionally follows `nix-homebrew` operational patterns where they make sense:

- Prefix lifecycle handled in activation scripts
- Safe migration flow with explicit `autoMigrate`
- Optional Rosetta workflow on Apple Silicon
- Architecture-aware unified launcher in system profile
- Shell integration toggles

Homebrew-specific concepts (for example tap management) are not implemented because Zerobrew does not use a tap model.

## Build and Verify

```bash
nix flake check --all-systems
nix build .#zerobrew
./result/bin/zb --help
```

## License

MIT License for this repository.

Upstream Zerobrew is dual-licensed (MIT OR Apache-2.0).

## Acknowledgments

- [Zerobrew](https://github.com/lucasgelfond/zerobrew) by Lucas Gelfond
- [nix-homebrew](https://github.com/zhaofengli/nix-homebrew) for lifecycle and integration patterns
