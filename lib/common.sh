# shellcheck shell=bash
# Shared helpers for install.sh: output, the final report, change tracking,
# directories, backups and symlinks. Sourced first; defines no steps.

# ---------------------------------------------------------------- output ---

say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

# have CMD: true when CMD is on PATH.
have() { command -v "$1" >/dev/null 2>&1; }

# tilde PATH: show $HOME as ~ (shorter, and keeps home paths out of logs).
# shellcheck disable=SC2088 # a literal ~ is the point here
tilde() {
  case $1 in
    "$HOME") printf '~' ;;
    "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# --------------------------------------------------------------- report ---
# Every step adds one or more lines: STATUS AREA REASON. STATUS is one of
# OK, SKIP, OFF, WARN, FAIL. The report is printed at the end and saved.

REPORT_LINES=()
CHANGES=0
FAILS=0

report() {
  local status=$1 area=$2
  shift 2
  REPORT_LINES+=("$(printf '%-4s  %-10s  %s' "$status" "$area" "$*")")
  if [ "$status" = FAIL ]; then FAILS=$((FAILS + 1)); fi
}

# changed WHAT: record one change to the machine (a second run should make none).
changed() {
  CHANGES=$((CHANGES + 1))
  say "  + $*"
}

# step TITLE: progress header while the install runs.
step() { printf '\n== %s\n' "$*"; }

# ------------------------------------------------------------- versions ---

# version_ge A B: true when dotted version A >= B (leading "v" ignored).
version_ge() {
  local a=${1#v} b=${2#v} x y _
  for _ in 1 2 3; do
    x=${a%%.*}
    y=${b%%.*}
    x=${x%%[!0-9]*}
    y=${y%%[!0-9]*}
    x=${x:-0}
    y=${y:-0}
    if [ "$x" -gt "$y" ]; then return 0; fi
    if [ "$x" -lt "$y" ]; then return 1; fi
    case $a in *.*) a=${a#*.} ;; *) a=0 ;; esac
    case $b in *.*) b=${b#*.} ;; *) b=0 ;; esac
  done
  return 0
}

# ---------------------------------------------------------- filesystem ---

# file_mode PATH: octal permission bits (GNU and BSD stat differ).
file_mode() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then
    stat -c '%a' "$1"
  else
    stat -f '%Lp' "$1"
  fi
}

# ensure_dir DIR [MODE]: create DIR (and fix MODE) only when needed.
ensure_dir() {
  local dir=$1 mode=${2:-}
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    changed "created $(tilde "$dir")"
  fi
  if [ -n "$mode" ] && [ "$(file_mode "$dir")" != "$mode" ]; then
    chmod "$mode" "$dir"
    changed "chmod $mode $(tilde "$dir")"
  fi
}

# backup PATH: move PATH into ~/.dotfiles-backup/<timestamp>/ (never deletes).
# backup_copy PATH: same place, but copies (PATH stays where it is).
BACKUP_DIR=
backup_target() {
  if [ -z "$BACKUP_DIR" ]; then
    BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$HOME/.dotfiles-backup" "$BACKUP_DIR"
  fi
  BACKUP_TO="$BACKUP_DIR/${1#"$HOME"/}"
  mkdir -p "$(dirname "$BACKUP_TO")"
}
backup() {
  backup_target "$1"
  mv "$1" "$BACKUP_TO"
  changed "moved $(tilde "$1") to $(tilde "$BACKUP_TO")"
}
backup_copy() {
  backup_target "$1"
  cp -p "$1" "$BACKUP_TO"
}

# link TARGET LINK: make LINK a symlink to TARGET. A real file or directory
# at LINK is moved to the backup first; a correct link is left alone.
link() {
  local target=$1 path=$2
  if [ -L "$path" ] && [ "$(readlink "$path")" = "$target" ]; then return 0; fi
  if [ -L "$path" ] || [ -e "$path" ]; then backup "$path"; fi
  mkdir -p "$(dirname "$path")"
  ln -s "$target" "$path"
  changed "linked $(tilde "$path") -> $(tilde "$target")"
}

# write_file DEST MODE < content: write DEST only when the content differs;
# a different file already there is moved to the backup first. Feed it with
# `write_file DEST MODE < <(producer)`, never `producer | write_file`: a
# pipe runs it in a subshell, which loses the change count and BACKUP_DIR.
write_file() {
  local dest=$1 mode=$2 tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/dotfiles.XXXXXX")
  cat >"$tmp"
  if [ -f "$dest" ] && [ ! -L "$dest" ] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    if [ "$(file_mode "$dest")" != "$mode" ]; then
      chmod "$mode" "$dest"
      changed "chmod $mode $(tilde "$dest")"
    fi
    return 0
  fi
  if [ -L "$dest" ] || [ -e "$dest" ]; then backup "$dest"; fi
  mkdir -p "$(dirname "$dest")"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$dest"
  changed "wrote $(tilde "$dest")"
}

# safe_relpath STRING: true for a plain relative path (letters, digits and
# ._/+-, no "..", not absolute). Checked before a path taken from tools.lock
# or a package is used.
safe_relpath() {
  case $1 in
    '' | *[!A-Za-z0-9._/+-]* | /* | *..*) return 1 ;;
  esac
  return 0
}

# quotable PATH: true when PATH can sit inside '...' in a generated script.
quotable() {
  case $1 in
    *"'"* | *'
'*) return 1 ;;
  esac
  return 0
}
