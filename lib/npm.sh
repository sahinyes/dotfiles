# shellcheck shell=bash
# Node language servers (macOS, dev tier) from tools/npm: exact versions in
# package.json, every package pinned with its integrity hash in
# package-lock.json. "npm ci --ignore-scripts" runs no install scripts and
# "npm audit signatures" checks the registry signatures. Only the server
# commands are linked into ~/.local/bin.

NPM_DIR="$REPO/tools/npm"
NPM_BINS="yaml-language-server vscode-json-language-server bash-language-server basedpyright-langserver tsc"

npm_step() {
  local stamp="$NPM_DIR/node_modules/.dotfiles-lock-sha256" want b linked=
  [ "$OS" = darwin ] || return 0
  step "Node language servers (tools/npm)"
  if [ "$TIER" != dev ]; then
    report SKIP npm "tier $TIER (Node servers are part of the dev tier)"
    return 0
  fi
  if ! have npm; then
    report FAIL npm "npm is missing (Brewfile: node)"
    return 0
  fi
  want=$(sha256_of "$NPM_DIR/package-lock.json")
  if [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$want" ]; then
    if ! (cd "$NPM_DIR" && npm ci --ignore-scripts --no-audit --no-fund); then
      report FAIL npm "npm ci failed (see the output above)"
      return 0
    fi
    if ! (cd "$NPM_DIR" && npm audit signatures); then
      rm -rf "$NPM_DIR/node_modules"
      report FAIL npm "npm audit signatures failed; node_modules removed"
      return 0
    fi
    printf '%s\n' "$want" >"$stamp"
    changed "npm ci in tools/npm (signatures verified)"
  fi
  for b in $NPM_BINS; do
    if [ -e "$NPM_DIR/node_modules/.bin/$b" ]; then
      link "$NPM_DIR/node_modules/.bin/$b" "$BIN_DIR/$b"
      linked="$linked $b"
    else
      report FAIL npm "$b missing in tools/npm/node_modules/.bin"
    fi
  done
  report OK npm "linked into ~/.local/bin:$linked"
}
