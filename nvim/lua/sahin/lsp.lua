-- Language servers. Definitions come from nvim-lspconfig (lsp/<name>.lua);
-- our overrides (bare PATH cmd, no network, no repo-local binaries) live in
-- after/lsp/<name>.lua. Every server is gated by sahin.trust. Completion is
-- set up in completion.lua.
local M = {}

M.servers = { 'marksman', 'lua_ls', 'yamlls', 'jsonls', 'bashls', 'basedpyright', 'ruff', 'gopls', 'tsc' }

-- A server is used only when its binary is on PATH and its definition is
-- complete (filetypes come from nvim-lspconfig; without them a server would
-- attach to every buffer).
local function installed()
  local names = {}
  for _, name in ipairs(M.servers) do
    local ok, cfg = pcall(function() return vim.lsp.config[name] end)
    local cmd = ok and cfg and cfg.cmd
    if type(cmd) == 'table' and vim.fn.executable(cmd[1]) == 1 and type(cfg.filetypes) == 'table' then
      names[#names + 1] = name
    end
  end
  return names
end

-- Fail closed: without a working trust gate no server is enabled.
M.enabled = {}
local ok_trust, trust = pcall(require, 'sahin.trust')
if ok_trust and type(trust) == 'table' and type(trust.setup) == 'function' then
  M.enabled = trust.setup(installed()) or {}
  if #M.enabled > 0 then vim.lsp.enable(M.enabled) end
else
  require('sahin.util').warn('sahin.trust did not load: LSP is off')
end

local function definitions()
  local ok, builtin = pcall(require, 'telescope.builtin')
  if not (ok and pcall(builtin.lsp_definitions)) then vim.lsp.buf.definition() end
end

-- Default LSP maps (grn gra grr gri grt gO K) are left as they are.
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('sahin.lsp', { clear = true }),
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    -- basedpyright answers K; ruff's hover would only duplicate it.
    if client and client.name == 'ruff' then client.server_capabilities.hoverProvider = false end
    vim.keymap.set('n', 'grd', definitions, { buffer = ev.buf, desc = 'Goto definition (telescope)' })
    -- Buffer-local maps added after mini.clue's triggers need a refresh.
    local clue = rawget(_G, 'MiniClue')
    if clue then clue.ensure_buf_triggers(ev.buf) end
  end,
})

return M
