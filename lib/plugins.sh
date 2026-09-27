# shellcheck shell=bash
# Neovim plugins through vim.pack at the revisions in nvim/nvim-pack-lock.json.
# When anything differs (missing plugin, other revision, leftover plugin),
# "NVIM_BOOTSTRAP=1 nvim --headless" runs sahin.pack's sync: install from the
# lockfile, realign every plugin to its locked revision and delete plugins
# that are no longer listed (the same as :PackSync).

PACK_LOCK="$REPO/nvim/nvim-pack-lock.json"

# pack_lock_revs: "name rev" per plugin in the lockfile (vim.pack writes it
# pretty-printed: plugin names at 4 spaces, their fields at 6).
pack_lock_revs() {
  awk -F'"' '/^    "[^"]+": \{/ { name = $2 } /^      "rev":/ { print name, $4 }' "$PACK_LOCK"
}

# plugins_check: compare disk with the lockfile. Sets PLUG_TOTAL, PLUG_GOOD
# and PLUG_BAD (a readable list of what differs); returns 0 when all match.
plugins_check() {
  local name rev head dir
  PLUG_TOTAL=0 PLUG_GOOD=0 PLUG_BAD=
  while read -r name rev <&3; do
    PLUG_TOTAL=$((PLUG_TOTAL + 1))
    head=$(git -C "$PLUGIN_DIR/$name" -c core.fsmonitor=false rev-parse HEAD 2>/dev/null || true)
    if [ "$head" = "$rev" ]; then
      PLUG_GOOD=$((PLUG_GOOD + 1))
    elif [ -z "$head" ]; then
      PLUG_BAD="$PLUG_BAD $name(missing)"
    else
      PLUG_BAD="$PLUG_BAD $name(${head:0:7}, lock ${rev:0:7})"
    fi
  done 3< <(pack_lock_revs)
  for dir in "$PLUGIN_DIR"/*; do
    [ -d "$dir" ] || continue
    name=${dir##*/}
    pack_lock_revs | awk -v n="$name" '$1 == n { f = 1 } END { exit !f }' ||
      PLUG_BAD="$PLUG_BAD $name(not in lockfile)"
  done
  [ "$PLUG_TOTAL" -gt 0 ] && [ -z "$PLUG_BAD" ]
}

plugins_step() {
  local before out rc=0
  step "plugins (vim.pack)"
  if [ "$(pack_lock_revs | wc -l)" -eq 0 ]; then
    report FAIL plugins "no plugins found in nvim/nvim-pack-lock.json"
    return 0
  fi
  if plugins_check; then
    report OK plugins "$PLUG_GOOD/$PLUG_TOTAL at lockfile revisions"
    return 0
  fi
  if ! have git; then
    report FAIL plugins "git is missing, cannot install plugins:$PLUG_BAD"
    return 0
  fi
  if [ ! -x "$NVIM" ]; then
    report FAIL plugins "nvim is missing, cannot install plugins"
    return 0
  fi
  say "  syncing:$PLUG_BAD"
  # vim.pack drops a plugin that failed to install from the lockfile without
  # an error, so keep a copy and restore it if the sync changed the file.
  before=$(mktemp "${TMPDIR:-/tmp}/dotfiles-lock.XXXXXX")
  cp "$PACK_LOCK" "$before"
  out=$(cd "$HOME" && NVIM_BOOTSTRAP=1 "$NVIM" --headless -i NONE -c 'qa!' </dev/null 2>&1) || rc=$?
  if ! cmp -s "$before" "$PACK_LOCK"; then
    cp "$before" "$PACK_LOCK"
    report WARN plugins "the sync rewrote nvim-pack-lock.json; restored the committed version"
  fi
  rm -f "$before"
  changed "vim.pack sync (NVIM_BOOTSTRAP=1)"
  if plugins_check; then
    report OK plugins "$PLUG_GOOD/$PLUG_TOTAL at lockfile revisions (installed now)"
  else
    report FAIL plugins "$PLUG_GOOD/$PLUG_TOTAL match the lockfile after sync (exit $rc); differs:$PLUG_BAD${out:+; nvim said: $(printf '%s' "$out" | head -n 3 | tr '\n' ' ')}"
  fi
}
