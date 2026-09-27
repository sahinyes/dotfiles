#!/bin/bash
# Runs inside the test container as the non-root user "dev" (see run.sh):
# copy the read-only repo mount, run install.sh twice, then assert.sh.
set -euo pipefail

mkdir -p "$HOME/dotfiles"
# A copy, not the mount: install.sh writes nvim/lua/local.lua into the repo.
tar -C /src --exclude=./tools/npm/node_modules --exclude=./nvim/lua/local.lua -cf - . |
  tar -C "$HOME/dotfiles" -xf -
if [ -d /cache ]; then
  mkdir -p "$HOME/.cache"
  ln -s /cache "$HOME/.cache/dotfiles"
fi

cd "$HOME/dotfiles"
# --dry-run first: it must not create or change anything in $HOME.
snapshot() { find "$HOME" -path "$HOME/dotfiles" -prune -o -path "$HOME/.cache" -prune -o -print | sort; }
snapshot >/tmp/home.before
./install.sh --dry-run >/tmp/dry.log 2>&1 || echo "dry run exit $?" >>/tmp/dry.log
snapshot >/tmp/home.after
diff /tmp/home.before /tmp/home.after >/tmp/dry.diff || true
echo "### dry run ($(grep -c '^[<>]' /tmp/dry.diff) changes in \$HOME)"
cat /tmp/dry.log /tmp/dry.diff

rc1=0
./install.sh --dev --tier notes >"$HOME/run1.log" 2>&1 || rc1=$?
echo "### run 1 (exit $rc1)"
cat "$HOME/run1.log"
rc2=0
./install.sh --dev --tier notes >"$HOME/run2.log" 2>&1 || rc2=$?
echo "### run 2 (exit $rc2)"
cat "$HOME/run2.log"
echo "### assertions"
RC1=$rc1 RC2=$rc2 bash "$HOME/dotfiles/tests/install/assert.sh"
