#!/bin/bash
# Checks scripts/gnome-terminal.sh against real gsettings/dconf. It re-runs
# itself inside a private D-Bus session with a temporary HOME and XDG dirs,
# so the desktop's real GNOME Terminal settings are never touched.
# Needs: gnome-terminal (its schemas), gsettings, dconf, dbus-run-session.
# Skips (exit 0) where they are missing, e.g. on macOS.
#   Debian: bash tests/terminal/gnome_terminal_spec.sh
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
gt="$repo/scripts/gnome-terminal.sh"
settings="$repo/terminal/gnome-terminal.dconf"

if [ "${1:-}" != --inner ]; then
    for tool in gsettings dconf dbus-run-session; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "[gnome_terminal_spec] SKIP: $tool not installed"
            exit 0
        fi
    done
    if ! gsettings list-schemas 2>/dev/null | grep -x org.gnome.Terminal.ProfilesList >/dev/null; then
        echo "[gnome_terminal_spec] SKIP: GNOME Terminal schemas not installed"
        exit 0
    fi
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/home" "$tmp/config" "$tmp/run" "$tmp/bin"
    chmod 700 "$tmp/run"
    rc=0
    env HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" XDG_RUNTIME_DIR="$tmp/run" \
        GSETTINGS_BACKEND=dconf dbus-run-session -- /bin/bash "$0" --inner "$tmp" || rc=$?
    exit "$rc"
fi

tmp="$2"
pass=0
fail=0
ok() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  - FAIL: $name"
    fi
}
eq() {
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  - FAIL: $1: expected [$3], got [$2]"
    fi
}
fails() { ! "$@"; }
missing() { [ ! -e "$1" ]; }
# grep without -q: with pipefail, -q's early exit can SIGPIPE printf
contains() { printf '%s\n' "$1" | grep -F -- "$2" >/dev/null; }

uuid="$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'")"
P="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$uuid/"
G="org.gnome.Terminal.Legacy.Settings"
want() { sed -n "s/^$1=//p" "$settings"; }

eq "fresh dconf is empty" "$(dconf dump /org/gnome/terminal/)" ""

# 1. No Nerd Font (fc-list stub finds nothing): dry-run and check change nothing
printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/fc-list"
chmod +x "$tmp/bin/fc-list"
export PATH="$tmp/bin:$PATH"
out="$("$gt" --dry-run)"
ok "dry-run lists the palette" contains "$out" "would set palette:"
ok "dry-run says the font is missing" contains "$out" "not found by fc-list"
ok "dry-run leaves the font alone" fails contains "$out" "would set font:"
eq "dry-run changed nothing" "$(dconf dump /org/gnome/terminal/)" ""
ok "check exits 1 while settings differ" fails "$gt" --check
ok "doctor warns while settings differ" contains "$(bash "$repo/scripts/doctor.sh")" "WARN  GNOME Terminal profile differs: "
ok "dry-run made no backup" missing "$HOME/.dotfiles-backup"

# 2. Apply without the font
out="$("$gt" --backup-dir "$tmp/backup1")"
ok "backup written first" test -f "$tmp/backup1/gnome-terminal.dconf"
for key in cursor-shape cursor-blink-mode audible-bell scrollback-unlimited bold-is-bright \
    use-theme-colors foreground-color background-color palette; do
    eq "profile $key" "$(gsettings get "$P" "$key")" "$(want "$key")"
done
eq "menu-accelerator-enabled" "$(gsettings get "$G" menu-accelerator-enabled)" false
eq "mnemonics-enabled" "$(gsettings get "$G" mnemonics-enabled)" false
eq "font untouched without the font" "$(gsettings get "$P" use-system-font)" true
ok "dconf holds the changed profile keys" contains "$(dconf dump /org/gnome/terminal/)" "cursor-blink-mode='off'"

# 3. Second run is a no-op (no backup, check passes)
out="$("$gt")"
ok "second run: already configured" contains "$out" "already configured"
ok "second run made no backup" missing "$HOME/.dotfiles-backup"
ok "check passes when configured" "$gt" --check

# 4. With the Nerd Font present, the font keys follow
printf '#!/bin/sh\necho "JetBrainsMono Nerd Font Mono"\n' >"$tmp/bin/fc-list"
out="$("$gt" --backup-dir "$tmp/backup2")"
eq "font set" "$(gsettings get "$P" font)" "$(want font)"
eq "use-system-font off" "$(gsettings get "$P" use-system-font)" false
ok "backup 2 has the earlier state" contains "$(cat "$tmp/backup2/gnome-terminal.dconf")" "cursor-blink-mode='off'"
ok "check passes with the font" "$gt" --check
out="$(VTE_VERSION=7600 bash "$repo/scripts/doctor.sh")"
ok "doctor: profile matches" contains "$out" "PASS  GNOME Terminal profile matches terminal/gnome-terminal.dconf"
ok "doctor: Nerd Font found" contains "$out" "PASS  JetBrainsMono Nerd Font Mono installed"
ok "doctor: VTE noted" contains "$out" "PASS  VTE 7600 (GNOME Terminal)"

# 5. The undo hint restores the previous state
dconf reset -f /org/gnome/terminal/
dconf load /org/gnome/terminal/ <"$tmp/backup1/gnome-terminal.dconf"
eq "restore from backup 1: font back to system" "$(gsettings get "$P" use-system-font)" true

if [ "$fail" -eq 0 ]; then
    echo "[gnome_terminal_spec] OK $pass passed"
else
    echo "[gnome_terminal_spec] FAIL $fail failed, $pass passed"
    exit 1
fi
