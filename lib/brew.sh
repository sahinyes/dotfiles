# shellcheck shell=bash
# macOS packages through Homebrew (Brewfile). Homebrew is never updated or
# upgraded here (--no-upgrade, no auto-update): only missing packages are added.

# brew_env: settings for every brew call. Brewfile reads the two
# HOMEBREW_DOTFILES_* variables (brew hides variables without that prefix).
brew_env() {
  export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1
  export HOMEBREW_DOTFILES_TIER="$TIER"
  if [ "$NO_FONTS" = 1 ] || [ "$NERD_FONT" = yes ]; then
    export HOMEBREW_DOTFILES_SKIP_FONT_CASK=1
  else
    unset HOMEBREW_DOTFILES_SKIP_FONT_CASK
  fi
}

brew_step() {
  step "Homebrew (Brewfile, tier $TIER)"
  if [ -z "$BREW" ]; then
    report FAIL brew "Homebrew not found: install it from https://brew.sh, then re-run"
    return 0
  fi
  brew_env
  if "$BREW" bundle check --no-upgrade --file "$REPO/Brewfile" >/dev/null 2>&1; then
    report OK brew "every Brewfile package is installed"
  elif "$BREW" bundle install --no-upgrade --file "$REPO/Brewfile"; then
    changed "brew bundle installed the missing Brewfile packages"
    report OK brew "installed the missing Brewfile packages"
  else
    report FAIL brew "brew bundle install failed (see the output above)"
  fi
  brew_drift
}

# brew_drift: compare Homebrew's versions with the tools.lock pins (which
# the Debian laptop uses), so a difference between the machines is visible.
brew_drift() {
  local pair formula name have_v lock_v drift=
  for pair in neovim:nvim ripgrep:ripgrep fd:fd fzf:fzf marksman:marksman \
    yq:yq gitleaks:gitleaks tree-sitter-cli:tree-sitter; do
    formula=${pair%%:*}
    name=${pair#*:}
    have_v=$("$BREW" list --versions "$formula" 2>/dev/null | awk '{print $2}')
    have_v=${have_v%%_*}
    lock_v=$(awk -v n="$name" '$1 == n && $6 != "git" { print $2; exit }' "$LOCK_FILE")
    lock_v=${lock_v#v}
    if [ -n "$have_v" ] && [ -n "$lock_v" ] && [ "$have_v" != "$lock_v" ]; then
      drift="$drift $formula $have_v (lock $lock_v),"
    fi
  done
  if [ -n "$drift" ]; then
    report WARN brew "Homebrew differs from tools.lock:${drift%,}"
  fi
}
