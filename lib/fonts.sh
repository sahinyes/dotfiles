# shellcheck shell=bash
# JetBrainsMono Nerd Font (icons for render-markdown and the statusline).
# Linux: the pinned nerd-fonts archive, only the "Mono" family, unpacked into
# ~/.local/share/fonts/<name>-<version> (no root). macOS: the Brewfile cask.

font_row() {
  local dir pattern tmp file
  dir="$FONT_DIR/$R_NAME-$R_VERSION"
  pattern=$(extra files)
  case $pattern in '' | *[!A-Za-z0-9._*-]*)
    report FAIL fonts "$R_NAME: bad files= pattern in tools.lock"
    return 0
    ;;
  esac
  if [ -f "$dir/.ok" ] && [ "$(cat "$dir/.ok")" = "$R_SHA" ]; then
    report OK fonts "$R_NAME $R_VERSION in $(tilde "$dir")"
    return 0
  fi
  if ! have xz; then
    report FAIL fonts "$R_NAME: xz is missing (Debian package xz-utils), cannot unpack .tar.xz"
    return 0
  fi
  if ! file=$(fetch_verified "$R_URL" "$R_SHA"); then
    report FAIL fonts "$R_NAME $R_VERSION: download or sha256 check failed ($R_URL)"
    return 0
  fi
  tmp="$dir.tmp"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  if ! tar -xJf "$file" -C "$tmp" --wildcards "$pattern"; then
    rm -rf "$tmp"
    report FAIL fonts "$R_NAME: unpacking $pattern failed"
    return 0
  fi
  printf '%s\n' "$R_SHA" >"$tmp/.ok"
  rm -rf "$dir"
  mv "$tmp" "$dir"
  changed "installed $R_NAME $R_VERSION into $(tilde "$dir")"
  if have fc-cache; then fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true; fi
  report OK fonts "$R_NAME $R_VERSION installed in $(tilde "$dir")"
}

fonts_step() {
  step "fonts"
  if [ "$NO_FONTS" = 1 ]; then
    report SKIP fonts "--no-fonts given"
  elif [ "$OS" = darwin ]; then
    if [ "$NERD_FONT" = yes ]; then
      report OK fonts "JetBrainsMono Nerd Font is installed"
    else
      report OK fonts "JetBrainsMono Nerd Font comes from the Brewfile cask"
    fi
  else
    lock_rows font font_row
  fi
  NERD_FONT=$(detect_nerd_font)
}
