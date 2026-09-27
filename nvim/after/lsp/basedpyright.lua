-- Python types. The interpreter is the python3 found on PATH when Neovim
-- starts, so the server does not go looking for a repo's own interpreter.
local python = vim.fn.exepath('python3')

return {
  cmd = { 'basedpyright-langserver', '--stdio' },
  settings = {
    python = { pythonPath = python ~= '' and python or nil },
  },
}
