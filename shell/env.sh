# shellcheck shell=sh
# Shell environment for this setup. Sourced by ~/.zshrc or ~/.bashrc
# (install.sh --shell-rc adds that one line). POSIX sh: works in zsh and bash.

# ~/.local/bin first, so the pinned nvim and tools win over older system
# packages (Debian's apt nvim is 0.7/0.10). Sourcing twice adds nothing.
case $PATH in
  "$HOME/.local/bin" | "$HOME/.local/bin":*) ;;
  *) PATH="$HOME/.local/bin:$PATH" && export PATH ;;
esac

# n: short for nvim.
alias n='nvim'
# nn: Neovim in ~/notes, straight into the note picker (same as Space n n).
nn() {
  (
    cd "$HOME/notes" || exit
    nvim -c 'lua require("sahin.notes.pickers").find_notes()'
  )
}

# nvu: Neovim for untrusted material (no plugins, LSP, notes, netrw, gzip).
alias nvu='NVIM_APPNAME=nvim-untrusted nvim'
# nvr0: one file, read-only, no config, no plugins, no shada, no modelines.
alias nvr0="nvim -u NONE -i NONE -n -R --cmd 'set nomodeline'"

# Set on the work laptop (install.sh creates the marker file there).
if [ -e "$HOME/.config/dotfiles/work" ]; then
  DOTFILES_WORK=1
  export DOTFILES_WORK
fi
