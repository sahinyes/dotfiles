# Notes convention

Notes are plain Markdown task lists. The same rules hold for `~/notes` and
for the `TODO.md` at the root of a project, so both you and a coding agent
can read and change them with `rg` and a text editor.

## Where notes live

```text
~/notes/                  a local git repo, never pushed (install.sh creates it)
├── inbox.md              :Capture appends here
├── daily/2026-09-27.md   :Daily, one file per day
├── <topic>.md            one file per project or topic (acme.md, recon.md ...)
└── .scratch/             tokens, cookies, raw payloads; git ignores it
<project>/TODO.md         :Todo, at the git root of a project
```

`vim.g.notes_dir` in `nvim/lua/local.lua` moves the notes folder. Each
machine has its own `~/notes`; there is no sync.

## File format

```markdown
---
project: acme
tags: [bugbounty, web]
date: 2026-01-02
---

## Recon

- [ ] enumerate subdomains #recon
  - [!] check staging for IDOR due:2026-01-10
  - [x] run ffuf on /api done:2026-01-03
- plain note, not a task

## Done

- [x] write scope file done:2026-01-02
```

Rules:

- **Front matter** at the top: `project:` (one word), `tags:` as a list on
  one line (`tags: [a, b]`), `date:` (the day the file was made). Migrated
  files also have `title:`.
- **Sections** are `## Heading`. A daily note has one `# YYYY-MM-DD` title.
  Keep headings to three levels.
- **One task per line.** A task line starts with `- [ ] ` (dash, space,
  state in brackets, space).
- **States**:

  | Written | Meaning | Shown as |
  |---|---|---|
  | `- [ ]` | open | box |
  | `- [!]` | open and important | red |
  | `- [x]` | done | struck through |
  | `- [>]` | deferred (not open, not done) | dim |

- **Subtasks** are indented by 2 spaces.
- **Plain bullets** (`- text`, no brackets) are notes, not tasks.
- **Tags** go at the end of the line: `#web`.
- **Dates** are ISO `YYYY-MM-DD`, written as `due:2026-10-01`,
  `done:2026-10-01` (added by `:TaskDone`), `added:2026-10-01` (added by
  `:Capture`). No space after the colon.
- Use `-` for task bullets, not `*` or `+`: the search patterns below only
  match `- `.

### `.scratch/` for secrets

Put pasted tokens, cookies, session IDs and raw HTTP payloads in
`~/notes/.scratch/`. It is listed in `~/notes/.gitignore`, the auto-commit
excludes it again, and `:Tasks` and the notes pickers skip it. Everything
else in `~/notes` is committed, and the gitleaks hook blocks a commit that
contains a known secret format (see below).

## Editing Markdown

These settings apply to every Markdown buffer (`after/ftplugin/markdown.lua`):

- **Enter or `o` on a `- [ ] ` line** starts a new `- [ ] ` line. After a
  `[!]`, `[x]` or `[>]` line you get a plain `- `, so "important" or "done"
  is never copied to the next line. Press `<CR>` in Normal mode to turn that
  `- ` into `- [ ] `.
- **`<CR>` in Normal mode** cycles the task state; in Visual mode it works on
  every selected line.
- **`xd`** followed by a space or punctuation, in Insert mode, becomes
  today's date.
- 2-space indent, soft wrap (long lines wrap at word boundaries and line up
  under the task text), no hard wrap.
- Folding by treesitter, all folds open at start: `zc` close, `zo` open,
  `za` toggle, `zM` close all, `zR` open all.
- `gO` lists the headings; `öö` / `ää` jump to the previous / next heading.
- Spelling: `<leader>ts` turns it on. `spelllang` holds `en`, plus `de_ch`
  and `tr` when their spell files are installed. `zg` adds a word to your
  local list (`~/.local/share/nvim/spell/local.utf-8.add`, not in git).
  `2zg` adds it to the shared list in this repo
  (`nvim/spell/en.utf-8.add`), which is public, and it leaves the laptop's
  checkout modified.
- Rendering (render-markdown): headings, bullets and states are drawn in
  Normal mode; Insert mode and the cursor line show the raw text.
  `<leader>tr` turns rendering off and on. Without a Nerd Font
  (`vim.g.have_nerd_font = false`) the states are drawn as text.
- No completion menu pops up while you write notes; `<C-Space>` asks marksman
  (links, headings) when you want it.

## Commands

| Keys | Command | What it does |
|---|---|---|
| `<CR>` (Markdown), `<leader>nx` | `:TaskCycle` | `[ ]` → `[!]` → `[x]` → `[ ]`. `[>]` goes back to `[ ]`. A plain line or bullet becomes `- [ ] `. Works on a range and with a count. |
| `<leader>nD` | `:TaskDone` | Sets `[x]` and adds ` done:YYYY-MM-DD` (only once). |
| `<leader>n!` | `:TaskMark !` | Sets `[!]` important. |
| `<leader>nz` | `:TaskMark >` | Sets `[>]` deferred. |
| | `:TaskMark space` (or `:TaskMark`) | Sets `[ ]` open. |
| `<leader>na` | `:TaskArchive` | Moves finished task trees under `## Done` (details below). |
| `<leader>no` | `:Tasks` or `:Tasks open` | Open tasks (`[ ]` and `[!]`) into the quickfix list. |
| `<leader>ni` | `:Tasks important` | Important tasks (`[!]`) into the quickfix list. |
| `<leader>ns` | telescope | Fuzzy search over the open tasks. |
| `<leader>nc` | `:Capture [text]` | Appends `- [ ] text added:YYYY-MM-DD` to `inbox.md`. Without text it asks. |
| `<leader>nd` | `:Daily` | Opens `daily/YYYY-MM-DD.md`, created from a template the first time. |
| `<leader>nt` | `:Todo` | Opens `TODO.md` at the git root. Outside git it uses the current folder and says so. |
| `<leader>nn` | telescope | Find a file in the notes folder. |
| `<leader>ng` | telescope | Grep the notes folder (without `.scratch/`). |
| `<leader>1` ... `<leader>5` | | Open hot note 1 ... 5. |

The task commands never touch blank lines, headings, `---`/`***` rules,
front-matter lines or code fences. A task that leaves `[x]` (by cycling or
`:TaskMark`) loses its `done:` date, so `done:` always means done. `[X]` is
treated like `[x]`.

### `:TaskArchive`

A task tree is a list item plus every line below it that is indented
deeper. A tree moves only when its first line and every task inside it are
`[x]`. Plain bullets inside the tree move with it. Only top-level trees are
checked, so a done subtask under an open parent stays where it is, and so
does an open child under a done parent. The trees are appended at the end
of the existing `## Done` section; if there is none, `## Done` is added at
the end of the file. One `u` undoes the whole move.

### `:Tasks` and the quickfix list

`:Tasks` searches every `*.md` file under the notes folder (hidden folders
such as `.scratch/` are skipped) plus `TODO.md` at the git root of the
current file. That `TODO.md` counts only when it is a regular file inside
the repo; a symlink that leads elsewhere is skipped. It uses `rg` when it
is installed (stopped after 10 s, with a warning), else a slower Lua scan
with the same pattern. The results open in the quickfix list:

```vim
:cnext  :cprev          " or äq / öq
:cdo s/due:2026-09-30/due:2026-10-07/ | update
:packadd cfilter
:Cfilter /acme/         " keep only matching entries
```

### Templates

`:Capture` creates `inbox.md` if it is missing:

```markdown
---
project: inbox
tags: [inbox]
date: 2026-09-27
---

## Inbox

- [ ] call the triage team added:2026-09-27
```

`:Daily` creates `daily/YYYY-MM-DD.md` and puts the cursor on `## Tasks`:

```markdown
---
project: daily
tags: [daily]
date: 2026-09-27
---

# 2026-09-27

## Tasks

## Notes
```

`:Todo` creates a `TODO.md` that carries this convention in a comment at the
top, then a `## Tasks` section. It never writes when a `TODO.md` exists,
even as a broken symlink.

### Hot notes

Up to five files you open all the time. In `nvim/lua/local.lua`:

```lua
vim.g.hot_notes = { '~/notes/inbox.md', '~/notes/acme.md' }
```

`<leader>1` opens the first one, and so on.

## Auto-save and auto-commit

- **Auto-save.** A changed note inside the notes folder is written when you
  leave its buffer or when the terminal window loses focus (`BufLeave`,
  `FocusLost`; tmux passes focus events on). A project `TODO.md` is not
  auto-saved.
- **Reload.** When the terminal window gets focus back, or a `:terminal`
  closes, Neovim reloads files that changed on disk (for example when an
  agent edited a note).
- **Auto-commit.** Only when `~/notes/.git` exists. About 1.5 s after the last
  save, it runs, in `~/notes`:

  ```sh
  git add -A -- . ':(exclude).scratch'
  git diff --cached --quiet || git commit --quiet --no-gpg-sign -m 'notes: <date time>'
  ```

  One git job runs at a time; a save during a running job commits again
  right after. When you quit Neovim, a waiting commit runs and Neovim waits
  for it (up to 10 s). Each git step has a 60 s timeout. It never pushes.
  Signing is skipped because these are local snapshots.
- **The gitleaks hook.** `install.sh` writes `~/notes/.git/hooks/pre-commit`,
  which runs `gitleaks git --pre-commit --staged --redact`. If gitleaks
  finds a secret, or gitleaks is not installed, the commit is refused and
  Neovim shows a warning with the (redacted) finding. The file stays saved;
  it is just not committed. Move the secret to `.scratch/` and save again.
- On a fresh laptop without a git identity, `install.sh` sets a local
  placeholder (`notes` / `notes@localhost`) for `~/notes` only.

## Agent contract

A coding agent (or a script) may read and change notes with these patterns.
They are the same patterns `:Tasks` uses.

| Question | Command |
|---|---|
| Open tasks (`[ ]` and `[!]`) | `rg -n '^\s*- \[[ !]\]' ~/notes` |
| Important tasks | `rg -n '^\s*- \[!\]' ~/notes` |
| Done tasks | `rg -n '^\s*- \[[xX]\]' ~/notes` |
| Deferred tasks | `rg -n '^\s*- \[>\]' ~/notes` |
| Files of one project | `rg -l '^project: acme' ~/notes` |
| Lines with a tag | `rg -n '#web\b' ~/notes` |
| Tasks due in a month | `rg -n '^\s*- \[[ !]\].*due:2026-10-' ~/notes` |
| Open tasks in a project | `rg -n '^\s*- \[[ !]\]' TODO.md` |

`rg` skips hidden folders and `.gitignore`d files by default, so
`.scratch/` stays out.

Rules for an agent that edits notes:

- Change the state by replacing the one character between the brackets.
- Keep one task per line, 2-space indents, and the front matter as it is.
- Add dates only as `due:`/`done:`/`added:` with `YYYY-MM-DD`.
- Never read or write `.scratch/`, and never put a secret in any other file.
- Do not commit or push; the editor commits `~/notes` by itself.

## One-off migration of the old Sublime notes

The old notes are outline files named `*.yaml` (not real YAML).
`scripts/migrate-notes.py` converts them once, on the Mac. It never changes
the old files and never overwrites a file; it writes new Markdown files into
the `--out` folder.

What it converts:

| Old | New |
|---|---|
| `-* text` | `- [!] text` (important) |
| `+ text` | `- [x] text` (done) |
| `- text` | `- [ ] text` (open), or `- text` with `--dash-as-note` |
| `-text` (dash glued to a word) | `- [ ] text` |
| `key:` at column 0, up to 60 characters | `## key` |
| `key:` indented | `- **key**` |
| a line of 2 or more dashes | `---` with blank lines around it |
| a line with 1-3 leading spaces and no marker | joined to the line above |

Tabs count as 4 columns; each level becomes 2 spaces. Every file gets front
matter with `title`, `project` (from the file name), `tags: [migrated]` and
`date`.

**Steps** (run `install.sh` first, so `~/notes` exists):

1. Dry run. Pass all sources in one run: files with the same name are
   renamed across the whole set (`Documents/notes.yaml` →
   `notes-documents.md`, `Desktop/notes.yaml` → `notes-desktop.md`; a single
   `notes.yaml` would become `notes.md`).

   ```sh
   cd ~/dotfiles
   old=(~/Documents/notes.yaml ~/Desktop/notes.yaml ~/Documents/sublime-docs/*.yaml)
   scripts/migrate-notes.py --dry-run --out ~/notes "${old[@]}"
   ```

   It prints per-file counts and a diff, and writes nothing. Add
   `--dash-as-note` if your plain `-` lines were notes rather than open tasks.

2. Convert:

   ```sh
   scripts/migrate-notes.py --out ~/notes "${old[@]}"
   ```

3. Read the `review:` lines it printed. They give line numbers (never
   content) of patterns it could not map cleanly, for example a task that
   ends in `:` and acts as a sub-heading. Open each new file and fix those
   lines by hand.

4. Check the result in Neovim: `:Tasks` should list the open tasks you
   expect.

5. Commit. The next note you save triggers the auto-commit, or commit by
   hand:

   ```sh
   git -C ~/notes add -A
   git -C ~/notes commit -m 'Migrate old notes'
   ```

   If the gitleaks hook refuses, an old note contains a token: move it to
   `~/notes/.scratch/` and commit again.

Safety checks built into the script: for every file, the number of each
marker must be the same before and after, and the text of every source line
must appear in the output in the same order. A file that fails is not
written. Exit code 0 means all files were written, 1 means at least one file
failed a check (the others were written), 2 means nothing was written (bad
arguments, a target file that already exists, or `--out` inside a source
folder).
