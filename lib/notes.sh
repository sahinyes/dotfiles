# shellcheck shell=bash
# ~/notes: a private, machine-local git repo (never pushed anywhere).
# A pre-commit hook runs gitleaks and blocks the commit when gitleaks finds a
# secret or is not installed (fail closed). Payloads with tokens belong in
# .scratch/, which git ignores. Finally ~/notes is trusted for marksman only.

NOTES_HOOK_MARK="# dotfiles: gitleaks pre-commit hook"

notes_hook() {
  cat <<EOF
#!/bin/sh
$NOTES_HOOK_MARK (written by install.sh).
# Fail closed: without gitleaks nothing can be committed.
PATH="\$HOME/.local/bin:\$PATH"
if ! command -v gitleaks >/dev/null 2>&1; then
  echo "pre-commit: gitleaks not found, refusing to commit (run install.sh)" >&2
  exit 1
fi
exec gitleaks git --pre-commit --staged --redact --no-banner
EOF
}

notes_inbox() {
  cat <<EOF
---
project: inbox
tags: [inbox]
date: $(date +%Y-%m-%d)
---

## Inbox

EOF
}

# notes_trust: trust ~/notes through sahin.trust (the only way to grant
# trust). Headless nvim with NVIM_OFFLINE=1 so no plugin install can start.
# force=true: the path comes from install.sh itself, and a temp HOME under
# /tmp (CI) would otherwise hit the default never_trust_globs.
# Prints "already" or "granted"; returns 1 with the reason on stdout otherwise.
notes_trust() {
  local lua
  lua='local ok, t = pcall(require, "sahin.trust")
    local dir = vim.env.DOTFILES_TRUST_DIR
    local function out(s) io.stdout:write(s .. "\n") end
    if not ok or type(t) ~= "table" or type(t.grant) ~= "function" then
      out("sahin.trust.grant is not available") vim.cmd("cquit 3") end
    if type(t.is_trusted) == "function" and t.is_trusted(dir) then out("already") vim.cmd("qa!") end
    local pok, granted, err = pcall(t.grant, dir, { silent = true, force = true })
    if pok and granted then out("granted") vim.cmd("qa!") end
    out("grant failed: " .. tostring(pok and err or granted)) vim.cmd("cquit 4")'
  (cd "$HOME" && DOTFILES_TRUST_DIR="$NOTES_DIR" NVIM_OFFLINE=1 \
    "$NVIM" --headless -i NONE -c "lua $lua" -c 'qa!' </dev/null 2>/dev/null)
}

notes_step() {
  local out rc=0
  step "notes (~/notes)"
  if ! have git; then
    report FAIL notes "git is missing, cannot create the notes repo"
    return 0
  fi
  ensure_dir "$NOTES_DIR/daily"
  if [ ! -d "$NOTES_DIR/.git" ]; then
    git -C "$NOTES_DIR" -c init.defaultBranch=main init -q
    changed "git init $(tilde "$NOTES_DIR")"
  fi
  notes_hook | write_file "$NOTES_DIR/.git/hooks/pre-commit" 755
  # A global core.hooksPath (hook managers) would make git skip the hook above.
  # Absolute, so the hook also runs in a linked worktree (git worktree add).
  if [ "$(git -C "$NOTES_DIR" config --local core.hooksPath || true)" != "$NOTES_DIR/.git/hooks" ]; then
    git -C "$NOTES_DIR" config --local core.hooksPath "$NOTES_DIR/.git/hooks"
    changed "pinned core.hooksPath for $(tilde "$NOTES_DIR")"
  fi
  # Auto-commit needs an identity; a fresh laptop may have none. Local only,
  # no personal data (these commits are never pushed).
  if [ -z "$(git -C "$NOTES_DIR" config user.email || true)" ]; then
    git -C "$NOTES_DIR" config --local user.name notes
    git -C "$NOTES_DIR" config --local user.email notes@localhost
    changed "set a local placeholder git identity for $(tilde "$NOTES_DIR")"
  fi
  if [ ! -f "$NOTES_DIR/.gitignore" ] || ! grep -qx '\.scratch/' "$NOTES_DIR/.gitignore"; then
    # A last line without a newline would otherwise merge with .scratch/.
    if [ -s "$NOTES_DIR/.gitignore" ] && [ -n "$(tail -c 1 "$NOTES_DIR/.gitignore")" ]; then
      printf '\n' >>"$NOTES_DIR/.gitignore"
    fi
    printf '.scratch/\n' >>"$NOTES_DIR/.gitignore"
    changed "added .scratch/ to $(tilde "$NOTES_DIR/.gitignore")"
  fi
  if [ ! -e "$NOTES_DIR/inbox.md" ]; then
    notes_inbox | write_file "$NOTES_DIR/inbox.md" 644
  fi
  if ! have gitleaks; then
    report WARN notes "gitleaks is missing: the pre-commit hook blocks every notes commit until it is installed"
  fi
  if [ ! -x "$NVIM" ]; then
    report FAIL notes "$(tilde "$NOTES_DIR") ready, but not trusted: nvim is missing"
    return 0
  fi
  out=$(notes_trust) || rc=$?
  out=$(printf '%s' "$out" | tail -n 1)
  case $rc:$out in
    0:already) report OK notes "$(tilde "$NOTES_DIR"): git, gitleaks hook, trusted (marksman only)" ;;
    0:granted)
      changed "trusted $(tilde "$NOTES_DIR") (marksman only)"
      report OK notes "$(tilde "$NOTES_DIR"): git, gitleaks hook, trusted now (marksman only)"
      ;;
    *) report FAIL notes "$(tilde "$NOTES_DIR") ready, but trust failed (exit $rc): ${out:-no output}" ;;
  esac
  # The trust gate is silent, so say it once here.
  report OFF trust "LSP and gitsigns stay off in other repos until you run :TrustProject there"
}
