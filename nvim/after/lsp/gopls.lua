-- Go. go.mod may name a toolchain or dependencies to download; keep gopls
-- on the installed toolchain and never let it rewrite go.mod/go.sum.
local env = { GOTOOLCHAIN = 'local', GOFLAGS = '-mod=readonly' }
if vim.g.work_laptop then env.GOPROXY = 'off' end -- no module downloads at work

return {
  cmd = { 'gopls' },
  cmd_env = env,
  -- nvim-lspconfig's root_dir runs `go env` in the current directory, which
  -- may be a hostile clone; plain markers do the same job without a process.
  root_dir = function(bufnr, on_dir) on_dir(vim.fs.root(bufnr, { 'go.work', 'go.mod', '.git' })) end,
}
