# Build zerobrew from source
#
# Zerobrew is a fast macOS package manager written in Rust.
# This derivation builds the `zb` and `zbx` CLI binaries from the workspace.
{ lib, rustPlatform, zerobrew-src, openssl, pkg-config, stdenv, apple-sdk_15
, darwinMinVersionHook, }:
let
  cargoToml = lib.importTOML "${zerobrew-src}/Cargo.toml";
  cliCargoToml = lib.importTOML "${zerobrew-src}/zb_cli/Cargo.toml";
  workspaceVersion = cargoToml.workspace.package.version;
  workspaceRustVersion = cargoToml.workspace.package.rust-version;
  resolveWorkspaceValue = value:
    if lib.isAttrs value && value ? workspace && value.workspace then
      workspaceVersion
    else
      value;
in rustPlatform.buildRustPackage {
  pname = "zerobrew";
  version = resolveWorkspaceValue cliCargoToml.package.version;

  src = zerobrew-src;

  postPatch = ''
    for manifest in zb_cli/Cargo.toml zb_core/Cargo.toml zb_io/Cargo.toml; do
      substituteInPlace "$manifest" \
        --replace "rust-version.workspace = true" "rust-version = \"${workspaceRustVersion}\"" \
        --replace "version.workspace = true" "version = \"${workspaceVersion}\""
    done
  '';

  cargoLock = {
    lockFile = "${zerobrew-src}/Cargo.lock";
    # If there are git dependencies, they may need to be specified here
    # outputHashes = { };
  };

  # Build and install both CLI binaries from the workspace crate.
  cargoBuildFlags = [ "--package" "zb_cli" "--bins" ];
  cargoInstallFlags = [ "--path" "zb_cli" "--bins" ];
  doCheck = false;

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [ openssl ] ++ lib.optionals stdenv.hostPlatform.isDarwin [
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
