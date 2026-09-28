# Key maps

The leader key is **Space**. In the tables, `<leader>x` means Space, then x.

Mode letters: `n` Normal, `x` Visual, `o` operator-pending (after `d`, `c`,
`y` ...), `i` Insert, `t` Terminal, `ia` an Insert-mode abbreviation.
Each table in section 2 names, in its heading, the file under `nvim/` that
creates its maps (the owner module).

The tables in section 2 list every map this config creates. They were taken
from `tests/keymap_probe.lua`, which records each map together with the file
that made it; `tests/keymaps.lua` then checks the rules in section 6. To look
a map up inside Neovim, use `<leader>sk` (search keymaps) or
`:verbose nmap <key>`.

## 1. The Swiss German layer

### Which key gives what

| Character | Mac (iTerm2, both Option keys = Normal) | Debian (GNOME Terminal) | Alias in this config |
|---|---|---|---|
| `[` | Option+5 | AltGr+ü | `ö` |
| `]` | Option+6 | AltGr+¨ | `ä` |
| `{` | Option+8 | AltGr+ä | `é` (Shift+ö) |
| `}` | Option+9 | AltGr+$ | `à` (Shift+ä) |
| `` ` `` | dead key (waits for a second key) | dead key | `§` (key left of 1) |
| `~` | dead key or chord | dead key or chord | `°` (Shift+§) |
| `^` | dead key | dead key | use `_` (first non-blank character, same motion) |
| `Ctrl-]` | needs Ctrl+Option | needs Ctrl+AltGr | `ü` |

### Why the aliases exist

Many Vim commands start with or end in `[`, `]`, `{`, `}`, `` ` `` or `~`:
`[d` (previous diagnostic), `]]` (next heading), `ci{` (change inside
braces), `` `a `` (exact mark). On a Swiss German keyboard each of those needs Option or AltGr,
or is a dead key that waits for a second key. The keys `ö ä é à § °` are
single keys (or Shift) on the same keyboard and have no meaning in Vim's
Normal mode, so they stand in for the brackets.

### The three layers

A single alias is not enough, because Vim reads some keys "with mappings
off". The layer file is `lua/sahin/swiss.lua`.

**Layer 1: single keys.** `ö` is mapped to `[` with `remap=true`, so it
behaves as if you had pressed `[`, and the key after it completes any `[`
command or map: `öd` = `[d`, `äq` = `]q`, `öc` = `[c` (previous git hunk),
`ä<Space>` = `]<Space>` (blank line below). `é`/`à` move by paragraph. `§a`
jumps to the exact position of mark `a`. `°` toggles case.

**Layer 2: pairs.** Built-in commands such as `[[`, `]}` or ` `` ` read their
second key with mappings off, so `öö` would become `[ö`. Each pair is its own
map. They also use `remap=true`, so a buffer's own `[[`/`]]` wins: heading
jumps in Markdown, prompt jumps in `:terminal`, plugin jumps in the vim.pack
update buffer.

**Layer 3: text objects.** After an operator, `i` and `a` also read their
next key with mappings off, so `ciö` needs explicit maps:
`iö aö iä aä ié aé ià aà`. mini.ai's `ib`/`ab` (any bracket) and `iq`/`aq`
(any quote) work too and need no alias.

**Timing.** `ö`, `ä` and `§` start longer maps (`öö`, `§§` ...). After `ö`,
Neovim waits up to `timeoutlen` (1000 ms) for a second key. Type the second
key without a pause. If you pause, mini.clue shows the possible next keys
after 300 ms (section 4).

Built-ins are used where no alias is needed: `Q` replays the last recorded
macro, `_` replaces `^`, `'a` (line of mark `a`) replaces `` `a `` when the
column does not matter, and `Ctrl-6` switches to the alternate file.

## 2. Every map this config creates

### Swiss layer (`lua/sahin/swiss.lua`)

| Mode | Keys | Description |
|---|---|---|
| n x o | `ö` | `[` (alias) |
| n x o | `ä` | `]` (alias) |
| n x o | `é` | `{` paragraph back (Shift+ö) |
| n x o | `à` | `}` paragraph forward (Shift+ä) |
| n x o | `§` | `` ` `` exact mark jump |
| n x o | `°` | `~` toggle case |
| n x o | `öö` | `[[` (alias) |
| n x o | `ää` | `]]` (alias) |
| n x o | `öä` | `[]` (alias) |
| n x o | `äö` | `][` (alias) |
| n x o | `öé` | `[{` (alias) |
| n x o | `äà` | `]}` (alias) |
| n x o | `§§` | ` `` ` (alias) |
| n x o | `§ö` | `` `[ `` (alias) |
| n x o | `§ä` | `` `] `` (alias) |
| x o | `iö` / `aö` | inner / a `[` block |
| x o | `iä` / `aä` | inner / a `]` block |
| x o | `ié` / `aé` | inner / a `{` block |
| x o | `ià` / `aà` | inner / a `}` block |
| n | `ü` | Go to definition / tag (`Ctrl-]`) |
| t | `<C-q>` | Leave terminal mode |
| n x | `+` | Increment number (`Ctrl-a` is the tmux prefix) |
| n x | `-` | Decrement number |
| x | `g+` | Increment sequentially |
| x | `g-` | Decrement sequentially |
| n | `Q` | Replay last recorded macro (only defined on Neovim 0.13+, where `Q` changes) |

### Core (`lua/sahin/keymaps.lua`)

| Mode | Keys | Description |
|---|---|---|
| n | `<Esc>` | Clear search highlight |
| n | `<leader>e` | File explorer (netrw) |
| n | `<leader>xq` | Quickfix: open |
| n | `<leader>xc` | Quickfix: close |
| n | `<leader>xl` | Location list: open |
| n | `<leader>xd` | Diagnostics: all to quickfix |
| n | `<leader>q` | Diagnostics: buffer to location list |
| n x | `<leader>y` | Yank to system clipboard (`"+y`) |
| n x | `<leader>p` | Paste from system clipboard (`"+p`) |
| n x | `<leader>cf` | Code: format buffer (LSP formatter, else `formatprg`) |
| n | `<leader>tw` | Toggle: line wrap |
| n | `<leader>ts` | Toggle: spell check |
| n | `<leader>tn` | Toggle: relative numbers |
| n | `<leader>tc` | Toggle: autocomplete (buffer) |
| n | `<leader>th` | Toggle: inlay hints |
| n | `<leader>uu` | Plugins: review updates (not in `nvu`) |
| n | `<leader>ud` | Plugins: diff code of pending updates, `:PackDiff` (not in `nvu`) |
| n | `<leader>ul` | Plugins: realign to lockfile, offline (not in `nvu`) |

### Inspect (`lua/sahin/inspect.lua`)

In Normal mode these work on the whole buffer. In Visual mode they work on
the selection (exact characters with `v`, whole lines with `V` and
`Ctrl-v`). The commands take a range, default the whole buffer.

| Mode | Keys | Command | Description |
|---|---|---|---|
| n x | `<leader>ij` | `:Json` | Inspect: pretty-print JSON |
| n x | `<leader>im` | `:JsonMin` | Inspect: minify JSON |
| n x | `<leader>ih` | `:Hex` | Inspect: hex dump (scratch split) |
| n x | `<leader>ib` | `:B64d` | Inspect: base64/base64url decode |
| n x | `<leader>iB` | `:B64e` | Inspect: base64 encode |
| n x | `<leader>iu` | `:UrlDecode` | Inspect: URL decode |
| n x | `<leader>iU` | `:UrlEncode` | Inspect: URL encode (component) |
| n x | `<leader>iw` | `:Jwt` | Inspect: decode JWT (signature NOT verified) |
| n x | `<leader>id` | `:DiffTool` | Inspect: `:DiffTool {left} {right}` (types the command, you add the paths) |

### Search (`lua/sahin/plugins/telescope.lua`)

| Mode | Keys | Description |
|---|---|---|
| n | `<leader>sh` | Search: help |
| n | `<leader>sk` | Search: keymaps |
| n | `<leader>sf` | Search: files |
| n x | `<leader>sw` | Search: word under cursor (or selection) |
| n | `<leader>sg` | Search: grep |
| n | `<leader>sd` | Search: diagnostics |
| n | `<leader>sr` | Search: resume last search |
| n | `<leader>s.` | Search: recent files |
| n | `<leader>sc` | Search: commands |
| n | `<leader>ss` | Search: select a telescope picker |
| n | `<leader><leader>` | Search: open buffers |
| n | `<leader>/` | Search: fuzzy in current buffer |
| n | `<leader>s/` | Search: grep in open files |
| n | `<leader>sn` | Search: Neovim config files |

The pickers are not gated by trust (see [SECURITY.md](../SECURITY.md)). For
a cloned target repository use `nvu`, which has no telescope.

### Notes (`lua/sahin/notes/init.lua`)

| Mode | Keys | Command | Description |
|---|---|---|---|
| n x | `<leader>nx` | `:TaskCycle` | Notes: cycle task state |
| n x | `<leader>nD` | `:TaskDone` | Notes: task done (+done: date) |
| n x | `<leader>n!` | `:TaskMark !` | Notes: mark task important `[!]` |
| n x | `<leader>nz` | `:TaskMark >` | Notes: defer task `[>]` |
| n | `<leader>na` | `:TaskArchive` | Notes: archive done task trees |
| n | `<leader>no` | `:Tasks open` | Notes: open tasks -> quickfix |
| n | `<leader>ni` | `:Tasks important` | Notes: important tasks -> quickfix |
| n | `<leader>ns` | telescope | Notes: search open tasks |
| n | `<leader>nc` | `:Capture` | Notes: capture task to inbox |
| n | `<leader>nd` | `:Daily` | Notes: today's daily note |
| n | `<leader>nt` | `:Todo` | Notes: project's TODO.md |
| n | `<leader>nn` | telescope | Notes: find note |
| n | `<leader>ng` | telescope | Notes: grep notes |
| n | `<leader>1` ... `<leader>5` | | Notes: hot note 1 ... 5 (`vim.g.hot_notes` in `lua/local.lua`) |

### Markdown buffers (`after/ftplugin/markdown.lua`, buffer-local)

| Mode | Keys | Description |
|---|---|---|
| n x | `<CR>` | Task: cycle state (`:TaskCycle`, on a range in Visual mode) |
| ia | `xd` | Insert today's date (type `xd` then a space or punctuation) |

### Git hunks (`lua/sahin/plugins/gitsigns.lua`, buffer-local, trusted roots only)

These exist only after gitsigns attached to the buffer, which happens only
inside a root you trusted with `:TrustProject`.

| Mode | Keys | Description |
|---|---|---|
| n | `]c` (type `äc`) | Git: next hunk (in diff mode: the built-in `]c`) |
| n | `[c` (type `öc`) | Git: previous hunk |
| n | `<leader>hs` | Git hunk: stage |
| n | `<leader>hr` | Git hunk: reset |
| x | `<leader>hs` | Git hunk: stage selected lines |
| x | `<leader>hr` | Git hunk: reset selected lines |
| n | `<leader>hS` | Git hunk: stage buffer |
| n | `<leader>hR` | Git hunk: reset buffer |
| n | `<leader>hp` | Git hunk: preview |
| n | `<leader>hb` | Git hunk: blame line |
| n | `<leader>hd` | Git hunk: diff against index |
| n | `<leader>hq` | Git hunk: hunks to quickfix |
| o x | `ih` | Git: inner hunk |
| n | `<leader>tb` | Toggle: git blame of current line |

### LSP, completion and plugin toggles

| Mode | Keys | Description | Owner |
|---|---|---|---|
| n | `grd` | Goto definition (telescope), buffer-local when a server attaches | `lua/sahin/lsp.lua` |
| i | `<C-Space>` | Complete: ask the LSP server (else omni completion) | `lua/sahin/completion.lua` |
| n | `<leader>tr` | Toggle: render markdown | `lua/sahin/plugins/render_markdown.lua` |
| n | `<leader>tp` | Toggle: precognition motion hints | `lua/sahin/plugins/precognition.lua` |

## 3. Defaults you get from Neovim and the plugins

These are not created by this config, so they are not in the tables above.

### LSP (Neovim 0.12 defaults, left unchanged)

| Mode | Keys | Action |
|---|---|---|
| n | `K` | Hover documentation. Without a server: the filetype's `keywordprg` (`:Man` by default). In Python files it never runs pydoc (see [SECURITY.md](../SECURITY.md)) |
| n | `grn` | Rename symbol |
| n x | `gra` | Code action |
| n | `grr` | References |
| n | `gri` | Implementation |
| n | `grt` | Type definition |
| n | `grx` | Run code lens |
| n | `gO` | Document symbols. In Markdown, the buffer's own `gO` shows the heading outline instead |
| i | `<C-s>` | Signature help |
| n | `ü` (`Ctrl-]`) | Go to definition through the LSP tag function |
| n | `öd` / `äd` | Previous / next diagnostic (`[d` / `]d`) |
| n | `öD` / `äD` | First / last diagnostic |
| n | `<C-w>d` | Diagnostic under the cursor in a float |

Diagnostics show as virtual lines for the current line only.

### Other Neovim defaults worth knowing

| Keys | Action |
|---|---|
| `öq` / `äq`, `öQ` / `äQ` | previous / next, first / last quickfix entry |
| `öl` / `äl` | previous / next location-list entry |
| `öb` / `äb` | previous / next buffer |
| `öa` / `äa` | previous / next argument-list file |
| `ö<Space>` / `ä<Space>` | add a blank line above / below |
| `gc{motion}`, `gcc` | comment / uncomment |
| `an` / `in` (Visual) | grow / shrink the selection by treesitter node |
| `Q` | replay the last recorded macro |

### mini.ai text objects (`lua/sahin/plugins/mini.lua`)

Use them after an operator (`d`, `c`, `y`, `v` ...) with `i` (inside) or `a`
(around):

| Key | Object |
|---|---|
| `b` | any bracket: `()` `[]` `{}` |
| `q` | any quote: `"` `'` `` ` `` |
| `f` | function call |
| `a` | argument |
| `t` | HTML/XML tag |
| `?` | asks for the left and right edges |

`aa`/`ii` select the next object (`cii"` changes inside the next quotes),
`al`/`il` the previous one. `g[`/`g]` move to the edge of an object; they need
the real bracket keys.

### mini.surround

| Keys | Action | Example |
|---|---|---|
| `sa{motion}{char}` | add a surrounding | `saiw"` puts quotes around a word |
| `sd{char}` | delete a surrounding | `sd"` |
| `sr{old}{new}` | replace a surrounding | `sr"'` |
| `sf` / `sF` | find the next / previous surrounding | |
| `sh` | highlight a surrounding | |

In Visual mode, `sa{char}` surrounds the selection. Plain `s` waits for the
next key for up to a second before it acts as Vim's `s`.

## 4. Key hints (mini.clue)

Press a trigger key and wait. After 300 ms a window lists every key that can
follow, with its description.

| Trigger | Modes | Shows |
|---|---|---|
| `<leader>` (Space) | n x | the leader groups and maps |
| `ö` / `ä` | n | the `[` / `]` families, written the Swiss way (`öd`, `öö`, `äc` ...) |
| `g`, `z` | n x | built-in `g` and `z` commands (folds, spelling, `gr*` LSP keys) |
| `"` | n x | registers and their contents |
| `'` | n x | marks |
| `<C-w>` | n | window commands |
| `<C-x>` | i | completion sources |
| `<C-r>` | i, command line | registers to insert |

Leader groups: `s` Search, `n` Notes, `h` Git hunk, `x` Quickfix, `c` Code,
`t` Toggle, `i` Inspect, `u` Update/plugins. `<leader>1`..`<leader>5`,
`<leader>y`, `<leader>p`, `<leader>q`, `<leader>e`, `<leader>/` and
`<leader><leader>` are single maps.

Inside the hint window: `<BS>` removes the last key, `<C-d>`/`<C-u>` scroll,
`<Esc>` cancels.

For `öö`, the window shows the global description `[[ (alias)`, not the
description of Markdown's own heading jump. The key still reaches the
buffer's `[[`.

## 5. Completion (`lua/sahin/completion.lua`)

Neovim's built-in completion, no plugin. In code buffers a menu opens while
you type (LSP items first, then words from this buffer, other windows and
other buffers). In
Markdown and git commit messages it stays closed until you ask.

| Keys (Insert mode) | Action |
|---|---|
| `<C-n>` / `<C-p>` | next / previous item (also opens the menu) |
| `<C-y>` | accept (applies snippets and auto-imports) |
| `<C-e>` | close the menu |
| `<C-Space>` | ask the LSP server now (without a server: omni completion) |
| `<C-x><C-o>` | omni completion (use this if macOS takes Ctrl+Space for input switching) |
| `<C-x><C-f>` / `<C-x><C-l>` | file names / whole lines |
| `<C-s>` | signature help |
| `<Tab>` / `<S-Tab>` | jump inside an accepted snippet (Neovim default); otherwise a normal tab |

`<Tab>` and `<CR>` are not mapped for completion. `<leader>tc` turns the
automatic menu on or off for the current buffer.

## 6. Rules: forbidden keys and why

`tests/keymaps.lua` fails when a map breaks one of these rules.

| Not allowed | Why |
|---|---|
| `<M-...>`, `<A-...>` (Alt/Meta) | The Option keys must stay "Normal" in iTerm2 to type `[ ] { } \|`, so Option+letter never arrives as Meta. On Debian AltGr types characters. |
| Ctrl+Shift (`<C-S-...>`) | tmux runs with `extended-keys off` and GNOME Terminal sends the legacy encoding, which cannot tell Ctrl+Shift+x from Ctrl+x. GNOME Terminal also uses Ctrl+Shift+C/V itself. |
| `<C-i>`, `<C-m>`, `<C-[>` | Same bytes as `<Tab>`, `<CR>`, `<Esc>` in a legacy terminal. |
| `<Tab>` in Normal mode | It is `<C-i>` (jump forward). |
| `<C-a>` | tmux prefix; Neovim never receives it. Increment/decrement are on `+`/`-`. |
| `<C-CR> <C-Tab> <C-BS> <C-/> <C-=> <C-\> <C-]> <C-arrows>` | Not sent reliably in legacy mode (`<C-]>` is also hard to type here, hence `ü`). |
| Dead keys `^`, `` ` ``, `~`, `¨`, `´` | They wait for a second key, so they cannot start a map. |
| A map without a description | Every map must show up in mini.clue and `<leader>sk`. |
| A key that is both a map and the start of a longer map | It would wait `timeoutlen` every time. Only `ö`, `ä`, `§` do this, on purpose. A leader group letter (`s n h x c t i u`) is never a map on its own. |

There is no `<Esc><Esc>` map in terminal mode: `timeoutlen` is global, so it
would delay every `Esc` that programs inside `:terminal` (fzf, less, Claude
Code) receive. Use `<C-q>`. Inside `:terminal`, `<C-q>` therefore does not
reach zsh (its push-line key).

## 7. What exists in `nvu`

`nvu` (the untrusted profile) loads only the Swiss layer, the core maps
(without `<leader>e`, `<leader>uu`, `<leader>ud`, `<leader>ul`) and the
inspect maps.
There are no search, notes, git, LSP or completion maps, and Markdown buffers
get the options but not `<CR>` or `xd`. netrw is not loaded in `nvu`, so
there is no `<leader>e` either.

## 8. tmux keys (`tmux/tmux.conf`)

The prefix is **Ctrl+a**. `prefix F1` shows a cheat sheet.

| Keys | Action |
|---|---|
| `prefix v` / `prefix -` | split left/right / top/bottom (`\|` and `_` also work) |
| `prefix h j k l` | move between panes |
| `prefix H J K L` | resize panes (repeatable) |
| Option+arrows (Mac), Alt+arrows (Debian) | move between panes, no prefix |
| Shift+Left / Shift+Right | previous / next window, no prefix |
| `prefix c` | new window in the current folder |
| `prefix <` / `prefix >` | move the window left / right |
| `prefix z` | zoom the pane |
| `prefix a` | type in all panes at once (toggle) |
| `prefix x` / `prefix Q` / `prefix X` | kill pane / window / session (asks first) |
| `prefix S` / `prefix N` | session list / new session |
| `prefix T` | sesh project picker (only when sesh and fzf-tmux are installed) |
| `prefix Enter` | copy mode (vi keys): `v` select, `V` line, `Ctrl-v` block, `y` copy |
| `prefix /` | search the scrollback |
| `prefix ]` | paste the last tmux buffer |
| `prefix Ctrl-s` / `prefix Ctrl-r` | save / restore sessions (tmux-resurrect) |
| `prefix r` | reload `~/.tmux.conf` |
| `prefix Ctrl-a` | send Ctrl+a to the program (for example a nested tmux) |

`y` in copy mode (and a mouse drag) copies to the system clipboard through
`pbcopy`, else `wl-copy` (Wayland), else `xclip` (X11). With none of them
the text stays in a tmux buffer; `prefix ]` pastes it.

`prefix I` and `prefix U` do nothing: tpm is gone. `install.sh` checks out
tmux-resurrect and tmux-continuum at pinned commits instead.
