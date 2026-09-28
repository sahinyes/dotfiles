# Troubleshooting

Start with the two doctors. They only read; they change nothing.

```sh
~/dotfiles/scripts/doctor.sh      # terminal: TERM, undercurl, clipboard tool, font, iTerm2/GNOME settings
```

```vim
:Doctor                           " editor: Neovim path, clipboard provider, parsers, spell files, trust, plugins
```

Then find the symptom below. Each table reads: what you see, why, what to do.

## Installer

| Symptom | Cause | Fix |
|---|---|---|
| `HEAD is not a release tag; check out a signed vX.Y.Z tag (or use --dev)` | The clone is on a branch or a commit, not a tag. | On the laptop: `install.sh update vX.Y.Z`. On the Mac, where you develop: `./install.sh --dev`. |
| `no pinned signing key yet (~/.config/dotfiles/allowed_signers): pin it as the README's bootstrap shows` | `trust-key` was never run on this machine. | Do steps 3 and 4 of the bootstrap in the [README](../README.md): check the key and the tag yourself, then `~/dotfiles/install.sh trust-key SHA256:<fingerprint from paper>`. |
| `fingerprints differ: do not use this checkout` | The key in the clone is not the key you know. | Stop. Delete the clone, check the fingerprint on the Mac again, clone again. |
| `tag vX.Y.Z does not verify` / `does NOT verify with the pinned key` | The tag is unsigned, signed by another key, or signed with OpenPGP or X.509 (always refused). | Stop. Do not use `--dev` to get past it. |
| `the tag object behind vX.Y.Z is named ...` | A signed tag with another name was published under this name, for example an older release passed off as a newer one. | Stop. Do not install it. |
| `the local tag vX.Y.Z differs from the verified one fetched` | Your clone already has a tag of that name, and it points somewhere else than the tag on GitHub. Tags are never moved, so one of the two is wrong. | Stop and find out why (`git -C ~/dotfiles show vX.Y.Z`). Nothing was changed. |
| `the checkout has local changes (git status); refusing to run` | A tracked file changed. Usual cases: `nvim/nvim-pack-lock.json` after `<leader>uu` + `:write`, or `nvim/spell/en.utf-8.add` after `2zg`. | `git -C ~/dotfiles status`, then `git -C ~/dotfiles checkout -- <file>`. Make such changes on the Mac and release them. |
| `https://github.com/ is not reachable; this install needs it` | No network, or a proxy is needed. | `curl`, `wget` and `python3` all honour `https_proxy`. Set it and run again. |
| `FAIL` lines in the report | The line says why (download, sha256, missing tool). | Fix that reason and run `install.sh` again. Re-running is always safe. |
| `WARN shell new shells do not put ~/.local/bin first on PATH` | Your shell rc does not source `shell/env.sh`. | `~/dotfiles/install.sh --shell-rc`, or add `source ~/dotfiles/shell/env.sh` yourself. Open a new terminal. |
| `WARN brew Homebrew differs from tools.lock: ...` | The Mac uses Homebrew's versions; the laptop uses the pinned ones. | Information only. Upgrade with `brew upgrade <formula>` when you want, or bump `tools.lock` (see [UPDATE.md](UPDATE.md)). |
| `FAIL nvim ... is 0.13.0, this config needs 0.12.x` | Homebrew upgraded Neovim. | See the Neovim 0.13 section in [UPDATE.md](UPDATE.md). To prevent it: `brew pin neovim`. |
| `FAIL apt ... apt-get download failed` | The apt mirror is blocked or `apt-get update` never ran on the laptop. | Ask IT for the package (git, tmux, wl-clipboard), then run `install.sh` again: a system package replaces the unpacked copy. |
| `WARN apt ... unpacked, but some libraries are missing` | A library the package needs could not be downloaded. A later `install.sh` does not retry it: an unpacked package is never downloaded again. | Ask IT for the package, or retry: `rm -rf ~/.local/opt/apt/<package>`, then run `install.sh`. |
| An unpacked git, tmux or wl-clipboard is older than Debian's current version | `install.sh` refreshes an unpacked package only when it runs. | Run `~/dotfiles/install.sh` again; it unpacks the newer version and the report says `was <old version>`. |
| Spell step takes minutes | The spell mirror (ftp.nluug.nl) is slow; each file is tried 3 times. | Wait. If it still fails, run `install.sh` again later; finished downloads are kept in `~/.cache/dotfiles`. |
| `WARN terminal scripts/doctor.sh found N warning(s)` | Terminal settings that `install.sh` does not own. | Run `~/dotfiles/scripts/doctor.sh` and follow each `fix:` line. |
| `WARN notes gitleaks is missing: the pre-commit hook blocks every notes commit` | gitleaks is not installed yet. | Run `install.sh` again (Linux: from `tools.lock`; Mac: Brewfile). |

## Plugins

| Symptom | Cause | Fix |
|---|---|---|
| Warning at start: `plugins missing (...): run :PackSync (or install.sh)` | A plugin folder is missing. Neovim never clones at startup, because a slow or blocked network could hang it. Plugins that exist are still loaded. When offline (`NVIM_OFFLINE=1`, `vim.g.nvim_offline`, or no git) the hint says `run install.sh when online`. | Laptop: run `install.sh`. Mac: `:PackSync`. |
| A prompt at start asks to install plugins | A plugin is missing, git exists and offline mode is off. | Answer yes, or quit and run `install.sh`. |
| `git status` shows `nvim/nvim-pack-lock.json` modified | vim.pack rewrote the lockfile (an update you confirmed, or a failed install). | `git -C ~/dotfiles checkout -- nvim/nvim-pack-lock.json`, restart (`ZR`), then `<leader>ul` and `:write` in the review buffer. Or `:PackSync`. |
| Report: `plugins ... match the lockfile after sync; differs: ...` | A clone failed or a plugin is at another revision. | Run `install.sh` again (online). `:checkhealth vim.pack` shows the state. |
| Warning at start: `gitsigns: repo guard not installed (plugin internals changed)` | A gitsigns update renamed the internal function this config wraps. gitsigns may now run git in untrusted folders. | Roll gitsigns back (see [UPDATE.md](UPDATE.md)) and adapt `nvim/lua/sahin/plugins/gitsigns.lua`. |
| `:TSInstall` / `:TSUpdate` do not exist | Removed on purpose; parsers come only from `install.sh`. | See "Treesitter" below. |

## LSP and trust

| Symptom | Cause | Fix |
|---|---|---|
| No LSP, no git signs in a project | The project is not trusted (the default). `:Doctor` says `NOT trusted`. | `:TrustProject` in a file of that project; read the root and servers, answer Yes. |
| `:TrustProject: ... matches never_trust_globs` | The folder is under `~/Downloads`, `~/bb`, `~/CTF-Lab`, `~/targets` or `/tmp`. | Intended: those hold target material. Move your own code elsewhere, or use `:TrustProject!` if you are sure. |
| `:TrustProject: ... is / or your home directory` | Trusting `~` would trust every loose file. | Trust the project folder instead. |
| `TrustProject: no VCS root here; pass a directory` | The file is not in a git, hg or jj repo. | `git init` the folder, then `:TrustProject`. Loose files outside a repo never get LSP, even in a trusted folder (`~/notes` is the exception). |
| Trusted, but one server still does not start | Its binary was not on PATH when Neovim started (on the laptop only marksman is installed), or its root is a nested folder (a subproject with its own `.luarc.json` or `.git`). | `:checkhealth vim.lsp`. Install the server and restart Neovim (`ZR`). For a nested root: `:TrustProject path/to/subproject`. |
| Only marksman runs in `~/notes` | By design: the notes folder allows marksman only. | Nothing to fix. |
| No LSP in `nvu` | By design: the untrusted profile has none. | Use `nvim` in a trusted project. |
| A server misbehaves | | `:lsp restart`; log: `~/.local/state/nvim/lsp.log`. |
| `K` in a Python file shows a man page error instead of Python docs | pydoc is switched off: it imports modules from the current folder, so `K` on `import utils` in a clone would run the clone's `utils.py`. | In a trusted project basedpyright answers `K`. |
| yamlls/jsonls: a schema from a URL is not loaded | By design: they are offline and read only the schemas in `nvim/schemas/`. | Add a vendored schema (see `nvim/schemas/SOURCES.md`). |
| Debian: marksman exits with an ICU / globalization error | libicu is missing and `~/.local/bin/marksman` is not the wrapper (for example after libicu was removed). | Run `install.sh` again: without libicu it writes a wrapper that sets `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1`. Check with `head -5 ~/.local/bin/marksman`. |

## Clipboard

`:Doctor` shows the provider Neovim uses and why.

| Symptom | Cause | Fix |
|---|---|---|
| Mac: yank does not reach the clipboard over SSH | OSC 52 is off on purpose. | Copy with the local tmux copy mode (`prefix Enter`, `v`, `y`). To accept the risk: `vim.g.osc52 = true` in `nvim/lua/local.lua` and allow clipboard access in iTerm2 (see [SECURITY.md](../SECURITY.md)). |
| Debian (Wayland): `"+y` or `<leader>y` does nothing | `wl-copy` is missing, or `WAYLAND_DISPLAY` is not set in this shell (for example a tmux server started from SSH). | `command -v wl-copy`; run `install.sh` (it unpacks wl-clipboard without root). Start the tmux server from a GNOME Terminal window: `tmux kill-server`, then `tmux`. |
| Debian (X11): no clipboard | `install.sh` does not install xclip. | Ask IT for `xclip`. Meanwhile GNOME Terminal's Ctrl+Shift+C / Ctrl+Shift+V work, and tmux buffers work (`prefix ]`). |
| tmux `y` in copy mode copies nowhere | The copy tool is chosen when the tmux server starts; none was found then. | Install the tool, then `tmux source-file ~/.tmux.conf`. `tmux show -sv copy-command` shows the current choice. |
| Every yank replaces the system clipboard | `clipboard=unnamedplus` is set when a local clipboard tool exists. | Intended. Use `"_d` to delete without copying, or `"0p` to paste the last yank. |

## Display and keyboard

| Symptom | Cause | Fix |
|---|---|---|
| Spelling/diagnostic underline is straight, not curly, inside tmux (Mac) | macOS's terminfo for `tmux-256color` lacks `Smulx`. `:Doctor` shows `Smulx ... no`. | `~/dotfiles/scripts/terminfo-mac.sh`, then `tmux kill-server` and start tmux again. |
| Same on Debian | tmux declares curly underlines for GNOME Terminal only when the server started inside GNOME Terminal (`VTE_VERSION` set). | `tmux kill-server`, then start tmux from a GNOME Terminal window. |
| Icons show as boxes or question marks | The terminal font is not a Nerd Font, or `vim.g.have_nerd_font` does not match. | Install the font (`install.sh`), set it in the terminal (iTerm2 profile; on Debian `scripts/gnome-terminal.sh`), then `vim.g.have_nerd_font = true` in `nvim/lua/local.lua`. With no Nerd Font, set it to `false` for plain text icons. |
| Colors look wrong | `TERM` is not `xterm-256color` outside tmux or `tmux-256color` inside. | `doctor.sh` says which. Do not export `TERM` in your shell rc. |
| Mac: Option+5 does not type `[` | iTerm2 sends Option as Meta. | iTerm2 > Settings > Profiles > Keys: both Option keys "Normal". `doctor.sh` checks it. |
| Mac: Option+arrow does not switch tmux panes | iTerm2 does not send Option+arrow as Alt+arrow. | Keys > "Treat Option as Alt for special keys" on. |
| `ö` or `ä` waits a second before it acts | It may be the start of `öö`, `öä` ... Neovim waits `timeoutlen` (1000 ms). | Type the second key without a pause. Do not lower `timeoutlen` below 700. |
| F10 or Alt+letter opens the GNOME Terminal menu | The profile script has not run. | `~/dotfiles/scripts/gnome-terminal.sh` (it backs up with `dconf dump` first). |
| `<C-Space>` does nothing on the Mac | macOS uses Ctrl+Space to switch input sources. | Use `<C-x><C-o>`, or change the macOS shortcut. |
| `<leader>e` does nothing in `nvu` | netrw is not loaded in the untrusted profile, so the map does not exist there. | Use `nvim` for browsing folders. |

## Treesitter

| Symptom | Cause | Fix |
|---|---|---|
| YAML, JSON, Python ... have plain regex colors | No extra parsers. The report says `OFF treesitter <reason>` and `:Doctor` lists the installed parsers. | See the reasons below, fix, run `install.sh` again. |
| Reason `... has glibc 2.36, tree-sitter 0.27.0 needs 2.39` | Debian 12: the pinned tree-sitter CLI cannot run. | None on Debian 12. Markdown still works (its parser ships with Neovim). |
| Reason `no C compiler (cc)` | Debian without `cc`. | Ask IT for `gcc`, or live with regex syntax. |
| Reason `no C compiler (run: xcode-select --install)` | Mac without the Command Line Tools. | `xcode-select --install`. |
| Reason `tree-sitter CLI missing` | Mac: `tree-sitter-cli` not installed. Linux: the tools step failed. | Run `install.sh` again and read the `tools`/`brew` lines. |
| A large file has no colors at all | Files over 1.5 MB open in big-file mode (no syntax, no treesitter). | Intended. |

## Spelling

| Symptom | Cause | Fix |
|---|---|---|
| German or Turkish words are not checked | Their spell files are missing. `:Doctor` shows `spell files missing: de_ch tr`. | Run `install.sh` (spell step). Neovim's own download is off on purpose. |
| `zg` word is not known on the other machine | `zg` writes to a local list. | Use `2zg` for words that belong in the shared, public list (`nvim/spell/en.utf-8.add`), then commit it on the Mac. |

## tmux

| Symptom | Cause | Fix |
|---|---|---|
| Errors or odd behaviour after upgrading tmux | The running server is the old version. | Save your work, then `tmux kill-server` and start tmux again. |
| `prefix I` / `prefix U` do nothing | tpm was removed. | Plugins are pinned by `install.sh`. Save/restore: `prefix Ctrl-s` / `prefix Ctrl-r`. |
| SSH window is not colored, or shows the host name in purple | No host map yet. | Create `~/.config/dotfiles/ssh-hosts` (`host-or-glob label` per line; labels `dev prod gpu oob mac` have colors). Your old map is in `~/.dotfiles-backup/<timestamp>/.tmux/scripts/ssh-colors.sh`. Make sure your shell rc sources `~/.tmux/scripts/ssh-colors.sh`. |
| No git branch in the status bar | git was not on PATH when tmux started, or the pane is not in a repo. | Start tmux from a shell that has `~/.local/bin` on PATH. |
| Nested tmux (tmux over SSH inside tmux) | Both use `Ctrl+a`. | `Ctrl+a Ctrl+a` sends the prefix to the inner one. |

## Notes

| Symptom | Cause | Fix |
|---|---|---|
| Warning `Notes auto-commit blocked (pre-commit hook?)` with gitleaks output | gitleaks found something that looks like a secret. The file is saved, not committed. | Move the secret to `~/notes/.scratch/` and save. For a false positive, gitleaks skips a line that contains `gitleaks:allow`. Never commit with `--no-verify`. |
| Same warning, `gitleaks not found, refusing to commit` | gitleaks is missing. | Run `install.sh`. |
| `Author identity unknown` | No git identity for `~/notes`. | `git -C ~/notes config user.name notes` and `git -C ~/notes config user.email notes@localhost` (what `install.sh` does). |
| `:Tasks` finds nothing | No notes folder yet, or tasks are not written as `- [ ] ` (dash, space, bracket). | `:Capture` or `:Daily` creates the folder. Check the format in [NOTES-CONVENTION.md](NOTES-CONVENTION.md). |
| `:Tasks` does not list the project's `TODO.md` | It is a symlink that leads outside the repo, or not a regular file. Such a file is skipped on purpose. | Make `TODO.md` a plain file in the repo. |
| `rg: stopped after 10 s, the list may be incomplete` | The notes folder is very large, or a search root is slow (network drive). | Move big non-note files out of `~/notes`, or use `<leader>ng` for one-off searches. |
| Notes are not auto-saved | Only files inside the notes folder are, and only on leaving the buffer or losing focus. | Save with `:w`. Inside tmux, focus events need `focus-events on` (set in `tmux.conf`). |
| `<leader>1` says "Hot note 1 is not set" | `vim.g.hot_notes` is empty. | Add it to `nvim/lua/local.lua` (see [NOTES-CONVENTION.md](NOTES-CONVENTION.md)). |
| `E21: Cannot make changes` after Enter in an LSP hover window | The hover window is Markdown, so `<CR>` tries to cycle a task there. | Harmless. Close the window with `q` or move out of it. |

## Inspect commands

| Symptom | Cause | Fix |
|---|---|---|
| `Json: not valid JSON: not a JSON number or literal: "NaN"` | The text is not strict JSON: `NaN`, `Infinity`, hex numbers, `+1`, `01` or `1.` are refused. | Fix or remove that value. `:Json` and `:JsonMin` accept only strict JSON (RFC 8259). |
| `Json: not valid JSON: raw control character (tab, newline, ...) in a string` | A string holds a real tab or line break instead of `\t` or `\n`. | Replace it with the escape. |
| `Json: result is larger than 50 MB (deeply nested?): refused` | Deep nesting repeats the indent before every value. | Use `:JsonMin`, or cut out the part you need first. |

## Where the logs are

| What | Where |
|---|---|
| Last install report | `~/.local/state/dotfiles/last-install.txt` |
| Backups of replaced files | `~/.dotfiles-backup/<timestamp>/` |
| Download cache | `~/.cache/dotfiles/` |
| Neovim messages of this session | `:messages` |
| Neovim log | `~/.local/state/nvim/nvim.log` |
| LSP log | `~/.local/state/nvim/lsp.log` |
| vim.pack log (installs, updates) | `~/.local/state/nvim/nvim-pack.log` |
| Plugin audit trail (one line per install/update/delete) | `~/.local/state/nvim/pack-audit.log` |
| Trust database | `~/.local/state/nvim/trust` |
| Notes history | `git -C ~/notes log --oneline` |
| tmux-resurrect saves | `~/.local/share/tmux/resurrect/` |
| Untrusted profile state (shada, undo, swap) | `~/.local/state/nvim-untrusted/` |
