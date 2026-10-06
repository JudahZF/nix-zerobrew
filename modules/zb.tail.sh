# Zerobrew launcher tail
#
# This script is appended to the launcher header that sets up
# the environment variables. It executes the actual Nix-built
# zerobrew binary.
#
# Expected environment variables:
# - ZEROBREW_ROOT: Root directory for zerobrew data
# - ZEROBREW_PREFIX: Link prefix directory (contains bin/, Cellar/, opt/, ...)
# - NIX_ZEROBREW_BIN: Path to the Nix-built zerobrew binary

# When nix-zerobrew.global.brewfile is enabled, bare `zb bundle` uses the
# Brewfile written during activation, matching HOMEBREW_BUNDLE_FILE.
args=("$@")
if [[ -n "${NIX_ZEROBREW_BUNDLE_FILE:-}" && -f "${NIX_ZEROBREW_BUNDLE_FILE}" && ${#args[@]} -ge 1 && "${args[0]}" == "bundle" ]]; then
  has_file=0
  for arg in "${args[@]}"; do
    case "$arg" in
      -f|--file|--file=*) has_file=1 ;;
    esac
  done
  if [[ "$has_file" -eq 0 ]]; then
    if [[ ${#args[@]} -ge 2 && ( "${args[1]}" == "install" || "${args[1]}" == "dump" ) ]]; then
      args=("${args[0]}" "${args[1]}" --file "${NIX_ZEROBREW_BUNDLE_FILE}" "${args[@]:2}")
    else
      args=("${args[0]}" --file "${NIX_ZEROBREW_BUNDLE_FILE}" "${args[@]:1}")
    fi
  fi
fi

exec "${NIX_ZEROBREW_BIN}" "${args[@]}"
