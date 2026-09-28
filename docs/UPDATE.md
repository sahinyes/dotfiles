# Updating

The Mac is where changes are made, reviewed, tested and released as a
signed tag. The Debian laptop only installs signed tags. Nothing updates on
its own: plugins, tools and servers move only when you change a pinned
version and commit it.

Text after `#` in the command blocks is a comment. zsh on the Mac accepts
it only with `setopt interactivecomments`; otherwise leave it out when you
paste.

| What | Pinned in | Update with |
|---|---|---|
| Neovim plugins | `nvim/nvim-pack-lock.json` (+ `nvim/lua/sahin/plugins/specs.lua`) | `<leader>uu`, `<leader>ud`, `:write` |
| Pinned downloads: Neovim, rg, fd, fzf, marksman, yq, gitleaks, tree-sitter and the font (Debian); spell files, parser sources and tmux plugins (both machines) | `tools.lock` | edit the row, `make lock-refresh` |
| Mac tools | nothing (Homebrew) | `brew upgrade <formula>`; `install.sh` warns about drift from `tools.lock` |
| Node language servers (Mac) | `tools/npm/package.json` + `package-lock.json` | `npm install --package-lock-only` |
| JSON schemas for yamlls | `nvim/schemas/` | see `nvim/schemas/SOURCES.md` |
| This repo on the laptop | a signed tag | `install.sh update vX.Y.Z` |
| GitHub Actions used by CI | commit SHAs in `.github/workflows/ci.yml` | Dependabot pull request (monthly); read the diff and the action's release notes, then merge |

## Plugins (monthly, on the Mac)

1. Start from a clean checkout of `main`:

   ```sh
   cd ~/dotfiles && git status
   ```

2. In Neovim, press `<leader>uu`. vim.pack fetches and opens a review tab.
   The `# Update` section lists each plugin with an update, its
   `Revision before:` and `Revision after:` and the new commits. Move between
   plugins with `öö`/`ää`; `gO` lists them.
3. Press `<leader>ud` (`:PackDiff`). A split opens with one summary line per
   plugin (`N risky token(s) in added lines`) and the `git diff` of each
   plugin, limited to the folders Neovim runs code from (`lua`, `plugin`,
   `ftplugin`, `ftdetect`, `after`, `autoload`, `lsp`, `syntax`, `indent`,
   `colors`, `compiler`, `parser`). These words are highlighted:
   `vim.system`, `io.popen`, `os.execute`, `vim.fn.system`, `jobstart`,
   `termopen`, `uv.spawn`, `loop.spawn`, `vim.net`, `loadstring`, `dofile`,
   `curl`, `wget`, `http`. Read every highlighted line in added code. Look hard at gitsigns:
   this config wraps one of its internal functions (see
   [SECURITY.md](../SECURITY.md)).
4. Accept with `:write` in the review buffer. To decline, `:quit` it instead.
5. Restart Neovim: `ZR`.
6. Test and review (`~/.config/nvim-test` is a link to `~/dotfiles/nvim`, see
   the README):

   ```sh
   make test NVIM_APPNAME=nvim-test
   make lint
   git diff nvim/nvim-pack-lock.json
   ```

7. Commit the lockfile and release a tag (below).
8. On the laptop: `~/dotfiles/install.sh update vX.Y.Z`.

Notes:

- Plugins with a version range (`2.*`, `0.2.*`, `8.*`, `stable`) move inside
  that range. plenary.nvim and nvim-treesitter have no tags and are frozen to
  a commit in `specs.lua`; they move only when you edit that sha.
  precognition.nvim is pinned to the tag `v1.3.0`.
- After you bump nvim-treesitter, run `make lock-refresh` too: the parser
  rows in `tools.lock` are derived from its `parsers.lua`.
- To remove a plugin: delete its line in `specs.lua`, restart, `:PackSync`
  (it deletes plugins that are no longer listed), test, commit.
- `<leader>uu`, `<leader>ud` and `<leader>ul` do not exist in `nvu`.

## Roll back a plugin update

On the Mac, go back to the lockfile before the update:

```sh
cd ~/dotfiles
git checkout HEAD~1 -- nvim/nvim-pack-lock.json   # or the commit before the update
```

Then in Neovim: `ZR`, `<leader>ul` (realign to the lockfile, offline),
`:write` in the review buffer. Test, commit, tag. The offline realign works
only for revisions that are already on disk; otherwise use `:PackSync`
(online).

On the laptop, install the previous tag:

```sh
~/dotfiles/install.sh update v<previous>
```

## Tools (`tools.lock`)

`scripts/lock-refresh.sh` re-derives every pin from its source. It runs on
the Mac, needs `gh` logged in (`gh auth login`), and takes a few minutes
(the spell mirror is slow).

Check that the pins still match upstream (changes nothing):

```sh
make lock-check          # scripts/lock-refresh.sh --check; exit 1 if anything differs
```

It also prints `newer release ...` for tools with a newer version. It never
bumps a version on its own.

Bump a tool:

1. Edit its rows in `tools.lock` by hand: the version and the URL, for both
   `x86_64` and `aarch64`.
2. Re-derive the hashes and the `verify` column:

   ```sh
   make lock-refresh        # scripts/lock-refresh.sh
   git diff tools.lock
   ```

   A changed hash for a spell file is flagged loudly. Find out why before you
   accept it.
3. Commit, release a tag, and run the installer on each machine. On Linux
   the new version goes to a new `~/.local/opt/<name>-<version>/`; the old
   folder stays.

Roll back a tool: revert the `tools.lock` change (`git revert <commit>`),
release, run the installer. The link in `~/.local/bin` points back to the
old folder, which is still on disk.

On the Mac, Homebrew provides these tools, not `tools.lock`. `install.sh`
never upgrades Homebrew packages (`--no-upgrade`); upgrade them yourself
when you want, and read the drift warning in the report.

## Node language servers (Mac)

```sh
cd ~/dotfiles/tools/npm
# edit package.json: exact versions only, no ^ or ~
npm install --package-lock-only --ignore-scripts
npm audit --audit-level=high
git diff package.json package-lock.json
```

Fix every high or critical finding before you continue. Then commit both
files. The next `install.sh` run on the Mac sees the new
`package-lock.json` and runs `npm ci --ignore-scripts` and
`npm audit signatures`; if the signature check fails it deletes
`node_modules` and reports `FAIL`.

## Release a signed tag (Mac)

### One-time setup

The tags are signed with the Mac's SSH key, the same key as
`signing_key.pub` in the repo. Check that they match:

```sh
cd ~/dotfiles
ssh-keygen -lf signing_key.pub
ssh-keygen -lf ~/.ssh/id_ed25519.pub
```

Tell git to sign with SSH in this repo only:

```sh
git config --local gpg.format ssh
git config --local user.signingkey "$HOME/.ssh/id_ed25519"
```

Let git verify tags here too. `trust-key` writes
`~/.config/dotfiles/allowed_signers` and sets `gpg.ssh.allowedSignersFile`
for this repo. If HEAD is not a tag it ends with
`key pinned, but HEAD is not a tag, so nothing was verified`; the key is
pinned anyway.

```sh
./install.sh trust-key SHA256:<your fingerprint>
```

On GitHub (repository settings), turn on private vulnerability reporting,
which [SECURITY.md](../SECURITY.md) points to. If you also publish GitHub
releases for the tags, turn on immutable releases so a published release
cannot be changed.

### Each release

```sh
cd ~/dotfiles
git status                      # clean, on main
make test NVIM_APPNAME=nvim-test
make lint
git push origin main
git tag -s vX.Y.Z -m vX.Y.Z     # asks for the key's passphrase, if it has one
git verify-tag vX.Y.Z           # must say: Good "git" signature for dotfiles-release
git push origin vX.Y.Z
```

- Pick the next version: the last number for plugin/tool bumps and fixes,
  the middle one for new features.
- Never move or delete a pushed tag. Make a new one.
- `git tag -l` lists the tags you have.

Right after tagging, HEAD on the Mac is the tag, so `./install.sh` runs
without `--dev`. After the next commit it needs `--dev` again.

## Update the laptop

```sh
~/dotfiles/install.sh update vX.Y.Z
```

It:

1. checks the tag name (`vX.Y.Z`) and that a signing key is pinned in
   `~/.config/dotfiles/allowed_signers`;
2. refuses when the checkout has local changes;
3. fetches only that tag, into a scratch ref instead of your tags (shallow
   clones stay shallow);
4. verifies it: the signature must come from the pinned SSH key, and the
   name inside the signed tag must be `vX.Y.Z`. If not, it deletes the
   scratch ref and stops; nothing has changed;
5. stores it as the tag `vX.Y.Z`. If a local tag of that name already points
   somewhere else, it stops instead of overwriting it;
6. checks the tag out (detached HEAD) and runs that tag's `install.sh` with
   the flags you gave, for example `update vX.Y.Z --no-fonts`.

To look first without changing anything:

```sh
~/dotfiles/install.sh update vX.Y.Z --dry-run
```

It fetches and verifies the tag, prints its commit and how much differs from
your checkout, and checks nothing out.

The plugins step then realigns every plugin to the new lockfile and deletes
plugins that are no longer listed. Never run `git pull` on the laptop: HEAD
is a detached tag, and commits on `main` are not signed.

If you ever lose the signing key: make a new key, commit its public key as
`signing_key.pub`, sign a new tag with it, and on every machine make a fresh
clone of that tag and repeat steps 3 and 4 of the README bootstrap with the
new fingerprint.

## Neovim 0.13

Stay on 0.12.x until the config has been checked against 0.13.

- The Mac gets Neovim from Homebrew, which does not pin versions. A plain
  `brew upgrade` would install 0.13. Prevent it with `brew pin neovim`.
- `install.sh` reports `FAIL` when Neovim is not 0.12.x (`NVIM_WANT` in
  `lib/nvim.sh`), and `scripts/doctor.sh` warns.
- Known changes to check: `Q` becomes a multicursor key (`swiss.lua` already
  maps `Q` back to "replay last macro" on 0.13), new built-in `al`/`il`
  text objects (mini.ai overrides them), netrw changes, and a lockfile option
  for vim.pack.

When you move:

1. In 0.13, read `:help news` from top to bottom.
2. Bump the two `nvim` rows in `tools.lock` (version and URL), then
   `make lock-refresh`.
3. Update `NVIM_WANT` in `lib/nvim.sh` and the version check in
   `scripts/doctor.sh`.
4. `brew unpin neovim && brew upgrade neovim` on the Mac.
5. Run every test suite (`make test NVIM_APPNAME=nvim-test`, `make test-mac`,
   `make test-install`), fix, commit, release.
