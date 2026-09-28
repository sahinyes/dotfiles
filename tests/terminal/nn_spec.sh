#!/bin/bash
# Drives `nn` (shell/env.sh) in a real terminal: an ISOLATED tmux server with
# its own socket and a temporary HOME holding two notes. Headless Neovim
# cannot show the bug this guards against: at startup the picker was drawn
# but the cursor stayed in the empty window, so typing, <Esc> and <C-w>o went
# there (E5601). Needs tmux, nvim and the installed plugins, else it skips.
# Usage: bash tests/terminal/nn_spec.sh
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd -P)
REAL_HOME=$HOME
if ! command -v tmux >/dev/null || ! command -v nvim >/dev/null ||
  [ ! -d "${XDG_DATA_HOME:-$REAL_HOME/.local/share}/${NVIM_APPNAME:-nvim}/site/pack/core/opt/telescope.nvim" ]; then
  echo "[nn_spec] SKIP: needs tmux, nvim and the installed plugins (install.sh)"
  exit 0
fi
T=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-nn-spec.XXXXXX")
SOCK="nn-spec-$$"
t() { tmux -L "$SOCK" -f /dev/null "$@"; }
cleanup() {
  t kill-server 2>/dev/null || true
  rm -rf "$T"
}
trap cleanup EXIT

mkdir -p "$T/home/notes"
printf '# Alpha\n\n- [ ] alpha task\n' >"$T/home/notes/alpha.md"
printf '# Bravo\n\n- [ ] bravo task\n' >"$T/home/notes/bravo.md"

pass=0 fail=0
ok() {
  local name=$1
  shift
  if "$@"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "  - $name"
    t capture-pane -p -t nn 2>/dev/null | grep -v '^[[:space:]~]*$' | tail -5 | sed 's/^/      /'
  fi
}
screen() { t capture-pane -p -t nn; }
shows() { screen | grep -q -- "$1"; }
wait_for() { # wait_for TEXT: up to 10 s

  for _ in $(seq 1 50); do
    if shows "$1"; then return 0; fi
    sleep 0.2
  done
  return 1
}
# start: a fresh nn in the temp HOME; config, plugins and state stay the
# real ones (read-only use), only HOME and so ~/notes change.
start() {
  t kill-server 2>/dev/null || true
  t new-session -d -s nn -x 150 -y 40 -c "$T/home/notes" \
    env HOME="$T/home" XDG_CONFIG_HOME="$REAL_HOME/.config" \
    XDG_DATA_HOME="$REAL_HOME/.local/share" XDG_STATE_HOME="$T/state" \
    NVIM_APPNAME="${NVIM_APPNAME:-nvim}" PATH="$PATH" \
    /bin/bash -c ". '$REPO/shell/env.sh' && nn"
  wait_for 'Notes'
}

start
ok "the picker opens" shows '2 / 2'
t send-keys -t nn 'brav'
ok "typing filters the list (cursor is in the prompt)" wait_for '1 / 2'
t send-keys -t nn Enter
ok "Enter opens the selected note" wait_for 'bravo task'
t send-keys -t nn C-w
sleep 0.5
t send-keys -t nn o
sleep 0.5
ok "<C-w>o in the note gives no E5601" sh -c "! tmux -L '$SOCK' capture-pane -p -t nn | grep -q E5601"

start
t send-keys -t nn Escape
sleep 0.8
ok "one Esc closes the picker" sh -c "! tmux -L '$SOCK' capture-pane -p -t nn | grep -q ' / 2'"
t send-keys -t nn C-w
sleep 0.5
t send-keys -t nn o
sleep 0.5
ok "<C-w>o after Esc gives no E5601" sh -c "! tmux -L '$SOCK' capture-pane -p -t nn | grep -q E5601"

if [ "$fail" -gt 0 ]; then
  echo "[nn_spec] FAIL $fail failed, $pass passed"
  exit 1
fi
echo "[nn_spec] OK $pass passed"
