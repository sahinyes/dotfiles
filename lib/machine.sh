# shellcheck shell=bash
# Machine-local facts: the work-laptop marker and nvim/lua/local.lua.
# local.lua is gitignored and written only when it does not exist yet, so
# your own edits there always win over a re-run.

# work_step: ~/.config/dotfiles/work marks the work laptop. tmux.conf and
# shell/env.sh test for it (e.g. no pane contents saved by tmux-resurrect).
work_step() {
  step "work-laptop marker"
  if [ "$WORK" = 1 ]; then
    if [ ! -e "$WORK_MARKER" ]; then
      mkdir -p "$(dirname "$WORK_MARKER")"
      : >"$WORK_MARKER"
      changed "created $(tilde "$WORK_MARKER")"
    fi
    report OK work "work laptop ($(tilde "$WORK_MARKER") present)"
  else
    if [ -e "$WORK_MARKER" ]; then
      rm -f "$WORK_MARKER"
      changed "removed $(tilde "$WORK_MARKER") (--no-work)"
    fi
    report OK work "not the work laptop (no $(tilde "$WORK_MARKER"))"
  fi
}

lua_bool() { if [ "$1" = yes ] || [ "$1" = 1 ]; then echo true; else echo false; fi; }

local_lua_step() {
  local file="$REPO/nvim/lua/local.lua"
  step "nvim/lua/local.lua"
  if [ -e "$file" ]; then
    report OK local.lua "exists, left unchanged (edit it by hand)"
    return 0
  fi
  {
    printf -- '-- Machine-local settings, written once by install.sh on %s.\n' "$(date +%Y-%m-%d)"
    printf -- '-- Not tracked by git; install.sh never overwrites this file.\n'
    if [ -f "$REPO/nvim/lua/local.lua.example" ]; then
      printf -- '-- More settings (hot_notes, never_trust_globs, ...): local.lua.example\n'
    fi
    printf 'vim.g.work_laptop = %s\n' "$(lua_bool "$WORK")"
    printf 'vim.g.have_nerd_font = %s\n' "$(lua_bool "$NERD_FONT")"
    printf "vim.g.notes_dir = vim.fn.expand('~/notes')\n"
  } | write_file "$file" 644
  report OK local.lua "written: work_laptop=$(lua_bool "$WORK") have_nerd_font=$(lua_bool "$NERD_FONT") notes_dir=~/notes"
}
