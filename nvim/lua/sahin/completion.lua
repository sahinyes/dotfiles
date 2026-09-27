-- Built-in completion (Neovim 0.12, no plugin). 'autocomplete' opens a menu
-- while typing: LSP items (through omnifunc, "o") plus words from buffers.
-- Keys: <C-n>/<C-p> move, <C-y> accept, <C-e> close, <C-Space> ask the LSP
-- server. Tab and Enter are not mapped: they keep inserting a tab/newline.
local group = vim.api.nvim_create_augroup('sahin.completion', { clear = true })

vim.o.autocomplete = true
vim.o.complete = 'o^10,.^5,w^5,b^5' -- "o" is skipped silently when no LSP is attached
vim.o.completeopt = 'menuone,noselect,fuzzy,popup'

-- Prose: no popup while writing notes and commit messages (<leader>tc toggles).
vim.api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = { 'markdown', 'gitcommit' },
  callback = function(ev) vim.bo[ev.buf].autocomplete = false end,
})

--- Effective 'autocomplete' of a buffer (the local value reads nil until set).
local function autocomplete_on(buf)
  local value = vim.bo[buf].autocomplete
  if value == nil then return vim.go.autocomplete end
  return value
end

vim.api.nvim_create_autocmd('LspAttach', {
  group = group,
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not (client and client:supports_method('textDocument/completion')) then return end
    -- enable(): <C-y> applies snippets/auto-imports, <C-Space> reaches this
    -- client. autotrigger re-asks the server on its trigger characters and for
    -- incomplete lists; next to 'autocomplete' it adds no second request
    -- (one per trigger character, tests/plugins_spec.lua). Prose stays manual.
    vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = autocomplete_on(ev.buf) })
  end,
})

vim.keymap.set('i', '<C-Space>', function()
  if #vim.lsp.get_clients({ bufnr = 0, method = 'textDocument/completion' }) > 0 then
    vim.lsp.completion.get()
  else
    vim.api.nvim_feedkeys(vim.keycode('<C-x><C-o>'), 'n', false)
  end
end, { desc = 'Complete: ask the LSP server (else omni completion)' })

return {}
