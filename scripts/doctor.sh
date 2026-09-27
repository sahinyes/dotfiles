#!/bin/bash
# Read-only terminal diagnostics for this setup (macOS + iTerm2, Debian +
# GNOME Terminal). Prints PASS/WARN lines; each WARN says how to fix it.
# It only reads: environment, versions, terminfo, fonts, iTerm2/GNOME
# Terminal preferences. Nothing is written or changed.
#
# Usage: scripts/doctor.sh [--osc52]
#   --osc52   you enabled iTerm2 clipboard access (OSC 52) on purpose
# Exit status is 0; count the WARN lines.
set -euo pipefail

osc52=false
while [ $# -gt 0 ]; do
    case "$1" in
    --osc52) osc52=true && shift ;;
    -h | --help)
        sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "doctor: unknown option: $1" >&2
        exit 2
        ;;
    esac
done

repo="$(cd "$(dirname "$0")/.." && pwd)"
os="$(uname -s)"
npass=0
nwarn=0

pass() {
    printf 'PASS  %s\n' "$1"
    npass=$((npass + 1))
}
warn() { # warn WHAT FIX
    printf 'WARN  %s\n      fix: %s\n' "$1" "$2"
    nwarn=$((nwarn + 1))
}
have() { command -v "$1" >/dev/null 2>&1; }
tilde() { # show paths under $HOME as ~/...
    case "$1" in
    "$HOME"/*) printf '%s/%s' '~' "${1#"$HOME"/}" ;;
    *) printf '%s' "$1" ;;
    esac
}
r="$(tilde "$repo")"

echo "== terminal doctor: $os, TERM=${TERM:-unset}${TMUX:+, inside tmux}${SSH_TTY:+, over SSH} =="

# ── Common ──────────────────────────────────────────────────────────────────
if [ -n "${TMUX:-}" ]; then
    if [ "${TERM:-}" = tmux-256color ]; then
        pass "TERM=tmux-256color inside tmux"
    else
        warn "TERM=${TERM:-unset} inside tmux (want tmux-256color)" \
            "tmux.conf sets default-terminal; restart the tmux server (tmux kill-server)"
    fi
elif [ "${TERM:-}" = xterm-256color ]; then
    pass "TERM=xterm-256color"
else
    warn "TERM=${TERM:-unset} (want xterm-256color outside tmux)" \
        "iTerm2: Settings > Profiles > Terminal > Report terminal type: xterm-256color; do not export TERM in your shell rc"
fi

if have tmux; then
    tv="$(tmux -V | awk '{print $2}')"
    case "$tv" in
    [3-9].[3-9]* | [4-9].* | 3.[1-9][0-9]*) pass "tmux $tv" ;;
    *) warn "tmux $tv is older than 3.3 (tmux.conf needs 3.3+)" "Mac: brew upgrade tmux; Debian: use the suite's tmux (bookworm 3.3a, trixie 3.5a)" ;;
    esac
else
    warn "tmux not installed" "Mac: brew install tmux; Debian: install.sh (apt_extract) or ask IT for the tmux package"
fi

if have nvim; then
    nv="$(nvim --version 2>/dev/null | head -n 1 || true)"
    np="$(tilde "$(command -v nvim)")"
    case "$nv" in
    "NVIM v0.12."*) pass "nvim ${nv#NVIM } at $np" ;;
    *) warn "nvim at $np is '${nv:-unknown}', this config wants 0.12.x" \
        "put ~/.local/bin (install.sh's nvim) or Homebrew first on PATH; run install.sh" ;;
    esac
else
    warn "nvim not found on PATH" "run $r/install.sh"
fi

lb="$(tilde "$HOME/.local/bin")"
case ":$PATH:" in
*":$HOME/.local/bin:"*) pass "$lb is on PATH" ;;
*) warn "$lb is not on PATH (tools and nvim installed there are not found)" \
    "add '. $r/shell/env.sh' to your shell rc (install.sh --shell-rc does it)" ;;
esac

if have infocmp; then
    if infocmp -x tmux-256color 2>/dev/null | grep 'Smulx=' >/dev/null; then
        pass "tmux-256color terminfo has Smulx (undercurl inside tmux)"
    elif [ "$os" = Darwin ]; then
        warn "tmux-256color terminfo lacks Smulx (no undercurl inside tmux)" "$r/scripts/terminfo-mac.sh"
    else
        warn "tmux-256color terminfo lacks Smulx (no undercurl inside tmux)" \
            "on the Mac: infocmp -x tmux-256color | ssh <this host> 'mkdir -p ~/.terminfo && tic -x -o ~/.terminfo -'"
    fi
else
    warn "infocmp not found; cannot check terminfo" "Mac: part of the OS; Debian: package ncurses-bin"
fi

# Clipboard tools used by Neovim's "+ register and tmux's copy-command
if [ "$os" = Darwin ]; then
    if have pbcopy && have pbpaste; then
        pass "clipboard: pbcopy/pbpaste"
    else
        warn "pbcopy/pbpaste missing" "they ship with macOS; check PATH includes /usr/bin"
    fi
elif [ -n "${WAYLAND_DISPLAY:-}" ]; then
    if have wl-copy && have wl-paste; then
        pass "clipboard: wl-copy/wl-paste (Wayland)"
    else
        warn "Wayland session without wl-copy/wl-paste (\"+y and tmux yank cannot reach the clipboard)" \
            "install.sh extracts wl-clipboard without sudo (apt_extract); or ask IT for wl-clipboard"
    fi
elif [ -n "${DISPLAY:-}" ]; then
    if have xclip || have xsel; then
        pass "clipboard: $(have xclip && echo xclip || echo xsel) (X11)"
    else
        warn "X11 session without xclip/xsel" "ask IT for the xclip package"
    fi
else
    pass "no graphical session: Neovim and tmux keep yanks in tmux buffers"
fi
if [ -n "${TMUX:-}" ]; then
    if ! cc="$(tmux show -sv copy-command 2>/dev/null)"; then
        warn "cannot query the running tmux server (tmux upgraded while it runs?)" \
            "save your work, then restart it: tmux kill-server; tmux"
    elif [ -n "$cc" ]; then
        pass "tmux copy-mode yank pipes to: $cc"
    else
        warn "tmux copy-mode yank only fills tmux buffers (no clipboard tool when the server started)" \
            "install a clipboard tool, then: tmux source-file ~/.tmux.conf"
    fi
fi

nerd="JetBrainsMono Nerd Font Mono"
if [ "$os" = Darwin ]; then
    if [ -n "$(find "$HOME/Library/Fonts" /Library/Fonts -maxdepth 2 -iname 'JetBrainsMonoNerdFontMono-*' 2>/dev/null | head -n 1)" ]; then
        pass "$nerd installed"
    else
        warn "$nerd not installed (icons show as boxes)" "brew install --cask font-jetbrains-mono-nerd-font"
    fi
elif have fc-list; then
    if fc-list : family | grep -iF "$nerd" >/dev/null; then
        pass "$nerd installed"
    else
        warn "$nerd not installed (icons show as boxes)" "install.sh (fonts step), then open a new terminal window"
    fi
else
    warn "fc-list not found; cannot check fonts" "Debian: package fontconfig"
fi

# ── macOS: iTerm2 (read-only: defaults export) ──────────────────────────────
if [ "$os" = Darwin ]; then
    prefs="$(defaults export com.googlecode.iterm2 - 2>/dev/null || true)"
    if [ -z "$prefs" ]; then
        pass "iTerm2 preferences not found; iTerm2 checks skipped"
    else
        pget() { printf '%s' "$prefs" | plutil -extract "$1" raw -o - - 2>/dev/null || true; }
        is_true() { case "$1" in 1 | true | YES) return 0 ;; esac; return 1; }
        guid="$(pget 'Default Bookmark Guid')"
        count="$(pget 'New Bookmarks')"
        idx=""
        i=0
        while [ "$i" -lt "${count:-0}" ]; do
            if [ "$(pget "New Bookmarks.$i.Guid")" = "$guid" ]; then
                idx="$i"
                break
            fi
            i=$((i + 1))
        done
        if [ -z "$idx" ]; then
            warn "iTerm2 default profile ($guid) is not in the preferences (a Dynamic Profile?)" \
                "check it by hand: Settings > Profiles > Keys and Terminal"
        else
            p="New Bookmarks.$idx"
            name="$(pget "$p.Name")"
            where="Settings > Profiles > $name"
            # iTerm2 defaults when a key is absent (iTermProfilePreferences.m)
            left="$(pget "$p.Option Key Sends")"
            right="$(pget "$p.Right Option Key Sends")"
            if [ "${left:-0}" = 0 ] && [ "${right:-0}" = 0 ]; then
                pass "iTerm2: both Option keys = Normal (Option+5 types [ on Swiss German)"
            else
                warn "iTerm2: Option keys are not both Normal (left=${left:-0} right=${right:-0}; 0=Normal)" \
                    "$where > Keys > General: Left and Right Option key: Normal"
            fi
            csiu="$(pget "$p.Use libtickit protocol")"
            if is_true "${csiu:-false}"; then
                warn "iTerm2: 'Report keys using CSI u' is on" \
                    "$where > Keys > General: uncheck 'Report keys using CSI u' (Neovim negotiates keys itself)"
            else
                pass "iTerm2: 'Report keys using CSI u' off"
            fi
            mok="$(pget "$p.Allow modifyOtherKeys")"
            if is_true "${mok:-true}"; then
                pass "iTerm2: 'Apps can change how keys are reported' on"
            else
                warn "iTerm2: 'Apps can change how keys are reported' is off" \
                    "$where > Keys > General: check 'Apps can change how keys are reported'"
            fi
            alt="$(pget "$p.Treat Option as Alt")"
            if [ -z "$alt" ]; then
                legacy="$(pget OptionIsMetaForSpecialChars)"
                if [ -n "$legacy" ]; then
                    if is_true "$legacy"; then alt=false; else alt=true; fi
                fi
            fi
            if is_true "${alt:-true}"; then
                pass "iTerm2: Option+arrow reaches tmux as Alt+arrow (pane switching)"
            else
                warn "iTerm2: Option+arrow is not sent as Alt+arrow (tmux Option+arrow pane switching fails)" \
                    "$where > Keys > General: check 'Treat Option as Alt for special keys like arrows'"
            fi
            unlimited="$(pget "$p.Unlimited Scrollback")"
            lines="$(pget "$p.Scrollback Lines")"
            if is_true "${unlimited:-false}"; then
                pass "iTerm2: unlimited scrollback"
            elif [ "${lines:-1000}" -ge 10000 ] 2>/dev/null; then
                pass "iTerm2: scrollback $lines lines"
            else
                warn "iTerm2: scrollback is only ${lines:-1000} lines (long logs scroll away outside tmux)" \
                    "$where > Terminal: Scrollback lines 10000 or more, or Unlimited scrollback"
            fi
            font="$(pget "$p.Normal Font")"
            case "$font" in
            *NF* | *Nerd*) pass "iTerm2: font $font" ;;
            *) warn "iTerm2: font '${font:-default}' is not a Nerd Font (icons show as boxes)" \
                "$where > Text > Font: JetBrainsMono Nerd Font Mono" ;;
            esac
            ttype="$(pget "$p.Terminal Type")"
            if [ "${ttype:-xterm-256color}" = xterm-256color ]; then
                pass "iTerm2: reports xterm-256color"
            else
                warn "iTerm2: reports '$ttype'" "$where > Terminal > Report terminal type: xterm-256color"
            fi
        fi
        clip="$(pget AllowClipboardAccess)"
        if ! is_true "${clip:-false}"; then
            pass "iTerm2: terminal apps cannot write the clipboard (OSC 52 off)"
        elif [ "$osc52" = true ]; then
            pass "iTerm2: OSC 52 clipboard access on (accepted: --osc52)"
        else
            warn "iTerm2: terminal apps may write the clipboard (OSC 52): output of curl/cat can replace what you paste" \
                "Settings > General > Selection: uncheck 'Applications in terminal may access clipboard' (or pass --osc52 if you want it)"
        fi
    fi
fi

# ── Linux: GNOME Terminal / VTE ─────────────────────────────────────────────
if [ "$os" = Linux ]; then
    if have gsettings && gsettings list-schemas 2>/dev/null | grep -x 'org.gnome.Terminal.ProfilesList' >/dev/null; then
        if gt_out="$(bash "$repo/scripts/gnome-terminal.sh" --check 2>&1)"; then
            pass "GNOME Terminal profile matches terminal/gnome-terminal.dconf"
        else
            keys="$(printf '%s\n' "$gt_out" | sed -n 's/^gnome-terminal: would set \([a-z0-9-]*\):.*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
            warn "GNOME Terminal profile differs: ${keys:-see $r/scripts/gnome-terminal.sh --dry-run}" \
                "$r/scripts/gnome-terminal.sh (backs up with dconf dump first)"
        fi
    fi
    if [ -n "${VTE_VERSION:-}" ]; then
        pass "VTE $VTE_VERSION (GNOME Terminal): no OSC 52, clipboard goes through wl-copy/xclip"
        if [ -n "${TMUX:-}" ]; then
            if tmux show -s terminal-features 2>/dev/null | grep usstyle >/dev/null; then
                pass "tmux declares usstyle for VTE (undercurl inside tmux)"
            else
                warn "tmux does not declare usstyle for VTE (no undercurl inside tmux)" \
                    "start the tmux server from GNOME Terminal (tmux kill-server, then tmux)"
            fi
        fi
    fi
fi

echo "== $npass PASS, $nwarn WARN =="
