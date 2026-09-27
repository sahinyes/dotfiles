# shellcheck shell=bash
# Final verification and the report (printed and saved to
# ~/.local/state/dotfiles/last-install.txt).

# nvim_start_check: start nvim headless with the real config and print what
# it said. Exits non-zero on a startup error (v:errmsg set or init failed).
nvim_start_check() {
  local lua='vim.defer_fn(function()
      if vim.v.errmsg ~= "" then io.stdout:write("errmsg: " .. vim.v.errmsg .. "\n") vim.cmd("cquit 1") end
      vim.cmd("qa!")
    end, 500)'
  (cd "$HOME" && NVIM_OFFLINE=1 "$NVIM" --headless -i NONE -c "lua $lua" </dev/null 2>&1)
}

verify_step() {
  local out rc=0
  step "verification"
  if [ ! -x "$NVIM" ]; then
    report FAIL verify "nvim is missing, nothing to verify"
    return 0
  fi
  out=$(nvim_start_check) || rc=$?
  if [ "$rc" -ne 0 ]; then
    report FAIL verify "nvim --headless startup error (exit $rc): $(printf '%s' "$out" | head -n 3 | tr '\n' ' ')"
  elif [ -n "$out" ]; then
    report WARN verify "nvim --headless starts, but says: $(printf '%s' "$out" | head -n 3 | tr '\n' ' ')"
  else
    report OK verify "nvim --headless starts without errors or messages"
  fi
  if [ -f "$REPO/tests/smoke.lua" ]; then
    rc=0
    out=$(cd "$REPO" && NVIM_OFFLINE=1 "$NVIM" --headless -i NONE -c 'luafile tests/smoke.lua' </dev/null 2>&1) || rc=$?
    if [ "$rc" -eq 0 ]; then
      report OK verify "tests/smoke.lua: $(printf '%s' "$out" | grep -m 1 '^\[smoke\]' || echo passed)"
    else
      report FAIL verify "tests/smoke.lua (exit $rc): $(printf '%s' "$out" | grep -v '^\[' | head -n 3 | tr '\n' ' ')"
    fi
  fi
}

report_finish() {
  local file="$STATE_DIR/last-install.txt" line
  mkdir -p "$STATE_DIR"
  {
    say "== dotfiles: $CHECKOUT | $OS ${SUITE:+$SUITE }$ARCH | tier $TIER | $(date '+%Y-%m-%d %H:%M') =="
    for line in ${REPORT_LINES[@]+"${REPORT_LINES[@]}"}; do say "$line"; done
    if [ "$CHANGES" -eq 0 ]; then
      say "changes: 0 (nothing to do, everything was already in place)"
    else
      say "changes: $CHANGES"
    fi
    if [ "$FAILS" -gt 0 ]; then
      say "result: $FAILS FAIL line(s) above; fix the reason and re-run (safe to repeat)"
    else
      say "result: OK. Next: open a new shell, run nvim, and :Doctor for the editor side"
    fi
  } >"$file.tmp"
  mv -f "$file.tmp" "$file"
  printf '\n'
  cat "$file"
  say "(saved to $(tilde "$file"))"
}
