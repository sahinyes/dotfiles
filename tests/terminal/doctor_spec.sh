#!/bin/bash
# Checks scripts/doctor.sh. On macOS the iTerm2 checks read fake preferences
# through a stub `defaults` placed first on PATH, so the real iTerm2 settings
# are never read or changed. On Linux only the common checks run here (the
# GNOME Terminal part is covered by gnome_terminal_spec.sh).
# Usage: bash tests/terminal/doctor_spec.sh
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
doctor="$repo/scripts/doctor.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
has() { # has NAME OUTPUT LINE-ERE
    # grep without -q: with pipefail, -q's early exit can SIGPIPE printf
    if printf '%s\n' "$2" | grep -E -- "$3" >/dev/null; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  - FAIL: $1 (no line matching: $3)"
    fi
}
hasnt() {
    if printf '%s\n' "$2" | grep -E -- "$3" >/dev/null; then
        fail=$((fail + 1))
        echo "  - FAIL: $1 (unexpected line matching: $3)"
    else
        pass=$((pass + 1))
    fi
}

# Common checks, with a controlled environment
out="$(env -u TMUX TERM=xterm-256color PATH="$HOME/.local/bin:$PATH" /bin/bash "$doctor")"
has "summary line" "$out" '^== [0-9]+ PASS, [0-9]+ WARN ==$'
has "TERM ok" "$out" '^PASS  TERM=xterm-256color$'
has "local bin on PATH" "$out" '^PASS  ~/.local/bin is on PATH$'
out="$(env -u TMUX TERM=vt100 PATH="/usr/bin:/bin:$(dirname "$(command -v tmux 2>/dev/null || echo /usr/bin/x)")" /bin/bash "$doctor")"
has "bad TERM warns" "$out" '^WARN  TERM=vt100'
has "missing ~/.local/bin warns" "$out" '^WARN  ~/.local/bin is not on PATH'
has "every WARN has a fix" "$out" '^      fix: '
out="$(env TMUX=/nonexistent/sock,1,0 TERM=tmux-256color /bin/bash "$doctor")"
has "unreachable tmux server warns" "$out" '^WARN  cannot query the running tmux server'

if [ "$(uname -s)" = Darwin ]; then
    mkdir -p "$tmp/bin"
    cat >"$tmp/bin/defaults" <<'EOF'
#!/bin/sh
cat "$FAKE_ITERM_PLIST"
EOF
    chmod +x "$tmp/bin/defaults"
    # plist_from JSON OUT: build a fake com.googlecode.iterm2 plist
    plist_from() { printf '%s' "$1" >"$tmp/p.json" && plutil -convert xml1 -o "$2" "$tmp/p.json"; }
    run_fake() { FAKE_ITERM_PLIST="$1" PATH="$tmp/bin:$PATH" /bin/bash "$doctor" "${@:2}"; }

    plist_from '{"Default Bookmark Guid":"G1","New Bookmarks":[{"Guid":"G1","Name":"Main",
      "Option Key Sends":0,"Right Option Key Sends":0,"Unlimited Scrollback":true,
      "Normal Font":"JetBrainsMonoNFM-Regular 13","Terminal Type":"xterm-256color"}]}' "$tmp/good.plist"
    out="$(run_fake "$tmp/good.plist")"
    hasnt "good prefs: no iTerm2 WARN" "$out" '^WARN  iTerm2'
    has "good prefs: Option keys" "$out" '^PASS  iTerm2: both Option keys = Normal'
    has "good prefs: CSI u off (default)" "$out" "^PASS  iTerm2: 'Report keys using CSI u' off"
    has "good prefs: key reporting on (default)" "$out" "^PASS  iTerm2: 'Apps can change how keys are reported' on"
    has "good prefs: clipboard off (default)" "$out" '^PASS  iTerm2: terminal apps cannot write the clipboard'

    plist_from '{"Default Bookmark Guid":"G2","AllowClipboardAccess":true,"New Bookmarks":[
      {"Guid":"G1","Name":"Other","Option Key Sends":0},
      {"Guid":"G2","Name":"Main","Option Key Sends":2,"Right Option Key Sends":0,
       "Use libtickit protocol":true,"Allow modifyOtherKeys":false,"Treat Option as Alt":false,
       "Unlimited Scrollback":false,"Scrollback Lines":1000,"Normal Font":"Monaco 12",
       "Terminal Type":"xterm"}]}' "$tmp/bad.plist"
    out="$(run_fake "$tmp/bad.plist")"
    has "bad: Option key" "$out" '^WARN  iTerm2: Option keys are not both Normal \(left=2 right=0'
    has "bad: fix names the profile" "$out" '^      fix: Settings > Profiles > Main > Keys'
    has "bad: CSI u" "$out" "^WARN  iTerm2: 'Report keys using CSI u' is on"
    has "bad: key reporting" "$out" "^WARN  iTerm2: 'Apps can change how keys are reported' is off"
    has "bad: Option as Alt" "$out" '^WARN  iTerm2: Option\+arrow is not sent as Alt\+arrow'
    has "bad: scrollback" "$out" '^WARN  iTerm2: scrollback is only 1000 lines'
    has "bad: font" "$out" "^WARN  iTerm2: font 'Monaco 12' is not a Nerd Font"
    has "bad: terminal type" "$out" "^WARN  iTerm2: reports 'xterm'"
    has "bad: clipboard" "$out" '^WARN  iTerm2: terminal apps may write the clipboard'
    out="$(run_fake "$tmp/bad.plist" --osc52)"
    has "--osc52 accepts clipboard access" "$out" '^PASS  iTerm2: OSC 52 clipboard access on \(accepted: --osc52\)'

    plist_from '{"Default Bookmark Guid":"G9","New Bookmarks":[{"Guid":"G1"}]}' "$tmp/dyn.plist"
    out="$(run_fake "$tmp/dyn.plist")"
    has "default profile missing warns" "$out" '^WARN  iTerm2 default profile \(G9\) is not in the preferences'
fi

if [ "$fail" -eq 0 ]; then
    echo "[doctor_spec] OK $pass passed"
else
    echo "[doctor_spec] FAIL $fail failed, $pass passed"
    exit 1
fi
