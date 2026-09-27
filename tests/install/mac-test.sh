#!/bin/bash
# Runs install.sh twice on this Mac against a throwaway HOME and checks that
# the second run changes nothing. It uses a copy of the repo and a brew shim
# that refuses "brew bundle install", so the real Homebrew, ~/.config,
# ~/.local and ~/notes are never touched. Needs network (plugins, npm, parsers).
#
#   tests/install/mac-test.sh
#
# DOTFILES_TEST_CACHE (optional): a download cache dir to reuse; every file
# is still sha256-checked. KEEP=1 keeps the temp dir for inspection.
set -euo pipefail

[ "$(uname -s)" = Darwin ] || {
  echo "mac-test: macOS only" >&2
  exit 2
}
REPO=$(cd "$(dirname "$0")/../.." && pwd -P)
REAL_BREW=$(command -v brew) || {
  echo "mac-test: Homebrew is required" >&2
  exit 2
}
T=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-mac-test.XXXXXX")
if [ "${KEEP:-0}" != 1 ]; then trap 'rm -rf "$T"' EXIT; fi
FAILS=0

pass() { printf 'PASS %s\n' "$*"; }
fail() {
  printf 'FAIL %s\n' "$*"
  FAILS=$((FAILS + 1))
}
check() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi
}

# Throwaway HOME and a copy of the working tree.
export HOME="$T/home" SHELL=/bin/zsh
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME NVIM_APPNAME
mkdir -p "$HOME" "$T/dotfiles" "$T/shim"
tar -C "$REPO" --exclude=./.git --exclude=./tools/npm/node_modules --exclude=./nvim/lua/local.lua -cf - . |
  tar -C "$T/dotfiles" -xf -
if [ -n "${DOTFILES_TEST_CACHE:-}" ]; then
  mkdir -p "$HOME/.cache"
  ln -s "$DOTFILES_TEST_CACHE" "$HOME/.cache/dotfiles"
fi
# shellcheck disable=SC2016 # the line is written literally, like a user's own
printf 'export PATH="$HOME/bin:$PATH" # pre-existing user line\n' >"$HOME/.zshrc"

# brew shim: read-only brew commands pass through, installs are refused.
cat >"$T/shim/brew" <<EOF
#!/bin/bash
if [ "\${1:-}" = bundle ] && [ "\${2:-}" = install ]; then
  echo "mac-test: refusing brew bundle install (it would change the real Homebrew)" >&2
  exit 1
fi
exec '$REAL_BREW' "\$@"
EOF
chmod +x "$T/shim/brew"
export PATH="$T/shim:$PATH"

rc1=0
"$T/dotfiles/install.sh" --dev --shell-rc >"$T/run1.log" 2>&1 || rc1=$?
rc2=0
"$T/dotfiles/install.sh" --dev --shell-rc >"$T/run2.log" 2>&1 || rc2=$?
echo "### run 2 report"
sed -n '/^== dotfiles/,$p' "$T/run2.log"

check "run 1 exited 0 (was $rc1)" test "$rc1" = 0
check "run 2 exited 0 (was $rc2)" test "$rc2" = 0
check "run 2 reports no changes" grep -q '^changes: 0' "$T/run2.log"
check "report has no FAIL lines" test -z "$(grep '^FAIL' "$HOME/.local/state/dotfiles/last-install.txt")"
check "config link points to the copy" test "$(readlink "$HOME/.config/nvim")" = "$(cd "$T/dotfiles" && pwd -P)/nvim"
check "local.lua: not the work laptop" grep -q '^vim.g.work_laptop = false' "$T/dotfiles/nvim/lua/local.lua"
check "no work marker on the Mac" test ! -e "$HOME/.config/dotfiles/work"
check ".zshrc got exactly one env.sh line" test "$(grep -c 'added by dotfiles install.sh' "$HOME/.zshrc")" = 1
check ".zshrc kept its own line" grep -q 'pre-existing user line' "$HOME/.zshrc"
for b in yaml-language-server vscode-json-language-server bash-language-server basedpyright-langserver tsc; do
  check "$b linked into ~/.local/bin" test -x "$HOME/.local/bin/$b"
done
check "tsc is TypeScript 7" sh -c "'$HOME/.local/bin/tsc' --version | grep -q 'Version 7'"
for lang in yaml json bash python go typescript http diff; do
  check "parser $lang.so built" test -s "$HOME/.local/share/nvim/site/parser/$lang.so"
done
opt="$HOME/.local/share/nvim/site/pack/core/opt"
lock="$T/dotfiles/nvim/nvim-pack-lock.json"
want=$(awk -F'"' '/^    "[^"]+": \{/ { n = $2 } /^      "rev":/ { print n, $4 }' "$lock")
good=0 total=0
while read -r name rev; do
  total=$((total + 1))
  if [ "$(git -C "$opt/$name" rev-parse HEAD 2>/dev/null)" = "$rev" ]; then good=$((good + 1)); fi
done <<EOF
$want
EOF
check "plugins at lockfile revisions ($good/$total)" test "$good" -eq "$total" -a "$total" -gt 0
check "notes: git repo with the hook" test -x "$HOME/notes/.git/hooks/pre-commit"
check "tmux-resurrect cloned" test -d "$HOME/.tmux/plugins/tmux-resurrect/.git"
# brewfile_has ENTRY [VAR=VALUE...]: true when the Brewfile lists ENTRY.
brewfile_has() {
  local entry=$1
  shift
  env HOMEBREW_NO_AUTO_UPDATE=1 "$@" brew bundle list --all --file "$T/dotfiles/Brewfile" | grep -qx "$entry"
}
check "Brewfile: dev tier has node" brewfile_has node
check "Brewfile: notes tier has no node" test ! "$(brewfile_has node HOMEBREW_DOTFILES_TIER=notes && echo yes)"
check "Brewfile: font cask can be skipped" test ! "$(brewfile_has font-jetbrains-mono-nerd-font HOMEBREW_DOTFILES_SKIP_FONT_CASK=1 && echo yes)"

if [ "$FAILS" -gt 0 ]; then
  echo "mac-test: $FAILS failed (logs: $T/run1.log $T/run2.log; KEEP=1 keeps them)"
  exit 1
fi
echo "mac-test: all passed"
