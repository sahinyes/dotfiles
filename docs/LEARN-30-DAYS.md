# Learn this setup in 30 days

A plan for someone new to Vim, built around this config. Each day takes
15-20 minutes. Do the exercises on real work where you can: your notes,
logs, a JSON response you saved. If a day takes longer, split it; the order
matters more than the pace.

Before you start:

- Keys are written the Vim way: `<CR>` is Enter, `<Esc>` is Escape, `<C-w>`
  is Ctrl+w, `<leader>` is Space. `<leader>nd` means Space, then n, then d.
- This keyboard is Swiss German. `ö` and `ä` stand in for `[` and `]`, `é`
  and `à` for `{` and `}`, `§` for the backtick, `ü` for `Ctrl-]`. See
  [KEYMAP.md](KEYMAP.md), section 1.
- `+` and `-` add to and subtract from the number under the cursor here (in
  plain Vim they move the cursor down or up a line).
- Stuck? Press `<Esc>` twice, then type `:q!` and Enter to leave without
  saving. Press Space and wait: a window shows what you can type next.
- Motion hints (precognition) are on until day 21. The letters above the
  cursor line show where `w`, `b`, `e`, `_`, `$` would jump; `é`/`à` in the
  left margin show the paragraph jumps.

Tip for exercises with payloads: put them in `~/notes/.scratch/`. That folder
is never committed.

---

## Week 1: move, edit, save

### Day 1: The tutor and your first note

Goal: get in, move, type, save, get out.

1. Run `nvim +Tutor` (Neovim's version of vimtutor). Do lessons 1.1 to 1.6.
2. Quit the tutor with `:q!`.
3. Run `nvim`, press `<leader>nd`. Today's daily note opens with the cursor
   on `## Tasks`.
4. Press `o`, type `- [ ] learn Vim for 30 days`, press `<Esc>`, then `:w`.
5. Quit with `:q`. Open it again with `nvim`, `<leader>nd`.

Check yourself: you can open, change, save (`:w`) and quit (`:q`, `:q!`,
`:wq`) without looking it up.

### Day 2: Delete, operators, undo

Goal: understand "operator + motion".

1. `nvim +Tutor`, lessons 2.1 to 2.7. Jump there with `/Lesson 2.1` and
   Enter.
2. In your daily note: `dw` deletes a word, `d$` to the end of the line, `dd`
   the whole line. Undo each with `u`, redo with `<C-r>`.
3. Try counts: `3w`, `2dd`, `d2w`.
4. Watch the hints above the cursor while you press `w`, `b`, `e`.

Check yourself: you can say what `d3w` does before you press it.

### Day 3: Put, replace, change, search

Goal: the middle of the tutor.

1. `:Tutor`, lessons 3.1 to 4.4: `p`, `r`, `c`, `ce`, `<C-g>`, `G`, `gg`,
   `/search`, `n`, `N`, `%`, `:s`.
2. In a note, search for a word with `/word`, jump with `n` and `N`.
3. Put the cursor on a `(` and press `%`.
4. Press `<Esc>` to clear the search highlight.

Check yourself: you can find a word, change it with `cw`, and repeat the
change on the next match with `n` and `.`.

### Day 4: The rest of the tutor

Goal: finish the first tutor.

1. `:Tutor`, lessons 5.1 to 7.2: `:!`, `:w file`, `v` + `:w`, `:r`, `o`,
   `O`, `a`, `A`, `R`, `y`, `p`, `:set ic`, `:help`. Skip lesson 7.3: it
   creates a config file, and yours is `~/dotfiles/nvim` (`~/.config/nvim`
   points there).
2. `:help w` and `:help d`; close help with `:q`.
3. `<leader>sh`: search the help with telescope, type `motion`, press Enter.

Check yourself: you know where to look (`:help`, `<leader>sh`) when you
forget a key.

### Day 5: Motions with hints

Goal: move by words, lines and paragraphs without the arrow keys.

1. Line: `0` start, `_` first character (the Swiss `^` is a dead key), `$`
   end. `f,` jumps to the next comma, `t,` stops before it, `;` repeats, `,`
   goes back.
2. Paragraphs: `é` and `à` (Shift+ö, Shift+ä) jump to the previous and next
   blank line. Watch the `é`/`à` hints in the margin.
3. Screen: `H`, `M`, `L`, then `<C-d>` and `<C-u>` to scroll half a page.
4. Relative line numbers: jump with `5j` or `12k` using the numbers on the
   left.

Check yourself: you can reach any character on the screen in three
keystrokes or fewer, most of the time.

### Day 6: Tasks

Goal: the notes workflow from [NOTES-CONVENTION.md](NOTES-CONVENTION.md).

1. In your daily note, on a `- [ ] ` line, press `o` and type a task: the
   `- [ ] ` is added for you.
2. In Normal mode press `<CR>` on a task three times: `[ ]` → `[!]` → `[x]`
   → `[ ]`.
3. `<leader>nD` marks a task done and adds `done:` with today's date.
4. `<leader>nc`, type a task, Enter: it lands in `~/notes/inbox.md` with
   `added:`.
5. In Insert mode type `xd` and a space: today's date.

Check yourself: you can capture, cycle and finish a task without typing
brackets.

### Day 7: Review and look around

Goal: find help inside the editor.

1. Press Space and wait. Read the groups (Search, Notes, Git hunk ...).
2. Press `g` and wait, then `z` and wait. Close the window with `<Esc>`.
3. Run `:Doctor`. Read each line. Close the window with `:q`.
4. In a shell, run `~/dotfiles/scripts/doctor.sh` and read the `WARN` lines.
5. Redo any day that felt shaky.

Check yourself: you can find a forgotten key with the hint window or
`<leader>sk`.

---

## Week 2: edit with intent

### Day 8: Text objects

Goal: change "the thing the cursor is in" instead of counting characters.

1. `ciw` change a word, `daw` delete a word and its space.
2. `dip` deletes a paragraph, `yap` copies it.
3. On a JSON value: `ci"` changes the text inside the quotes.
4. `ci(` changes inside parentheses, `da(` deletes them too.
5. `:Tutor vim-02-beginner`, lesson 2.1.1 (text objects).

Check yourself: you use `ci"` without thinking about where the quote
starts.

### Day 9: Brackets on the Swiss keyboard

Goal: the Swiss text objects and mini.ai.

1. `ciö` changes inside `[...]`, `daö` deletes the brackets too.
2. `cié` changes inside `{...}`, `yié` copies the inside of a JSON object.
3. `cib` changes inside the nearest bracket of any kind, `ciq` inside the
   nearest quotes.
4. `cii"` changes inside the *next* quotes on the line (the cursor does not
   need to be inside).
5. `vié` selects inside `{...}`; press `aé` next to take the braces too.

Check yourself: you can edit inside any bracket or quote without pressing
Option or AltGr.

### Day 10: Surround

Goal: add, change and remove quotes and brackets.

1. `saiw"` puts quotes around a word.
2. `sr"'` turns double quotes into single quotes.
3. `sd'` removes them.
4. Select a few words with `v`, then `sa)`.
5. `.` repeats the last surround.

Check yourself: you can wrap a URL in backticks with `saiW` followed by the
backtick (dead key: press it, then Space).

### Day 11: Registers and the clipboard

Goal: know where copied text goes.

1. `yy` then `p`. Then `dd` on another line and `"0p`: register 0 still has
   the yank.
2. `"_dd` deletes without touching any register.
3. `<leader>y` copies to the system clipboard, `<leader>p` pastes from it.
   (On the Mac every yank also reaches the clipboard.)
4. Press `"` and wait: the hint window shows every register's content. In
   Insert mode, `<C-r>0` inserts register 0.
5. `:Tutor vim-02-beginner`, lessons 2.1.2 to 2.1.5 (registers).

Check yourself: you can paste the thing you yanked before your last delete.

### Day 12: Marks and jumps

Goal: jump back and forth in a long log.

1. `ma` sets mark a. Move away. `'a` jumps to its line, `§a` to the exact
   spot.
2. `mA` (capital) works across files.
3. `§§` jumps back to where you were before the last jump.
4. `<C-o>` goes back through your jumps, `<Tab>` goes forward.
5. Press `'` and wait: the hint window lists your marks. Then
   `:Tutor vim-02-beginner`, lesson 2.1.6 (marks).

Check yourself: you can jump to a line far away and come back in two keys.

### Day 13: Search with telescope

Goal: find files and text fast in your own folders. For cloned targets
you use `nvu` (day 20), which has no telescope.

1. `<leader>sf` find a file, `<leader>sg` grep for text, Enter opens it.
2. Put the cursor on a word, `<leader>sw` greps for it.
3. `<leader><leader>` switches between open buffers, `<leader>/` searches
   the current file.
4. `<leader>sr` reopens the last search where you left it.
5. `<leader>sk`, type `notes`: all notes keys.

Check yourself: you can open any note by a few letters of its name.

### Day 14: Tasks across all notes

Goal: work from lists, not from files.

1. `<leader>no`: every open task goes to the quickfix list. `<CR>` jumps.
2. `äq` / `öq` next / previous entry, `<leader>xc` closes the list.
3. `<leader>ni` only the important ones. `<leader>ns` fuzzy-search tasks.
4. In a note with done tasks, `<leader>na` moves finished trees under
   `## Done`. `u` undoes it.
5. Add two hot notes to `~/dotfiles/nvim/lua/local.lua`
   (`vim.g.hot_notes = { '~/notes/inbox.md', ... }`), restart with `ZR`,
   try `<leader>1`.

Check yourself: you start the day with `<leader>no`, not by opening files.

---

## Week 3: batch edits and payloads

### Day 15: Change many places at once

Goal: `:cdo` on search results.

1. `<leader>no`, then `:cdo s/due:2026-09-30/due:2026-10-07/ | update`
   (use a date that exists in your notes).
2. `:packadd cfilter`, then `:Cfilter /acme/` keeps only matching entries.
3. `<leader>sg`, search a word, `<C-q>` in the picker sends all results to
   quickfix.
4. `:cfdo %s/foo/bar/ge | update` runs once per file in the list instead of
   once per entry.

Check yourself: you can change the same thing in ten files without opening
them one by one.

### Day 16: Substitute and global commands

Goal: clean up logs.

1. `:%s/old/new/gc`: the split below shows every change before you confirm.
2. `:g/DEBUG/d` deletes every line with DEBUG. `u` undoes it.
3. `:v/ERROR/d` keeps only lines with ERROR.
4. `:sort u` sorts and removes duplicate lines (for example a list of
   subdomains).
5. `:g/\[x\]/m$` moves done tasks to the end of the file.

Check yourself: you can reduce a 2000-line log to the lines you care about.

### Day 17: Macros and numbers

Goal: repeat a change you cannot express as one command.

1. `qq` starts recording into register q, do an edit, `j`, `q` stops.
2. `@q` replays it, `5@q` five times, `Q` replays the last recorded macro.
3. `:'<,'>normal @q` runs it on every selected line.
4. On a port or ID: `+` adds 1, `5-` subtracts 5.
5. Select a column of zeros with `<C-v>`, then `g+`: 1, 2, 3 ...

Check yourself: you can turn a list of hosts into `https://host/` lines with
one macro.

### Day 18: JSON

Goal: read JSON payloads.

1. Paste a minified JSON response into `~/notes/.scratch/resp.json`. `:Json`
   pretty-prints it (keys stay in order, big numbers stay exact).
2. `:JsonMin` makes it one line again. `u` goes back.
3. Select one value with `v` and press `<leader>ij`: only the selection
   changes.
4. `:setlocal foldmethod=indent`, then `zM` folds every level, `zo` opens
   one fold, `zR` opens all.
5. A file over 1.5 MB opens without colors on purpose (big-file mode).

Check yourself: you can find one field in a large response in under a
minute.

### Day 19: Encodings and tokens

Goal: the inspect commands.

1. Write `hello world` on a line, `<leader>iB` (base64), then `<leader>ib`
   (decode). `:UrlEncode` and `:UrlDecode` on `a=1&b=x y`.
2. Build a test JWT: on two lines write `{"alg":"HS256"}` and
   `{"sub":"tester","exp":1}`. Encode each line on its own (`V`, then
   `<leader>iB`). Join them into one line as `<line 1>.<line 2>.sig`. Put
   the cursor on it and press `<leader>iw`. Read the claims, the
   `exp ... (expired)` line and the "NOT verified" warning.
3. `<leader>ih` shows a hex dump of the file; `ga` shows the code of the
   character under the cursor, `g8` its UTF-8 bytes.
4. Decode something binary with `:B64d`: you get a hex dump instead of a
   broken buffer.

Check yourself: you can decode a cookie value and say whether it is JSON,
text or binary.

### Day 20: Hostile material

Goal: open target files safely.

1. In a shell: `nvu ~/some-cloned-target`. Run `:Doctor`: it starts with
   `UNTRUSTED PROFILE`. There are no plugins, no LSP and no notes keys here,
   but `:Json` and the other inspect commands work.
2. `nvr0 suspicious.txt` opens one file read-only with no config at all.
3. In `nvu`, press `gx` on a URL: it asks before opening, and refuses
   anything that is not http, https or mailto.
4. `:DiffTool old.json new.json` compares two files (or folders).
   `nvim -d a b` does the same from the shell; `äc`/`öc` jump between changes, `do`
   and `dp` copy a change over.

Check yourself: you know which of `nvim`, `nvu` and `nvr0` to use for a
cloned repo, a downloaded file and your own notes.

### Day 21: Hints off

Goal: move without training wheels.

1. Open `~/dotfiles/nvim/lua/local.lua` and add
   `vim.g.precognition = false`.
2. Restart Neovim with `ZR`. The hints are gone.
3. Redo day 5's exercises without hints.
4. If you miss them for a moment, `<leader>tp` shows them again until the
   next start.

Check yourself: you move by `w`, `f`, `é`/`à` and search without looking for
hints.

---

## Week 4: windows, tmux and code

### Day 22: Windows and buffers

Goal: work with more than one file.

1. `<C-w>v` splits left/right, `<C-w>s` top/bottom, `<C-w>h/j/k/l` moves.
2. `<C-w>=` makes them equal, `<C-w>o` keeps only the current one.
3. Press `<C-w>` and wait: the hint window lists all window keys.
4. `<C-6>` switches to the previous file, `<leader><leader>` picks any open
   buffer.

Check yourself: you can have a note and a log side by side and copy between
them.

### Day 23: tmux and the terminal

Goal: panes outside Neovim, a shell inside it.

1. tmux prefix is `Ctrl+a`. `prefix v` and `prefix -` split, Option+arrows
   (Alt+arrows on Debian) move between panes, `prefix z` zooms.
2. `prefix Enter` starts copy mode: `v` select, `y` copy to the clipboard.
3. `prefix F1` shows the cheat sheet.
4. In Neovim, `:terminal`, run a command, then `<C-q>` to get back to Normal
   mode and scroll the output. `i` goes back to typing. If your shell marks
   its prompts (OSC 133), `öö`/`ää` jump between them.

Check yourself: you can run a request in one pane and take notes in the
other without the mouse.

### Day 24: Trust and LSP basics

Goal: turn on language servers in your own project.

1. Open a file in a repo you own (for example `~/dotfiles`). `:Doctor` shows
   `NOT trusted`.
2. `:TrustProject`. Read the root and the servers it lists, answer Yes.
3. `K` on a function shows its documentation. `grd` goes to the definition,
   `<C-o>` comes back. `grr` lists the references.
4. `grn` renames a symbol everywhere.
5. `:checkhealth vim.lsp` shows what is running.

Check yourself: you can explain why the same file in a cloned target repo
gets no LSP.

### Day 25: Diagnostics and code actions

Goal: fix what the server reports.

1. `äd` / `öd` jump to the next / previous diagnostic. `<C-w>d` shows it in a
   float.
2. `gra` shows code actions for it.
3. `<leader>xd` puts all diagnostics into quickfix, `<leader>sd` searches
   them.
4. `<leader>cf` formats the file (when the server can).

Check yourself: you can clear the warnings in one file without the mouse.

### Day 26: Completion

Goal: the built-in completion.

1. In a code file, type: the menu opens by itself. `<C-n>`/`<C-p>` move,
   `<C-y>` accepts, `<C-e>` closes.
2. In a note the menu stays closed. `<C-Space>` asks marksman (try it after
   `[` or `#`). If macOS takes Ctrl+Space, use `<C-x><C-o>`.
3. `<C-x><C-f>` completes a file path, `<C-x><C-l>` a whole line.
4. `<C-s>` in Insert mode shows the function signature.
5. `<leader>tc` turns the automatic menu off and on for this buffer.

Check yourself: you accept a suggestion with `<C-y>`, not with Tab or Enter.

### Day 27: Git in a trusted repo

Goal: review your own changes.

1. In a trusted repo, change a file. Signs appear in the left column.
2. `äc` / `öc` next / previous hunk, `<leader>hp` preview it.
3. `<leader>hs` stages the hunk, `<leader>hr` resets it, `<leader>hb` shows
   who wrote the line.
4. `vih` selects the hunk; `<leader>tb` shows who changed the current line
   as you move.
5. `<leader>nt` opens the project's `TODO.md`.

Check yourself: you can stage part of a file from Neovim.

### Day 28: Structure

Goal: treesitter selections, folds and outlines.

1. In a Lua file (its parser ships with Neovim), `v` then `an` grows the
   selection to the next bigger syntax node, `in` shrinks it.
2. In a note, `zM` folds every section, `zo` opens one, `zR` opens all.
3. In a note, `gO` lists the headings; `öö`/`ää` jump between them.
4. `:Inspect` shows what highlight the text under the cursor has.

Check yourself: you can select a whole Lua table or function with `van`
pressed a few times.

### Day 29: Maintenance

Goal: know how the setup is kept healthy.

1. `:Doctor` and `~/dotfiles/scripts/doctor.sh`: fix any `WARN` you
   understand.
2. Read `~/.local/state/dotfiles/last-install.txt`.
3. On the Mac: `<leader>uu` opens the plugin update review. `<leader>ud`
   shows the code changes. Close both with `:q` without writing (the real
   procedure is in [UPDATE.md](UPDATE.md)).
4. Skim [TROUBLESHOOTING.md](TROUBLESHOOTING.md) once, so you know what is
   there.

Check yourself: you know where to look when something breaks.

### Day 30: Review

Goal: make the setup yours.

1. Go through [KEYMAP.md](KEYMAP.md). Mark the keys you use every day and
   the ones you never touched.
2. Redo the two days that felt weakest.
3. Write your own one-page cheat sheet in `~/notes/vim.md`.
4. Decide on precognition: if you do not miss it, remove it for good on the
   Mac (delete its line in `nvim/lua/sahin/plugins/specs.lua`, run
   `:PackSync`, run `make test` and fix what still expects it, commit).
   Otherwise keep `vim.g.precognition = false` and toggle it with
   `<leader>tp` when you want it.
5. Keep `timeoutlen` at 1000 (at least 700): the `ö`/`ä` pairs need that
   time.

Check yourself: you can do a full day of notes and payload work without
opening this file.
