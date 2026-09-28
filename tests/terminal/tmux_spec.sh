#!/bin/bash
# Checks tmux/tmux.conf and tmux/scripts on an ISOLATED tmux server: its own
# socket (-L) and a temporary HOME, so the user's running tmux, resurrect
# saves and clipboard are never touched (the clipboard is only read).
# Usage: bash tests/terminal/tmux_spec.sh     (macOS or Linux, bash 3.2+)
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
conf="$repo/tmux/tmux.conf"
scripts="$repo/tmux/scripts"
st="$scripts/status.sh"

if ! command -v tmux >/dev/null 2>&1; then
    echo "[tmux_spec] SKIP: tmux not installed"
    exit 0
fi
# Absolute path: some servers below start with a reduced PATH.
tmux_bin="$(command -v tmux)"

tmp="$(mktemp -d)"
sock="sahin-test-$$"
home="$tmp/home"
fakebin="$tmp/bin"
mkdir -p "$home/.tmux" "$fakebin" "$tmp/nobin"
# nobin: a PATH entry holding only tmux (plugins call it), no other tools
ln -s "$tmux_bin" "$tmp/nobin/tmux"
ln -s "$conf" "$home/.tmux.conf"
ln -s "$scripts" "$home/.tmux/scripts"

sock_path=""
cleanup() {
    "$tmux_bin" -L "$sock" kill-server >/dev/null 2>&1 || true
    if [ -n "$sock_path" ]; then rm -f "$sock_path"; fi
    rm -rf "$tmp"
}
trap cleanup EXIT

pass=0
fail=0
ok() { # ok NAME COMMAND... : passes when COMMAND succeeds
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  - FAIL: $name"
    fi
}
eq() { # eq NAME ACTUAL EXPECTED
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  - FAIL: $1: expected [$3], got [$2]"
    fi
}

# Predicates used with ok
# No grep -q after a pipe: with pipefail its early exit can SIGPIPE the
# writer and turn a match into a failure.
contains() { printf '%s\n' "$1" | grep -E -- "$2" >/dev/null; } # contains TEXT ERE
lacks() { ! contains "$@"; }
missing() { [ ! -e "$1" ]; }
private_dir() { [ -n "$(find "$1" -prune -type d -perm 0700)" ]; }
file_has() { grep -aq -- "$2" "$1"; } # file_has FILE TEXT
file_lacks() { ! file_has "$@"; }
percentage() { "$st" "$1" | grep -E '^[0-9]+%$' >/dev/null; }
prints_something() { [ -n "$("$st" "$1")" ]; }

t() { env -u TMUX HOME="$home" "$tmux_bin" -L "$sock" "$@"; }
has_client() { [ -n "$(t list-clients)" ]; }
has_buffer() { [ -n "$(t list-buffers)" ]; }
pane_has() { t capture-pane -p -t main | grep -- "$1" >/dev/null; }

# Start a fresh server from the config. Extra VAR=value args go into its
# environment; VTE_VERSION/WAYLAND_DISPLAY/DISPLAY are cleared first so the
# result does not depend on the terminal running the test.
# The old server must be gone first: a client that connects while it shuts
# down gets "server exited unexpectedly".
server_pid=""
gone() { ! kill -0 "$1" 2>/dev/null; }
start() {
    t kill-server >/dev/null 2>&1 || true
    if [ -n "$server_pid" ]; then wait_for gone "$server_pid" || true; fi
    env -u TMUX -u VTE_VERSION -u WAYLAND_DISPLAY -u DISPLAY HOME="$home" "$@" \
        "$tmux_bin" -L "$sock" -f "$conf" new-session -d -s main -x 100 -y 30 "sleep 600"
    server_pid="$(t display -p '#{pid}')"
}
# attach_client SESSION OUT: a real client inside `script`, so every byte
# tmux sends to the "outer terminal" lands in OUT (-F/-f flush every write,
# so the file is live). Its stdin is a pipe that stays open while
# $tmp/clients-on exists (BSD script rejects a fifo as stdin). Detach:
# t kill-server; rm -f "$tmp/clients-on"; wait for the returned $!.
keep_open() { while [ -e "$tmp/clients-on" ]; do sleep 0.2; done; }
attach_client() {
    : >"$tmp/clients-on"
    if script --version 2>/dev/null | grep util-linux >/dev/null; then
        printf '#!/bin/sh\nexec "%s" -L "%s" attach -t "%s"\n' "$tmux_bin" "$sock" "$1" >"$tmp/attach-$1.sh"
        chmod +x "$tmp/attach-$1.sh"
        keep_open | env -u TMUX HOME="$home" TERM=xterm-256color \
            script -q -f -c "$tmp/attach-$1.sh" "$2" >/dev/null 2>&1 &
    else
        keep_open | env -u TMUX HOME="$home" TERM=xterm-256color \
            script -q -F "$2" "$tmux_bin" -L "$sock" attach -t "$1" >/dev/null 2>&1 &
    fi
}
wait_for() { # wait_for COMMAND... : retry for up to 5 s
    local i=0
    while [ "$i" -lt 50 ]; do
        if "$@" >/dev/null 2>&1; then return 0; fi
        sleep 0.1
        i=$((i + 1))
    done
    return 1
}

# Fake plugins: record that they ran, in which order, and whether
# status-right was already set (continuum hooks into it).
make_fake_plugins() {
    mkdir -p "$home/.tmux/plugins/tmux-resurrect" "$home/.tmux/plugins/tmux-continuum"
    cat >"$home/.tmux/plugins/tmux-resurrect/resurrect.tmux" <<'EOF'
#!/bin/sh
tmux set -g @fake-resurrect yes
EOF
    cat >"$home/.tmux/plugins/tmux-continuum/continuum.tmux" <<'EOF'
#!/bin/sh
tmux set -g @fake-continuum yes
[ "$(tmux show -gv @fake-resurrect)" = yes ] && tmux set -g @fake-continuum-after-resurrect yes
case "$(tmux show -gv status-right)" in *status.sh*) tmux set -g @fake-continuum-saw-status yes ;; esac
EOF
    chmod +x "$home/.tmux/plugins/tmux-resurrect/resurrect.tmux" \
        "$home/.tmux/plugins/tmux-continuum/continuum.tmux"
}

echo "[tmux_spec] tmux $("$tmux_bin" -V | awk '{print $2}') with $conf"

# ── 1. Base server: options, keys, plugins ──────────────────────────────────
make_fake_plugins
start PATH="$tmp/nobin:/usr/bin:/bin"
sock_path="$(t display -p '#{socket_path}')"
ok "config re-sources without errors" t source-file "$conf"
eq "set-clipboard" "$(t show -sv set-clipboard)" external
eq "allow-passthrough" "$(t show -gwv allow-passthrough)" off
eq "extended-keys" "$(t show -sv extended-keys)" off
eq "escape-time" "$(t show -sv escape-time)" 10
eq "focus-events" "$(t show -sv focus-events)" on
eq "prefix" "$(t show -gv prefix)" C-a
eq "default-terminal" "$(t show -sv default-terminal)" tmux-256color
eq "resurrect captures panes without work marker" "$(t show -gv @resurrect-capture-pane-contents)" on
# shellcheck disable=SC2088 # the literal "~" is what the option must hold
eq "@resurrect-dir" "$(t show -gv @resurrect-dir)" "~/.local/share/tmux/resurrect"
ok "no usstyle outside VTE" lacks "$(t show -s terminal-features)" usstyle
ok "status-left shows the session" contains "$(t display -p -t main: '#{T:status-left}')" ' main '
# tmux 3.3 reads "#D" inside a status format as the pane id (fg=%0...)
ok "status-right colors survive format expansion" lacks "$(t display -p -t main: '#{T:status-right}')" '=%'
keys="$(t list-keys)"
ok "dead M-h/j/k/l 1-cell resizes are gone" lacks "$keys" 'resize-pane -[LDUR] 1$'
for k in Left Right Up Down; do
    ok "root M-$k selects a pane" contains "$keys" "T root +M-$k +select-pane"
done
ok "no tpm bindings" lacks "$keys" tpm
ok "no @plugin options (tpm dropped)" lacks "$(t show -g)" '@plugin'
ok "copy-mode-vi y pipes to copy-command" contains "$keys" 'copy-mode-vi +y +send-keys -X copy-pipe-and-cancel$'
ok "prefix r reloads ~/.tmux.conf" contains "$keys" "T prefix +r +source-file $home/.tmux.conf"
ok "no sesh binding without sesh" lacks "$keys" 'sesh connect'
eq "resurrect plugin loaded" "$(t show -gv @fake-resurrect)" yes
eq "continuum loaded after resurrect" "$(t show -gv @fake-continuum-after-resurrect)" yes
eq "continuum saw status-right" "$(t show -gv @fake-continuum-saw-status)" yes
ok "resurrect dir is private (0700)" private_dir "$home/.local/share/tmux/resurrect"
if command -v pbcopy >/dev/null 2>&1; then
    eq "copy-command on macOS" "$(t show -sv copy-command)" pbcopy
else
    eq "no clipboard tool: copy-command empty" "$(t show -sv copy-command)" ""
fi

# ── 2. OSC 52 from a pane never reaches the clipboard ───────────────────────
# A real client is attached inside `script` (attach_client), so every byte
# tmux sends to the "outer terminal" lands in client.out and can be searched.
emit="$tmp/emit.sh"
cat >"$emit" <<'EOF'
#!/bin/sh
# BEL-terminated, ST-terminated and DCS-passthrough-wrapped OSC 52
printf 'copy-me\n'
printf '\033]52;c;SGk=\007'
printf '\033]52;c;U1Q=\033\\'
printf '\033Ptmux;\033\033]52;c;UFQ=\007\033\\'
printf 'emitted\n'
exec sleep 600
EOF
out="$tmp/client.out"
attach_client main "$out"
client_pid=$!
ok "test client attached" wait_for has_client

clip_before=""
if command -v pbpaste >/dev/null 2>&1; then clip_before="$(pbpaste | cksum)"; fi

t clear-history -t main
t respawn-pane -k -t main "sh '$emit'"
ok "emitter ran" wait_for pane_has emitted
sleep 0.3
eq "pane OSC 52 creates no tmux buffer" "$(t list-buffers)" ""
for payload in SGk= U1Q= UFQ=; do
    ok "pane OSC 52 ($payload) not forwarded to the terminal" file_lacks "$out" "52;c;$payload"
done

# tmux's own copy mode still sets the terminal clipboard (base64 "copy-me\n")
t copy-mode -t main
t send-keys -t main -X history-top
t send-keys -t main -X select-line
t send-keys -t main -X copy-selection-and-cancel
ok "copy mode sends OSC 52 to the terminal" wait_for file_has "$out" "52;;Y29weS1tZQo="
# Neovim's tmux clipboard provider copies with `tmux load-buffer -w -`
printf 'nv-yank' | t load-buffer -w -
ok "load-buffer -w (Neovim tmux provider) reaches the terminal" wait_for file_has "$out" "bnYteWFuaw=="

# Control: with set-clipboard on, the same kind of sequence DOES get through,
# which proves the checks above can see a leak.
t set -s set-clipboard on
t delete-buffer >/dev/null 2>&1 || true
t respawn-pane -k -t main "printf '\033]52;c;T04=\007'; exec sleep 600"
ok "control: set-clipboard on creates a buffer" wait_for has_buffer
case "$("$tmux_bin" -V | awk '{print $2}')" in
[12].* | 3.[0-3] | 3.[0-3][a-z]) ;; # tmux < 3.4 only makes the buffer
*) ok "control: set-clipboard on forwards pane OSC 52" wait_for file_has "$out" "52;c;T04=" ;;
esac
t set -s set-clipboard external

if [ -n "$clip_before" ]; then
    eq "system clipboard unchanged (pbpaste)" "$(pbpaste | cksum)" "$clip_before"
fi

# y in copy mode pipes the selection to copy-command (pointed at a file here,
# so the real clipboard stays untouched).
t set -s copy-command "cat > '$tmp/yanked'"
t respawn-pane -k -t main "sh '$emit'"
ok "emitter ran again" wait_for pane_has emitted
t copy-mode -t main
t send-keys -t main -X history-top
t send-keys -t main -X select-line
t send-keys -t main y
ok "y wrote the selection through copy-command" wait_for grep -qx copy-me "$tmp/yanked"

t kill-server
rm -f "$tmp/clients-on"
wait "$client_pid" 2>/dev/null || true

# ── 3. Variants: work marker, VTE, no plugins, clipboard tools, sesh ────────
# Work laptop: no pane text, and no continuum, so nothing is saved on its
# own (every save also records the command line of each running program).
mkdir -p "$home/.config/dotfiles"
: >"$home/.config/dotfiles/work"
start PATH="$tmp/nobin:/usr/bin:/bin"
eq "work marker turns pane capture off" "$(t show -gv @resurrect-capture-pane-contents)" off
eq "work marker: resurrect loaded (manual save)" "$(t show -gqv @fake-resurrect)" yes
eq "work marker: continuum not loaded (no auto-save)" "$(t show -gqv @fake-continuum)" ""
rm -f "$home/.config/dotfiles/work"

rm -rf "$home/.tmux/plugins" "$home/.local/share/tmux"
start PATH="$tmp/nobin:/usr/bin:/bin"
eq "no plugins: nothing loaded" "$(t show -gqv @fake-resurrect)" ""
ok "no plugins: no resurrect dir created" missing "$home/.local/share/tmux/resurrect"

start PATH="$tmp/nobin:/usr/bin:/bin" VTE_VERSION=7600
ok "VTE gets usstyle" contains "$(t show -s terminal-features)" 'xterm-256color:usstyle'

# Fake tools; a PATH without /usr/bin also hides pbcopy on macOS.
ln -s "$tmux_bin" "$fakebin/tmux"
for tool in wl-copy xclip sesh fzf-tmux; do
    printf '#!/bin/sh\nexit 0\n' >"$fakebin/$tool"
    chmod +x "$fakebin/$tool"
done
start PATH="$fakebin:/bin" WAYLAND_DISPLAY=wayland-0
eq "Wayland: copy-command wl-copy" "$(t show -sv copy-command)" wl-copy
ok "sesh binding with sesh + fzf-tmux" contains "$(t list-keys)" 'T prefix +T +run-shell "sesh connect'
start PATH="$fakebin:/bin" DISPLAY=:0
eq "X11: copy-command xclip" "$(t show -sv copy-command)" "xclip -selection clipboard"

# ── 4. status.sh segments ───────────────────────────────────────────────────
ok "cpu is a percentage" percentage cpu
ok "ram is a percentage" percentage ram
ok "uptime prints something" prints_something uptime
ok "net prints something" prints_something net
eq "unknown segment prints nothing" "$("$st" nonsense)" ""
eq "claude without cache prints nothing" "$(XDG_CACHE_HOME="$tmp/nocache" "$st" claude)" ""

# Window names: a directory name, or the pane title a remote host sets,
# shows as text and never styles the tab (q/h turns "#" into "##").
mkdir -p "$tmp/#[bg=red]evil"
evil_win="$(t new-window -d -P -F '#{window_id}' -t main -c "$tmp/#[bg=red]evil" "sleep 600")"
window_name_is() { [ "$(t display -p -t "$1" '#{window_name}')" = "$2" ]; }
ok "directory name does not style the tab" wait_for window_name_is "$evil_win" '##[bg=red]evil'
# The ssh branch of the format, evaluated for a hostile title
ssh_fmt="$(t show -gwv automatic-rename-format | sed 's/#{pane_current_command}/ssh/')"
t select-pane -t "$evil_win" -T 'x#[bg=red]y'
eq "remote pane title does not style the tab" "$(t display -p -t "$evil_win" "$ssh_fmt")" 'x##[bg=red]y'

# git segment inside a cloned "target" repo whose fsmonitor hook would
# create a file: it must show the branch and never run the hook.
tmux_env="$(t display -p '#{socket_path}'),$(t display -p '#{pid}'),0"
if command -v git >/dev/null 2>&1; then
    target="$tmp/target"
    mkdir -p "$target"
    git -C "$target" init -q
    git -C "$target" symbolic-ref HEAD refs/heads/probe
    printf '#!/bin/sh\ntouch "%s/pwned"\n' "$tmp" >"$target/hook.sh"
    chmod +x "$target/hook.sh"
    git -C "$target" config core.fsmonitor "$target/hook.sh"
    # A background window: status.sh must use the pane id tmux.conf passes,
    # not whatever pane tmux considers current.
    probe_pane="$(t new-window -d -P -F '#{pane_id}' -t main -c "$target" "sleep 600")"
    eq "git segment shows the branch of the given pane" "$(TMUX="$tmux_env" "$st" git "$probe_pane")" " probe"
    ok "git segment never ran the repo's fsmonitor" missing "$tmp/pwned"
    eq "git segment without a pane id prints nothing" "$(TMUX="$tmux_env" "$st" git)" ""

    # Two clients on two sessions in two repos: each shows its own branch
    # (one shared job used to show the same branch to every client).
    other="$tmp/other"
    mkdir -p "$other"
    git -C "$other" init -q
    git -C "$other" symbolic-ref HEAD refs/heads/other-side
    start PATH="$tmp/nobin:/usr/bin:/bin"
    t respawn-pane -k -t main -c "$target" "sleep 600"
    t new-session -d -s other -c "$other" "sleep 600"
    # Keep only tmux.conf's git job, so it fits the clients' 80 columns.
    t set -g status-right "$(t show -gv status-right | grep -o '#([^)]*status.sh git[^)]*)')"
    attach_client main "$tmp/main.out"
    main_pid=$!
    attach_client other "$tmp/other.out"
    other_pid=$!
    ok "client on session main shows its branch" wait_for file_has "$tmp/main.out" probe
    ok "client on session other shows its branch" wait_for file_has "$tmp/other.out" other-side
    t kill-server
    rm -f "$tmp/clients-on"
    wait "$main_pid" "$other_pid" 2>/dev/null || true
fi

# ── 5. ssh-colors.sh (bash and zsh) ─────────────────────────────────────────
mkdir -p "$tmp/xdg/dotfiles"
cat >"$tmp/xdg/dotfiles/ssh-hosts" <<'EOF'
# host        label
box-a         dev
192.0.2.10    prod
*oob*         oob
EOF
# Fake ssh, "connected" until it exits. It records the status-left, window
# name and tab style of its own pane (line 1) and of the active window
# (line 2). With SSH_WAIT set it stays connected until that file exists.
cat >"$tmp/nobin/ssh" <<EOF
#!/bin/sh
fmt='#{T:status-left}|#{window_name}|#{window-status-style}'
tmux display -p -t "\$TMUX_PANE" "\$fmt" >"$tmp/connected"
tmux display -p -t main: "\$fmt" >>"$tmp/connected"
while [ -n "\$SSH_WAIT" ] && [ ! -e "\$SSH_WAIT" ]; do sleep 0.1; done
EOF
chmod +x "$tmp/nobin/ssh"
# conn LINE FIELD: 1 = the ssh pane, 2 = the active window;
# fields: 1 status-left, 2 window name, 3 tab style
conn() { sed -n "${1}p" "$tmp/connected" | cut -d'|' -f"$2"; }
pane_fmt() { t display -p -t "$1" "$2"; } # pane_fmt PANE FORMAT

start PATH="$tmp/nobin:/usr/bin:/bin"
tmux_env="$(t display -p '#{socket_path}'),$(t display -p '#{pid}'),0"
# ssh runs in background windows 2 and 3; window 1 stays the active one
p2="$(t new-window -d -P -F '#{pane_id}' -t main "sleep 600")"
p3="$(t new-window -d -P -F '#{pane_id}' -t main "sleep 600")"
normal_left="$(pane_fmt "$p2" '#{T:status-left}')"
normal_style="$(pane_fmt "$p2" '#{window-status-style}')"
active_name="$(pane_fmt main: '#{window_name}')"
ssh_wait=""
for sh_name in bash zsh; do
    command -v "$sh_name" >/dev/null 2>&1 || continue
    # run_sh PANE CODE: source the wrapper in a clean $sh_name that runs in
    # PANE ($TMUX_PANE), then run CODE with the fake ssh first on PATH.
    run_sh() {
        local flags="--noprofile --norc"
        if [ "$sh_name" = zsh ]; then flags="-f"; fi
        # shellcheck disable=SC2086 # $flags is a fixed list of options
        env XDG_CONFIG_HOME="$tmp/xdg" HOME="$home" PATH="$tmp/nobin:$PATH" \
            TMUX="$tmux_env" TMUX_PANE="$1" SSH_WAIT="$ssh_wait" \
            "$sh_name" $flags -c ". '$scripts/ssh-colors.sh'; $2"
    }
    eq "$sh_name: exact host" "$(run_sh "$p2" '_ssh_colors_label box-a')" dev
    eq "$sh_name: IP" "$(run_sh "$p2" '_ssh_colors_label 192.0.2.10')" prod
    eq "$sh_name: glob" "$(run_sh "$p2" '_ssh_colors_label my-oob-1')" oob
    eq "$sh_name: unmapped host keeps its name" "$(run_sh "$p2" '_ssh_colors_label other')" other

    rm -f "$tmp/connected"
    run_sh "$p2" 'ssh -p 22 me@box-a' || true
    ok "$sh_name: ssh pane's status bar shows the label" contains "$(conn 1 1)" ' dev '
    eq "$sh_name: ssh window is named after the label" "$(conn 1 2)" dev
    eq "$sh_name: ssh window tab is colored" "$(conn 1 3)" "bg=#81A1C1,fg=#2E3440"
    eq "$sh_name: active window's status bar untouched" "$(conn 2 1)" "$normal_left"
    eq "$sh_name: active window's name untouched" "$(conn 2 2)" "$active_name"
    eq "$sh_name: active window's tab untouched" "$(conn 2 3)" "$normal_style"
    eq "$sh_name: after exit the status bar is back" "$(pane_fmt "$p2" '#{T:status-left}')" "$normal_left"
    eq "$sh_name: after exit the tab style is back" "$(pane_fmt "$p2" '#{window-status-style}')" "$normal_style"
    eq "$sh_name: after exit automatic-rename is back" "$(pane_fmt "$p2" '#{automatic-rename}')" 1

    # prod stays connected in window 2 while dev connects and exits in 3
    rm -f "$tmp/connected" "$tmp/release"
    ssh_wait="$tmp/release"
    run_sh "$p2" 'ssh 192.0.2.10' &
    prod_pid=$!
    ssh_wait=""
    ok "$sh_name: prod connected" wait_for file_has "$tmp/connected" ' prod '
    run_sh "$p3" 'ssh box-a' || true
    ok "$sh_name: prod window keeps its label after dev exits" contains "$(pane_fmt "$p2" '#{T:status-left}')" ' prod '
    eq "$sh_name: prod window keeps its name after dev exits" "$(pane_fmt "$p2" '#{window_name}')" prod
    touch "$tmp/release"
    wait "$prod_pid" || true
    eq "$sh_name: prod window back to normal after its exit" "$(pane_fmt "$p2" '#{T:status-left}')" "$normal_left"

    # The host is found behind options and their values
    for args in '-vp 2222 192.0.2.10' '-Ap 2222 192.0.2.10' '-B en0 192.0.2.10' \
        '-P tag 192.0.2.10' '-lroot 192.0.2.10' '-o Port=22 -- 192.0.2.10'; do
        run_sh "$p2" "ssh $args" || true
        ok "$sh_name: ssh $args is prod" contains "$(conn 1 1)" ' prod '
    done

    run_sh "$p2" "ssh '#(touch $tmp/injected)'" || true
    ok "$sh_name: tmux format in a host name is replaced" contains "$(conn 1 1)" ' ssh '
    ok "$sh_name: nothing was injected" missing "$tmp/injected"
done

t kill-server >/dev/null 2>&1 || true
if [ "$fail" -eq 0 ]; then
    echo "[tmux_spec] OK $pass passed"
else
    echo "[tmux_spec] FAIL $fail failed, $pass passed"
    exit 1
fi
