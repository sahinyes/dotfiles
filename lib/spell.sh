# shellcheck shell=bash
# Spell files (German, English suggestions, Turkish) into
# stdpath('data')/site/spell. Neovim's own downloader is disabled in
# nvim/lua/sahin/security.lua, so these pinned files are the only source.

spell_row() {
  local dest="$NVIM_DATA/site/spell/$R_NAME" file
  case $R_NAME in *[!A-Za-z0-9._-]*) return 0 ;; esac
  if sha256_ok "$dest" "$R_SHA"; then
    SPELL_OK="$SPELL_OK $R_NAME"
    return 0
  fi
  if ! file=$(fetch_verified "$R_URL" "$R_SHA"); then
    report FAIL spell "$R_NAME: download or sha256 check failed ($R_URL)"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ]; then backup "$dest"; fi
  cp "$file" "$dest.tmp"
  mv -f "$dest.tmp" "$dest"
  changed "installed spell file $R_NAME"
  SPELL_OK="$SPELL_OK $R_NAME"
}

spell_step() {
  step "spell files"
  SPELL_OK=
  lock_rows spell spell_row
  if [ -n "$SPELL_OK" ]; then
    report OK spell "${SPELL_OK# } in $(tilde "$NVIM_DATA/site/spell") (en.utf-8.spl ships with Neovim)"
  fi
}
