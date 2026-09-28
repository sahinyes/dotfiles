# dotfiles

A Neovim 0.12 setup for Markdown task notes and for reading logs, JSON and
HTTP payloads during bug bounty work, plus the tmux and terminal settings
around it. It runs on a MacBook (iTerm2, tmux) and on a Debian 12/13 work
laptop without sudo (GNOME Terminal). Both machines use a Swiss German
keyboard, so the key maps avoid Alt, Ctrl+Shift and bracket chords. One
script, `install.sh`, installs everything from pinned, sha256-checked
downloads, and by default it runs only from a git tag signed with an SSH
key. Language servers and git integration stay off in a project until you
trust it.

This is a personal setup. It is public so the laptop can clone it. Read
[SECURITY.md](SECURITY.md) before you use it on material you do not trust.

## What you get on each machine

| | MacBook | Debian work laptop |
|---|---|---|
| Neovim | Homebrew `neovim` (0.12.x; Homebrew does not pin, `install.sh` warns when it drifts from `tools.lock`) | Official 0.12.5 release tarball, sha256-checked, in `~/.local/opt/nvim-v0.12.5` |
| Search and CLI tools | Homebrew: ripgrep, fd, fzf, marksman, yq, gitleaks, tree-sitter-cli, tmux, ncurses | `tools.lock`: rg, fd, fzf, marksman, yq, gitleaks in `~/.local/opt`, linked into `~/.local/bin` |
| Dev tools | shellcheck, shfmt, stylua, lua-language-server, ruff, go, gopls, node, pre-commit | none (notes tier only) |
| Language servers | marksman, lua_ls, yamlls, jsonls, bashls, basedpyright, ruff, gopls, tsc (Node ones from `tools/npm`) | marksman only |
| Extra treesitter parsers | yaml, json, bash, python, go, typescript, http, diff (built locally) | Same list on Debian 13 with a C compiler. Debian 12 (glibc 2.36) or no compiler: none, regex syntax instead |
| git, tmux, wl-clipboard | system / Homebrew | system packages if present, else unpacked from Debian packages without root (`apt_extract`) |
| Font | JetBrainsMono Nerd Font (Homebrew cask) | Same font in `~/.local/share/fonts` |
| Terminal | Undercurl fix for tmux (`scripts/terminfo-mac.sh`); iTerm2 settings are only checked, never written | GNOME Terminal profile: font, block cursor, no bell, unlimited scrollback, Catppuccin colors, F10 off |
| Clipboard | pbcopy | wl-copy (Wayland) or xclip (X11, not installed by the script) |
| Work-laptop mark | off | on: tmux does not save pane text to disk; `vim.g.work_laptop = true` |

Both machines share the same Neovim config, the same 8 plugins at the same
revisions (`nvim/nvim-pack-lock.json`), the notes workflow in `~/notes`, the
inspect commands and `tmux.conf`.

## Bootstrap a new machine

There is no `curl | bash`. You clone a signed tag, check its signature
against a fingerprint you carry yourself, read the script, then run it.

Text after `#` in the command blocks of these docs is a comment. bash
ignores it. zsh (the macOS default) ignores it only with
`setopt interactivecomments`; otherwise leave the comment out when you
paste a line.

**1. Get the fingerprint of the signing key, on the Mac.** The release tags
are signed with the Mac's SSH key.

```sh
ssh-keygen -lf ~/.ssh/id_ed25519.pub
```

Write the `SHA256:...` part on paper or keep it on your phone.

This README does not print the fingerprint on purpose. The README comes
from the same place as the code. Anyone who can change the code (a taken-over
account, a fake mirror, a changed download) can change the README too, so a
fingerprint printed here would prove nothing. A copy that travels on paper
or on your phone is the one check that does not depend on GitHub.

**2. Clone a release tag on the new machine.** Replace `vX.Y.Z` with the
newest tag.

```sh
git clone --depth 1 --branch vX.Y.Z https://github.com/sahinyes/dotfiles ~/dotfiles
```

**3. Check the key and the tag with your own tools.** Nothing from the
clone runs in this step, only your system's `ssh-keygen` and `git`.

```sh
cd ~/dotfiles
ssh-keygen -lf signing_key.pub
f=$(mktemp)
printf 'dotfiles-release namespaces="git" %s\n' "$(cut -d ' ' -f 1,2 signing_key.pub)" >"$f"
git -c gpg.ssh.allowedSignersFile="$f" -c gpg.openpgp.program=false \
  -c gpg.x509.program=false verify-tag vX.Y.Z
git for-each-ref --format='%(tag)' refs/tags/vX.Y.Z
rm -f "$f"
```

Go on only if all three hold:

- `ssh-keygen` shows the `SHA256:...` fingerprint from your paper;
- `verify-tag` prints `Good "git" signature for dotfiles-release`. A line
  without `for dotfiles-release`, followed by `No principal matched.`, means
  another key signed the tag. `cannot verify a non-tag object` means the tag
  is not signed at all;
- `for-each-ref` prints the tag name you cloned. Another name means an
  older signed release was republished under a new name.

If one fails, stop and delete the clone.

**4. Pin the key.**

```sh
~/dotfiles/install.sh trust-key SHA256:<fingerprint from your paper>
```

This is the first code from the clone that runs. It cannot vouch for the
clone it came in; that is what step 3 was for. It prints the fingerprint of
`signing_key.pub` next to the one you typed and stops if they differ. If
they match, it writes `~/.config/dotfiles/allowed_signers`, points this
clone's git config at it (`gpg.ssh.allowedSignersFile`) and verifies the tag
again. From then on `install.sh` runs only from a clean checkout of a
verified tag, and `install.sh update` only installs tags that verify with
this key.

**5. Read the script.**

```sh
less ~/dotfiles/install.sh ~/dotfiles/lib/*.sh
```

**6. Dry run.** It prints what it detected (OS, glibc, network, tools,
fonts, compiler, work mark) and the plan. It changes nothing.

```sh
~/dotfiles/install.sh --dry-run
```

**7. Install.** `--shell-rc` adds one line to `~/.zshrc` or `~/.bashrc` so
new shells put `~/.local/bin` first on PATH and get the `nvu`/`nvr0`
aliases (`$ZDOTDIR/.zshrc` when you set `ZDOTDIR`). Leave it out if you
want to add that line yourself
(`source ~/dotfiles/shell/env.sh`).

```sh
~/dotfiles/install.sh --shell-rc
```

Open a new terminal, start `nvim` and run `:Doctor`.

What you need first:

- macOS: Homebrew, and the Command Line Tools (`xcode-select --install`) for
  the parser builds.
- Debian: `git` (for the clone and the signature check), `ssh-keygen`
  (package `openssh-client`), one of `curl`/`wget`/`python3`, `tar`, `xz` and
  `gzip`. `apt-get` and `dpkg-deb` are used to unpack missing packages
  without root. Access to `https://github.com/`.

Other flags (`./install.sh --help`):

| Flag | Meaning |
|---|---|
| `--dry-run` | show detection and plan, change nothing |
| `--dev` | allow an unsigned or modified checkout (development, tests) |
| `--tier notes\|dev` | default `dev` on macOS, `notes` on Linux (Linux supports `notes` only) |
| `--no-fonts` | skip the Nerd Font |
| `--no-terminal` | skip terminfo / GNOME Terminal setup |
| `--work` / `--no-work` | set or remove the work-laptop mark (default: on for Linux, off for macOS) |
| `--shell-rc` | add the `shell/env.sh` line to your shell rc file |
| `--osc52` | print how to allow OSC 52 in iTerm2; changes nothing |

On the Mac, the clone in `~/dotfiles` is also where you develop. Once HEAD
has moved past a tag, run `./install.sh --dev` there, and read the `--dev`
warning in the report as expected.

## What the installer changes

Every step checks first and changes only what differs. A second run prints
`changes: 0`. It never uses sudo, never runs a download before its sha256
matches `tools.lock`, and never overwrites a file without moving the old one
to the backup first.

| Step | Where |
|---|---|
| Symlinks | `~/.config/nvim` and `~/.config/nvim-untrusted` → `~/dotfiles/nvim`; `~/.tmux.conf` → `tmux/tmux.conf`; `~/.tmux/scripts` → `tmux/scripts` |
| Homebrew (Mac) | `brew bundle install --no-upgrade` with the `Brewfile` (no auto-update, no upgrades) |
| Neovim and tools (Linux) | `~/.local/opt/<name>-<version>/`, linked into `~/.local/bin` |
| apt_extract (Linux) | git, tmux, wl-clipboard when missing: `~/.local/opt/apt/<package>/` plus wrapper scripts in `~/.local/bin` |
| Font | `~/.local/share/fonts/JetBrainsMonoNerdFont-v3.5.1/` (Linux), Homebrew cask (Mac) |
| Spell files | `~/.local/share/nvim/site/spell/` (German, English suggestions, Turkish) |
| Treesitter parsers | `~/.local/share/nvim/site/parser/*.so`, when a compiler and the tree-sitter CLI can be used |
| Terminal | Mac: `~/.terminfo` (tmux-256color with undercurl). Linux: GNOME Terminal profile via `dconf`/`gsettings` |
| tmux plugins | tmux-resurrect and tmux-continuum at pinned commits in `~/.tmux/plugins/`; `~/.local/share/tmux/resurrect` mode 0700 |
| Work mark | `~/.config/dotfiles/work` (created with `--work`, removed with `--no-work`) |
| `nvim/lua/local.lua` | written once if missing (gitignored); your edits are never overwritten |
| Notes | `~/notes`: `git init`, gitleaks pre-commit hook, `core.hooksPath`, a local placeholder git identity if you have none, `.scratch/` in `.gitignore`, `inbox.md`, trust entry (marksman only) |
| Plugins | `~/.local/share/nvim/site/pack/core/opt/`, synced to the lockfile only when something differs |
| Node servers (Mac, dev tier) | `tools/npm/node_modules` (`npm ci --ignore-scripts`, `npm audit signatures`), five commands linked into `~/.local/bin` |
| Shell rc (only with `--shell-rc`) | one line marked `# added by dotfiles install.sh`; a copy of the old rc file goes to the backup |
| Download cache | `~/.cache/dotfiles/` (re-checked before every use) |

**Backups.** Anything in the way is moved (never deleted) to
`~/.dotfiles-backup/<YYYYMMDD-HHMMSS>/`, mode 0700, under the same path it had
in your home directory. On the first run on the Mac this includes the old
`~/.config/nvim`, `~/.tmux.conf`, `~/.tmux/tmux.conf` and `~/.tmux/scripts`.
The GNOME Terminal script saves `dconf dump /org/gnome/terminal/` to its own
`~/.dotfiles-backup/<timestamp>/gnome-terminal.dconf`.

**The report.** The end of every run prints one line per step and saves it to
`~/.local/state/dotfiles/last-install.txt`:

```text
== dotfiles: v1.0.0 (signature verified) | linux trixie x86_64 | tier notes | 2026-09-27 21:00 ==
OK    nvim        0.12.5 ~/.local/bin/nvim (release tarball, sha256 OK)
OFF   treesitter  no C compiler (cc) -> bundled parsers only (markdown works; yaml/json use legacy syntax)
WARN  shell       new shells do not put ~/.local/bin first on PATH: re-run with --shell-rc (or source shell/env.sh yourself)
changes: 0 (nothing to do, everything was already in place)
result: OK. Next: open a new shell, run nvim, and :Doctor for the editor side
```

The status is one of `OK`, `SKIP`, `OFF`, `WARN`, `FAIL`, and every line says
the real reason. The script exits non-zero when any line is `FAIL`. Fix the
reason and run it again; that is always safe. The lines above are an
example, not output from a real machine.

## Daily use

```text
<Space>nd / <Space>nc      today's daily note / capture a task into inbox.md
<CR> on a task line         cycle  [ ] -> [!] -> [x] -> [ ]
<Space>no / <Space>ni      open / important tasks from ~/notes and TODO.md -> quickfix
<Space>nn / <Space>ng      find a note / grep the notes
<Space>ij <Space>ib <Space>iw   pretty-print JSON / base64-decode / decode a JWT
nvu <path>  /  nvr0 <file>  open target material without plugins, LSP or notes
:TrustProject               in your own repo: turn on LSP, gitsigns and editorconfig
:Doctor                     what this machine and profile really have
<Space> (wait)              key hints for everything under the leader key
ö / ä                       [ and ] on the Swiss keyboard (öd = [d, ää = ]])
```

More: [docs/KEYMAP.md](docs/KEYMAP.md) for every key,
[docs/NOTES-CONVENTION.md](docs/NOTES-CONVENTION.md) for the notes format,
[docs/LEARN-30-DAYS.md](docs/LEARN-30-DAYS.md) if you are new to Vim.

Terminal side: `~/dotfiles/scripts/doctor.sh` checks the terminal (TERM,
undercurl, clipboard tool, font, iTerm2 key and clipboard settings, the
GNOME Terminal profile) and prints a fix for every `WARN`. It only reads.

To color the tmux status bar per SSH host, source
`~/.tmux/scripts/ssh-colors.sh` in your shell rc and list your hosts in
`~/.config/dotfiles/ssh-hosts` (one `host-or-glob label` per line; the labels
`dev`, `prod`, `gpu`, `oob` and `mac` have their own colors). Host names stay
out of this public repo.

## Updating

- Laptop: `~/dotfiles/install.sh update vX.Y.Z` fetches the tag, verifies its
  signature, checks it out and runs its `install.sh`. Plugins then follow the
  new lockfile. Never `git pull` there. With `--dry-run` it only fetches and
  verifies the tag and checks nothing out.
- Mac (maintainer): plugin updates, `tools.lock` refreshes, Node servers and
  the signed release are in [docs/UPDATE.md](docs/UPDATE.md).

## Uninstall or roll back

Your notes in `~/notes` are yours; nothing below touches them.

```sh
# 1. What was backed up, and when
ls -la ~/.dotfiles-backup/

# 2. Remove the links (no trailing slash: this removes the link, not the repo)
rm ~/.config/nvim ~/.config/nvim-untrusted ~/.tmux.conf ~/.tmux/scripts

# 3. Put the old files back (use your own timestamp; skip the ones that are not there)
b=~/.dotfiles-backup/20260927-210000
mv "$b/.config/nvim" ~/.config/nvim
mv "$b/.tmux/tmux.conf" ~/.tmux/tmux.conf
mv "$b/.tmux/scripts" ~/.tmux/scripts
mv "$b/.tmux.conf" ~/.tmux.conf    # only if it was there before
```

4. Remove the line that ends with `# added by dotfiles install.sh` from
   `~/.zshrc` or `~/.bashrc` (or restore the copy in the backup).
5. GNOME Terminal (Linux): the backup script printed its own undo command:

   ```sh
   dconf reset -f /org/gnome/terminal/ && dconf load /org/gnome/terminal/ < ~/.dotfiles-backup/<timestamp>/gnome-terminal.dconf
   ```

6. Optional clean-up of what the installer added: the links and wrappers it
   made in `~/.local/bin`, `~/.local/opt/<tool>-<version>` and
   `~/.local/opt/apt`, `~/.local/share/fonts/JetBrainsMonoNerdFont-*`,
   `~/.local/share/nvim/site/{pack,parser,spell}`, `~/.tmux/plugins/tmux-resurrect`
   and `tmux-continuum`, `~/.config/dotfiles`, `~/.local/state/dotfiles`,
   `~/.cache/dotfiles`, and on the Mac `~/.terminfo/74/tmux-256color`. Homebrew
   packages stay until you `brew uninstall` them.

To go back to an older release instead, run
`~/dotfiles/install.sh update v<older tag>`.

## Repo layout

```text
dotfiles/
├── install.sh              the installer; read it first
├── lib/                    installer steps, one file per topic
├── tools.lock              every download, pinned by sha256
├── Brewfile                Mac packages
├── Makefile                make help: tests, lint, lock-check, lock-refresh
├── signing_key.pub         public key that signs release tags
├── shell/env.sh            PATH (~/.local/bin first), nvu and nvr0 aliases
├── nvim/                   Neovim config (~/.config/nvim and ~/.config/nvim-untrusted)
│   ├── init.lua            load order; security first
│   ├── nvim-pack-lock.json plugin revisions
│   ├── lua/sahin/          options, swiss, keymaps, trust, lsp, notes/, plugins/, ...
│   ├── lua/local.lua.example  machine-local settings (copy to lua/local.lua)
│   ├── after/lsp/          language server overrides (no network, no repo binaries)
│   ├── after/ftplugin/markdown.lua
│   ├── schemas/            vendored JSON schemas for yamlls
│   └── spell/en.utf-8.add  shared word list (public)
├── tmux/                   tmux.conf and status-bar scripts
├── terminal/               GNOME Terminal settings
├── scripts/                doctor.sh, terminfo-mac.sh, gnome-terminal.sh,
│                           lock-refresh.sh, migrate-notes.py
├── tools/npm/              Node language servers for the Mac (exact versions)
├── tests/                  Neovim, Python, shell and install tests
├── docs/                   the guides linked below
├── .github/                CI workflow and Dependabot (action pins only)
├── README.md
└── SECURITY.md
```

Development checks (Mac):

```sh
ln -s ~/dotfiles/nvim ~/.config/nvim-test   # once: a test profile with its own state
NVIM_APPNAME=nvim-test NVIM_BOOTSTRAP=1 nvim --headless +qa   # once: its plugins (then git status: lockfile unchanged)
make test NVIM_APPNAME=nvim-test           # Lua suites, migration tests, tmux/doctor tests
make lint                                  # stylua, shellcheck, shfmt, bash 3.2, ruff, gitleaks
pre-commit install                         # once per clone: gitleaks before every commit
```

The Lua suites load the real config. With `NVIM_APPNAME=nvim-test` they use
`~/.local/state/nvim-test` and friends instead of your everyday profile;
without it they use `~/.config/nvim`.

`make test-install` (Debian containers, needs docker, slow), `make test-mac`
and `make test-release` test the installer.

CI (`.github/workflows/ci.yml`) runs on every push to `main` and every pull
request: `make lint` on macOS (its `/bin/bash` is 3.2),
`install.sh --dev --tier notes` and `make test` on Ubuntu, the terminal
specs on macOS, the release-flow test with throwaway keys, the GNOME
Terminal script in a Debian 13 container, and a check that every Linux
download in `tools.lock` still matches its sha256. The Debian install
containers run only on pushes and manual runs, not on pull requests. No job
uses a secret, and every action is pinned to a commit SHA; Dependabot
proposes new pins once a month (`.github/dependabot.yml`). `make test-mac`
is not in CI.

## Documentation

| File | What it covers |
|---|---|
| [SECURITY.md](SECURITY.md) | Threat model, what runs when, the trust gate, download checks, reporting |
| [docs/KEYMAP.md](docs/KEYMAP.md) | Every key map, the Swiss German layer, forbidden chords, tmux keys |
| [docs/NOTES-CONVENTION.md](docs/NOTES-CONVENTION.md) | Notes format, commands, auto-commit, agent contract, migration |
| [docs/LEARN-30-DAYS.md](docs/LEARN-30-DAYS.md) | A 30-day plan, 15-20 minutes a day |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Symptom, cause, fix; where the logs are |
| [docs/UPDATE.md](docs/UPDATE.md) | Plugin and tool updates, rollback, releases |
