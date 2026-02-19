# Shell utilities for nix-zerobrew
#
# Adapted from the Homebrew install script.
# BSD 2-Clause License
# Copyright (c) 2009-present, Homebrew contributors
# All rights reserved.
#
# Uses:
#
# - ZEROBREW_ROOT
# - ZEROBREW_STORE_DIR
# - ZEROBREW_DB_DIR
# - ZEROBREW_CACHE_DIR
# - ZEROBREW_LOCKS_DIR
# - ZEROBREW_LINK_DIR
# - NIX_ZEROBREW_UID
# - NIX_ZEROBREW_GID
# - NIX_ZEROBREW_MARKER

# macOS-specific commands
STAT_PRINTF=("/usr/bin/stat" "-f")
PERMISSION_FORMAT="%A"

CHMOD=("/bin/chmod")
CHOWN=("/usr/sbin/chown")
CHGRP=("/usr/bin/chgrp")
MKDIR=("/bin/mkdir" "-p")
TOUCH=("/usr/bin/touch")
INSTALL=("/usr/bin/install" -d -o "root" -g "wheel" -m "0755")

# string formatters
if [[ -t 1 ]]
then
  tty_escape() { printf "\033[%sm" "$1"; }
else
  tty_escape() { :; }
fi
tty_mkbold() { tty_escape "1;$1"; }
tty_underline="$(tty_escape "4;39")"
tty_blue="$(tty_mkbold 34)"
tty_red="$(tty_mkbold 31)"
tty_bold="$(tty_mkbold 39)"
tty_reset="$(tty_escape 0)"

shell_join() {
  local arg
  printf "%s" "$1"
  shift
  for arg in "$@"
  do
    printf " "
    printf "%s" "${arg// /\ }"
  done
}

chomp() {
  printf "%s" "${1/"$'\n'"/}"
}

ohai() {
  printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$(shell_join "$@")"
}

warn() {
  printf "${tty_red}Warning${tty_reset}: %s\n" "$(chomp "$1")" >&2
}

error() {
  printf "${tty_red}Error${tty_reset}: %s\n" "$(chomp "$1")" >&2
}

get_permission() {
  "${STAT_PRINTF[@]}" "${PERMISSION_FORMAT}" "$1"
}

exists_but_not_writable() {
  [[ -e "$1" ]] && ! [[ -r "$1" && -w "$1" && -x "$1" ]]
}

user_only_chmod() {
  [[ -d "$1" ]] && [[ "$(get_permission "$1")" != 75[0145] ]]
}

get_owner() {
  "${STAT_PRINTF[@]}" "%u" "$1"
}

file_not_owned() {
  [[ "$(get_owner "$1")" != "${NIX_ZEROBREW_UID}" ]]
}

get_group() {
  "${STAT_PRINTF[@]}" "%g" "$1"
}

file_not_grpowned() {
  [[ " ${NIX_ZEROBREW_GID} " != *" $(get_group "$1") "* ]]
}

# Initialize or repair the Zerobrew directory structure for one prefix.
initialize_zerobrew_layout() {
  directories=(
    "${ZEROBREW_ROOT}"
    "${ZEROBREW_STORE_DIR}"
    "${ZEROBREW_DB_DIR}"
    "${ZEROBREW_CACHE_DIR}"
    "${ZEROBREW_LOCKS_DIR}"
    "${ZEROBREW_LINK_DIR}"
    "${ZEROBREW_LINK_DIR}/bin"
    "${ZEROBREW_LINK_DIR}/Cellar"
    "${ZEROBREW_LINK_DIR}/opt"
    "${ZEROBREW_LINK_DIR}/lib"
    "${ZEROBREW_LINK_DIR}/include"
    "${ZEROBREW_LINK_DIR}/share"
    "${ZEROBREW_LINK_DIR}/etc"
  )

  group_chmods=()
  for dir in "${directories[@]}"
  do
    if exists_but_not_writable "${dir}"
    then
      group_chmods+=("${dir}")
    fi
  done

  mkdirs=()
  for dir in "${directories[@]}"
  do
    if ! [[ -d "${dir}" ]]
    then
      mkdirs+=("${dir}")
    fi
  done

  chmods=()
  if [[ "${#group_chmods[@]}" -gt 0 ]]
  then
    chmods+=("${group_chmods[@]}")
  fi

  chowns=()
  chgrps=()
  if [[ "${#chmods[@]}" -gt 0 ]]
  then
    for dir in "${chmods[@]}"
    do
      if file_not_owned "${dir}"
      then
        chowns+=("${dir}")
      fi
      if file_not_grpowned "${dir}"
      then
        chgrps+=("${dir}")
      fi
    done
  fi

  if [[ -d "${ZEROBREW_ROOT}" ]]
  then
    if [[ "${#chmods[@]}" -gt 0 ]]
    then
      "${CHMOD[@]}" "u+rwx" "${chmods[@]}"
    fi
    if [[ "${#group_chmods[@]}" -gt 0 ]]
    then
      "${CHMOD[@]}" "g+rwx" "${group_chmods[@]}"
    fi
    if [[ "${#chowns[@]}" -gt 0 ]]
    then
      "${CHOWN[@]}" "${NIX_ZEROBREW_UID}" "${chowns[@]}"
    fi
    if [[ "${#chgrps[@]}" -gt 0 ]]
    then
      "${CHGRP[@]}" "${NIX_ZEROBREW_GID}" "${chgrps[@]}"
    fi
  else
    "${INSTALL[@]}" "${ZEROBREW_ROOT}"
  fi

  if [[ "${#mkdirs[@]}" -gt 0 ]]
  then
    "${MKDIR[@]}" "${mkdirs[@]}"
    "${CHMOD[@]}" "ug=rwx" "${mkdirs[@]}"
    "${CHOWN[@]}" "${NIX_ZEROBREW_UID}" "${mkdirs[@]}"
    "${CHGRP[@]}" "${NIX_ZEROBREW_GID}" "${mkdirs[@]}"
  fi

  # Mark as managed by nix-darwin
  "${TOUCH[@]}" "${NIX_ZEROBREW_MARKER}"
  "${CHOWN[@]}" "${NIX_ZEROBREW_UID}:${NIX_ZEROBREW_GID}" "${NIX_ZEROBREW_MARKER}"
}

# vim: set et ts=2 sw=2:
