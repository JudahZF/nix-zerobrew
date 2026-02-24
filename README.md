# nix-zerobrew

Declarative [Zerobrew](https://github.com/lucasgelfond/zerobrew) management for macOS via [nix-darwin](https://github.com/LnL7/nix-darwin).

[Zerobrew](https://github.com/lucasgelfond/zerobrew) is a 5-20x faster experimental Homebrew alternative written in Rust. It brings uv-style architecture to Homebrew packages -- using content-addressable storage, APFS clonefiles, and Homebrew's existing formula ecosystem.

`nix-zerobrew` pins the Zerobrew binary through Nix and manages activation-time lifecycle concerns: directory setup, migration safeguards, ownership, launchers, Rosetta routing, and shell integration. It manages the package manager itself, not the packages you install with it.

## Highlights

- Declarative Zerobrew installation via nix-darwin
- Builds Zerobrew from source with a pinned Rust toolchain
- Prefix lifecycle management with migration safeguards
- Multi-prefix support with sensible defaults
- Optional Rosetta prefix for Intel binaries on Apple Silicon
- Architecture-aware `zb` launcher that dispatches to the correct prefix
- Shell integration for bash, zsh, and fish

## Installation

Add `nix-zerobrew` to your flake inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    nix-zerobrew.url = "github:JudahZF/nix-zerobrew";
    nix-zerobrew.inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Then import the module in your nix-darwin configuration:

```nix
{
  modules = [
    nix-zerobrew.darwinModules.default
  ];
}
```

## Quick Start

### New Installation

```nix
{
  nix-zerobrew = {
    enable = true;
    user = "yourusername";
  };
}
```

### Existing Zerobrew Installation

If you already have Zerobrew installed outside of Nix, set `autoMigrate` to allow nix-zerobrew to take ownership of the existing directories:

```nix
{
  nix-zerobrew = {
    enable = true;
    user = "yourusername";
    autoMigrate = true;
  };
}
```

Without `autoMigrate`, nix-zerobrew will error if it finds an existing installation that it doesn't manage (indicated by the absence of a `.managed_by_nix_darwin` marker file).

## Rosetta (Apple Silicon)

On Apple Silicon Macs, you can set up a second Intel-architecture prefix under Rosetta 2:

```nix
{
  nix-zerobrew = {
    enable = true;
    user = "yourusername";
    enableRosetta = true;
  };
}
```

This creates both an ARM64 prefix (`/opt/zerobrew`) and an Intel prefix (`/usr/local/zerobrew`). The unified `zb` launcher detects the current architecture at runtime, so `arch -x86_64 zb install ...` will target the Intel prefix automatically.

Rosetta 2 must be installed on the system. nix-zerobrew will print a warning during activation if it is not detected.

## Configuration Options

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | `bool` | `false` | Enable Zerobrew management |
| `enableRosetta` | `bool` | `false` | Set up Intel prefix for Rosetta on Apple Silicon |
| `package` | `package` | flake default | Native Zerobrew package |
| `packageRosetta` | `null or package` | x86_64 package | Zerobrew package for Intel launchers on Apple Silicon |
| `user` | `string` | required | Owner of managed directories |
| `group` | `string` | `"admin"` | Group owner of managed directories |
| `autoMigrate` | `bool` | `false` | Allow taking over existing non-managed installations |
| `extraEnv` | `attrsOf string` | `{}` | Additional environment variables injected into launchers |
| `prefixes` | `attrsOf submodule` | auto | Prefix configuration map (see below) |
| `enableBashIntegration` | `bool` | `true` | Add Zerobrew bin directory to PATH in bash |
| `enableZshIntegration` | `bool` | `true` | Add Zerobrew bin directory to PATH in zsh |
| `enableFishIntegration` | `bool` | `true` | Add Zerobrew bin directory to PATH in fish |

### Prefixes

Each prefix represents a Zerobrew installation root. nix-zerobrew creates the following layout under each prefix:

- `${prefix}/store` -- content-addressable package storage
- `${prefix}/db` -- package database
- `${prefix}/cache` -- download cache
- `${prefix}/locks` -- lock files
- `${prefix}/prefix/bin`, `${prefix}/prefix/Cellar`, `${prefix}/prefix/opt`, `${prefix}/prefix/lib`, `${prefix}/prefix/include`, `${prefix}/prefix/share`, `${prefix}/prefix/etc` -- user-facing link directory

This layout matches Zerobrew's internal structure and is not independently configurable.

#### `prefixes.<name>` options

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | `bool` | varies by architecture | Whether this prefix is active |
| `prefix` | `string` | attribute key | Zerobrew root directory |
| `linkDir` | `string` | `${prefix}/prefix` | User-facing link directory |
| `package` | `null or package` | `null` (falls back to `nix-zerobrew.package`) | Override the Zerobrew package for this prefix |

By default on Apple Silicon, the ARM64 prefix (`/opt/zerobrew`) is enabled and the Intel prefix (`/usr/local/zerobrew`) is disabled unless `enableRosetta` is set. On Intel Macs, only the Intel prefix is enabled.

### Advanced Prefix Example

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

After activation, the `zb` command is available system-wide:

```bash
zb --help                       # show help
zb install jq ripgrep           # install packages
zb uninstall jq                 # uninstall a package
zb bundle                       # install from Brewfile
zb bundle install -f myfile     # install from a custom file
zb bundle dump                  # export installed packages to Brewfile
zb bundle dump -f out --force   # dump to a custom file (overwrite)
zb gc                           # garbage collect unused store entries
zb reset                        # uninstall everything
zbx jq --version                # run a package without linking it
```

On Apple Silicon with Rosetta enabled, use `arch -x86_64 zb ...` to target the Intel prefix.

## Build and Verify

```bash
nix flake check --all-systems
nix build .#zerobrew
./result/bin/zb --help
```

## Comparison with nix-homebrew

`nix-zerobrew` follows the same lifecycle patterns as [nix-homebrew](https://github.com/zhaofengli/nix-homebrew) (prefix management, migration guards, Rosetta dual-prefix, shell integration) but targets Zerobrew instead of Homebrew. Homebrew-specific concepts like declarative taps, mutable taps, and brew patching have no Zerobrew equivalent and are intentionally absent.

Both modules can coexist in the same nix-darwin configuration. When both are enabled, nix-zerobrew ensures its prefixes are set up before Homebrew activation runs.

## License

MIT License for this repository.

Upstream Zerobrew is dual-licensed (MIT OR Apache-2.0).

## Acknowledgments

- [Zerobrew](https://github.com/lucasgelfond/zerobrew) by Lucas Gelfond
- [nix-homebrew](https://github.com/zhaofengli/nix-homebrew) for lifecycle and integration patterns
