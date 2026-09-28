# shellcheck shell=bash
# tmux plugins without tpm: tmux-resurrect and tmux-continuum are checked out
# at the commits pinned in tools.lock (kind git) into ~/.tmux/plugins/<name>;
# tmux.conf loads them with run-shell. Existing tpm clones are reused after
# their origin is checked. tpm itself is never touched or deleted.

# canonical_url URL: strip tpm's "git::@" prefix and a trailing ".git".
canonical_url() {
  local u=${1%.git}
  printf '%s' "${u/https:\/\/git::@/https://}"
}

git_row() {
  local dest="$TMUX_PLUGIN_DIR/$R_NAME" head origin
  case $R_NAME in *[!A-Za-z0-9._-]*) return 0 ;; esac
  case $R_VERSION in *[!0-9a-f]* | '')
    report FAIL tmux "$R_NAME: version must be a commit sha in tools.lock"
    return 0
    ;;
  esac
  if ! have git; then
    report FAIL tmux "$R_NAME: git is missing"
    return 0
  fi
  if [ -d "$dest/.git" ]; then
    origin=$(git -C "$dest" config --get remote.origin.url 2>/dev/null || true)
    if [ "$(canonical_url "$origin")" != "$R_URL" ]; then
      report FAIL tmux "$R_NAME: $(tilde "$dest") has origin '$origin', expected $R_URL; not touched"
      return 0
    fi
    head=$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)
    if [ "$head" = "$R_VERSION" ]; then
      report OK tmux "$R_NAME at ${R_VERSION:0:12}"
      return 0
    fi
  elif [ -e "$dest" ]; then
    backup "$dest"
  fi
  local depth=()
  if [ ! -d "$dest/.git" ]; then
    mkdir -p "$dest"
    git -C "$dest" -c init.defaultBranch=main init -q
    git -C "$dest" remote add origin "$R_URL"
    depth=(--depth 1)
  fi
  if ! git -C "$dest" cat-file -e "$R_VERSION^{commit}" 2>/dev/null &&
    ! git -C "$dest" fetch -q ${depth[@]+"${depth[@]}"} origin "$R_VERSION"; then
    report FAIL tmux "$R_NAME: fetching $R_VERSION from $R_URL failed"
    return 0
  fi
  if git -C "$dest" -c advice.detachedHead=false checkout -q --detach "$R_VERSION"; then
    changed "checked out $R_NAME at ${R_VERSION:0:12}"
    report OK tmux "$R_NAME at ${R_VERSION:0:12}"
  else
    report FAIL tmux "$R_NAME: checking out $R_VERSION failed (local changes in $(tilde "$dest")?)"
  fi
}

tmux_step() {
  step "tmux plugins"
  lock_rows git git_row
  ensure_dir "$HOME/.local/share/tmux/resurrect" 700
  report OK tmux "resurrect dir $(tilde "$HOME/.local/share/tmux/resurrect") mode 0700"
  if [ ! -f "$CONF_DIR/ssh-hosts" ]; then
    report SKIP tmux "no $(tilde "$CONF_DIR/ssh-hosts"): ssh panes show the host name; the file format is in tmux/scripts/ssh-colors.sh"
  fi
}
