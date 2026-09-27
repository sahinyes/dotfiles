#!/bin/bash
# Configure GNOME Terminal's default profile for this setup (no sudo needed).
#
# Applies terminal/gnome-terminal.dconf: block cursor, no bell, unlimited
# scrollback, Catppuccin Mocha colors, the Nerd Font (only if installed), and
# no F10/Alt menu shortcuts. Before changing anything it saves
# `dconf dump /org/gnome/terminal/` to the backup dir. Idempotent.
#
# Usage: scripts/gnome-terminal.sh [--dry-run | --check] [--backup-dir DIR]
#   --dry-run         print what would change, change nothing
#   --check           like --dry-run, but exit 1 if anything differs
#   --backup-dir DIR  backup location (default ~/.dotfiles-backup/<timestamp>)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
settings="$here/../terminal/gnome-terminal.dconf"
mode=apply
backup_dir=""

while [ $# -gt 0 ]; do
    case "$1" in
    --dry-run) mode=dry-run && shift ;;
    --check) mode=check && shift ;;
    --backup-dir)
        [ $# -ge 2 ] || {
            echo "gnome-terminal: --backup-dir needs a directory" >&2
            exit 2
        }
        backup_dir="$2"
        shift 2
        ;;
    -h | --help)
        sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "gnome-terminal: unknown option: $1" >&2
        exit 2
        ;;
    esac
done

say() { printf 'gnome-terminal: %s\n' "$*"; }

if ! command -v gsettings >/dev/null 2>&1 ||
    ! gsettings list-schemas 2>/dev/null | grep -x 'org.gnome.Terminal.ProfilesList' >/dev/null; then
    say "GNOME Terminal is not installed here; nothing to do"
    exit 0
fi

uuid="$(gsettings get org.gnome.Terminal.ProfilesList default)"
uuid="${uuid#\'}"
uuid="${uuid%\'}"
case "$uuid" in
'' | *[!0-9a-fA-F-]*)
    echo "gnome-terminal: unexpected default profile id: $uuid" >&2
    exit 1
    ;;
esac
profile_schema="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$uuid/"
global_schema="org.gnome.Terminal.Legacy.Settings"

# The [font] section applies only when fontconfig knows the family, e.g.
# font='JetBrainsMono Nerd Font Mono 12' -> JetBrainsMono Nerd Font Mono
font_value="$(sed -n '/^font=/{s/^font=//p;q;}' "$settings")"
font_family="${font_value#\'}"
font_family="${font_family%\'}"
font_family="${font_family% *}"
font_ok=false
if [ -n "$font_family" ] && command -v fc-list >/dev/null 2>&1 &&
    fc-list : family | grep -iF "$font_family" >/dev/null; then
    font_ok=true
fi

# Collect the keys whose current value differs from the wanted one.
ch_schema=()
ch_key=()
ch_want=()
ch_have=()
section=""
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
    '' | '#'*) continue ;;
    '['*']')
        section="${line#[}"
        section="${section%]}"
        continue
        ;;
    esac
    key="${line%%=*}"
    want="${line#*=}"
    case "$key" in
    '' | *[!a-z0-9-]*)
        echo "gnome-terminal: bad line in $settings: $line" >&2
        exit 1
        ;;
    esac
    case "$section" in
    profile) schema="$profile_schema" ;;
    font)
        [ "$font_ok" = true ] || continue
        schema="$profile_schema"
        ;;
    global) schema="$global_schema" ;;
    *)
        echo "gnome-terminal: unknown section [$section] in $settings" >&2
        exit 1
        ;;
    esac
    have="$(gsettings get "$schema" "$key")"
    if [ "$have" != "$want" ]; then
        ch_schema+=("$schema")
        ch_key+=("$key")
        ch_want+=("$want")
        ch_have+=("$have")
    fi
done <"$settings"

if [ "$font_ok" != true ]; then
    say "font '$font_family' not found by fc-list; keeping the current font (install it, then rerun)"
fi

n=${#ch_key[@]}
if [ "$n" -eq 0 ]; then
    say "profile $uuid already configured"
    exit 0
fi

if [ "$mode" != apply ]; then
    i=0
    while [ "$i" -lt "$n" ]; do
        say "would set ${ch_key[$i]}: ${ch_have[$i]} -> ${ch_want[$i]}"
        i=$((i + 1))
    done
    say "$n setting(s) differ on profile $uuid"
    if [ "$mode" = check ]; then exit 1; fi
    exit 0
fi

if ! command -v dconf >/dev/null 2>&1; then
    echo "gnome-terminal: dconf not found (package dconf-cli); not changing anything without a backup" >&2
    exit 1
fi
if [ -z "$backup_dir" ]; then
    backup_dir="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$backup_dir"
dconf dump /org/gnome/terminal/ >"$backup_dir/gnome-terminal.dconf"
say "backup: $backup_dir/gnome-terminal.dconf"
say "  undo: dconf reset -f /org/gnome/terminal/ && dconf load /org/gnome/terminal/ < $backup_dir/gnome-terminal.dconf"

i=0
while [ "$i" -lt "$n" ]; do
    gsettings set "${ch_schema[$i]}" "${ch_key[$i]}" "${ch_want[$i]}"
    say "set ${ch_key[$i]} = ${ch_want[$i]}"
    i=$((i + 1))
done
say "configured profile $uuid ($n change(s)); open a new window to see them"
