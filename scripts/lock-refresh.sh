#!/bin/bash
# lock-refresh.sh: re-derive every pin in tools.lock from its source and show
# the difference. A maintainer tool for the Mac; needs gh (logged in).
#
#   scripts/lock-refresh.sh          rewrite tools.lock, then review: git diff tools.lock
#   scripts/lock-refresh.sh --check  change nothing; exit 1 when anything differs
#
# What is checked, per row kind:
#   tar bin gz font  the GitHub release asset digest (sha256). When the release
#                    publishes checksum files, the digest must appear in them
#                    (verify=checksum). When an attestation exists, the asset is
#                    downloaded and "gh attestation verify" (build provenance)
#                    or "gh release verify-asset" (immutable release) must pass
#                    (verify=attest). Otherwise verify=digest.
#   spell            downloaded again; a new hash is written but flagged loudly.
#   ts-parser        rebuilt from nvim-treesitter's parsers.lua at the revision
#                    pinned in nvim/nvim-pack-lock.json: revision (tags resolved
#                    to commits), location, tarball sha256.
#                    Grammars that need "tree-sitter generate" are refused.
#   git              compared with upstream HEAD (printed, never changed).
# Newer releases are only reported; bump a version by editing its row by hand.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd -P)
LOCK="$REPO/tools.lock"
PACK_LOCK="$REPO/nvim/nvim-pack-lock.json"
CHECK=0

die() {
  printf 'lock-refresh: %s\n' "$*" >&2
  exit 2
}
note() { printf '  %s\n' "$*" >&2; }

case ${1:-} in
  --check) CHECK=1 ;;
  '') ;;
  -h | --help)
    sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *) die "unknown argument: $1" ;;
esac
[ "$(uname -s)" = Darwin ] || die "run this on the Mac"
command -v gh >/dev/null || die "gh is missing (brew install gh)"
gh auth status >/dev/null 2>&1 || die "gh is not logged in (gh auth login)"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/lock-refresh.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
download() { curl -fsSL --proto '=https' --retry 3 --retry-all-errors -o "$2" "$1"; }

# ---------------------------------------------------------- release rows ---

# sums_lines ASSET FILE: lines of a checksum file that name exactly ASSET
# (formats: "hash  asset", "hash *asset", "SHA256 (asset) = hash", yq's table).
sums_lines() {
  awk -v a="$1" '{ for (i = 1; i <= NF; i++) { f = $i; gsub(/^[*(]|[)]$/, "", f); if (f == a) { print; next } } }' "$2"
}

# release_row NAME VERSION TIER OS ARCH KIND URL SHA VERIFY EXTRA
release_row() {
  local url=$7 owner_repo tag asset digest verify=digest sums s lines latest file
  case $url in
    https://github.com/*/releases/download/*) ;;
    *) die "$1: not a GitHub release URL: $url" ;;
  esac
  owner_repo=$(printf '%s' "$url" | cut -d/ -f4-5)
  tag=$(printf '%s' "$url" | cut -d/ -f8)
  asset=$(printf '%s' "$url" | cut -d/ -f9)
  digest=$(gh api "repos/$owner_repo/releases/tags/$tag" \
    --jq ".assets[] | select(.name == \"$asset\") | .digest")
  digest=${digest#sha256:}
  [ -n "$digest" ] && [ "$digest" != null ] || die "$1: no digest for $asset in $owner_repo $tag"

  # Vendor checksum files of the release: shared lists, or <asset>.sha256.
  sums=$(gh api "repos/$owner_repo/releases/tags/$tag" --jq ".assets[] | .name as \$n
    | select(\$n | test(\"(?i)(checksums?|sha256|sha-256)\"))
    | select(\$n | test(\"\\\\.(sig|pem|bundle|sh)$\") | not)
    | select((\$n | endswith(\".sha256\") | not) or \$n == \"$asset.sha256\")
    | .browser_download_url")
  for s in $sums; do
    download "$s" "$TMP/sums" || continue
    lines=$(sums_lines "$asset" "$TMP/sums")
    [ -n "$lines" ] || continue
    if printf '%s\n' "$lines" | grep -qi -- "$digest"; then
      verify=checksum
    else
      die "$1: $s lists $asset with a hash that differs from the GitHub digest"
    fi
  done

  # Attestations, when published: build provenance (gh attestation verify)
  # or an immutable-release attestation (gh release verify-asset).
  if gh api "repos/$owner_repo/attestations/sha256:$digest" >/dev/null 2>&1; then
    file="$TMP/$asset"
    download "$url" "$file"
    [ "$(sha256 "$file")" = "$digest" ] || die "$1: downloaded $asset does not match its digest"
    if gh attestation verify "$file" -R "$owner_repo" >/dev/null 2>&1 ||
      gh release verify-asset "$tag" "$file" -R "$owner_repo" >/dev/null 2>&1; then
      verify=attest
    else
      die "$1: an attestation exists for $asset but neither gh attestation verify nor gh release verify-asset accepts it"
    fi
    rm -f "$file"
  fi

  latest=$(gh api "repos/$owner_repo/releases/latest" --jq .tag_name 2>/dev/null || true)
  if [ -n "$latest" ] && [ "$latest" != "$tag" ]; then note "$1: newer release $latest (pinned $tag)"; fi
  if [ "$8" != "$digest" ]; then note "$1 $5: sha256 changed $8 -> $digest"; fi
  printf '%s %s %s %s %s %s %s %s %s %s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$digest" "$verify" "${10}"
}

# ------------------------------------------------------------ spell rows ---

spell_row() {
  local got
  download "$7" "$TMP/spell"
  got=$(sha256 "$TMP/spell")
  if [ "$got" != "$8" ]; then
    note "!! $1 CHANGED upstream ($8 -> $got): nobody publishes checksums for these;"
    note "!! compare with a second mirror before you commit this"
  fi
  printf '%s %s %s %s %s %s %s %s %s %s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$got" tofu "${10}"
}

# -------------------------------------------------------- ts-parser rows ---

PARSERS_LUA="$TMP/parsers.lua"

fetch_parsers_lua() {
  local rev
  rev=$(awk -F'"' '/^    "nvim-treesitter": \{/ { p = 1 } p && /"rev":/ { print $4; exit }' "$PACK_LOCK")
  [ -n "$rev" ] || die "nvim-treesitter is not in nvim/nvim-pack-lock.json"
  note "ts-parser rows from nvim-treesitter $rev"
  gh api "repos/nvim-treesitter/nvim-treesitter/contents/lua/nvim-treesitter/parsers.lua?ref=$rev" \
    --jq .content | base64 -d >"$PARSERS_LUA"
}

# parser_field LANG KEY: a quoted value from LANG's block in parsers.lua.
parser_block() { awk -v l="$1" '$0 ~ "^  " l " = \\{" { p = 1 } p { print } p && /^  \},/ { exit }' "$PARSERS_LUA"; }
parser_field() { parser_block "$1" | sed -n "s/^ *$2 = '\\([^']*\\)',*$/\\1/p" | head -n 1; }

ts_row() {
  local lang=$1 url rev sha location extra owner_repo
  [ -s "$PARSERS_LUA" ] || fetch_parsers_lua
  [ -n "$(parser_block "$lang")" ] || die "$lang: not in parsers.lua"
  if parser_block "$lang" | grep -q -e 'generate = true' -e 'generate_from_json'; then
    die "$lang: needs tree-sitter generate; refused (remove the row)"
  fi
  url=$(parser_field "$lang" url)
  rev=$(parser_field "$lang" revision)
  location=$(parser_field "$lang" location)
  case $url in https://github.com/*) ;; *) die "$lang: not a GitHub grammar: $url" ;; esac
  owner_repo=${url#https://github.com/}
  case $rev in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) ;;
    *) rev=$(gh api "repos/$owner_repo/commits/$rev" --jq .sha) ;;
  esac
  download "$url/archive/$rev.tar.gz" "$TMP/ts.tar.gz"
  sha=$(sha256 "$TMP/ts.tar.gz")
  extra=-
  if [ -n "$location" ]; then extra="location=$location"; fi
  if [ "$rev" != "$2" ]; then note "$lang: revision $2 -> $rev"; fi
  printf '%s %s %s %s %s %s %s %s %s %s\n' "$lang" "$rev" "$3" "$4" "$5" "$6" \
    "$url/archive/$rev.tar.gz" "$sha" tofu "$extra"
}

# -------------------------------------------------------------- git rows ---

git_row() {
  local head
  head=$(gh api "repos/${7#https://github.com/}/commits/HEAD" --jq .sha 2>/dev/null || true)
  if [ -n "$head" ] && [ "$head" != "$2" ]; then note "$1: upstream HEAD is $head (pinned $2)"; fi
  printf '%s\n' "$*"
}

# ------------------------------------------------------------------ main ---

main() {
  local line new="$TMP/tools.lock"
  : >"$new"
  while IFS= read -r line <&3 || [ -n "$line" ]; do
    case $line in
      '' | '#'*)
        printf '%s\n' "$line" >>"$new"
        continue
        ;;
    esac
    set -f
    # shellcheck disable=SC2086 # split the row into its columns on purpose
    set -- $line
    set +f
    [ $# -eq 10 ] || die "malformed row: $line"
    case $6 in
      tar | bin | gz | font) release_row "$@" >>"$new" ;;
      spell) spell_row "$@" >>"$new" ;;
      ts-parser) ts_row "$@" >>"$new" ;;
      git) git_row "$@" >>"$new" ;;
      *) die "unknown kind $6 in row: $line" ;;
    esac
  done 3<"$LOCK"

  if cmp -s "$LOCK" "$new"; then
    echo "tools.lock is up to date"
    return 0
  fi
  diff -u "$LOCK" "$new" || true
  if [ "$CHECK" = 1 ]; then
    echo "tools.lock differs (--check: nothing written)"
    return 1
  fi
  cp "$new" "$LOCK"
  echo "tools.lock rewritten: review with git diff tools.lock"
}

main
