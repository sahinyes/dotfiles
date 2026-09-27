# shellcheck shell=bash
# Detection: look at the machine without changing anything, then print the
# table that the plan (and --dry-run) is based on.

# os_release KEY: value from /etc/os-release, read as data (never sourced).
os_release() {
  [ -r /etc/os-release ] || return 0
  sed -n "s/^$1=//p" /etc/os-release | head -n 1 | tr -d '"'
}

detect_glibc() {
  local v=
  if have getconf; then v=$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}') || v=; fi
  if [ -z "$v" ] && have ldd; then v=$(ldd --version 2>/dev/null | awk 'NR == 1 {print $NF}') || v=; fi
  printf '%s' "$v"
}

# detect_icu: yes when libicu is installed (marksman needs it or a wrapper).
detect_icu() {
  local ldconfig f
  for ldconfig in /sbin/ldconfig /usr/sbin/ldconfig; do
    if [ -x "$ldconfig" ]; then
      if "$ldconfig" -p 2>/dev/null | grep -q 'libicuuc\.so'; then echo yes; else echo no; fi
      return 0
    fi
  done
  for f in /usr/lib/*/libicuuc.so.* /usr/lib/libicuuc.so.* /lib/*/libicuuc.so.*; do
    if [ -e "$f" ]; then
      echo yes
      return 0
    fi
  done
  echo no
}

# detect_nerd_font: yes / no / unknown. The Mac is checked through the font
# folders (fc-list there may rewrite its cache, which --dry-run must not do).
detect_nerd_font() {
  local f
  if [ "$OS" = darwin ]; then
    for f in "$HOME"/Library/Fonts/JetBrainsMonoNerdFont* /Library/Fonts/JetBrainsMonoNerdFont*; do
      if [ -e "$f" ]; then
        echo yes
        return 0
      fi
    done
    echo no
  elif have fc-list; then
    if fc-list 2>/dev/null | grep -qi 'JetBrainsMono Nerd Font'; then echo yes; else echo no; fi
  else
    echo unknown
  fi
}

# detect_smulx: yes when tmux-256color has the Smulx (undercurl) capability.
detect_smulx() {
  have infocmp || {
    echo unknown
    return 0
  }
  if infocmp -x tmux-256color 2>/dev/null | grep -q 'Smulx'; then echo yes; else echo no; fi
}

# detect_cc: yes when a C compiler can be used. On the Mac /usr/bin/cc is a
# stub that opens an installer dialog, so the Command Line Tools are checked.
detect_cc() {
  if [ "$OS" = darwin ]; then
    if xcode-select -p >/dev/null 2>&1; then echo yes; else echo no; fi
  elif have cc; then
    echo yes
  else
    echo no
  fi
}

detect_session() {
  local s=${XDG_SESSION_TYPE:-}
  if [ -z "$s" ]; then
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
      s=wayland
    elif [ -n "${DISPLAY:-}" ]; then
      s=x11
    else
      s=none
    fi
  fi
  [ -n "${SSH_TTY:-}" ] && s="$s ssh"
  [ -n "${TMUX:-}" ] && s="$s tmux"
  [ -n "${VTE_VERSION:-}" ] && s="$s vte"
  [ -n "${TERM_PROGRAM:-}" ] && s="$s ${TERM_PROGRAM}"
  printf '%s' "$s"
}

detect() {
  local b
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)
  case $ARCH in arm64) ARCH=aarch64 ;; amd64) ARCH=x86_64 ;; esac
  DISTRO=$(os_release ID)
  SUITE=$(os_release VERSION_CODENAME)
  GLIBC=
  if [ "$OS" = linux ]; then GLIBC=$(detect_glibc); fi

  if [ -z "$TIER" ]; then
    if [ "$OS" = darwin ]; then TIER=dev; else TIER=notes; fi
  fi

  if [ "$OS" = darwin ]; then
    BREW=$(command -v brew || true)
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      if [ -z "$BREW" ] && [ -x "$b" ]; then BREW=$b; fi
    done
    if [ -n "$BREW" ]; then NVIM="$("$BREW" --prefix)/bin/nvim"; else NVIM=''; fi
  else
    NVIM="$BIN_DIR/nvim"
  fi

  FETCH_TOOL=$(fetch_tool)
  if net_probe; then NET=online; else NET=offline; fi
  HAVE_ICU=n/a
  if [ "$OS" = linux ]; then HAVE_ICU=$(detect_icu); fi
  NERD_FONT=$(detect_nerd_font)
  SMULX=$(detect_smulx)
  CC_OK=$(detect_cc)
  SESSION=$(detect_session)
  case " $(id -nG 2>/dev/null) " in
    *" sudo "* | *" admin "* | *" wheel "*) ADMIN=yes ;;
    *) ADMIN=no ;;
  esac
  if [ -e "$WORK_MARKER" ]; then WORK_NOW=yes; else WORK_NOW=no; fi
  CHECKOUT=$(checkout_describe)
}

detect_print() {
  local present='' missing='' t nv
  nv=$(nvim_version)
  nv=${nv:-not installed yet}
  for t in git curl wget python3 ssh-keygen tar xz gzip cc make tmux gitleaks \
    fc-cache gsettings dconf wl-copy xclip infocmp apt-get dpkg-deb brew node npm; do
    if have "$t"; then present="$present $t"; else missing="$missing $t"; fi
  done
  say "== detected"
  printf '  %-12s %s\n' \
    os "$OS ${DISTRO:+$DISTRO }${SUITE:+$SUITE }$ARCH" \
    glibc "${GLIBC:-n/a}" \
    network "$NET (https://github.com/ via $FETCH_TOOL)" \
    tier "$TIER" \
    nvim "$(tilde "${NVIM:-none}") ($nv)" \
    checkout "$CHECKOUT" \
    session "$SESSION" \
    libicu "$HAVE_ICU" \
    nerd-font "$NERD_FONT" \
    smulx "$SMULX (tmux-256color undercurl)" \
    c-compiler "$CC_OK" \
    admin-group "$ADMIN (information only; install.sh never uses sudo)" \
    work-marker "$WORK_NOW ($(tilde "$WORK_MARKER"))" \
    present "${present# }" \
    missing "${missing# }"
}
