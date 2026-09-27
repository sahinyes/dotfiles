-- Markdown buffers (notes, TODO.md). Runs after the runtime ftplugin, which
-- sets 4-space indent and removes the r/o format options.
local o = vim.opt_local

-- Enter/o continue '- [ ] ' tasks and '- ' bullets. [!], [x] and [>] are left
-- out on purpose: the next line becomes a plain '- ', so flags never inherit.
o.comments = { 'b:- [ ]', 'b:-', 'n:>' }
o.formatoptions:append('ro')
-- Wrapped task text lines up after '- [ ] ' (used by breakindentopt list:-1).
o.formatlistpat = [[^\s*\%([-*+]\|\d\+[.)]\)\s\+\%(\[.\]\s\+\)\=]]
o.shiftwidth = 2
o.tabstop = 2
o.softtabstop = 2
o.expandtab = true
o.wrap = true
o.linebreak = true
o.breakindent = true
o.breakindentopt = 'list:-1'
o.textwidth = 0
o.foldmethod = 'expr'
o.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
o.foldlevel = 99
o.conceallevel = 0 -- keep [!] visible; render-markdown raises it while rendering
o.spelllang = require('sahin.spell').langs() -- only languages installed on this machine

vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '')
  .. '\n setl com< fo< flp< sw< ts< sts< et< wrap< lbr< bri< briopt< tw< fdm< fde< fdl< cole< spl<'

-- nvu (untrusted profile) loads no notes module: options only.
if vim.g.untrusted then return end

vim.keymap.set({ 'n', 'x' }, '<CR>', ':TaskCycle<CR>', { buffer = true, silent = true, desc = 'Task: cycle state' })
vim.keymap.set('ia', 'xd', function() return os.date('%Y-%m-%d') end, {
  buffer = true,
  expr = true,
  desc = "Insert today's date",
})

vim.b.undo_ftplugin = vim.b.undo_ftplugin
  .. '\n sil! nunmap <buffer> <CR>\n sil! xunmap <buffer> <CR>\n sil! iunabbrev <buffer> xd'
