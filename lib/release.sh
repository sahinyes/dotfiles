# shellcheck shell=bash
# Trust in this checkout. Releases are git tags signed with the SSH key in
# signing_key.pub. "install.sh trust-key <fingerprint>" pins that key once per
# machine after you compare its fingerprint with your paper/phone copy; from
# then on install.sh only runs from a clean checkout of a verified tag
# (unless --dev), and "install.sh update vX.Y.Z" verifies before checkout.

SIGNERS_FILE="$CONF_DIR/allowed_signers"
SIGNER_NAME="dotfiles-release"

# repo_git ARGS: git in this repo without optional index writes.
repo_git() { git --no-optional-locks -C "$REPO" "$@"; }

is_git_checkout() { have git && [ -e "$REPO/.git" ]; }

repo_dirty() { [ -n "$(repo_git status --porcelain 2>/dev/null)" ]; }

head_tag() { repo_git describe --tags --exact-match HEAD 2>/dev/null; }

# tag_verified TAG: true when TAG carries a good signature from the pinned key.
tag_verified() {
  [ -n "$(repo_git config --get gpg.ssh.allowedSignersFile 2>/dev/null)" ] &&
    repo_git verify-tag "$1" >/dev/null 2>&1
}

# checkout_describe: one line for the detection table and the report.
checkout_describe() {
  local tag desc
  if ! is_git_checkout; then
    echo "no git metadata (cannot verify)"
    return 0
  fi
  desc=$(repo_git describe --tags --always 2>/dev/null || echo unknown)
  if repo_dirty; then desc="$desc, modified"; fi
  tag=$(head_tag || true)
  if [ -z "$tag" ]; then
    echo "$desc (not a release tag)"
  elif tag_verified "$tag"; then
    echo "$desc (signature verified)"
  else
    echo "$desc (signature NOT verified: run install.sh trust-key first)"
  fi
}

# require_verified_checkout: stop unless this is a clean, verified tag.
require_verified_checkout() {
  local tag
  if [ "$DEV" = 1 ]; then
    say "*** --dev: running from an unverified checkout ($CHECKOUT) ***"
    report WARN checkout "--dev: not verified ($CHECKOUT)"
    return 0
  fi
  is_git_checkout || die "cannot verify this checkout without git and .git (use --dev to override)"
  if repo_dirty; then
    die "the checkout has local changes (git status); refusing to run. Use --dev for development."
  fi
  tag=$(head_tag) || die "HEAD is not a release tag; check out a signed vX.Y.Z tag (or use --dev)"
  if [ -z "$(repo_git config --get gpg.ssh.allowedSignersFile 2>/dev/null)" ]; then
    die "no pinned signing key yet: run ./install.sh trust-key <SHA256:fingerprint> first"
  fi
  repo_git verify-tag "$tag" >/dev/null 2>&1 ||
    die "tag $tag does not verify against $(tilde "$SIGNERS_FILE"); refusing to run"
  report OK checkout "$tag, clean, signature verified"
}

# trust_key_cmd FINGERPRINT: pin signing_key.pub after comparing fingerprints.
trust_key_cmd() {
  local want=${1:-} got key tag
  case $want in
    SHA256:?*) ;;
    ?*) want="SHA256:$want" ;;
    *) die "usage: install.sh trust-key SHA256:<fingerprint from your paper/phone copy>" ;;
  esac
  have ssh-keygen || die "ssh-keygen is missing (Debian package openssh-client)"
  have git || die "git is missing"
  got=$(ssh-keygen -lf "$REPO/signing_key.pub" | awk '{print $2}')
  say "signing_key.pub: $got"
  say "you typed:       $want"
  [ "$got" = "$want" ] || die "fingerprints differ: do not use this checkout"
  key=$(awk '{print $1 " " $2; exit}' "$REPO/signing_key.pub")
  mkdir -p "$CONF_DIR"
  printf '%s namespaces="git" %s\n' "$SIGNER_NAME" "$key" >"$SIGNERS_FILE"
  repo_git config --local gpg.ssh.allowedSignersFile "$SIGNERS_FILE"
  say "pinned: $(tilde "$SIGNERS_FILE") (gpg.ssh.allowedSignersFile in this repo)"
  tag=$(head_tag) || die "key pinned, but HEAD is not a tag, so nothing was verified"
  repo_git verify-tag "$tag" || die "tag $tag does NOT verify with the pinned key"
  say "tag $tag: good signature. Next: less install.sh lib/*.sh, then ./install.sh"
}

# update_cmd TAG [FLAGS]: fetch TAG, verify its signature, check it out and
# run the install from it. Plugins then realign to its lockfile.
update_cmd() {
  local tag=${1:-}
  shift || true
  case $tag in
    v[0-9]*.[0-9]*.[0-9]*) ;;
    *) die "usage: install.sh update vX.Y.Z [flags]" ;;
  esac
  case $tag in *[!v0-9.]*) die "bad tag name: $tag" ;; esac
  is_git_checkout || die "update needs git and a git checkout"
  [ -n "$(repo_git config --get gpg.ssh.allowedSignersFile 2>/dev/null)" ] ||
    die "no pinned signing key: run ./install.sh trust-key <SHA256:fingerprint> first"
  if repo_dirty && [ "$DEV" != 1 ]; then die "the checkout has local changes; refusing to update"; fi
  say "fetching $tag"
  local depth=()
  if [ "$(repo_git rev-parse --is-shallow-repository)" = true ]; then depth=(--depth 1); fi
  repo_git fetch -q ${depth[@]+"${depth[@]}"} origin "refs/tags/$tag:refs/tags/$tag" ||
    die "fetching $tag failed (a local tag of that name that differs is never overwritten)"
  repo_git verify-tag "$tag" || die "tag $tag does NOT verify with the pinned key; nothing changed"
  repo_git -c advice.detachedHead=false checkout -q --detach "$tag" || die "checkout of $tag failed"
  say "checked out $tag (signature verified); running its install.sh"
  exec "$BASH" "$REPO/install.sh" "$@"
}
