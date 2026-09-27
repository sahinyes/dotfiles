# shellcheck shell=bash
# Neovim itself. Debian's packages are too old (bookworm 0.7.2, trixie
# 0.10.4), so Linux gets the official release tarball pinned in tools.lock;
# the Mac gets Homebrew's neovim from the Brewfile. Every later step calls
# nvim through the absolute path in $NVIM, never a bare "nvim" from PATH.

NVIM_WANT=0.12

# nvim_version: "0.12.5" for $NVIM, empty when it does not run. The log file
# is redirected because even --version would create ~/.local/state/nvim.
nvim_version() {
  [ -x "$NVIM" ] || return 0
  NVIM_LOG_FILE=/dev/null "$NVIM" --version 2>/dev/null </dev/null |
    awk 'NR == 1 { sub(/^v/, "", $2); print $2 }'
}

# nvim_linux_row: tools.lock callback; installs the nvim tarball row.
nvim_linux_row() {
  [ "$R_NAME" = nvim ] || return 0
  NVIM_ROW_VERSION=$R_VERSION
  if ! install_row; then
    report FAIL nvim "$R_VERSION: download or sha256 check failed ($R_URL)"
    return 0
  fi
  link "$ROW_BIN" "$BIN_DIR/nvim"
}

nvim_step() {
  local v
  step "neovim"
  NVIM_ROW_VERSION=
  if [ "$OS" = linux ]; then
    lock_rows tar nvim_linux_row
    [ -n "$NVIM_ROW_VERSION" ] || {
      report FAIL nvim "no nvim row in tools.lock for linux/$ARCH"
      return 0
    }
  fi
  v=$(nvim_version)
  case $v in
    "$NVIM_WANT".*)
      local how="Homebrew"
      if [ "$OS" = linux ]; then how="release tarball, sha256 OK"; fi
      report OK nvim "$v $(tilde "$NVIM") ($how)"
      ;;
    '') report FAIL nvim "$(tilde "$NVIM") is missing or does not run" ;;
    *) report FAIL nvim "$(tilde "$NVIM") is $v, this config needs $NVIM_WANT.x" ;;
  esac
}
