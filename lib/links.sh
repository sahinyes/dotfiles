# shellcheck shell=bash
# Symlinks from $HOME into the repo. A real file or directory in the way is
# moved to ~/.dotfiles-backup/<timestamp>/ first; nothing is deleted.

links_step() {
  step "symlinks"
  local made=
  link "$REPO/nvim" "$HOME/.config/nvim"
  link "$REPO/nvim" "$HOME/.config/nvim-untrusted"
  made="$(tilde "$HOME/.config/nvim") $(tilde "$HOME/.config/nvim-untrusted")"
  if [ -f "$REPO/tmux/tmux.conf" ]; then
    link "$REPO/tmux/tmux.conf" "$HOME/.tmux.conf"
    # The old standalone config would be confusing next to the linked one.
    if [ -f "$HOME/.tmux/tmux.conf" ] && [ ! -L "$HOME/.tmux/tmux.conf" ]; then
      backup "$HOME/.tmux/tmux.conf"
    fi
    made="$made $(tilde "$HOME/.tmux.conf")"
  else
    report WARN links "tmux/tmux.conf is missing in the repo, so ~/.tmux.conf was not linked"
  fi
  if [ -d "$REPO/tmux/scripts" ]; then
    link "$REPO/tmux/scripts" "$HOME/.tmux/scripts"
    made="$made $(tilde "$HOME/.tmux/scripts")"
  fi
  report OK links "$made -> repo${BACKUP_DIR:+ (replaced files are in $(tilde "$BACKUP_DIR"))}"
}

# shell_rc_step: new shells need ~/.local/bin first on PATH. With --shell-rc,
# append one marked line that sources shell/env.sh to ~/.zshrc or ~/.bashrc.
# Only that marked line is searched for; the rest of the file is never read
# or printed.
shell_rc_step() {
  local rc src mark="# added by dotfiles install.sh"
  case ${SHELL##*/} in
    zsh) rc="$HOME/.zshrc" ;;
    bash) rc="$HOME/.bashrc" ;;
    *) rc= ;;
  esac
  if [ -n "$rc" ] && [ -f "$rc" ] && grep -qF -- "$mark" "$rc"; then
    report OK shell "$(tilde "$rc") sources shell/env.sh"
    return 0
  fi
  if [ "$SHELL_RC" != 1 ]; then
    case $ORIG_PATH in
      "$BIN_DIR":*) report OK shell "PATH already starts with ~/.local/bin" ;;
      *) report WARN shell "new shells do not put ~/.local/bin first on PATH: re-run with --shell-rc (or source shell/env.sh yourself)" ;;
    esac
    return 0
  fi
  if [ -z "$rc" ]; then
    report WARN shell "--shell-rc supports zsh and bash, not ${SHELL:-unknown}: source shell/env.sh yourself"
    return 0
  fi
  src="$REPO/shell/env.sh"
  case $src in "$HOME"/*) src="\$HOME/${src#"$HOME"/}" ;; esac
  if [ -f "$rc" ]; then backup_copy "$rc"; fi
  printf '\n[ -r "%s" ] && source "%s" %s\n' "$src" "$src" "$mark" >>"$rc"
  changed "appended one line to $(tilde "$rc")${BACKUP_DIR:+ (old copy in $(tilde "$BACKUP_DIR"))}"
  report OK shell "$(tilde "$rc") now sources shell/env.sh (takes effect in new shells)"
}
