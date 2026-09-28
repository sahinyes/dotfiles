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

# iTerm2 "Notes" hotkey window: Ctrl+Option+N from any app shows a floating
# window with the note picker (nn from shell/env.sh). It is a separate
# Dynamic Profile that inherits the Default profile (font, colors, Option
# keys), so the main iTerm2 settings stay untouched. Delete the file to undo.
ITERM_NOTES_PROFILE="$HOME/Library/Application Support/iTerm2/DynamicProfiles/dotfiles-notes.json"

# iterm_notes_json PARENT_GUID: the profile. Hotkey = key code 45 (N) with
# Control (1<<18) + Option (1<<19); iTerm2 matches the key code, not the
# character, so the Swiss layout does not matter.
iterm_notes_json() {
  local parent='' cmd
  if [ -n "$1" ]; then parent="\"Dynamic Profile Parent GUID\": \"$1\","; fi
  # JSON string: the command runs zsh, which sources env.sh and runs nn.
  cmd="/bin/zsh -lc '. \\\"$REPO/shell/env.sh\\\" && nn'"
  cat <<EOF
{
  "Profiles": [
    {
      "Name": "Notes (dotfiles)",
      "Guid": "dotfiles-notes-hotkey",
      $parent
      "Custom Command": "Yes",
      "Command": "$cmd",
      "Window Type": 17,
      "Columns": 110,
      "Rows": 34,
      "Space": -1,
      "Has Hotkey": true,
      "HotKey Key Code": 45,
      "HotKey Characters": "n",
      "HotKey Characters Ignoring Modifiers": "n",
      "HotKey Modifier Flags": 786432,
      "HotKey Activated By Modifier": false,
      "HotKey Window AutoHides": true,
      "HotKey Window Reopens On Activation": false,
      "HotKey Window Animates": true,
      "HotKey Window Floats": true,
      "HotKey Window Dock Click Action": 0,
      "HotKey Alternate Shortcuts": []
    }
  ]
}
EOF
}

iterm_notes_step() {
  local parent
  if [ ! -d /Applications/iTerm.app ] && [ ! -d "$HOME/Applications/iTerm.app" ]; then
    report SKIP iterm2 "iTerm2 is not installed, no notes hotkey"
    return 0
  fi
  # The path goes into a JSON string and a zsh command line.
  if ! quotable "$REPO" || case $REPO in *[\"\\]*) true ;; *) false ;; esac then
    report WARN iterm2 "the repo path contains a quote or backslash, no notes hotkey"
    return 0
  fi
  parent=$(defaults read com.googlecode.iterm2 "Default Bookmark Guid" 2>/dev/null || true)
  case $parent in *[!A-Za-z0-9-]*) parent= ;; esac
  write_file "$ITERM_NOTES_PROFILE" 644 < <(iterm_notes_json "$parent")
  report OK iterm2 "Ctrl+Option+N opens the notes picker in a floating iTerm2 window ($(tilde "$ITERM_NOTES_PROFILE"))"
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
    iterm_notes_step
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
    say "Neovim over SSH also needs: vim.g.osc52 = true in ~/dotfiles/nvim/lua/local.lua"
    report WARN terminal "--osc52: enable clipboard access in iTerm2 by hand and set vim.g.osc52 = true in local.lua (see above); off by default on purpose"
  fi
}
