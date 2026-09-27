-- TypeScript 7 native server (`tsc --lsp`). nvim-lspconfig's version runs
-- node_modules/.bin/tsc --version from the project to pick a binary; this
-- one only uses the tsc on PATH and never executes anything to find a root.
return {
  cmd = { 'tsc', '--lsp', '--stdio' },
  root_dir = function(bufnr, on_dir)
    local lockfiles = { 'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml', 'bun.lockb', 'bun.lock' }
    on_dir(vim.fs.root(bufnr, { lockfiles, '.git' }))
  end,
}
