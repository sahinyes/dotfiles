#!/bin/bash
# Tests "install.sh trust-key", the verified-checkout gate and "install.sh
# update" on a throwaway repository signed with a throwaway SSH key.
# Everything happens in a temp dir with its own HOME and no global git config;
# install.sh only ever runs with --dry-run or stops at the gate, so nothing
# is installed. Needs git >= 2.34 and ssh-keygen (macOS or Linux).
#
#   tests/install/release-test.sh
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd -P)
T=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-release-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
FAILS=0

pass() { printf 'PASS %s\n' "$*"; }
fail() {
  printf 'FAIL %s\n' "$*"
  FAILS=$((FAILS + 1))
}
# expect_ok NAME CMD... / expect_fail NAME CMD...: the output of CMD lands in
# $T/out once CMD has finished, so the next check can grep it.
expect_ok() {
  local name=$1 rc=0
  shift
  "$@" >"$T/out.new" 2>&1 || rc=$?
  mv -f "$T/out.new" "$T/out"
  if [ "$rc" -eq 0 ]; then pass "$name"; else fail "$name: $(tail -n 3 "$T/out")"; fi
}
expect_fail() {
  local name=$1 rc=0
  shift
  "$@" >"$T/out.new" 2>&1 || rc=$?
  mv -f "$T/out.new" "$T/out"
  if [ "$rc" -ne 0 ]; then pass "$name"; else fail "$name (it succeeded)"; fi
}
g() { git -c user.name=test -c user.email=test -c gpg.format=ssh "$@"; }

# Two throwaway keys: the release key and an impostor.
ssh-keygen -q -t ed25519 -N '' -C release-test -f "$T/key"
ssh-keygen -q -t ed25519 -N '' -C impostor -f "$T/other"
fp=$(ssh-keygen -lf "$T/key.pub" | awk '{print $2}')

# "origin": this working tree with the test key as signing_key.pub.
mkdir "$T/origin"
tar -C "$REPO" --exclude=./.git --exclude=./tools/npm/node_modules --exclude=./nvim/lua/local.lua -cf - . |
  tar -C "$T/origin" -xf -
cp "$T/key.pub" "$T/origin/signing_key.pub"
g -C "$T/origin" init -q -b main
g -C "$T/origin" add -A
g -C "$T/origin" commit -q -m release
g -C "$T/origin" -c user.signingkey="$T/key" tag -s -m v1.0.0 v1.0.0

git clone -q --depth 1 --branch v1.0.0 "file://$T/origin" "$T/clone" 2>/dev/null
C="$T/clone"

expect_fail "trust-key refuses a wrong fingerprint" "$C/install.sh" trust-key SHA256:wrongwrongwrong
expect_fail "no allowed_signers after a refused key" test -e "$HOME/.config/dotfiles/allowed_signers"
expect_fail "real run refuses before trust-key" "$C/install.sh" --no-fonts
expect_ok "trust-key accepts the right fingerprint" "$C/install.sh" trust-key "$fp"
expect_ok "trust-key verified the tag" grep -q 'good signature' "$T/out"
expect_ok "allowed_signers written" test -s "$HOME/.config/dotfiles/allowed_signers"
expect_ok "repo points git at allowed_signers" git -C "$C" config --get gpg.ssh.allowedSignersFile
expect_ok "dry run shows the verified tag" "$C/install.sh" --dry-run
expect_ok "dry run output says 'signature verified'" grep -q 'v1.0.0 (signature verified)' "$T/out"

printf 'x\n' >"$C/untracked-file"
expect_fail "real run refuses a modified checkout" "$C/install.sh" --no-fonts
expect_ok "the refusal names the local changes" grep -q 'local changes' "$T/out"
expect_fail "nothing was installed by the refused run" test -e "$HOME/.local"
rm -f "$C/untracked-file"

# An unsigned tag, then a tag signed by the impostor: both refused.
printf 'change 1\n' >>"$T/origin/README-test"
g -C "$T/origin" add -A
g -C "$T/origin" commit -q -m unsigned
g -C "$T/origin" tag -a -m v1.0.1 v1.0.1
before=$(git -C "$C" rev-parse HEAD)
expect_fail "update refuses an unsigned tag" "$C/install.sh" update v1.0.1 --dry-run
expect_ok "HEAD unchanged after the refused update" test "$(git -C "$C" rev-parse HEAD)" = "$before"
g -C "$T/origin" -c user.signingkey="$T/other" tag -s -m v1.0.2 v1.0.2
expect_fail "update refuses a tag signed by another key" "$C/install.sh" update v1.0.2 --dry-run
expect_ok "HEAD still unchanged" test "$(git -C "$C" rev-parse HEAD)" = "$before"

# A properly signed release: update fetches, verifies, checks out, re-runs.
printf 'change 2\n' >>"$T/origin/README-test"
g -C "$T/origin" add -A
g -C "$T/origin" commit -q -m release2
g -C "$T/origin" -c user.signingkey="$T/key" tag -s -m v1.0.3 v1.0.3
expect_ok "update accepts a signed tag" "$C/install.sh" update v1.0.3 --dry-run
expect_ok "update re-ran install.sh from the new tag" grep -q 'dry run: nothing was changed' "$T/out"
expect_ok "HEAD is at v1.0.3" test "$(git -C "$C" rev-parse HEAD)" = "$(git -C "$T/origin" rev-parse 'v1.0.3^{commit}')"
expect_fail "update rejects a malformed tag name" "$C/install.sh" update 'v1.0.3;id' --dry-run

if [ "$FAILS" -gt 0 ]; then
  echo "release-test: $FAILS failed"
  exit 1
fi
echo "release-test: all passed"
