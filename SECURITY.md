# Security

This setup is used to open material that may be hostile: cloned target
repositories, HTTP responses, logs, JSON payloads, tokens. This file
says what runs, when, with what trust, and what is still exposed. It
describes the code in this repo as it is, including the gaps that remain.

## Threat model

Three kinds of attacker input are in scope:

1. **Hostile files and repositories opened in the editor.** A clone or a
   downloaded file tries to run code or reach the network when you open it.
   Examples: modelines, `.exrc`/`.nvim.lua`, a Lua file in the current
   directory that shadows a missing module, a `.git/config` with
   `core.fsmonitor`, `.editorconfig`, language-server project files
   (`.luarc.json`, `pyrightconfig.json`, `go.mod` toolchains,
   `node_modules/.bin`), `$schema:` URLs that call home, crafted file names.
2. **Hostile terminal output.** Text printed by `curl`, `cat` or a log viewer
   carries escape sequences, for example OSC 52 to replace your clipboard.
3. **Supply chain.** A download (Neovim, tools, plugins, parsers, npm
   packages, spell files) or this repo itself is swapped or changed.

Out of scope: a machine that is already compromised, other local users,
root or IT on the work laptop, the integrity of Homebrew itself, and bugs in
the terminal emulator or the kernel. Once you trust a project, its language
servers read and sometimes run its project files; that is accepted, see
[Residual risks](#residual-risks-of-the-trust-gate).

## Defaults at a glance

| Setting | Value | Where |
|---|---|---|
| Lua modules from the current directory | removed from `package.path`/`cpath` before anything loads | `nvim/init.lua` |
| `modeline`, `modelineexpr`, `exrc` | off | `lua/sahin/security.lua` |
| Language providers (python3, node, perl, ruby) | off | `security.lua` |
| Built-in net plugin (`:edit https://...`), spell-file download, zip, tar | off | `security.lua` |
| netrw remote reads on open (`scp://`, `sftp://`, `ftp://`, `rsync://`, `dav://`, `file://`) | the `Network` autocommand group is deleted | `after/plugin/harden.lua` |
| `vim.ui.open` (`gx`, `:Open`, LSP links) | only `http`, `https`, `mailto`; asks first in `nvu` | `security.lua` |
| `K` in Python files (`keywordprg` = `python3 -m pydoc`, which imports modules from the current folder) | emptied in `python`, `pyrex` and `bzl` buffers: `K` uses `:Man`, or the LSP hover when a server is attached | `security.lua` |
| git started by Neovim or a plugin | `core.fsmonitor=false` forced through `GIT_CONFIG_COUNT` | `security.lua` |
| OSC 52 clipboard | off unless `vim.g.osc52 = true` | `security.lua`, `clipboard.lua` |
| editorconfig | only in trusted roots | `security.lua`, `trust.lua` |
| Language servers and gitsigns | only in trusted roots | `trust.lua`, `lsp.lua`, `plugins/gitsigns.lua` |
| Files over 1.5 MB | no syntax, no treesitter, no swap file, no undo history | `options.lua` |

## Three ways to open a file

| | `nvim` | `nvu` | `nvr0` |
|---|---|---|---|
| Command | `nvim` | `NVIM_APPNAME=nvim-untrusted nvim` | `nvim -u NONE -i NONE -n -R --cmd 'set nomodeline'` |
| Config | full | same repo config, stops after the editor core | none |
| Plugins | 8 | none | none |
| LSP, gitsigns, editorconfig | trusted roots only | none | none |
| Notes commands, auto-save, auto-commit | yes | no | no |
| netrw, gzip | local netrw, gzip | neither | not loaded |
| Inspect commands (`:Json`, `:B64d`, `:Jwt`, ...) | yes | yes | no |
| `gx` | http/https/mailto only | same, and asks first | Neovim default: no scheme filter, do not use it here |
| Leaves on disk | shada, undo, swap in `~/.local/state/nvim` | the same in `~/.local/state/nvim-untrusted` | nothing (read-only, no shada, no swap) |

Use `nvu` for a target repository or a folder of downloaded material. Use
`nvr0` for a single file you do not want any config to touch. Both aliases
come from `shell/env.sh`. `:Doctor` in `nvu` starts with
`!! UNTRUSTED PROFILE`.

`nvu` keeps undo files and swap files. They contain text from the files you
opened, in `~/.local/state/nvim-untrusted/`. Delete that folder after an
engagement if that matters to you.

## What runs, when, and with what trust

### Neovim and its plugins

All 8 plugins load at startup in the normal profile and never in `nvu`.
`vim.pack` runs no build hooks; a `PackChanged` handler only appends a line
to `~/.local/state/nvim/pack-audit.log`.

| Component | What it runs | When | Trust needed | Network |
|---|---|---|---|---|
| Neovim runtime | ftplugins; bundled parsers c, lua, markdown, markdown_inline, query, vim, vimdoc | every file | none | none |
| gzip plugin | `gzip -d` on a temp copy (Vim's own plugin; file names are passed through `shellescape()`) | opening a `.gz` file | none; off in `nvu` | none |
| netrw (local) | directory listing for `:Explore`; `:Nread`/`:Nwrite` still exist and run scp/curl if you type them | on request | none | only if you type those commands |
| vim.pack | `git clone`/`fetch`/`checkout` of the 8 plugins | `install.sh`, `:PackSync`, `<leader>uu`, `<leader>ul`; never at startup (a missing plugin only gives a warning) | none | github.com |
| plenary.nvim | library; its job runner starts telescope's commands as argv | with telescope | none | none |
| telescope.nvim | `rg`, `fd`/`find` as argv. `check_mime_type` is off, so the file preview never runs `file --mime-type` (telescope builds that command as a shell string, and a file named like `$(cmd)` would run `cmd`); files without a known type are shown as text | when you open a picker | **not gated** | none |
| gitsigns.nvim | `git` (rev-parse, diff, show, blame) | only for buffers in trusted roots; its startup branch lookup (`git rev-parse` in the cwd) is blocked outside trusted roots by a wrapper around `gitsigns.git.repo.get_info` | trusted root | none |
| mini.nvim (ai, surround, icons, statusline, hipatterns, clue) | pure Lua | always | none | none |
| nvim-treesitter | query files only. `install()` is never called, `:TSInstall`/`:TSUpdate` are removed (`vim.g.loaded_nvim_treesitter`) | always | none | none |
| Extra parsers (`site/parser/*.so`) | native code inside the Neovim process | every buffer of that language, trusted or not; not in `nvu` (other data dir) | none | none |
| render-markdown.nvim | pure Lua. Its LaTeX support would pipe `$...$` text to `utftex`/`latex2text`, but only with a LaTeX parser and one of those programs; this setup installs neither | markdown buffers | none | none |
| precognition.nvim | pure Lua | always | none | none |
| nvim-lspconfig | server definitions (`lsp/*.lua`, executed when a config is resolved). The parts that run programs or pick repo binaries are replaced in `after/lsp/` | startup | none | none |

The gitsigns wrapper depends on a gitsigns internal. If an update renames
it, a startup warning appears (`gitsigns: repo guard not installed`) and
`tests/plugins_spec.lua` fails. Review every gitsigns update with `:PackDiff`.

### This config's own code

| Component | What it runs | When | Network |
|---|---|---|---|
| Inspect commands (`:Json`, `:JsonMin`, `:Hex`, `:B64d`, `:B64e`, `:UrlDecode`, `:UrlEncode`, `:Jwt`) | pure Lua; buffer text never reaches a shell or another program. `:Json` refuses what is not strict JSON (`NaN`, `Infinity`, hex, `+1`, `01`, raw tabs in strings) and any result over 50 MB | on request | none |
| `:DiffTool` | `packadd nvim.difftool` (bundled) | on request | none |
| `:Tasks` | `rg --no-config --vimgrep` as argv (Lua scan if rg is missing), stopped after 10 s. A project `TODO.md` is searched only when it is a regular file inside the repo, so a symlink to `/dev/zero` cannot hang Neovim | on request | none |
| `:Todo` | writes the template only when no `TODO.md` exists, not even a dangling symlink | on request | none |
| Notes auto-commit | `git add -A -- . ':(exclude).scratch'`, `git diff --cached --quiet`, `git commit --no-gpg-sign` in `~/notes`; the pre-commit hook runs `gitleaks` | 1.5 s after the last save of a note, and on exit | none; never pushes |
| `:PackDiff` | `git diff --no-color --no-ext-diff --no-textconv` as argv in plugin folders | on request | none |
| `:Doctor` | `infocmp -x` as argv | on request | none |
| Spell word list | `:mkspell!` on `nvim/spell/en.utf-8.add` when it is newer than its `.spl` | first markdown buffer | none |
| Clipboard | `pbcopy`/`wl-copy`/`xclip` through Neovim's provider | on yank | none |

### Language servers

A server starts only when (1) its binary is on PATH when Neovim starts,
(2) the file is inside a trusted root, and (3) for `~/notes`, the server is
marksman. Every `cmd` is a bare name from PATH, never
`<root>/node_modules/.bin`.

| Server | Command | What it may read or run in a trusted root | Network |
|---|---|---|---|
| marksman | `marksman server` | Markdown files; root is the nearest `.marksman.toml` or `.git` | none |
| lua_ls | `lua-language-server` | `.luarc.json`; its `runtime.plugin` setting runs Lua inside the server | none |
| yamlls | `yaml-language-server --stdio` | only the schemas vendored in `nvim/schemas`; SchemaStore, Kubernetes CRD store and telemetry off | blocked: `http.proxy` and `HTTP(S)_PROXY` point at `127.0.0.1:9` |
| jsonls | `vscode-json-language-server --stdio` | `file://` schemas only (`handledSchemaProtocols`) | blocked the same way |
| bashls | `bash-language-server start` | runs `shellcheck` from PATH on your scripts, when installed | none |
| basedpyright | `basedpyright-langserver --stdio` | `pythonPath` is the `python3` on PATH at startup; a `pyrightconfig.json` in the repo can still point at a repo interpreter | none |
| ruff | `ruff server` | `pyproject.toml`/`ruff.toml` (hover off) | none |
| gopls | `gopls` with `GOTOOLCHAIN=local`, `GOFLAGS=-mod=readonly`, and `GOPROXY=off` when `vim.g.work_laptop` | runs the local `go` toolchain; on the Mac it may download modules; root found by markers only (no `go env`) | module proxy on the Mac |
| tsc | `tsc --lsp --stdio` (TypeScript 7) | `tsconfig.json` and type files; root found by lockfile/`.git` markers only (nothing is executed to find it) | none |

On the Debian laptop only marksman is installed, so only marksman runs.

### tmux and the shell

| Component | What it runs | When | Notes |
|---|---|---|---|
| `tmux/scripts/status.sh git` | `git -c core.fsmonitor=false branch --show-current` in the active pane's folder | every 5 s while tmux runs | the pane may sit in a hostile clone; `branch --show-current` does not read the index today, the flag keeps it that way |
| other status segments | `ps`, `awk`, `/proc`, `networksetup`, `route`, `ip`, `nmcli`, `tailscale` (when present); `claude-pulse-tmux.py` reads a local cache file | every 5 s | missing tools print nothing |
| tmux-resurrect + continuum | save layouts every 15 min; on the Mac also the **text of every pane, in plain text**, to `~/.local/share/tmux/resurrect` (made 0700 at every tmux start) | always | off on the work laptop (`~/.config/dotfiles/work` exists). Pane text can hold tokens and cookies |
| tmux plugins | loaded with `run-shell` from `~/.tmux/plugins/` at pinned commits; no tpm, so no `prefix+I`/`prefix+U` | tmux start | |
| `ssh-colors.sh` (if you source it) | `tmux set` with a label from `~/.config/dotfiles/ssh-hosts`, limited to `[A-Za-z0-9._:-]` so a host name cannot inject a tmux `#(...)` command | when you run `ssh` inside tmux | |
| `apt_extract` wrappers (Debian) | `git`, `tmux`, `wl-copy`, `wl-paste` from `~/.local/opt/apt/<pkg>` with `LD_LIBRARY_PATH` set to the unpacked library folders | whenever you run them | child processes inherit `LD_LIBRARY_PATH`, e.g. every tmux pane when tmux came from `apt_extract` |

### The installer

| Step | What runs | Network |
|---|---|---|
| Downloads | `curl`, else `python3`, else `wget`; https only, and curl and python3 also refuse redirects to anything but https (wget cannot, so a wget-only machine may fetch a redirect over plain http); three attempts; every file is checked against `tools.lock` before use | github.com and its download hosts, ftp.nluug.nl |
| Homebrew (Mac) | `brew bundle install --no-upgrade`, no auto-update, no analytics | Homebrew |
| Node servers (Mac, dev tier) | `npm ci --ignore-scripts` (no install scripts run), then `npm audit signatures`; on failure `node_modules` is removed. Only five server commands are linked into `~/.local/bin` | registry.npmjs.org |
| `apt_extract` (Debian) | `apt-get download` and `dpkg-deb -x` (unpack only, no maintainer scripts); unpacked again when apt's candidate version changes (Debian security updates) or a library download failed last time | the configured apt mirrors |
| Parsers | `tree-sitter build` on a verified grammar tarball; a grammar without `src/parser.c` is refused (no `tree-sitter generate`) | none after the download |
| Plugins | `NVIM_BOOTSTRAP=1 nvim --headless`; the committed lockfile is restored if vim.pack rewrote it | github.com |
| Notes trust, verification | headless `nvim` with `NVIM_OFFLINE=1`, so no plugin install can start | none |

## The trust gate

Policy: **silent deny**. Opening a file never prompts and never starts a
language server, gitsigns or editorconfig. They start only inside a
directory you trusted.

- The trust key of a file is the nearest `.git`, `.hg` or `.jj` root of its
  real path (symlinks resolved). Files under `~/notes` use `~/notes`, unless a
  nearer repo sits inside it.
- `:TrustProject` trusts the current file's root. It shows the root and the
  servers that may start there, and asks (default No).
- `:TrustProject {dir}` trusts exactly that folder. Use it for a nested
  root, for example a subproject with its own `.luarc.json`; the enclosing
  repo must be trusted too.
- `:TrustProject!` also accepts roots that match `vim.g.never_trust_globs`,
  `/` or your home directory. Without `!` those are refused. Defaults:
  `~/Downloads/**`, `~/bb/**`, `~/CTF-Lab/**`, `~/targets/**`, `/tmp/**`
  (change them in `nvim/lua/local.lua`).
- `:UntrustProject [dir]` removes the entry, stops the servers under it and
  detaches gitsigns.
- A server whose root differs from the trust key (a nested `.luarc.json`, a
  nested repo) needs its own grant.
- `~/notes` is trusted by `install.sh` for marksman only.
- Trust is stored in Neovim's own database, `~/.local/state/nvim/trust`,
  through `vim.secure`. `nvu` never reads it.
- If `sahin.trust` fails to load, `lsp.lua` enables no server at all.

`:Doctor` shows the trust state of the current folder and the servers it
allows.

### Residual risks of the trust gate

1. **Trust is by folder name.** A different repo cloned later at a trusted
   path inherits the trust. Run `:UntrustProject` before you delete a trusted
   repo. `:UntrustProject` cannot remove an entry for a folder that no longer
   exists (vim.secure needs a real path); delete that line from
   `~/.local/state/nvim/trust` by hand.
2. The trust database is written in place (not atomically) under your
   default umask, and two Neovim instances granting at the same moment can
   lose one entry.
3. The yamlls/jsonls network block has two layers: the `http.proxy` setting
   and `HTTP(S)_PROXY`/`http(s)_proxy` in the server's environment, both
   pointing at `127.0.0.1:9`, plus `handledSchemaProtocols = { 'file' }` for
   jsonls. The yamlls layer is tested with a local listener
   (`tests/trust_spec.lua`); the jsonls layer was checked by reading the
   server's source, because jsonls was not installed on the test machine.
4. Accepted in trusted roots: `.luarc.json` `runtime.plugin` (Lua inside
   lua_ls), a `pyrightconfig.json` that points at a repo interpreter, gopls
   running the local Go toolchain (and downloading modules on the Mac).
5. Repo-local `node_modules/.bin` binaries are never executed: yamlls, jsonls
   and tsc use bare commands from PATH, and tsc's root is found without
   running anything.
6. Only the nine listed servers are gated, and only the ones installed when
   Neovim started. `:lsp enable <name>` starts any other nvim-lspconfig
   server (or one you installed after startup) **without** the gate. Do not
   use `:lsp enable`; restart Neovim after installing a server.
7. Telescope pickers are not gated at all: in a cloned target they list,
   grep and preview its files (as text, with syntax colors). Use `nvu` for
   cloned targets; it has no telescope.

## Download verification

Every file `install.sh` downloads is listed in `tools.lock` with its sha256.
Nothing is unpacked, copied or run before the hash matches, and cached files
are checked again before every use. The `verify` column records how each
pin was established when `scripts/lock-refresh.sh` ran on the Mac:

| verify | Meaning | Rows |
|---|---|---|
| `digest` | GitHub's sha256 digest of the release asset. The vendor publishes no checksum, so GitHub's record is the only reference | nvim (x86_64, aarch64), marksman |
| `checksum` | GitHub digest, and it matches the vendor's own checksum file in the release | ripgrep, fzf, gitleaks, JetBrainsMono Nerd Font |
| `attest` | GitHub digest, and an attestation was verified: `gh attestation verify` (build provenance) or `gh release verify-asset` (immutable release) | fd and tree-sitter (build provenance), yq (immutable release) |
| `tofu` | No upstream checksum. The hash was pinned at first download ("trust on first use") | spell files from ftp.nluug.nl (two mirrors gave the same hash); ts-parser grammar tarballs (GitHub archive of a pinned commit) |
| `git` | A pinned commit, fetched over https and checked out by its sha | tmux-resurrect, tmux-continuum |

Attestations and vendor checksums are checked when the pins are made
(`make lock-check`, `make lock-refresh`, Mac only, needs `gh`), not at install
time. The Debian laptop only compares sha256 values and needs no token.

Other sources:

| Source | How it is pinned or checked |
|---|---|
| This repo | Release tags signed with an SSH key; see [Release tags](#release-tags) below. Commits on `main` are not verified; only tags are. |
| Neovim plugins | Exact commits in `nvim/nvim-pack-lock.json`, fetched with git over https. No signatures. Review updates with `:PackDiff` before you accept them. |
| Homebrew (Mac) | Not pinned by this repo. `--no-upgrade` adds only missing packages, and `install.sh` warns when a version differs from `tools.lock`. |
| npm (Mac) | Exact versions in `tools/npm/package.json`, integrity hashes in `package-lock.json`, `npm ci --ignore-scripts`, `npm audit signatures`. |
| apt_extract (Debian) | apt's signed chain for the running suite (InRelease → Packages → sha256). |
| JSON schemas | Vendored copies; commit, license and sha256 in `nvim/schemas/SOURCES.md`. |
| CI actions | `.github/workflows/ci.yml` pins every action to a full commit SHA, grants only `contents: read`, keeps no git credentials after checkout and uses no secrets. Dependabot proposes new pins once a month, for releases that are at least 7 days old; read the diff before you merge. CI never publishes or signs anything. |

Trust anchors: GitHub (digests, attestations, the repo itself) and your paper
fingerprint, which is the only one that does not depend on GitHub. If you
lose the signing key, every machine needs a fresh clone and the README's
bootstrap steps 3 and 4 with the new fingerprint.

### Release tags

- On a new machine you check the key and the first tag with your own
  `ssh-keygen` and `git`
  ([README, bootstrap step 3](README.md#bootstrap-a-new-machine)). Then
  `install.sh trust-key` pins the key in
  `~/.config/dotfiles/allowed_signers`. `trust-key` is code from the clone,
  so it cannot vouch for that clone; step 3 is the real check.
- Only that file counts. A `gpg.ssh.allowedSignersFile` in your global git
  config is ignored, and OpenPGP and X.509 signatures always fail (their
  verifiers are switched off), so a gpg keyring cannot vouch for a tag.
- The name inside the signed tag must match the tag you asked for, so an
  older release cannot be passed off under a newer name.
- `install.sh` refuses an unsigned, unverified or modified checkout unless
  you pass `--dev`.
- `install.sh update vX.Y.Z` fetches the tag into a scratch ref, verifies
  it, and only then stores it as a tag and checks it out. With `--dry-run`
  it stops after the check.

## Clipboard and OSC 52

OSC 52 lets any program that prints to the terminal set your clipboard. A
line printed by `curl` or `cat` could replace what you paste next. So it is
off at every layer:

- **tmux**: `set-clipboard external` (programs in a pane cannot set the
  clipboard; tmux's own copy mode can) and `allow-passthrough off` (a pane
  cannot wrap OSC 52 to get it past tmux). Tested in
  `tests/terminal/tmux_spec.sh`.
- **iTerm2**: "Applications in terminal may access clipboard" stays off.
  `scripts/doctor.sh` warns when it is on, unless you pass `--osc52`.
- **GNOME Terminal** (VTE) does not support OSC 52 at all.
- **Neovim**: terminal OSC 52 detection is off (`vim.g.termfeatures`). The
  `osc52` provider is used only when `vim.g.osc52 = true` in
  `nvim/lua/local.lua` and you are in an SSH session outside tmux.
  `install.sh --osc52` only prints how to enable it in iTerm2 and changes
  nothing.

Trade-off: yanking in a Neovim on a remote server does not reach the Mac
clipboard. Select the text with the local tmux copy mode instead
(`prefix Enter`, `v`, `y`).

## Secrets in notes

- `~/notes` is a local git repo. Nothing pushes it.
- Its pre-commit hook runs `gitleaks git --pre-commit --staged --redact`. It
  fails closed: without gitleaks nothing can be committed. `core.hooksPath` is
  pinned to the absolute `~/notes/.git/hooks`, so neither a global hook
  manager nor a `git worktree` of `~/notes` can skip it.
  Auto-commit never uses `--no-verify`.
- Pasted tokens, cookies and raw payloads go in `~/notes/.scratch/`. It is in
  `.gitignore`, excluded again by the auto-commit pathspec, and skipped by
  `:Tasks` and the notes pickers.
- A blocked commit shows the redacted gitleaks output as a warning; the file
  is saved but not committed.
- gitleaks knows common token formats. It is a safety net, not a guarantee.
- For this repo: `.pre-commit-config.yaml` runs gitleaks before each commit
  once you run `pre-commit install`, and `make lint` runs `gitleaks dir .`.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting:
<https://github.com/sahinyes/dotfiles/security/advisories/new>

Do not open a public issue for a security problem. Include the release tag,
the machine type (macOS or Debian 12/13) and the steps to reproduce. This is
a personal project: replies are best effort, and fixes go into the next
signed tag. Only the newest tag is supported.
