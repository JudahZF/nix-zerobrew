# Zerobrew launcher tail
#
# This script is appended to the launcher header that sets up
# the environment variables. It executes the actual Nix-built
# zerobrew binary.
#
# Expected environment variables:
# - ZEROBREW_ROOT: Root directory for zerobrew data
# - ZEROBREW_PREFIX: Link prefix directory (contains bin/, Cellar/, opt/, ...)
# - NIX_ZB_BIN: Path to the Nix-built zb binary

# Filter environment and exec the real binary
exec "${NIX_ZB_BIN}" "$@"
