# Build zerobrew from source
#
# Zerobrew is a fast macOS package manager written in Rust.
# This derivation builds the `zb` and `zbx` CLI binaries from the workspace.

{ lib
, rustPlatform
, zerobrew-src
, openssl
, pkg-config
, stdenv
, apple-sdk_15
, darwinMinVersionHook
}:

rustPlatform.buildRustPackage {
  pname = "zerobrew";
  version = (lib.importTOML "${zerobrew-src}/zb_cli/Cargo.toml").package.version;

  src = zerobrew-src;

  cargoLock = {
    lockFile = "${zerobrew-src}/Cargo.lock";
    # If there are git dependencies, they may need to be specified here
    # outputHashes = { };
  };

  # Build and install both CLI binaries from the workspace crate.
  cargoBuildFlags = [ "--package" "zb_cli" "--bins" ];
  cargoInstallFlags = [ "--path" "zb_cli" "--bins" ];
  doCheck = false;

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    openssl
  ] ++ lib.optionals stdenv.hostPlatform.isDarwin [
    apple-sdk_15
    (darwinMinVersionHook "10.15")
  ];

  meta = with lib; {
    description = "A fast macOS package manager";
    homepage = "https://github.com/lucasgelfond/zerobrew";
    license = with licenses; [ mit asl20 ];
    maintainers = [ ];
    platforms = platforms.darwin;
    mainProgram = "zb";
  };
}
