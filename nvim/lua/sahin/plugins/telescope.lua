-- Fuzzy finder. Map names follow kickstart.nvim: <leader>s = search.
local util = require('sahin.util')
local telescope = util.try_require('telescope.nvim', 'telescope')
if not telescope then return {} end

-- check_mime_type off: for files without a known filetype the previewer would
-- run io.popen('file --mime-type -b "<path>"'), a shell string, so a cloned
-- file named like $(cmd) would run cmd. Such files are shown as plain text.
-- One <Esc> closes a picker. By default the first <Esc> only enters the
-- picker's normal mode, and a window command typed there (<C-w>o) acts on
-- the floating picker (E5601). Move with the arrow keys or <C-n>/<C-p>.
telescope.setup({
  defaults = {
    preview = { check_mime_type = false },
    mappings = { i = { ['<Esc>'] = require('telescope.actions').close } },
  },
})

local builtin = require('telescope.builtin')
local map = util.map

map('n', '<leader>sh', builtin.help_tags, 'Search: help')
map('n', '<leader>sk', builtin.keymaps, 'Search: keymaps')
map('n', '<leader>sf', builtin.find_files, 'Search: files')
map({ 'n', 'x' }, '<leader>sw', builtin.grep_string, 'Search: word under cursor (or selection)')
map('n', '<leader>sg', builtin.live_grep, 'Search: grep')
map('n', '<leader>sd', builtin.diagnostics, 'Search: diagnostics')
map('n', '<leader>sr', builtin.resume, 'Search: resume last search')
map('n', '<leader>s.', builtin.oldfiles, 'Search: recent files')
map('n', '<leader>sc', builtin.commands, 'Search: commands')
map('n', '<leader>ss', builtin.builtin, 'Search: select a telescope picker')
map('n', '<leader><leader>', builtin.buffers, 'Search: open buffers')

map(
  'n',
  '<leader>/',
  function()
    builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown({ winblend = 10, previewer = false }))
  end,
  'Search: fuzzy in current buffer'
)

map(
  'n',
  '<leader>s/',
  function() builtin.live_grep({ grep_open_files = true, prompt_title = 'Live Grep in Open Files' }) end,
  'Search: grep in open files'
)

map(
  'n',
  '<leader>sn',
  function() builtin.find_files({ cwd = vim.fn.stdpath('config'), follow = true }) end,
  'Search: Neovim config files'
)

return {}
