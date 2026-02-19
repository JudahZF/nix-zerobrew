# Build zerobrew from source
#
# Zerobrew is a fast macOS package manager written in Rust.
# This derivation builds the `zb` CLI binary from the workspace.

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

  # Build only the CLI crate
  cargoBuildFlags = [ "--package" "zb_cli" ];
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

  # The CLI binary is named 'zb'
  postInstall = ''
    # Ensure the binary is named correctly
    if [ -f "$out/bin/zb_cli" ]; then
      mv "$out/bin/zb_cli" "$out/bin/zb"
    fi
  '';

  meta = with lib; {
    description = "A fast macOS package manager";
    homepage = "https://github.com/lucasgelfond/zerobrew";
    license = with licenses; [ mit asl20 ];
    maintainers = [ ];
    platforms = platforms.darwin;
    mainProgram = "zb";
  };
}
