#!/bin/bash
# install.sh: set up Neovim, its tools and ~/notes from this repo, on macOS
# and on Debian 12/13 without root. Read it (and lib/*.sh) before running it:
#   less install.sh lib/*.sh
#
# What it never does: use sudo, pipe a download into a shell, run a download
# before its sha256 matched tools.lock, or overwrite a file without moving
# the old one to ~/.dotfiles-backup/<timestamp>/ first. It is safe to re-run;
# a second run changes nothing and says so ("changes: 0").
#
# Usage:
#   ./install.sh [flags]                  install or repair
#   ./install.sh trust-key SHA256:<fp>    pin the release signing key (once per machine)
#   ./install.sh update vX.Y.Z [flags]    fetch, verify and install a signed release
#
# Flags:
#   --dry-run         show what was detected and the plan; change nothing
#   --dev             allow an unsigned or modified checkout (development, tests)
#   --tier notes|dev  default: dev on macOS, notes on Linux (Linux: notes only)
#   --no-fonts        skip the Nerd Font
#   --no-terminal     skip terminfo / GNOME Terminal setup
#   --work            mark this machine as the work laptop (default on Linux)
#   --no-work         remove that mark (default on macOS)
#   --shell-rc        add one line to ~/.zshrc or ~/.bashrc that sources shell/env.sh
#   --osc52           print how to allow OSC 52 clipboard writes in iTerm2 (changes nothing)
#   -h, --help        show this help
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd -P)

# Paths (XDG defaults, as Neovim uses them).
BIN_DIR="$HOME/.local/bin"
OPT_DIR="$HOME/.local/opt"
FONT_DIR="$HOME/.local/share/fonts"
STATE_DIR="$HOME/.local/state/dotfiles"
CONF_DIR="$HOME/.config/dotfiles"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
NVIM_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
PLUGIN_DIR="$NVIM_DATA/site/pack/core/opt"
TMUX_PLUGIN_DIR="$HOME/.tmux/plugins"
NOTES_DIR="$HOME/notes"
WORK_MARKER="$CONF_DIR/work"

# The steps live in lib/, one file per topic. Read them too.
# shellcheck source-path=SCRIPTDIR
. "$REPO/lib/common.sh"      # output, report, backups, symlinks
. "$REPO/lib/fetch.sh"       # downloads: curl, wget or python3
. "$REPO/lib/verify.sh"      # sha256 checks
. "$REPO/lib/detect.sh"      # what this machine has
. "$REPO/lib/release.sh"     # signed tags: trust-key, update, checkout check
. "$REPO/lib/links.sh"       # symlinks into $HOME, --shell-rc
. "$REPO/lib/brew.sh"        # macOS: Brewfile
. "$REPO/lib/tools.sh"       # tools.lock rows
. "$REPO/lib/nvim.sh"        # Neovim itself
. "$REPO/lib/apt_extract.sh" # Debian packages without root
. "$REPO/lib/fonts.sh"       # Nerd Font
. "$REPO/lib/spell.sh"       # spell files
. "$REPO/lib/parsers.sh"     # treesitter parsers
. "$REPO/lib/terminal.sh"    # terminfo / GNOME Terminal
. "$REPO/lib/tmux.sh"        # tmux plugins at pinned commits
. "$REPO/lib/machine.sh"     # work marker, nvim/lua/local.lua
. "$REPO/lib/notes.sh"       # ~/notes
. "$REPO/lib/plugins.sh"     # vim.pack plugins
. "$REPO/lib/npm.sh"         # macOS: Node language servers
. "$REPO/lib/check.sh"       # verification and the report

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

# Flags (set by parse_flags).
DRY_RUN=0 DEV=0 TIER='' NO_FONTS=0 NO_TERMINAL=0 WORK_FLAG='' SHELL_RC=0 OSC52=0

parse_flags() {
  while [ $# -gt 0 ]; do
    case $1 in
      --dry-run) DRY_RUN=1 ;;
      --dev) DEV=1 ;;
      --tier)
        [ $# -ge 2 ] || die "--tier needs notes or dev"
        TIER=$2
        shift
        ;;
      --tier=*) TIER=${1#--tier=} ;;
      --no-fonts) NO_FONTS=1 ;;
      --no-terminal) NO_TERMINAL=1 ;;
      --work) WORK_FLAG=1 ;;
      --no-work) WORK_FLAG=0 ;;
      --shell-rc) SHELL_RC=1 ;;
      --osc52) OSC52=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) die "unknown argument: $1 (see ./install.sh --help)" ;;
    esac
    shift
  done
  case $TIER in '' | notes | dev) ;; *) die "--tier must be notes or dev" ;; esac
}

# Decide the tier and the work mark from the flags and what was detected.
decide() {
  if [ "$OS" = linux ] && [ "$TIER" = dev ]; then
    die "--tier dev is macOS only: Node/Go language servers are out of scope on Linux (use --tier notes)"
  fi
  case $OS in darwin | linux) ;; *) die "unsupported OS: $OS" ;; esac
  if [ -n "$WORK_FLAG" ]; then
    WORK=$WORK_FLAG
  elif [ "$WORK_NOW" = yes ] || [ "$OS" = linux ]; then
    WORK=1
  else
    WORK=0
  fi
}

# plan_line TEXT: one numbered line of the plan.
PLAN_N=0
plan_line() {
  PLAN_N=$((PLAN_N + 1))
  printf '  %2d %s\n' "$PLAN_N" "$*"
}

plan_print() {
  local ts
  ts=$(ts_blocker plan)
  say ""
  say "== plan (every step checks first and changes only what differs)"
  plan_line "symlinks     ~/.config/nvim, ~/.config/nvim-untrusted, ~/.tmux.conf, ~/.tmux/scripts -> repo"
  if [ "$OS" = darwin ]; then
    plan_line "homebrew     brew bundle install --no-upgrade (Brewfile, tier $TIER)"
  else
    plan_line "neovim       release tarball (tools.lock) -> ~/.local/opt, ~/.local/bin/nvim"
    plan_line "tools        tools.lock rows for linux/$ARCH -> ~/.local/opt, ~/.local/bin"
    plan_line "apt_extract  git, tmux, wl-clipboard when missing (apt-get download, no root)"
  fi
  if [ "$NO_FONTS" = 1 ]; then
    plan_line "fonts        skipped (--no-fonts)"
  else
    plan_line "fonts        JetBrainsMono Nerd Font (installed now: $NERD_FONT)"
  fi
  plan_line "spell        de/en/tr spell files -> $(tilde "$NVIM_DATA/site/spell")"
  if [ -n "$ts" ]; then
    plan_line "treesitter   OFF: $ts"
  else
    plan_line "treesitter   build the ts-parser rows with tree-sitter build"
  fi
  if [ "$NO_TERMINAL" = 1 ]; then
    plan_line "terminal     skipped (--no-terminal)"
  else
    plan_line "terminal     terminfo (macOS) or GNOME Terminal profile (Linux, if GNOME)"
  fi
  plan_line "tmux         tmux-resurrect, tmux-continuum at pinned commits; resurrect dir 0700"
  if [ "$WORK" = 1 ]; then
    plan_line "machine      work-laptop marker on; nvim/lua/local.lua only if missing"
  else
    plan_line "machine      work-laptop marker off; nvim/lua/local.lua only if missing"
  fi
  plan_line "notes        ~/notes: git, gitleaks pre-commit hook, .gitignore, inbox.md, trust"
  plan_line "plugins      vim.pack sync to nvim/nvim-pack-lock.json when anything differs"
  if [ "$OS" = darwin ] && [ "$TIER" = dev ]; then
    plan_line "npm          tools/npm: npm ci --ignore-scripts, audit signatures, link servers"
  fi
  if [ "$SHELL_RC" = 1 ]; then
    plan_line "shell        append the shell/env.sh line to your rc file (--shell-rc)"
  else
    plan_line "shell        check only (--shell-rc appends the shell/env.sh line)"
  fi
  plan_line "verify       nvim --headless starts clean, tests/smoke.lua, report"
  if [ "$NET" != online ]; then say "  !! network is $NET: a real run needs https://github.com/"; fi
}

main() {
  case ${1:-} in
    trust-key)
      shift
      trust_key_cmd "$@"
      exit 0
      ;;
    update)
      shift
      local tag=${1:-}
      [ $# -gt 0 ] && shift
      parse_flags "$@"
      update_cmd "$tag" "$@"
      ;;
  esac
  parse_flags "$@"

  # Preflight: our own bin dir first, and one Neovim profile only.
  ORIG_PATH=$PATH
  export PATH="$BIN_DIR:$PATH"
  unset NVIM_APPNAME

  detect
  decide
  detect_print
  plan_print
  if [ "$DRY_RUN" = 1 ]; then
    say ""
    say "dry run: nothing was changed."
    exit 0
  fi
  require_verified_checkout
  [ "$NET" = online ] || die "https://github.com/ is not reachable; this install needs it"

  ensure_dir "$BIN_DIR"
  ensure_dir "$OPT_DIR"
  links_step
  if [ "$OS" = darwin ]; then brew_step; fi
  nvim_step
  tools_step
  apt_step
  fonts_step
  spell_step
  parsers_step
  terminal_step
  tmux_step
  work_step
  local_lua_step
  notes_step
  plugins_step
  npm_step
  shell_rc_step
  verify_step
  report_finish
  [ "$FAILS" -eq 0 ]
}

main "$@"
