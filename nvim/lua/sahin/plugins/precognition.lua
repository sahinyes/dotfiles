-- Motion hints (w b e ... above the cursor line): training wheels for the
-- first weeks. vim.g.precognition = false in local.lua starts with them hidden.
local util = require('sahin.util')
local precognition = util.try_require('precognition.nvim', 'precognition')
if not precognition then return {} end

precognition.setup({
  startVisible = vim.g.precognition ~= false,
  -- Show the keys this keyboard really uses: ^ is a dead key (_ does the
  -- same), { } are é à through swiss.lua.
  hints = { Caret = { text = '_' } },
  gutterHints = { PrevParagraph = { text = 'é' }, NextParagraph = { text = 'à' } },
})

util.map('n', '<leader>tp', function()
  local visible = precognition.toggle()
  vim.notify('precognition ' .. (visible and 'on' or 'off'))
end, 'Toggle: precognition motion hints')

return {}
