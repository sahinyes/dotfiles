# Homebrew packages for the Mac. install.sh runs:
#   brew bundle install --no-upgrade --file Brewfile
# Homebrew does not pin versions; install.sh warns when they drift from tools.lock.
# (brew passes only HOMEBREW_* variables through, hence the names below.)
tier = ENV.fetch("HOMEBREW_DOTFILES_TIER", "dev")

# notes tier: editor, search, notes LSP, YAML/JSON, secret scanning, parser builds
brew "neovim"
brew "ripgrep"
brew "fd"
brew "fzf"
brew "marksman"
brew "yq"
brew "gitleaks"
brew "tree-sitter-cli"
brew "tmux"
brew "ncurses" # keg-only; scripts/terminfo-mac.sh compiles tmux-256color from it (undercurl)

# dev tier: shell/Lua/Python/Go tooling and Node for the servers in tools/npm
if tier == "dev"
  brew "shellcheck"
  brew "shfmt"
  brew "stylua"
  brew "lua-language-server"
  brew "ruff"
  brew "go"
  brew "gopls" # lsp.lua enables gopls only when it is on PATH
  brew "node"
  brew "pre-commit"
end

# install.sh sets HOMEBREW_DOTFILES_SKIP_FONT_CASK=1 with --no-fonts or when the
# font is already in a font folder (a second copy would make the cask fail).
cask "font-jetbrains-mono-nerd-font" unless ENV["HOMEBREW_DOTFILES_SKIP_FONT_CASK"] == "1"
