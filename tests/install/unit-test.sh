#!/bin/bash
# Unit checks for single install.sh helpers, sourced from lib/ into a
# throwaway HOME. Fast, no network, no docker, no root.
#
#   tests/install/unit-test.sh
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd -P)
T=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-unit-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
# (lib/common.sh has its own FAILS counter, so this one has another name.)
TEST_FAILS=0
result() {
  if [ "$1" = 0 ]; then printf 'PASS %s\n' "$2"; else
    printf 'FAIL %s\n' "$2"
    TEST_FAILS=$((TEST_FAILS + 1))
  fi
}
# check NAME CMD... passes when CMD succeeds; check_not when it fails.
check() {
  local name=$1 rc=0
  shift
  ("$@") >/dev/null 2>&1 || rc=1
  result "$rc" "$name"
}
check_not() {
  local name=$1 rc=1
  shift
  ("$@") >/dev/null 2>&1 || rc=0
  result "$rc" "$name"
}

# The globals install.sh sets before it sources lib/.
# shellcheck disable=SC2034 # used by the sourced lib/*.sh
BIN_DIR="$HOME/.local/bin" OPT_DIR="$HOME/.local/opt" CONF_DIR="$HOME/.config/dotfiles"
# shellcheck disable=SC2034
NOTES_DIR="$HOME/notes" NVIM="$T/no-nvim" SHELL_RC=1 ORIG_PATH=$PATH
# shellcheck source=/dev/null
for f in common fetch notes links apt_extract; do . "$REPO/lib/$f.sh"; done

# --- notes: .gitignore without a final newline, absolute hooksPath --------
mkdir -p "$NOTES_DIR"
printf '*.swp' >"$NOTES_DIR/.gitignore"
notes_step >/dev/null 2>&1 || true
check "notes: existing last pattern kept intact" grep -qx '\*\.swp' "$NOTES_DIR/.gitignore"
check "notes: .scratch/ on its own line" grep -qx '\.scratch/' "$NOTES_DIR/.gitignore"
check "notes: hooksPath is absolute" test "$(git -C "$NOTES_DIR" config --local core.hooksPath)" = "$NOTES_DIR/.git/hooks"
check "notes: placeholder identity when none is set" test "$(git -C "$NOTES_DIR" config user.email)" = notes@localhost
before=$(cat "$NOTES_DIR/.gitignore")
CHANGES=0
notes_step >/dev/null 2>&1 || true
check "notes: second run changes nothing" test "$CHANGES" -eq 0 -a "$(cat "$NOTES_DIR/.gitignore")" = "$before"
git -C "$NOTES_DIR" worktree add -q "$T/wt" -b wt 2>/dev/null ||
  { git -C "$NOTES_DIR" commit -q --allow-empty --no-verify -m init && git -C "$NOTES_DIR" worktree add -q "$T/wt" -b wt; }
printf '#!/bin/sh\necho hook-ran >&2\nexit 1\n' >"$NOTES_DIR/.git/hooks/pre-commit"
check_not "notes: the hook also blocks commits in a linked worktree" \
  git -C "$T/wt" commit -q --allow-empty -m x

# --- shell rc: ZDOTDIR and metacharacters ----------------------------------
mkdir -p "$HOME/zdot"
: >"$HOME/zdot/.zshrc"
SHELL=/bin/zsh ZDOTDIR="$HOME/zdot" REPO="$REPO" shell_rc_step >/dev/null 2>&1
check "shell-rc: writes \$ZDOTDIR/.zshrc" grep -q 'shell/env.sh' "$HOME/zdot/.zshrc"
check "shell-rc: leaves ~/.zshrc alone with ZDOTDIR" test ! -e "$HOME/.zshrc"
: >"$HOME/.bashrc"
# shellcheck disable=SC2016 # a literal $( in the path is the test
SHELL=/bin/bash REPO="$T/evil\$(touch $T/pwned)" shell_rc_step >/dev/null 2>&1
check "shell-rc: refuses a repo path with shell metacharacters" test ! -s "$HOME/.bashrc"

# --- fetch: python3 refuses redirects to http ------------------------------
if have python3; then
  port_file="$T/port"
  python3 - "$port_file" <<'PY' &
import http.server, sys, threading
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/plain":  # the plain-http target serves content
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"plain")
            return
        self.send_response(302)
        self.send_header("Location", "http://127.0.0.1:%d/plain" % self.server.server_port)
        self.end_headers()
    def log_message(self, *a):
        pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_port))
threading.Timer(20, s.shutdown).start()
s.serve_forever()
PY
  server=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if [ -s "$port_file" ]; then break; fi
    sleep 0.2
  done
  fetch_tool() { echo python3; }
  check_not "fetch: python3 refuses a redirect to http" fetch_once "http://127.0.0.1:$(cat "$port_file")/x" "$T/dl"
  check "fetch: nothing written after the refusal" test ! -s "$T/dl"
  kill "$server" 2>/dev/null || true
  wait "$server" 2>/dev/null || true
fi

# --- apt_extract: refresh when apt has a newer version ----------------------
root="$OPT_DIR/apt/git"
mkdir -p "$root"
printf 'git 1:2.39.5-0+deb12u2\nlibfoo1 1.0\n' >"$root/.dotfiles-ok"
: >"$root/.dotfiles-missing"
# shellcheck disable=SC2329 # called by apt_candidate
apt-cache() { printf 'Package: git\nVersion: 1:2.39.5-0+deb12u3\n'; }
check "apt: stale when the candidate is newer" apt_stale git "$root"
apt-cache() { printf 'Package: git\nVersion: 1:2.39.5-0+deb12u2\n'; }
check_not "apt: current when the versions match" apt_stale git "$root"
printf ' libbar2' >"$root/.dotfiles-missing"
check "apt: stale when a library download failed last time" apt_stale git "$root"
printf 'git_1%%3a2.39.5_amd64.deb\n' >"$root/.dotfiles-ok"
: >"$root/.dotfiles-missing"
check "apt: old-format marker gets refreshed once" apt_stale git "$root"

if [ "$TEST_FAILS" -gt 0 ]; then
  echo "unit-test: $TEST_FAILS failed"
  exit 1
fi
echo "unit-test: all passed"
