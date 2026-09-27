# shellcheck shell=bash
# sha256 checks. Nothing downloaded is unpacked, copied or run before its
# sha256 matches the value pinned in tools.lock.

# sha256_of FILE: print the hex sha256 of FILE.
sha256_of() {
  if have sha256sum; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# sha256_ok FILE SHA: true when FILE exists and matches SHA.
sha256_ok() {
  [ -f "$1" ] && [ "$(sha256_of "$1")" = "$2" ]
}

# fetch_verified URL SHA: download URL into the cache (or reuse a cached
# copy), check it and print the verified file's path. Returns 1 on a mismatch.
fetch_verified() {
  local url=$1 sha=$2 file
  file="$CACHE_DIR/${sha:0:12}-$(basename "$url")"
  if sha256_ok "$file" "$sha"; then
    printf '%s\n' "$file"
    return 0
  fi
  mkdir -p "$CACHE_DIR"
  rm -f "$file"
  say "  downloading $url" >&2
  fetch "$url" "$file" || return 1
  if ! sha256_ok "$file" "$sha"; then
    warn "sha256 mismatch for $url (expected $sha, got $(sha256_of "$file")); deleted"
    rm -f "$file"
    return 1
  fi
  printf '%s\n' "$file"
}
