# shellcheck shell=bash
# Extra treesitter parsers (yaml json bash python go typescript http diff).
# Neovim 0.12 already bundles c lua markdown markdown_inline query vim vimdoc,
# so notes never need this step. Each grammar tarball is pinned in tools.lock,
# checked, then compiled with "tree-sitter build" into
# stdpath('data')/site/parser/<lang>.so. nvim-treesitter's install() is never
# called; nvim/lua/sahin/plugins/treesitter.lua puts its query files on
# 'runtimepath'.

# ts_blocker [plan]: why parsers cannot be built here (empty = they can).
# With "plan", a Linux tree-sitter CLI that the tools step will install
# does not count as missing.
ts_blocker() {
  if [ "$OS" = darwin ]; then
    have tree-sitter || {
      echo "tree-sitter CLI missing (Brewfile: tree-sitter-cli)"
      return 0
    }
    [ "$CC_OK" = yes ] || echo "no C compiler (run: xcode-select --install)"
    return 0
  fi
  if ! version_ge "${GLIBC:-0}" 2.39; then
    echo "${SUITE:-this system} has glibc ${GLIBC:-unknown}, tree-sitter 0.27.0 needs 2.39"
  elif [ "$CC_OK" != yes ]; then
    echo "no C compiler (cc)"
  elif [ "${1:-}" != plan ] && ! have tree-sitter; then
    echo "tree-sitter CLI missing (see the tools lines)"
  fi
}

parser_row() {
  local lang=$R_NAME location stamp src out file
  case $lang in *[!a-z0-9_]*) return 0 ;; esac
  location=$(extra location)
  location=${location:-.}
  if ! safe_relpath "$location"; then
    report FAIL treesitter "$lang: bad location= in tools.lock; refused"
    return 0
  fi
  stamp="$STATE_DIR/parsers/$lang"
  out="$NVIM_DATA/site/parser/$lang.so"
  if [ -f "$out" ] && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$R_SHA" ]; then
    TS_OK="$TS_OK $lang"
    return 0
  fi
  if ! file=$(fetch_verified "$R_URL" "$R_SHA"); then
    report FAIL treesitter "$lang: download or sha256 check failed ($R_URL)"
    return 0
  fi
  src="$CACHE_DIR/ts/$lang-$R_VERSION"
  rm -rf "$src"
  mkdir -p "$src"
  if ! tar -xzf "$file" -C "$src" --strip-components=1; then
    report FAIL treesitter "$lang: unpacking the grammar failed"
    return 0
  fi
  if [ ! -f "$src/$location/src/parser.c" ]; then
    report FAIL treesitter "$lang: src/parser.c missing (grammar would need generate); refused"
    return 0
  fi
  mkdir -p "$(dirname "$out")" "$(dirname "$stamp")"
  if ! (cd "$src/$location" && tree-sitter build -o "$out.tmp" >/dev/null 2>&1); then
    rm -f "$out.tmp"
    report FAIL treesitter "$lang: tree-sitter build failed"
    return 0
  fi
  # A parser this script did not build (no stamp) is kept in the backup.
  if [ -e "$out" ] && [ ! -f "$stamp" ]; then backup "$out"; fi
  mv -f "$out.tmp" "$out"
  printf '%s\n' "$R_SHA" >"$stamp"
  rm -rf "$src"
  changed "built treesitter parser $lang"
  TS_OK="$TS_OK $lang"
}

parsers_step() {
  local why
  step "treesitter parsers"
  why=$(ts_blocker)
  if [ -n "$why" ]; then
    report OFF treesitter "$why -> bundled parsers only (markdown works; yaml/json use legacy syntax)"
    return 0
  fi
  TS_OK=
  lock_rows ts-parser parser_row
  if [ -n "$TS_OK" ]; then
    report OK treesitter "parsers:$TS_OK in $(tilde "$NVIM_DATA/site/parser")"
  fi
}
