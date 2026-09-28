# shellcheck shell=bash
# Trust in this checkout. Releases are git tags signed with the SSH key in
# signing_key.pub, and ~/.config/dotfiles/allowed_signers pins that key once
# per machine. verify_tag below is the one check that every command uses.
#
# On a new machine, check the key and the tag with your own ssh-keygen and
# git before any code from the clone runs (README, "Bootstrap a new
# machine"). "install.sh trust-key" is code from the clone too, so it cannot
# vouch for the clone it came in: it records a key you have already checked
# and points this clone's git config at it. From then on install.sh only
# runs from a clean checkout of a verified tag (unless --dev), and
# "install.sh update vX.Y.Z" verifies a tag before it checks it out.

SIGNERS_FILE="$CONF_DIR/allowed_signers"
SIGNER_NAME="dotfiles-release"
# update fetches a tag here first; it becomes refs/tags/<tag> only once verified.
CANDIDATE_REF="refs/dotfiles/candidate"

# repo_git ARGS: git in this repo without optional index writes.
repo_git() { git --no-optional-locks -C "$REPO" "$@"; }

is_git_checkout() { have git && [ -e "$REPO/.git" ]; }

repo_dirty() { [ -n "$(repo_git status --porcelain 2>/dev/null)" ]; }

head_tag() { repo_git describe --tags --exact-match HEAD 2>/dev/null; }

# key_pinned: true once allowed_signers exists. Only that file counts; a
# gpg.ssh.allowedSignersFile in your global git config is never used.
key_pinned() { [ -s "$SIGNERS_FILE" ]; }

# verify_tag REF NAME: true when REF is a signed tag object that calls itself
# NAME (so an older signed release cannot be passed off under a newer name)
# and its SSH signature is good for the key in allowed_signers. OpenPGP and
# X.509 signatures always fail: their verifiers are switched off, so a gpg
# keyring cannot vouch for a tag. git's messages go to stderr.
verify_tag() {
  local ref=$1 name=$2 inner
  key_pinned || return 1
  [ "$(repo_git cat-file -t "$ref" 2>/dev/null)" = tag ] || return 1
  # The "tag" line of the header (the header ends at the first empty line).
  inner=$(repo_git cat-file tag "$ref" | awk 'NF == 0 { body = 1 } !body && $1 == "tag" { print $2 }') ||
    return 1
  if [ "$inner" != "$name" ]; then
    warn "the tag object behind $name is named ${inner:-nothing} (an older release under a new name?)"
    return 1
  fi
  repo_git -c gpg.ssh.allowedSignersFile="$SIGNERS_FILE" \
    -c gpg.openpgp.program=false -c gpg.x509.program=false \
    verify-tag "$ref"
}

# tag_verified TAG: true when the local tag TAG passes verify_tag.
tag_verified() { verify_tag "refs/tags/$1" "$1" >/dev/null 2>&1; }

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
  elif ! key_pinned; then
    echo "$desc (signature NOT verified: no pinned signing key yet)"
  else
    echo "$desc (signature NOT verified)"
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
  key_pinned || die "no pinned signing key yet ($(tilde "$SIGNERS_FILE")): pin it as the README's bootstrap shows"
  verify_tag "refs/tags/$tag" "$tag" >/dev/null 2>&1 ||
    die "tag $tag does not verify against $(tilde "$SIGNERS_FILE"); refusing to run"
  report OK checkout "$tag, clean, signature verified"
}

# trust_key_cmd FINGERPRINT: pin signing_key.pub after comparing fingerprints,
# then verify HEAD's tag with it. This runs code from this checkout, so on a
# new clone check the key and the tag with your own tools first (README).
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
  verify_tag "refs/tags/$tag" "$tag" || die "tag $tag does NOT verify with the pinned key"
  say "tag $tag: good signature. Next: less install.sh lib/*.sh, then ./install.sh"
}

# update_cmd TAG [FLAGS]: fetch TAG into a scratch ref and verify it. Only a
# verified tag is stored as refs/tags/TAG, checked out and its install.sh
# run; plugins then realign to its lockfile. With --dry-run it stops after
# the check and checks nothing out.
update_cmd() {
  local tag=${1:-} commit new old stat depth=()
  shift || true
  case $tag in
    v[0-9]*.[0-9]*.[0-9]*) ;;
    *) die "usage: install.sh update vX.Y.Z [flags]" ;;
  esac
  case $tag in *[!v0-9.]*) die "bad tag name: $tag" ;; esac
  is_git_checkout || die "update needs git and a git checkout"
  key_pinned || die "no pinned signing key yet ($(tilde "$SIGNERS_FILE")): pin it as the README's bootstrap shows"
  if repo_dirty && [ "$DEV" != 1 ]; then die "the checkout has local changes; refusing to update"; fi
  say "fetching $tag"
  if [ "$(repo_git rev-parse --is-shallow-repository)" = true ]; then depth=(--depth 1); fi
  # --no-tags: nothing lands in refs/tags before the check.
  repo_git fetch -q --no-tags ${depth[@]+"${depth[@]}"} origin "+refs/tags/$tag:$CANDIDATE_REF" ||
    die "fetching $tag failed"
  if ! verify_tag "$CANDIDATE_REF" "$tag"; then
    repo_git update-ref -d "$CANDIDATE_REF"
    die "tag $tag does NOT verify with the pinned key; nothing changed"
  fi
  new=$(repo_git rev-parse "$CANDIDATE_REF")
  commit=$(repo_git rev-parse "$CANDIDATE_REF^{commit}")
  repo_git update-ref -d "$CANDIDATE_REF"
  if [ "$DRY_RUN" = 1 ]; then
    stat=$(repo_git diff --shortstat HEAD "$commit")
    say "dry run: $tag has a good signature (commit ${commit:0:12}; against this checkout:${stat:- no changes})."
    say "It was not checked out; run the same command without --dry-run to install it."
    exit 0
  fi
  old=$(repo_git rev-parse -q --verify "refs/tags/$tag" || true)
  if [ -z "$old" ]; then
    repo_git update-ref "refs/tags/$tag" "$new"
  elif [ "$old" != "$new" ]; then
    die "the local tag $tag differs from the verified one fetched; it is never overwritten (nothing changed)"
  fi
  repo_git -c advice.detachedHead=false checkout -q --detach "$commit" || die "checkout of $tag failed"
  say "checked out $tag (signature verified); running its install.sh"
  exec "$BASH" "$REPO/install.sh" "$@"
}
