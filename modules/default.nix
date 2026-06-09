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

      taps = lib.mkOption {
        description = ''
          A set of Nix-managed taps for this prefix.
        '';
        type = types.attrsOf types.package;
        default = { };
        example = lib.literalExpression ''
          {
            "homebrew/homebrew-core" = pkgs.fetchFromGitHub {
              owner = "homebrew";
              repo = "homebrew-core";
              rev = "...";
              hash = "...";
            };
          }
        '';
      };

      extraLinkDirs = lib.mkOption {
        description = ''
          Additional Homebrew-style directories to create under this prefix's link directory.
        '';
        type = types.listOf types.str;
        default = [ ];
      };

      brews = lib.mkOption {
        description = ''
          Zerobrew formula names, fully qualified formula references, or Brewfile-shaped entries to install declaratively in this prefix.
        '';
        type = types.listOf packageEntryType;
        default = [ ];
        example = lib.literalExpression ''
          [ "jq" { name = "ripgrep"; args = [ "HEAD" ]; } ]
        '';
      };

      casks = lib.mkOption {
        description = ''
          Zerobrew cask tokens, or Brewfile-shaped entries, to install declaratively in this prefix, without the `cask:` prefix.
        '';
        type = types.listOf packageEntryType;
        default = [ ];
        example = lib.literalExpression ''
          [ "iterm2" { name = "visual-studio-code"; args = [ "no_quarantine" ]; } ]
        '';
      };

      masApps = lib.mkOption {
        description = ''
          Mac App Store apps to install declaratively in this prefix. Attribute names are labels and values are app IDs.
        '';
        type = types.attrsOf types.ints.positive;
        default = { };
        example = lib.literalExpression ''
          {
            Xcode = 497799835;
          }
        '';
      };
    };
  });

  armPrefix = lib.attrByPath [ cfg.defaultArm64Prefix ] null cfg.prefixes;
  intelPrefix = lib.attrByPath [ cfg.defaultIntelPrefix ] null cfg.prefixes;

  hostDefaultPrefixKey = if pkgs.stdenv.hostPlatform.isAarch64 then
    cfg.defaultArm64Prefix
  else
    cfg.defaultIntelPrefix;
  hostDefaultPrefix = lib.attrByPath [ hostDefaultPrefixKey ] null cfg.prefixes;

  makePrefixLauncher = binary: prefix:
    let
      selectedPackage =
        if prefix.package != null then prefix.package else cfg.package;
    in pkgs.writeScriptBin binary (''
      #!/bin/bash
      set -euo pipefail
      export ZEROBREW_ROOT="${prefix.prefix}"
      export ZEROBREW_PREFIX="${prefix.linkDir}"
      export HOMEBREW_PREFIX="$ZEROBREW_PREFIX"
      export HOMEBREW_CELLAR="$ZEROBREW_PREFIX/Cellar"
      export NIX_ZEROBREW_BIN="${selectedPackage}/bin/${binary}"
      export PATH="${prefix.linkDir}/bin:$PATH"
    '' + lib.optionalString (!cfg.mutableTaps) ''
      export HOMEBREW_NO_AUTO_UPDATE=1
    '' + (lib.optionalString (cfg.extraEnv != { }) (lib.concatLines
      (lib.mapAttrsToList
        (name: value: "export ${name}=${lib.escapeShellArg value}")
        cfg.extraEnv))) + (builtins.readFile ./zb.tail.sh));

  prefixLaunchers = lib.mapAttrs (_: prefix: {
    zb = makePrefixLauncher "zb" prefix;
    zbx = makePrefixLauncher "zbx" prefix;
  }) cfg.prefixes;
  enabledPrefixNames = lib.filter (name: cfg.prefixes.${name}.enable)
    (builtins.attrNames cfg.prefixes);
  declaredTapNames = lib.unique ((builtins.attrNames cfg.taps)
    ++ lib.concatMap (name: builtins.attrNames cfg.prefixes.${name}.taps)
    (builtins.attrNames cfg.prefixes));
  validTapName = name:
    let parts = lib.splitString "/" name;
    in builtins.length parts >= 2 && !builtins.elem "" parts;
  validStateValue = value:
    !(lib.hasInfix "	" value) && !(lib.hasInfix "\n" value);
  packageEntryType = types.either types.str (types.submodule {
    options = {
      name = lib.mkOption {
        description = "Formula or cask token.";
        type = types.str;
      };
      args = lib.mkOption {
        description = "Brewfile args emitted for this entry.";
        type = types.listOf types.str;
        default = [ ];
      };
    };
  });
  packageEntryName = entry:
    if builtins.isString entry then entry else entry.name;
  escapeBrewfileString = value:
    builtins.replaceStrings [ "\\" ''"'' ] [ "\\\\" ''\"'' ] value;
  brewfileArgs = args:
    lib.optionalString (args != [ ]) (", args: ["
      + lib.concatMapStringsSep ", " (arg: ''"${escapeBrewfileString arg}"'')
      args + "]");
  brewfileLine = kind: entry:
    let value = packageEntryName entry;
    in ''
      ${kind} "${escapeBrewfileString value}"${
        brewfileArgs (entry.args or [ ])
      }'';
  stateLine = kind: entry: "${kind}	${packageEntryName entry}";
  uniquePackageEntries = entries:
    lib.foldl' (acc: entry:
      let name = packageEntryName entry;
      in if builtins.elem name acc.names then
        acc
      else {
        names = acc.names ++ [ name ];
        values = acc.values ++ [ entry ];
      }) {
        names = [ ];
        values = [ ];
      } entries;
  normalizedPackagesForPrefix = name:
    let
      prefix = cfg.prefixes.${name};
      topMasAppIds = map toString (lib.attrValues cfg.masApps);
      prefixMasAppIds = map toString (lib.attrValues prefix.masApps);
    in if name == hostDefaultPrefixKey then {
      brews = (uniquePackageEntries (cfg.brews ++ prefix.brews)).values;
      casks = (uniquePackageEntries (cfg.casks ++ prefix.casks)).values;
      masAppIds = topMasAppIds
        ++ lib.filter (id: !(builtins.elem id topMasAppIds)) prefixMasAppIds;
    } else {
      brews = (uniquePackageEntries prefix.brews).values;
      casks = (uniquePackageEntries prefix.casks).values;
      masAppIds = lib.unique prefixMasAppIds;
    };
  safePrefixName = name:
    builtins.replaceStrings [ "/" " " "	" "\n" ] [ "_" "_" "_" "_" ] name;
  brewfileForPrefix = name:
    let packages = normalizedPackagesForPrefix name;
    in pkgs.writeText "nix-zerobrew-Brewfile-${safePrefixName name}"
    (lib.concatLines ((map (brewfileLine "brew") packages.brews)
      ++ (map (brewfileLine "cask") packages.casks)));
  stateForPrefix = name:
    let packages = normalizedPackagesForPrefix name;
    in pkgs.writeText "nix-zerobrew-state-${safePrefixName name}"
    (lib.concatLines ((map (stateLine "brew") packages.brews)
      ++ (map (stateLine "cask") packages.casks)
      ++ (map (id: "mas	${id}") packages.masAppIds)));
  hasDeclarativePackagesForPrefix = name:
    let packages = normalizedPackagesForPrefix name;
    in packages.brews != [ ] || packages.casks != [ ] || packages.masAppIds
    != [ ];
  hasTopLevelDeclarativePackages = cfg.brews != [ ] || cfg.casks != [ ]
    || cfg.masApps != { };
  hasPerPrefixDeclarativePackages = builtins.any (name:
    cfg.prefixes.${name}.brews != [ ] || cfg.prefixes.${name}.casks != [ ]
    || cfg.prefixes.${name}.masApps != { }) (builtins.attrNames cfg.prefixes);
  hasAnyDeclarativePackages = hasTopLevelDeclarativePackages
    || hasPerPrefixDeclarativePackages;
  effectiveDoctorRepair = cfg.enableDoctorRepair || cfg.onActivation.doctor
    == "repair";
  effectiveDoctorCheck = !effectiveDoctorRepair
    && ((cfg.enableDoctorCheck && cfg.onActivation.doctor != "none")
      || cfg.onActivation.doctor == "check");
  effectiveGc = cfg.enableGc || cfg.onActivation.gc;

  setupTaps = taps:
    if cfg.mutableTaps then
      lib.concatMapStrings (path:
        let
          namespace = builtins.head (lib.splitString "/" path);
          target = taps.${path};
          namespaceDir = "$ZEROBREW_LINK_DIR/Library/Taps/${namespace}";
          tapDir = "$ZEROBREW_LINK_DIR/Library/Taps/${path}";
        in ''
          if [[ -e "${namespaceDir}" ]] && [[ ! -d "${namespaceDir}" ]]; then
            error "${namespaceDir} is in the way and needs to be moved out for ${path}"
            exit 1
          fi
          if is_occupied "${tapDir}"; then
            error "An existing ${tapDir} is in the way"
            exit 1
          fi
          "''${MKDIR[@]}" "${namespaceDir}"
          "''${CHOWN[@]}" "$NIX_ZEROBREW_UID:$NIX_ZEROBREW_GID" "${namespaceDir}"
          "''${CHMOD[@]}" "ug=rwx" "${namespaceDir}"
          /bin/ln -shf "${target}" "${tapDir}"
        '') (builtins.attrNames taps)
    else
      let
        env = pkgs.runCommandLocal "zerobrew-taps-env" { } (lib.concatMapStrings
          (path:
            let
              namespace = builtins.head (lib.splitString "/" path);
              target = taps.${path};
            in ''
              mkdir -p "$out/${namespace}"
              ln -s "${target}" "$out/${path}"
            '') (builtins.attrNames taps));
      in ''
        if is_occupied "$ZEROBREW_LINK_DIR/Library/Taps"; then
          error "An existing $ZEROBREW_LINK_DIR/Library/Taps is in the way"
          exit 1
        fi

        /bin/ln -shf "${env}" "$ZEROBREW_LINK_DIR/Library/Taps"
      '';

  setupDeclarativePackagesForPrefix = cleanup: name:
    let
      packages = normalizedPackagesForPrefix name;
      brewfile = brewfileForPrefix name;
      state = stateForPrefix name;
      hasMasApps = packages.masAppIds != [ ];
    in ''
      ${lib.optionalString
      (hasTopLevelDeclarativePackages && name == hostDefaultPrefixKey) ''
        # Top-level nix-zerobrew package declarations target the host default prefix only.
      ''}
      NIX_ZEROBREW_DECLARATIVE_DIR="$ZEROBREW_ROOT/db/nix-zerobrew"
      NIX_ZEROBREW_BREWFILE="$NIX_ZEROBREW_DECLARATIVE_DIR/Brewfile"
      NIX_ZEROBREW_STATE="$NIX_ZEROBREW_DECLARATIVE_DIR/state"
      NIX_ZEROBREW_NEW_STATE="$NIX_ZEROBREW_DECLARATIVE_DIR/state.new"
      NIX_ZEROBREW_OLD_STATE="$NIX_ZEROBREW_DECLARATIVE_DIR/state.old"

      "''${MKDIR[@]}" "$NIX_ZEROBREW_DECLARATIVE_DIR"
      if [[ -f "$NIX_ZEROBREW_STATE" ]]; then
        /bin/cp "$NIX_ZEROBREW_STATE" "$NIX_ZEROBREW_OLD_STATE"
      else
        : > "$NIX_ZEROBREW_OLD_STATE"
      fi
      /bin/cp "${brewfile}" "$NIX_ZEROBREW_BREWFILE"
      /bin/cp "${state}" "$NIX_ZEROBREW_NEW_STATE"

      ${lib.optionalString (packages.brews != [ ] || packages.casks != [ ]) ''
        ohai "Installing declarative Zerobrew brews and casks for $ZEROBREW_LINK_DIR..."
        "$BIN_ZB" bundle install --file "$NIX_ZEROBREW_BREWFILE"
      ''}

      ${lib.optionalString hasMasApps ''
        ohai "Installing declarative Mac App Store apps for $ZEROBREW_LINK_DIR..."
        "$BIN_ZB" install mas
        NIX_ZEROBREW_MAS_LIST="$("$ZEROBREW_LINK_DIR/bin/mas" list || true)"
        while IFS=$'\t' read -r kind value; do
          [[ "$kind" == "mas" && -n "$value" ]] || continue
          if printf '%s\n' "$NIX_ZEROBREW_MAS_LIST" | awk '{ print $1 }' | grep -Fqx "$value"; then
            continue
          fi
          "$ZEROBREW_LINK_DIR/bin/mas" install "$value"
        done < "$NIX_ZEROBREW_NEW_STATE"
      ''}

      ${lib.optionalString cleanup ''
        while IFS=$'\t' read -r kind value; do
          [[ -n "$kind" && -n "$value" ]] || continue
          if grep -Fqx "$kind"$'\t'"$value" "$NIX_ZEROBREW_NEW_STATE"; then
            continue
          fi
          case "$kind" in
            brew)
              ohai "Removing declarative Zerobrew brew no longer configured: $value"
              "$BIN_ZB" uninstall "$value"
              ;;
            cask)
              ohai "Removing declarative Zerobrew cask no longer configured: $value"
              "$BIN_ZB" uninstall "cask:$value"
              ;;
            mas)
              warn "Mac App Store app $value was removed from nix-zerobrew declarations, but MAS uninstall is unsupported; dropping it from nix-zerobrew state only"
              ;;
          esac
        done < "$NIX_ZEROBREW_OLD_STATE"
      ''}

      /bin/mv "$NIX_ZEROBREW_NEW_STATE" "$NIX_ZEROBREW_STATE"
      /bin/rm -f "$NIX_ZEROBREW_OLD_STATE"
    '';

  setupPrefix = name:
    let
      prefix = cfg.prefixes.${name};
      launchers = prefixLaunchers.${name};
    in ''
      ZEROBREW_ROOT="${prefix.prefix}"
      ZEROBREW_LINK_DIR="${prefix.linkDir}"
      NIX_ZEROBREW_MARKER="$ZEROBREW_ROOT/${nixMarker}"
      NIX_ZEROBREW_EXTRA_LINK_DIRS=(${
        lib.concatMapStringsSep " " lib.escapeShellArg prefix.extraLinkDirs
      })
      NIX_ZEROBREW_MUTABLE_TAPS="${lib.optionalString cfg.mutableTaps "1"}"

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

      ${setupTaps prefix.taps}

      ${lib.optionalString cfg.onActivation.autoUpdate ''
        ohai "Running Zerobrew update for $ZEROBREW_LINK_DIR..."
        "$BIN_ZB" update
      ''}

      ${setupDeclarativePackagesForPrefix
      (cfg.onActivation.cleanup == "uninstall") name}

      ${lib.optionalString cfg.onActivation.upgrade ''
        ohai "Running Zerobrew upgrade for $ZEROBREW_LINK_DIR..."
        "$BIN_ZB" upgrade
      ''}

      ${lib.optionalString effectiveDoctorRepair ''
        ohai "Running Zerobrew doctor --repair for $ZEROBREW_LINK_DIR..."
        "$BIN_ZB" doctor --repair
      ''}
      ${lib.optionalString effectiveDoctorCheck ''
        ohai "Running Zerobrew doctor for $ZEROBREW_LINK_DIR..."
        "$BIN_ZB" doctor
      ''}
      ${lib.optionalString effectiveGc ''
        ohai "Running Zerobrew gc for $ZEROBREW_LINK_DIR..."
        "$BIN_ZB" gc
      ''}
    '';

  makeArchDispatcher = binary:
    pkgs.writeScriptBin binary (''
      #!/bin/bash
      set -euo pipefail
      cur_arch=$(/usr/bin/uname -m)
    '' + lib.optionalString (armPrefix != null && armPrefix.enable) ''
      if [[ "$cur_arch" == "arm64" || "$cur_arch" == "aarch64" ]]; then
        exec "${armPrefix.linkDir}/bin/${binary}" "$@"
      fi
    '' + lib.optionalString (intelPrefix != null && intelPrefix.enable) ''
      if [[ "$cur_arch" == "x86_64" || "$cur_arch" == "i386" ]]; then
        exec "${intelPrefix.linkDir}/bin/${binary}" "$@"
      fi
    '' + ''
      >&2 echo "nix-zerobrew: no Zerobrew installation available for $cur_arch"
      exit 1
    '');

  # Unified launcher scripts. Use `arch -x86_64 zb` or `arch -x86_64 zbx` to target Intel when enabled.
  zbLauncher = makeArchDispatcher "zb";
  zbxLauncher = makeArchDispatcher "zbx";

  setupZerobrew = ''
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

    ${lib.optionalString
    (cfg.warnAboutPackageManagement && !hasAnyDeclarativePackages) ''
      ohai "nix-zerobrew manages Zerobrew prefixes and launchers. Add top-level nix-zerobrew.brews/casks/masApps or per-prefix package declarations to manage packages declaratively."
      ohai "Use zb install, zb upgrade, or zb bundle manually for package state outside nix-zerobrew declarations."
    ''}
    ${lib.optionalString
    (cfg.warnAboutPackageManagement && hasTopLevelDeclarativePackages) ''
      ohai "Top-level nix-zerobrew.brews/casks/masApps target the host default prefix only and only entries previously tracked by nix-zerobrew."
    ''}
    ${lib.optionalString
    (cfg.warnAboutPackageManagement && hasPerPrefixDeclarativePackages) ''
      ohai "Per-prefix nix-zerobrew package declarations are reconciled independently for their prefix and only entries previously tracked by nix-zerobrew."
    ''}
    ${lib.optionalString (cfg.warnAboutPackageManagement
      && hasAnyDeclarativePackages && !cfg.onActivation.upgrade) ''
        ohai "Declarative package activation installs configured packages but does not run zb upgrade."
      ''}

    if [[ -n "${toString cfg.enableRosetta}" ]] && ! pgrep -q oahd; then
      warn "The Intel Zerobrew prefix has been set up, but Rosetta isn't installed yet."
      ohai "Run softwareupdate --install-rosetta to install it."
    fi
  '';

  posixShellIntegration = prefix: ''
    export ZEROBREW_ROOT="${prefix.prefix}"
    export ZEROBREW_PREFIX="${prefix.linkDir}"
    export ZEROBREW_CELLAR="$ZEROBREW_PREFIX/Cellar"
    export HOMEBREW_PREFIX="$ZEROBREW_PREFIX"
    export HOMEBREW_CELLAR="$ZEROBREW_CELLAR"

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

    if [ -d "$ZEROBREW_PREFIX/sbin" ]; then
      _nix_zb_prepend_path "$ZEROBREW_PREFIX/sbin"
    fi
    _nix_zb_prepend_path "$ZEROBREW_PREFIX/bin"
  '';

  fishShellIntegration = prefix: ''
    set -gx ZEROBREW_ROOT "${prefix.prefix}"
    set -gx ZEROBREW_PREFIX "${prefix.linkDir}"
    set -gx ZEROBREW_CELLAR "$ZEROBREW_PREFIX/Cellar"
    set -gx HOMEBREW_PREFIX "$ZEROBREW_PREFIX"
    set -gx HOMEBREW_CELLAR "$ZEROBREW_CELLAR"

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

    if test -d "$ZEROBREW_PREFIX/sbin"; and not contains -- "$ZEROBREW_PREFIX/sbin" $PATH
      fish_add_path "$ZEROBREW_PREFIX/sbin"
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

      taps = lib.mkOption {
        description = ''
          A set of Nix-managed taps.

          These are applied to the default prefixes.
        '';
        type = types.attrsOf types.package;
        default = { };
        example = lib.literalExpression ''
          {
            "homebrew/homebrew-core" = pkgs.fetchFromGitHub {
              owner = "homebrew";
              repo = "homebrew-core";
              rev = "...";
              hash = "...";
            };
          }
        '';
      };

      mutableTaps = lib.mkOption {
        description = ''
          Whether to allow imperative management of taps.

          When disabled, the tap tree is fully managed from Nix and
          Zerobrew auto-update behavior is disabled in generated launchers.
        '';
        type = types.bool;
        default = true;
      };

      enableDoctorCheck = lib.mkOption {
        description = ''
          Whether activation should run `zb doctor` for each enabled prefix after setup.
        '';
        type = types.bool;
        default = true;
      };

      enableDoctorRepair = lib.mkOption {
        description = ''
          Whether activation should run `zb doctor --repair` instead of `zb doctor`.

          This is opt-in because repair may mutate Zerobrew package-manager state.
        '';
        type = types.bool;
        default = false;
      };

      enableGc = lib.mkOption {
        description = ''
          Whether activation should run `zb gc` for each enabled prefix after doctor succeeds.

          This is opt-in because garbage collection removes unreferenced store entries.
        '';
        type = types.bool;
        default = false;
      };

      onActivation = lib.mkOption {
        description = ''
          Zerobrew package lifecycle actions to run during nix-darwin activation.

          Defaults preserve the historical nix-zerobrew behavior: no update,
          no upgrade, tracked declarative cleanup enabled, doctor check enabled,
          and no garbage collection unless `enableGc` is also enabled.
        '';
        type = types.submodule {
          options = {
            autoUpdate = lib.mkOption {
              description =
                "Run `zb update` after prefix, tap, and launcher setup.";
              type = types.bool;
              default = false;
            };

            upgrade = lib.mkOption {
              description =
                "Run `zb upgrade` after declarative install and cleanup.";
              type = types.bool;
              default = false;
            };

            cleanup = lib.mkOption {
              description =
                "How to remove previously tracked packages that are no longer declared.";
              type = types.enum [ "none" "uninstall" "zap" ];
              default = "uninstall";
            };

            gc = lib.mkOption {
              description = "Run `zb gc` after doctor succeeds.";
              type = types.bool;
              default = false;
            };

            doctor = lib.mkOption {
              description = "Doctor action to run during activation.";
              type = types.enum [ "none" "check" "repair" ];
              default = "check";
            };
          };
        };
        default = { };
      };

      warnAboutPackageManagement = lib.mkOption {
        description = ''
          Whether activation should note how nix-zerobrew scopes declarative package management.
        '';
        type = types.bool;
        default = true;
      };

      brews = lib.mkOption {
        description = ''
          Zerobrew formula names, fully qualified formula references, or Brewfile-shaped entries to install declaratively.
        '';
        type = types.listOf packageEntryType;
        default = [ ];
        example = lib.literalExpression ''
          [ "jq" { name = "ripgrep"; args = [ "HEAD" ]; } ]
        '';
      };

      casks = lib.mkOption {
        description = ''
          Zerobrew cask tokens, or Brewfile-shaped entries, to install declaratively, without the `cask:` prefix.
        '';
        type = types.listOf packageEntryType;
        default = [ ];
        example = lib.literalExpression ''
          [ "iterm2" { name = "visual-studio-code"; args = [ "no_quarantine" ]; } ]
        '';
      };

      masApps = lib.mkOption {
        description = ''
          Mac App Store apps to install declaratively. Attribute names are labels and values are app IDs.
        '';
        type = types.attrsOf types.ints.positive;
        default = { };
        example = lib.literalExpression ''
          {
            Xcode = 497799835;
          }
        '';
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
        default = { };
        example = lib.literalExpression ''
          {
            ZEROBREW_NO_ANALYTICS = "1";
          }
        '';
      };

      # Shell integrations
      enableBashIntegration = lib.mkEnableOption "zerobrew bash integration"
        // {
          default = true;
        };

      enableFishIntegration = lib.mkEnableOption "zerobrew fish integration"
        // {
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
        message =
          "nix-zerobrew.enableRosetta is set to true but this isn't an Apple Silicon Mac";
      }
      {
        assertion = options.system ? primaryUser;
        message =
          "Please update your nix-darwin version to use system-wide activation";
      }
      {
        assertion = lib.hasAttrByPath [ cfg.defaultArm64Prefix ] cfg.prefixes;
        message =
          "nix-zerobrew.defaultArm64Prefix must exist under nix-zerobrew.prefixes";
      }
      {
        assertion = lib.hasAttrByPath [ cfg.defaultIntelPrefix ] cfg.prefixes;
        message =
          "nix-zerobrew.defaultIntelPrefix must exist under nix-zerobrew.prefixes";
      }
      {
        assertion = builtins.length enabledPrefixNames > 0;
        message =
          "At least one entry in nix-zerobrew.prefixes must have enable = true";
      }
      {
        assertion = (!cfg.enableRosetta)
          || ((intelPrefix != null) && intelPrefix.enable);
        message =
          "nix-zerobrew.enableRosetta requires nix-zerobrew.defaultIntelPrefix to be enabled";
      }
      {
        assertion = builtins.all validTapName declaredTapNames;
        message = ''
          nix-zerobrew tap keys must be in owner/repo form, for example "homebrew/homebrew-core" or "hashicorp/homebrew-tap"'';
      }
      {
        assertion = builtins.all validStateValue (map packageEntryName
          (cfg.brews ++ cfg.casks ++ lib.concatMap
            (name: cfg.prefixes.${name}.brews ++ cfg.prefixes.${name}.casks)
            (builtins.attrNames cfg.prefixes)));
        message =
          "nix-zerobrew brews and casks entries must not contain tabs or newlines";
      }
      {
        assertion = cfg.onActivation.cleanup != "zap";
        message = ''
          nix-zerobrew.onActivation.cleanup = "zap" is not supported yet; Zerobrew zap support must be verified and safely implemented first'';
      }
    ];

    nix-zerobrew.prefixes = {
      "${cfg.defaultArm64Prefix}" = {
        enable = lib.mkDefault pkgs.stdenv.hostPlatform.isAarch64;
        package = lib.mkDefault cfg.package;
        taps = lib.mkDefault cfg.taps;
      };

      "${cfg.defaultIntelPrefix}" = {
        enable = lib.mkDefault
          (pkgs.stdenv.hostPlatform.isx86_64 || cfg.enableRosetta);
        package = lib.mkDefault (if pkgs.stdenv.hostPlatform.isAarch64 then
          (if cfg.packageRosetta != null then
            cfg.packageRosetta
          else
            cfg.package)
        else
          cfg.package);
        taps = lib.mkDefault cfg.taps;
      };
    };

    # Shell integrations
    programs.bash.interactiveShellInit =
      lib.mkIf (cfg.enableBashIntegration && hostDefaultPrefix != null)
      (posixShellIntegration hostDefaultPrefix);

    programs.zsh.interactiveShellInit =
      lib.mkIf (cfg.enableZshIntegration && hostDefaultPrefix != null)
      (posixShellIntegration hostDefaultPrefix);

    programs.fish.interactiveShellInit =
      lib.mkIf (cfg.enableFishIntegration && hostDefaultPrefix != null)
      (fishShellIntegration hostDefaultPrefix);

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
