-- Options that differ from Neovim 0.12 defaults (defaults are not repeated).
local o = vim.o
local opt = vim.opt

o.number = true
o.relativenumber = true
o.ignorecase = true
o.smartcase = true
o.undofile = true
o.scrolloff = 8
o.splitright = true
o.splitbelow = true
o.signcolumn = 'yes'
o.cursorline = true
o.updatetime = 250
o.timeoutlen = 1000 -- keep >= 700: ö/ä aliases in operator-pending mode need the window
o.confirm = true
o.inccommand = 'split'
o.smoothscroll = true
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.smartindent = true
o.termguicolors = true
o.winborder = 'rounded'
o.pumborder = 'rounded'
o.pumheight = 12
o.showmode = false -- mini.statusline shows the mode

o.list = true
opt.listchars = { tab = '» ', trail = '·', leadmultispace = '│ ', nbsp = '␣' }
opt.path:append('**')
opt.nrformats:append('unsigned')

-- Spell: plain `zg` writes to a local, untracked list; `2zg` writes to the
-- shared list in the (public) repo on purpose.
local spelldir = vim.fn.stdpath('data') .. '/spell'
vim.fn.mkdir(spelldir, 'p')
opt.spellfile = { spelldir .. '/local.utf-8.add', vim.fn.stdpath('config') .. '/spell/en.utf-8.add' }

vim.diagnostic.config({
  virtual_text = false,
  virtual_lines = { current_line = true },
  severity_sort = true,
})

local group = vim.api.nvim_create_augroup('sahin.options', { clear = true })

-- Big files: no syntax/treesitter/undo history/swap above 1.5 MB.
vim.api.nvim_create_autocmd('BufReadPre', {
  group = group,
  callback = function(ev)
    local stat = vim.uv.fs_stat(ev.match)
    if stat and stat.size > 1.5 * 1024 * 1024 then
      vim.b[ev.buf].bigfile = true
      vim.bo[ev.buf].swapfile = false
      vim.bo[ev.buf].undolevels = -1
      vim.api.nvim_create_autocmd('BufReadPost', {
        buffer = ev.buf,
        once = true,
        callback = function()
          vim.bo[ev.buf].filetype = 'bigfile'
          vim.bo[ev.buf].syntax = 'OFF'
          vim.wo.foldmethod = 'manual'
        end,
      })
    end
  end,
})

-- Reload files changed outside Neovim (other machine, agents, scripts).
vim.api.nvim_create_autocmd({ 'FocusGained', 'TermClose', 'TermLeave' }, {
  group = group,
  command = 'silent! checktime',
})

-- Brief highlight of yanked text.
vim.api.nvim_create_autocmd('TextYankPost', {
  group = group,
  callback = function() vim.hl.on_yank() end,
})
