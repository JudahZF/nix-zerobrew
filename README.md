# nix-zerobrew

`nix-zerobrew` manages [Zerobrew](https://github.com/lucasgelfond/zerobrew) on macOS with [nix-darwin](https://github.com/LnL7/nix-darwin).

It pins the Zerobrew binary through Nix and manages activation-time lifecycle concerns (directory setup, migration safeguards, ownership, launchers, Rosetta routing, and shell integration).

Like `nix-homebrew`, this project manages the package manager itself, not the full set of installed packages.

## Design Rule

Only Zerobrew-supported capabilities are exposed as config options.

Homebrew-only concepts are intentionally not implemented and do not exist as `nix-zerobrew` options.

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
| `linkDir` | `string` | `${prefix}/prefix` | Link prefix (`bin`, `Cellar`, `opt`, ...) |
| `package` | `null or package` | `null` | Override launcher package for this prefix |

`nix-zerobrew` always uses Zerobrew's standard root layout under each configured `prefix`:
- `${prefix}/store`
- `${prefix}/db`
- `${prefix}/cache`
- `${prefix}/locks`

These are intentionally not configurable because Zerobrew does not expose separate config for them.

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
zb install jq ripgrep
zb list
zb info jq
zb uninstall jq
zb gc
zb bundle --help
zb migrate --help
```

## Compatibility with nix-homebrew

| Area | `nix-homebrew` | `nix-zerobrew` |
|---|---|---|
| Prefix lifecycle | Activation-managed | Activation-managed |
| Migration guard (`autoMigrate`) | Yes | Yes |
| Rosetta dual-prefix flow | Yes | Yes |
| Unified launcher in system profile | `brew` | `zb` |
| Shell integration toggles | Yes | Yes |
| Declarative taps (`taps`) | Yes | Not supported by Zerobrew |
| Mutable taps (`mutableTaps`) | Yes | Not supported by Zerobrew |
| Homebrew patching (`patchBrew`) | Yes | Not applicable to Zerobrew |

Unsupported Homebrew-only concepts are intentionally absent as `nix-zerobrew` options.

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
