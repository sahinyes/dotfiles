#!/bin/bash
# Fix undercurl inside tmux on macOS.
#
# macOS ships ncurses 6.0 (2015), whose tmux-256color entry lacks Smulx, the
# capability Neovim needs for curly underlines inside tmux (it does not probe
# the terminal there). Homebrew's ncurses has a current entry. This script
# compiles that entry into ~/.terminfo, which ncurses and Neovim search first.
#
# Usage: scripts/terminfo-mac.sh [--dest DIR]   (default DIR: ~/.terminfo)
# Idempotent: does nothing when DIR already has a tmux-256color with Smulx.
set -euo pipefail

dest="$HOME/.terminfo"
while [ $# -gt 0 ]; do
    case "$1" in
    --dest)
        [ $# -ge 2 ] || {
            echo "terminfo-mac: --dest needs a directory" >&2
            exit 2
        }
        dest="$2"
        shift 2
        ;;
    -h | --help)
        sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "terminfo-mac: unknown option: $1" >&2
        exit 2
        ;;
    esac
done

if [ "$(uname -s)" != Darwin ]; then
    echo "terminfo-mac: macOS only (Debian's ncurses-base already has Smulx); nothing to do"
    exit 0
fi

# The system tools read what we write: -A reads only DIR, not the system db.
# (grep without -q reads all input: with pipefail, -q's early exit can
# SIGPIPE the writer and turn a match into a failure)
has_smulx() { /usr/bin/infocmp -x -A "$1" tmux-256color 2>/dev/null | grep 'Smulx=' >/dev/null; }

if has_smulx "$dest"; then
    echo "terminfo-mac: $dest already has tmux-256color with Smulx"
    exit 0
fi

ncurses=""
if command -v brew >/dev/null 2>&1; then
    ncurses="$(brew --prefix ncurses 2>/dev/null || true)"
fi
for d in "$ncurses" /opt/homebrew/opt/ncurses /usr/local/opt/ncurses; do
    if [ -n "$d" ] && [ -x "$d/bin/infocmp" ] && [ -d "$d/share/terminfo" ]; then
        ncurses="$d"
        break
    fi
    ncurses=""
done
if [ -z "$ncurses" ]; then
    echo "terminfo-mac: Homebrew ncurses not found; run: brew install ncurses" >&2
    exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# -A pins Homebrew's own database; otherwise TERMINFO_DIRS (set by iTerm2)
# would hand back the old system entry.
"$ncurses/bin/infocmp" -x -A "$ncurses/share/terminfo" tmux-256color >"$tmp/tmux-256color.src"
if ! grep -q 'Smulx=' "$tmp/tmux-256color.src"; then
    echo "terminfo-mac: Homebrew's tmux-256color has no Smulx; nothing compiled" >&2
    exit 1
fi

# Compile with the SYSTEM tic on purpose: Homebrew's tic writes the ncurses
# 6.1+ 32-bit format, which the system ncurses 6.0 used by zsh, less and
# tput cannot read, so every program in tmux would lose its TERM entry.
mkdir -p "$dest"
/usr/bin/tic -x -o "$dest" "$tmp/tmux-256color.src"

if has_smulx "$dest"; then
    echo "terminfo-mac: compiled tmux-256color with Smulx into $dest"
else
    echo "terminfo-mac: compiled entry in $dest has no Smulx; check $dest" >&2
    exit 1
fi
