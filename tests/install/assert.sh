#!/bin/bash
# Checks after two install.sh runs (inside the test container, see run.sh).
# Expectations come from run.sh: EXPECT_TS (on|off), EXPECT_TS_REASON,
# EXPECT_GIT (system|apt), and the exit codes RC1/RC2 of the two runs.
set -uo pipefail

export PATH="$HOME/.local/bin:$PATH"
REPO="$HOME/dotfiles"
REPORT="$HOME/.local/state/dotfiles/last-install.txt"
NVIM="$HOME/.local/bin/nvim"
FAILS=0

pass() { printf 'PASS %s\n' "$*"; }
fail() {
  printf 'FAIL %s\n' "$*"
  FAILS=$((FAILS + 1))
}
# check NAME CMD...: pass when CMD succeeds.
check() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi
}
# nvim_lua CODE: run CODE headless with the full config, print its output.
nvim_lua() {
  (cd "$HOME" && NVIM_OFFLINE=1 "$NVIM" --headless -i NONE -c "lua $1" -c 'qa!' </dev/null 2>&1)
}

check "dry run changed nothing in \$HOME" test ! -s /tmp/dry.diff
check "dry run printed the plan" grep -q 'dry run: nothing was changed' /tmp/dry.log
check "run 1 exited 0 (was ${RC1:-?})" test "${RC1:-1}" = 0
check "run 2 exited 0 (was ${RC2:-?})" test "${RC2:-1}" = 0
check "run 2 reports no changes" grep -q '^changes: 0' "$HOME/run2.log"
check "run 2 downloads nothing" test -z "$(grep 'downloading' "$HOME/run2.log")"

# nvim and tools
check "nvim is v0.12.5" test "$("$NVIM" --version | head -n 1)" = "NVIM v0.12.5"
check "nvim linked from ~/.local/opt" test -L "$NVIM"
for t in rg fd fzf yq gitleaks marksman; do
  check "$t runs" "$t" --version
done
check "marksman runs through the no-ICU wrapper" grep -q DOTNET_SYSTEM_GLOBALIZATION_INVARIANT "$HOME/.local/bin/marksman"

# apt_extract
check "wl-copy present and runs" wl-copy --version
check "tmux runs" tmux -V
case ${EXPECT_GIT:-system} in
  apt)
    check "git comes from apt_extract" grep -q apt_extract "$HOME/.local/bin/git"
    check "git (apt_extract) runs" git --version
    check "git (apt_extract) can ls-remote over https" git ls-remote https://github.com/tmux-plugins/tmux-resurrect HEAD
    ;;
  *) check "git is the system package" test "$(command -v git)" = /usr/bin/git ;;
esac

# plugins: every lockfile plugin at its revision, nothing extra
lock="$REPO/nvim/nvim-pack-lock.json"
opt="$HOME/.local/share/nvim/site/pack/core/opt"
want=$(awk -F'"' '/^    "[^"]+": \{/ { n = $2 } /^      "rev":/ { print n, $4 }' "$lock")
total=$(printf '%s\n' "$want" | grep -c .)
good=0
while read -r name rev; do
  if [ "$(git -C "$opt/$name" rev-parse HEAD 2>/dev/null)" = "$rev" ]; then good=$((good + 1)); fi
done <<EOF
$want
EOF
check "plugins at lockfile revisions ($good/$total)" test "$good" -eq "$total" -a "$total" -gt 0
check "no plugins beyond the lockfile" test "$(find "$opt" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq "$total"
check "lockfile unchanged by the install" cmp -s "$lock" /src/nvim/nvim-pack-lock.json

# machine files
check "config link nvim points to the repo" test "$(readlink "$HOME/.config/nvim")" = "$REPO/nvim"
check "config link nvim-untrusted points to the repo" test "$(readlink "$HOME/.config/nvim-untrusted")" = "$REPO/nvim"
check "work marker exists (Linux default)" test -e "$HOME/.config/dotfiles/work"
check "local.lua written" grep -q '^vim.g.work_laptop = true' "$REPO/nvim/lua/local.lua"
check "local.lua has have_nerd_font = true" grep -q '^vim.g.have_nerd_font = true' "$REPO/nvim/lua/local.lua"
check "Nerd Font visible to fontconfig" sh -c "fc-list | grep -q 'JetBrainsMono Nerd Font Mono'"
for f in de.utf-8.spl de.utf-8.sug en.utf-8.sug tr.utf-8.spl; do
  check "spell file $f" test -s "$HOME/.local/share/nvim/site/spell/$f"
done
for p in tmux-resurrect tmux-continuum; do
  rev=$(awk -v n="$p" '$1 == n { print $2 }' "$REPO/tools.lock")
  check "$p at pinned commit" test "$(git -C "$HOME/.tmux/plugins/$p" rev-parse HEAD)" = "$rev"
done
check "resurrect dir is 0700" test "$(stat -c %a "$HOME/.local/share/tmux/resurrect")" = 700

# notes
check "notes: is a git repo" test -d "$HOME/notes/.git"
check "notes: daily/ exists" test -d "$HOME/notes/daily"
check "notes: ignores .scratch/" grep -qx '.scratch/' "$HOME/notes/.gitignore"
check "notes: inbox.md seeded" grep -q '^project: inbox' "$HOME/notes/inbox.md"
check "pre-commit hook is executable" test -x "$HOME/notes/.git/hooks/pre-commit"
# Without gitleaks on PATH (and no ~/.local/bin) the hook must refuse.
if (cd "$HOME/notes" && env -i HOME=/nonexistent PATH=/usr/bin:/bin sh .git/hooks/pre-commit) >/dev/null 2>&1; then
  fail "pre-commit hook fails closed without gitleaks"
else
  pass "pre-commit hook fails closed without gitleaks"
fi
# commit_in_notes FILE CONTENT: try to commit FILE to ~/notes (test identity).
commit_in_notes() {
  (
    cd "$HOME/notes" || exit 1
    printf '%s\n' "$2" >"$1"
    git add "$1"
    if git -c user.name=test -c user.email=test -c commit.gpgsign=false commit -q -m test >/dev/null 2>&1; then
      exit 0
    fi
    git reset -q HEAD "$1"
    rm -f "$1"
    exit 1
  )
}
check "hook lets a normal note commit through" commit_in_notes task-test.md '- [ ] plain task'
# A token-shaped value generated now, so no secret-like literal is in the repo.
token="ghp_$(head -c 400 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 36)"
if commit_in_notes leak-test.md "github_token = \"$token\""; then
  fail "hook blocks a commit with a token"
else
  pass "hook blocks a commit with a token"
fi
trusted=$(nvim_lua 'io.stdout:write(tostring(require("sahin.trust").is_trusted(vim.fn.expand("~/notes"))))')
check "notes: trusted (sahin.trust.is_trusted: $trusted)" test "$trusted" = true

# treesitter
if [ "${EXPECT_TS:-off}" = on ]; then
  for lang in yaml json bash python go typescript http diff; do
    check "parser $lang.so built" test -s "$HOME/.local/share/nvim/site/parser/$lang.so"
  done
  out=$(nvim_lua 'local ok = pcall(vim.treesitter.language.add, "yaml")
    local q = ok and vim.treesitter.query.get("typescript", "highlights")
    io.stdout:write(tostring(ok and q ~= nil))')
  check "nvim loads the yaml parser and typescript queries (got: $out)" test "$out" = true
else
  check "report says treesitter OFF: ${EXPECT_TS_REASON:-}" \
    sh -c "grep '^OFF   treesitter' '$REPORT' | grep -q '${EXPECT_TS_REASON:-}'"
fi

# report and a clean start
check "report saved" test -s "$REPORT"
bad=$(sed '1d' "$REPORT" | grep -v -E '^(OK|SKIP|OFF|WARN|FAIL) +[a-z.]+ +[^ ].+|^changes: |^result: ' || true)
check "every report line has a status, an area and a reason" test -z "$bad"
check "report has no FAIL lines" test -z "$(grep '^FAIL' "$REPORT")"
out=$(cd "$HOME" && "$NVIM" --headless -i NONE -c 'qa!' </dev/null 2>&1)
check "nvim --headless starts without output (got: ${out:0:200})" test -z "$out"

echo "---- report"
cat "$REPORT"
if [ "$FAILS" -gt 0 ]; then
  echo "assertions: $FAILS failed"
  exit 1
fi
echo "assertions: all passed"
