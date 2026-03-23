# Zerobrew installation manager
#
# This module manages one or more Zerobrew prefixes on macOS via nix-darwin.
# It mirrors nix-homebrew's lifecycle guarantees while staying Zerobrew-native.

{ pkgs, lib, config, options, ... }:
let
  inherit (lib) types;

  # Marker file to indicate this installation is managed by nix-darwin.
  nixMarker = ".managed_by_nix_darwin";

  cfg = config.nix-zerobrew;

  prefixType = types.submodule ({ name, config, ... }: {
    options = {
      enable = lib.mkOption {
        description = ''
          Whether to set up this Zerobrew prefix.
        '';
        type = types.bool;
      };

      prefix = lib.mkOption {
        description = ''
          Root directory for this Zerobrew installation.
        '';
        type = types.str;
        default = name;
      };

      linkDir = lib.mkOption {
        description = ''
          User-facing install prefix used for links (`bin`, `Cellar`, `opt`, etc).
        '';
        type = types.str;
        default = config.prefix;
      };

      package = lib.mkOption {
        description = ''
          Zerobrew package used by this prefix launcher.
        '';
        type = types.nullOr types.package;
        default = null;
      };
    };
  });

  armPrefix = lib.attrByPath [ cfg.defaultArm64Prefix ] null cfg.prefixes;
  intelPrefix = lib.attrByPath [ cfg.defaultIntelPrefix ] null cfg.prefixes;

  hostDefaultPrefixKey =
    if pkgs.stdenv.hostPlatform.isAarch64
    then cfg.defaultArm64Prefix
    else cfg.defaultIntelPrefix;
  hostDefaultPrefix = lib.attrByPath [ hostDefaultPrefixKey ] null cfg.prefixes;

  makePrefixLauncher = binary: prefix:
    let
      selectedPackage = if prefix.package != null then prefix.package else cfg.package;
    in
    pkgs.writeScriptBin binary (
      ''
        #!/bin/bash
        set -euo pipefail
        export ZEROBREW_ROOT="${prefix.prefix}"
        export ZEROBREW_PREFIX="${prefix.linkDir}"
        export NIX_ZEROBREW_BIN="${selectedPackage}/bin/${binary}"
        export PATH="${prefix.linkDir}/bin:$PATH"
      ''
      + (lib.optionalString
        (cfg.extraEnv != {})
        (lib.concatLines (
          lib.mapAttrsToList
            (name: value: "export ${name}=${lib.escapeShellArg value}")
            cfg.extraEnv
        )))
      + (builtins.readFile ./zb.tail.sh)
    );

  prefixLaunchers = lib.mapAttrs (_: prefix: {
    zb = makePrefixLauncher "zb" prefix;
    zbx = makePrefixLauncher "zbx" prefix;
  }) cfg.prefixes;
  enabledPrefixNames =
    lib.filter
      (name: cfg.prefixes.${name}.enable)
      (builtins.attrNames cfg.prefixes);

  setupPrefix = name:
    let
      prefix = cfg.prefixes.${name};
      launchers = prefixLaunchers.${name};
    in
    ''
      ZEROBREW_ROOT="${prefix.prefix}"
      ZEROBREW_LINK_DIR="${prefix.linkDir}"
      NIX_ZEROBREW_MARKER="$ZEROBREW_ROOT/${nixMarker}"

      >&2 echo "setting up Zerobrew ($ZEROBREW_ROOT)..."

      if [[ -e "$ZEROBREW_ROOT" ]] && [[ ! -e "$NIX_ZEROBREW_MARKER" ]]; then
        if [[ -z "${toString cfg.autoMigrate}" ]]; then
          warn "An existing Zerobrew installation exists at $ZEROBREW_ROOT"
          ohai "Set nix-zerobrew.autoMigrate = true; to allow nix-zerobrew to migrate the installation"
          ohai "During auto-migration, nix-zerobrew will take ownership of the existing installation"
          exit 1
        fi

        ohai "Taking ownership of existing Zerobrew installation at $ZEROBREW_ROOT..."
      fi

      maybe_migrate_legacy_link_dir
      initialize_zerobrew_layout

      ${lib.optionalString (lib.stringLength prefix.linkDir > 13) ''
        warn "The Zerobrew link directory $ZEROBREW_LINK_DIR exceeds the macOS Mach-O path limit (13 characters)."
        ohai "Path-sensitive packages such as git and curl may fail to install under this prefix."
      ''}

      BIN_ZB="$ZEROBREW_LINK_DIR/bin/zb"
      BIN_ZBX="$ZEROBREW_LINK_DIR/bin/zbx"
      if is_occupied "$BIN_ZB"; then
        error "An existing $BIN_ZB is in the way"
        exit 1
      fi
      if is_occupied "$BIN_ZBX"; then
        error "An existing $BIN_ZBX is in the way"
        exit 1
      fi
      /bin/ln -shf "${launchers.zb}/bin/zb" "$BIN_ZB"
      /bin/ln -shf "${launchers.zbx}/bin/zbx" "$BIN_ZBX"
    '';

  makeArchDispatcher = binary: pkgs.writeScriptBin binary (
    ''
      #!/bin/bash
      set -euo pipefail
      cur_arch=$(/usr/bin/uname -m)
    ''
    + lib.optionalString (armPrefix != null && armPrefix.enable) ''
      if [[ "$cur_arch" == "arm64" || "$cur_arch" == "aarch64" ]]; then
        exec "${armPrefix.linkDir}/bin/${binary}" "$@"
      fi
    ''
    + lib.optionalString (intelPrefix != null && intelPrefix.enable) ''
      if [[ "$cur_arch" == "x86_64" || "$cur_arch" == "i386" ]]; then
        exec "${intelPrefix.linkDir}/bin/${binary}" "$@"
      fi
    ''
    + ''
      >&2 echo "nix-zerobrew: no Zerobrew installation available for $cur_arch"
      exit 1
    ''
  );

  # Unified launcher scripts. Use `arch -x86_64 zb` or `arch -x86_64 zbx` to target Intel when enabled.
  zbLauncher = makeArchDispatcher "zb";
  zbxLauncher = makeArchDispatcher "zbx";

  setupZerobrew = pkgs.writeShellScript "setup-zerobrew" ''
    set -euo pipefail
    source ${./utils.sh}

    NIX_ZEROBREW_UID=$(id -u "${cfg.user}" || (error "Failed to get UID of ${cfg.user}"; exit 1))
    NIX_ZEROBREW_GID=$(dscl . -read "/Groups/${cfg.group}" | awk '($1 == "PrimaryGroupID:") { print $2 }' || (error "Failed to get GID of ${cfg.group}"; exit 1))

    is_in_nix_store() {
      [[ "$1" != "${builtins.storeDir}"* ]] || return 0

      if [[ -e "$1" ]]
      then
        path="$(readlink -f "$1")"
      else
        path="$1"
      fi

      if [[ "$path" == "${builtins.storeDir}"* ]]
      then
        return 0
      else
        return 1
      fi
    }

    is_occupied() {
      [[ -e "$1" ]] && ([[ ! -L "$1" ]] || ! is_in_nix_store "$1")
    }

    ${lib.concatMapStrings setupPrefix enabledPrefixNames}

    if [[ -n "${toString cfg.enableRosetta}" ]] && ! pgrep -q oahd; then
      warn "The Intel Zerobrew prefix has been set up, but Rosetta isn't installed yet."
      ohai "Run softwareupdate --install-rosetta to install it."
    fi
  '';

  posixShellIntegration = prefix: ''
    export ZEROBREW_ROOT="${prefix.prefix}"
    export ZEROBREW_PREFIX="${prefix.linkDir}"

    _nix_zb_prepend_path() {
      local argpath="$1"
      case ":''${PATH:-}:" in
        *:"$argpath":*) ;;
        *) export PATH="''${argpath}''${PATH:+:''${PATH}}" ;;
      esac
    }

    _nix_zb_prepend_pkg_config_path() {
      local argpath="$1"
      case ":''${PKG_CONFIG_PATH:-}:" in
        *:"$argpath":*) ;;
        *) export PKG_CONFIG_PATH="''${argpath}''${PKG_CONFIG_PATH:+:''${PKG_CONFIG_PATH}}" ;;
      esac
    }

    _nix_zb_prepend_pkg_config_path "$ZEROBREW_PREFIX/lib/pkgconfig"

    if [ -z "''${CURL_CA_BUNDLE:-}" ] || [ -z "''${SSL_CERT_FILE:-}" ]; then
      if [ -f "$ZEROBREW_PREFIX/opt/ca-certificates/share/ca-certificates/cacert.pem" ]; then
        [ -z "''${CURL_CA_BUNDLE:-}" ] && export CURL_CA_BUNDLE="$ZEROBREW_PREFIX/opt/ca-certificates/share/ca-certificates/cacert.pem"
        [ -z "''${SSL_CERT_FILE:-}" ] && export SSL_CERT_FILE="$ZEROBREW_PREFIX/opt/ca-certificates/share/ca-certificates/cacert.pem"
      elif [ -f "$ZEROBREW_PREFIX/etc/ca-certificates/cacert.pem" ]; then
        [ -z "''${CURL_CA_BUNDLE:-}" ] && export CURL_CA_BUNDLE="$ZEROBREW_PREFIX/etc/ca-certificates/cacert.pem"
        [ -z "''${SSL_CERT_FILE:-}" ] && export SSL_CERT_FILE="$ZEROBREW_PREFIX/etc/ca-certificates/cacert.pem"
      elif [ -f "$ZEROBREW_PREFIX/etc/openssl/cert.pem" ]; then
        [ -z "''${CURL_CA_BUNDLE:-}" ] && export CURL_CA_BUNDLE="$ZEROBREW_PREFIX/etc/openssl/cert.pem"
        [ -z "''${SSL_CERT_FILE:-}" ] && export SSL_CERT_FILE="$ZEROBREW_PREFIX/etc/openssl/cert.pem"
      elif [ -f "$ZEROBREW_PREFIX/share/ca-certificates/cacert.pem" ]; then
        [ -z "''${CURL_CA_BUNDLE:-}" ] && export CURL_CA_BUNDLE="$ZEROBREW_PREFIX/share/ca-certificates/cacert.pem"
        [ -z "''${SSL_CERT_FILE:-}" ] && export SSL_CERT_FILE="$ZEROBREW_PREFIX/share/ca-certificates/cacert.pem"
      fi
    fi

    if [ -z "''${SSL_CERT_DIR:-}" ]; then
      if [ -d "$ZEROBREW_PREFIX/etc/ca-certificates" ]; then
        export SSL_CERT_DIR="$ZEROBREW_PREFIX/etc/ca-certificates"
      elif [ -d "$ZEROBREW_PREFIX/etc/openssl/certs" ]; then
        export SSL_CERT_DIR="$ZEROBREW_PREFIX/etc/openssl/certs"
      elif [ -d "$ZEROBREW_PREFIX/share/ca-certificates" ]; then
        export SSL_CERT_DIR="$ZEROBREW_PREFIX/share/ca-certificates"
      fi
    fi

    _nix_zb_prepend_path "$ZEROBREW_PREFIX/bin"
  '';

  fishShellIntegration = prefix: ''
    set -gx ZEROBREW_ROOT "${prefix.prefix}"
    set -gx ZEROBREW_PREFIX "${prefix.linkDir}"

    if set -q PKG_CONFIG_PATH
      if not contains -- "$ZEROBREW_PREFIX/lib/pkgconfig" (string split ":" -- "$PKG_CONFIG_PATH")
        set -gx PKG_CONFIG_PATH "$ZEROBREW_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"
      end
    else
      set -gx PKG_CONFIG_PATH "$ZEROBREW_PREFIX/lib/pkgconfig"
    end

    if not set -q CURL_CA_BUNDLE; or not set -q SSL_CERT_FILE
      if test -f "$ZEROBREW_PREFIX/opt/ca-certificates/share/ca-certificates/cacert.pem"
        set -q CURL_CA_BUNDLE; or set -gx CURL_CA_BUNDLE "$ZEROBREW_PREFIX/opt/ca-certificates/share/ca-certificates/cacert.pem"
        set -q SSL_CERT_FILE; or set -gx SSL_CERT_FILE "$ZEROBREW_PREFIX/opt/ca-certificates/share/ca-certificates/cacert.pem"
      else if test -f "$ZEROBREW_PREFIX/etc/ca-certificates/cacert.pem"
        set -q CURL_CA_BUNDLE; or set -gx CURL_CA_BUNDLE "$ZEROBREW_PREFIX/etc/ca-certificates/cacert.pem"
        set -q SSL_CERT_FILE; or set -gx SSL_CERT_FILE "$ZEROBREW_PREFIX/etc/ca-certificates/cacert.pem"
      else if test -f "$ZEROBREW_PREFIX/etc/openssl/cert.pem"
        set -q CURL_CA_BUNDLE; or set -gx CURL_CA_BUNDLE "$ZEROBREW_PREFIX/etc/openssl/cert.pem"
        set -q SSL_CERT_FILE; or set -gx SSL_CERT_FILE "$ZEROBREW_PREFIX/etc/openssl/cert.pem"
      else if test -f "$ZEROBREW_PREFIX/share/ca-certificates/cacert.pem"
        set -q CURL_CA_BUNDLE; or set -gx CURL_CA_BUNDLE "$ZEROBREW_PREFIX/share/ca-certificates/cacert.pem"
        set -q SSL_CERT_FILE; or set -gx SSL_CERT_FILE "$ZEROBREW_PREFIX/share/ca-certificates/cacert.pem"
      end
    end

    if not set -q SSL_CERT_DIR
      if test -d "$ZEROBREW_PREFIX/etc/ca-certificates"
        set -gx SSL_CERT_DIR "$ZEROBREW_PREFIX/etc/ca-certificates"
      else if test -d "$ZEROBREW_PREFIX/etc/openssl/certs"
        set -gx SSL_CERT_DIR "$ZEROBREW_PREFIX/etc/openssl/certs"
      else if test -d "$ZEROBREW_PREFIX/share/ca-certificates"
        set -gx SSL_CERT_DIR "$ZEROBREW_PREFIX/share/ca-certificates"
      end
    end

    if not contains -- "$ZEROBREW_PREFIX/bin" $PATH
      fish_add_path "$ZEROBREW_PREFIX/bin"
    end
  '';
in {
  options = {
    nix-zerobrew = {
      enable = lib.mkOption {
        description = ''
          Whether to install and manage Zerobrew.
        '';
        type = types.bool;
        default = false;
      };

      enableRosetta = lib.mkOption {
        description = ''
          Whether to set up the Intel Zerobrew prefix for Rosetta 2.

          This is only supported on Apple Silicon Macs.
        '';
        type = types.bool;
        default = false;
      };

      package = lib.mkOption {
        description = ''
          The Zerobrew package to use for native architecture launchers.
        '';
        type = types.package;
      };

      packageRosetta = lib.mkOption {
        description = ''
          The Zerobrew package to use for Intel launchers on Apple Silicon.

          When null, `package` is used.
        '';
        type = types.nullOr types.package;
        default = null;
      };

      autoMigrate = lib.mkOption {
        description = ''
          Whether to allow nix-zerobrew to automatically migrate existing Zerobrew installations.

          When enabled, the activation script will take ownership of
          existing installations while keeping installed packages.
        '';
        type = types.bool;
        default = false;
      };

      user = lib.mkOption {
        description = ''
          The user owning the Zerobrew directories.
        '';
        type = types.str;
      };

      group = lib.mkOption {
        description = ''
          The group owning the Zerobrew directories.
        '';
        type = types.str;
        default = "admin";
      };

      prefixes = lib.mkOption {
        description = ''
          A set of Zerobrew prefixes to set up.

          Usually you don't need to configure this and sensible defaults
          are already set up.
        '';
        type = types.attrsOf prefixType;
      };

      defaultArm64Prefix = lib.mkOption {
        description = ''
          Key of the default Zerobrew prefix for ARM64 macOS.
        '';
        internal = true;
        type = types.str;
        default = "/opt/zerobrew";
      };

      defaultIntelPrefix = lib.mkOption {
        description = ''
          Key of the default Zerobrew prefix for Intel macOS or Rosetta 2.
        '';
        internal = true;
        type = types.str;
        default = "/usr/local/zerobrew";
      };

      extraEnv = lib.mkOption {
        description = ''
          Extra environment variables to set for Zerobrew.
        '';
        type = types.attrsOf types.str;
        default = {};
        example = lib.literalExpression ''
          {
            ZEROBREW_NO_ANALYTICS = "1";
          }
        '';
      };

      # Shell integrations
      enableBashIntegration = lib.mkEnableOption "zerobrew bash integration" // {
        default = true;
      };

      enableFishIntegration = lib.mkEnableOption "zerobrew fish integration" // {
        default = true;
      };

      enableZshIntegration = lib.mkEnableOption "zerobrew zsh integration" // {
        default = true;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = "nix-zerobrew is only supported on macOS";
      }
      {
        assertion = cfg.enableRosetta -> pkgs.stdenv.hostPlatform.isAarch64;
        message = "nix-zerobrew.enableRosetta is set to true but this isn't an Apple Silicon Mac";
      }
      {
        assertion = options.system ? primaryUser;
        message = "Please update your nix-darwin version to use system-wide activation";
      }
      {
        assertion = lib.hasAttrByPath [ cfg.defaultArm64Prefix ] cfg.prefixes;
        message = "nix-zerobrew.defaultArm64Prefix must exist under nix-zerobrew.prefixes";
      }
      {
        assertion = lib.hasAttrByPath [ cfg.defaultIntelPrefix ] cfg.prefixes;
        message = "nix-zerobrew.defaultIntelPrefix must exist under nix-zerobrew.prefixes";
      }
      {
        assertion = builtins.length enabledPrefixNames > 0;
        message = "At least one entry in nix-zerobrew.prefixes must have enable = true";
      }
      {
        assertion = (!cfg.enableRosetta) || ((intelPrefix != null) && intelPrefix.enable);
        message = "nix-zerobrew.enableRosetta requires nix-zerobrew.defaultIntelPrefix to be enabled";
      }
    ];

    nix-zerobrew.prefixes = {
      "${cfg.defaultArm64Prefix}" = {
        enable = lib.mkDefault pkgs.stdenv.hostPlatform.isAarch64;
        package = lib.mkDefault cfg.package;
      };

      "${cfg.defaultIntelPrefix}" = {
        enable = lib.mkDefault (pkgs.stdenv.hostPlatform.isx86_64 || cfg.enableRosetta);
        package = lib.mkDefault (
          if pkgs.stdenv.hostPlatform.isAarch64
          then (if cfg.packageRosetta != null then cfg.packageRosetta else cfg.package)
          else cfg.package
        );
      };
    };

    # Shell integrations
    programs.bash.interactiveShellInit = lib.mkIf (cfg.enableBashIntegration && hostDefaultPrefix != null) (
      posixShellIntegration hostDefaultPrefix
    );

    programs.zsh.interactiveShellInit = lib.mkIf (cfg.enableZshIntegration && hostDefaultPrefix != null) (
      posixShellIntegration hostDefaultPrefix
    );

    programs.fish.interactiveShellInit = lib.mkIf (cfg.enableFishIntegration && hostDefaultPrefix != null) (
      fishShellIntegration hostDefaultPrefix
    );

    environment.systemPackages = [ zbLauncher zbxLauncher ];

    system.activationScripts = {
      setup-zerobrew.text = ''
        >&2 echo "setting up Zerobrew prefixes..."
        ${setupZerobrew}
      '';

      # Set up Zerobrew prefixes before nix-darwin's homebrew activation takes place.
      homebrew.text = lib.mkIf config.homebrew.enable (lib.mkBefore ''
        ${config.system.activationScripts.setup-zerobrew.text}
      '');
    };
  };
}
