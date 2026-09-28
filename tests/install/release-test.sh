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

# A signed release previewed with --dry-run: verified, nothing checked out.
printf 'change 2\n' >>"$T/origin/README-test"
g -C "$T/origin" add -A
g -C "$T/origin" commit -q -m release2
g -C "$T/origin" -c user.signingkey="$T/key" tag -s -m v1.0.3 v1.0.3
expect_ok "update --dry-run accepts a signed tag" "$C/install.sh" update v1.0.3 --dry-run
expect_ok "the dry run reports a good signature" grep -q 'v1.0.3 has a good signature' "$T/out"
expect_ok "HEAD unchanged after the dry run" test "$(git -C "$C" rev-parse HEAD)" = "$before"
expect_fail "the dry run stored no tag" git -C "$C" rev-parse -q --verify refs/tags/v1.0.3
expect_fail "no candidate ref is left behind" git -C "$C" rev-parse -q --verify refs/dotfiles/candidate
expect_fail "update rejects a malformed tag name" "$C/install.sh" update 'v1.0.3;id' --dry-run

# Replay: a new tag name pointing at the old, validly signed v1.0.0 object.
git -C "$T/origin" update-ref refs/tags/v1.0.4 "$(git -C "$T/origin" rev-parse v1.0.0)"
expect_fail "update refuses an old signed tag under a new name" "$C/install.sh" update v1.0.4 --dry-run
expect_ok "the refusal names the replay" grep -q 'is named v1.0.0' "$T/out"

# OpenPGP: even a gpg that answers GOODSIG for anything must not vouch for a tag.
mkdir "$T/fakebin"
cat >"$T/fakebin/gpg" <<'EOF'
#!/bin/sh
printf '\n[GNUPG:] NEWSIG\n[GNUPG:] GOODSIG 0000000000000000 attacker\n'
printf '[GNUPG:] VALIDSIG 00 2026-01-01 0 0 0 0 0 0 00\n[GNUPG:] TRUST_ULTIMATE 0 pgp\n'
exit 0
EOF
chmod +x "$T/fakebin/gpg"
pgp_tag=$(printf 'object %s\ntype commit\ntag v1.0.5\ntagger test <test> 1790000000 +0000\n\nv1.0.5\n-----BEGIN PGP SIGNATURE-----\n\nZmFrZQ==\n-----END PGP SIGNATURE-----\n' \
  "$(git -C "$T/origin" rev-parse HEAD)" | git -C "$T/origin" mktag)
git -C "$T/origin" update-ref refs/tags/v1.0.5 "$pgp_tag"
expect_ok "setup: plain git verify-tag trusts the stub gpg" env PATH="$T/fakebin:$PATH" git -C "$T/origin" verify-tag v1.0.5
expect_fail "update refuses an OpenPGP-signed tag" env PATH="$T/fakebin:$PATH" "$C/install.sh" update v1.0.5 --dry-run
expect_ok "HEAD unchanged after the refusals" test "$(git -C "$C" rev-parse HEAD)" = "$before"

# A real update checks out the tag and runs the NEW tag's install.sh (a stub
# here, so nothing gets installed).
printf '#!/bin/bash\necho "install.sh from v1.0.6 ran with: $*"\n' >"$T/origin/install.sh"
g -C "$T/origin" add -A
g -C "$T/origin" commit -q -m release3
g -C "$T/origin" -c user.signingkey="$T/key" tag -s -m v1.0.6 v1.0.6
expect_ok "update installs a signed tag" "$C/install.sh" update v1.0.6 --no-fonts
expect_ok "it ran the new tag's install.sh with the flags" grep -q 'install.sh from v1.0.6 ran with: --no-fonts' "$T/out"
expect_ok "HEAD is at v1.0.6" test "$(git -C "$C" rev-parse HEAD)" = "$(git -C "$T/origin" rev-parse 'v1.0.6^{commit}')"
expect_ok "the verified tag is stored locally" git -C "$C" rev-parse -q --verify refs/tags/v1.0.6

if [ "$FAILS" -gt 0 ]; then
  echo "release-test: $FAILS failed"
  exit 1
fi
echo "release-test: all passed"
