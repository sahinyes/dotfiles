-- Core keymaps (no plugins). Plugin/notes/inspect maps live in their modules.
-- Contract (docs/KEYMAP.md): no Alt/Meta, no Ctrl+Shift, no <C-a>, every map has desc.
local map = require('sahin.util').map

map('n', '<Esc>', '<Cmd>nohlsearch<CR>', 'Clear search highlight')
map('n', '<leader>e', '<Cmd>Explore<CR>', 'File explorer (netrw)')

-- Quickfix / location list / diagnostics
map('n', '<leader>xq', '<Cmd>botright copen<CR>', 'Quickfix: open')
map('n', '<leader>xc', '<Cmd>cclose<CR>', 'Quickfix: close')
map('n', '<leader>xl', '<Cmd>lopen<CR>', 'Location list: open')
map('n', '<leader>xd', function() vim.diagnostic.setqflist() end, 'Diagnostics: all to quickfix')
map('n', '<leader>q', function() vim.diagnostic.setloclist() end, 'Diagnostics: buffer to location list')

-- System clipboard (explicit; see clipboard.lua for the provider)
map({ 'n', 'x' }, '<leader>y', '"+y', 'Yank to system clipboard')
map({ 'n', 'x' }, '<leader>p', '"+p', 'Paste from system clipboard')

-- Code
map({ 'n', 'x' }, '<leader>cf', function()
  local clients = vim.lsp.get_clients({ bufnr = 0, method = 'textDocument/formatting' })
  if #clients > 0 then
    vim.lsp.buf.format({ async = false })
  elseif vim.bo.formatprg ~= '' or vim.o.formatprg ~= '' then
    vim.cmd('normal! mzgggqG`z')
  else
    vim.notify('No LSP formatter or formatprg for this buffer', vim.log.levels.INFO)
  end
end, 'Code: format buffer')

-- Toggles
local function toggle(option, label)
  return function()
    vim.opt_local[option] = not vim.opt_local[option]:get()
    vim.notify(('%s %s'):format(label, vim.opt_local[option]:get() and 'on' or 'off'))
  end
end
map('n', '<leader>tw', toggle('wrap', 'wrap'), 'Toggle: line wrap')
map('n', '<leader>ts', toggle('spell', 'spell'), 'Toggle: spell check')
map('n', '<leader>tn', toggle('relativenumber', 'relativenumber'), 'Toggle: relative numbers')
map('n', '<leader>tc', function()
  vim.bo.autocomplete = not vim.bo.autocomplete
  vim.notify('autocomplete ' .. (vim.bo.autocomplete and 'on' or 'off'))
end, 'Toggle: autocomplete (buffer)')
map(
  'n',
  '<leader>th',
  function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), { bufnr = 0 }) end,
  'Toggle: inlay hints'
)

-- Plugins (vim.pack). <leader>u = update group.
map('n', '<leader>uu', function() vim.pack.update() end, 'Plugins: review updates')
map('n', '<leader>ud', '<Cmd>PackDiff<CR>', 'Plugins: diff code of pending updates')
map(
  'n',
  '<leader>ul',
  function() vim.pack.update(nil, { offline = true, target = 'lockfile' }) end,
  'Plugins: realign to lockfile (offline)'
)
