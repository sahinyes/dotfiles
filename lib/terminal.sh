# shellcheck shell=bash
# Terminal setup, delegated to the scripts that own it:
#   macOS  scripts/terminfo-mac.sh   tmux-256color with undercurl into ~/.terminfo
#   GNOME  scripts/gnome-terminal.sh profile (font, cursor, palette), dconf backup first
# A script that supports --check is asked first, so a second run changes nothing.

# run_terminal_script NAME AREA: run scripts/NAME unless its --check says done.
run_terminal_script() {
  local script="$REPO/scripts/$1" area=$2
  if [ ! -f "$script" ]; then
    report SKIP "$area" "scripts/$1 is not in this checkout"
    return 0
  fi
  if grep -q -- '--check' "$script" && bash "$script" --check >/dev/null 2>&1; then
    report OK "$area" "nothing to change (scripts/$1 --check)"
    return 0
  fi
  if bash "$script"; then
    changed "ran scripts/$1"
    report OK "$area" "configured by scripts/$1"
  else
    report FAIL "$area" "scripts/$1 failed (see the output above)"
  fi
}

terminal_step() {
  step "terminal"
  if [ "$NO_TERMINAL" = 1 ]; then
    report SKIP terminal "--no-terminal given"
  elif [ "$OS" = darwin ]; then
    if [ "$SMULX" = yes ]; then
      report OK terminal "tmux-256color already has Smulx (undercurl)"
    else
      run_terminal_script terminfo-mac.sh terminal
    fi
  elif have gsettings && have dconf; then
    run_terminal_script gnome-terminal.sh terminal
  else
    report SKIP terminal "no gsettings/dconf (not a GNOME session), GNOME Terminal profile not touched"
  fi
  # Read-only check of the terminal settings install.sh does not own
  # (iTerm2 profile, clipboard access, fonts).
  if [ -f "$REPO/scripts/doctor.sh" ]; then
    local warns doctor_args=()
    if [ "$OSC52" = 1 ]; then doctor_args=(--osc52); fi
    warns=$(bash "$REPO/scripts/doctor.sh" ${doctor_args[@]+"${doctor_args[@]}"} 2>/dev/null | grep -c '^WARN' || true)
    if [ "${warns:-0}" -gt 0 ]; then
      report WARN terminal "scripts/doctor.sh found $warns warning(s): run it to see the fixes"
    else
      report OK terminal "scripts/doctor.sh: no warnings"
    fi
  fi
  if [ "$OSC52" = 1 ]; then
    say "OSC 52 in iTerm2 (only if you accept that text printed in the terminal can"
    say "replace your clipboard): Settings > General > Selection >"
    say "  'Applications in terminal may access clipboard'. install.sh changes nothing here."
    report WARN terminal "--osc52: enable clipboard access in iTerm2 by hand (see above); off by default on purpose"
  fi
}
