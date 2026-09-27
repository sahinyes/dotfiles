-- Treesitter highlighting.
-- nvim-treesitter (main branch, pinned) is only a source of queries: its
-- install()/update() are never called. install.sh builds extra parsers from
-- sha256-pinned sources into stdpath('data')/site/parser, which is already on
-- 'runtimepath' and is nvim-treesitter's default install_dir, so no setup().
-- Neovim itself bundles c lua markdown markdown_inline query vim vimdoc.
local util = require('sahin.util')
if not util.try_require('nvim-treesitter', 'nvim-treesitter') then return {} end

-- The queries live in <plugin>/runtime/queries. Append them (lowest priority)
-- so Neovim's own queries keep winning for the bundled parsers.
vim.opt.runtimepath:append(util.opt_dir .. 'nvim-treesitter/runtime')

-- Skip the plugin's :TSInstall/:TSUpdate commands: they download and compile
-- parser sources that tools.lock did not verify. (Set before plugin/ loads.)
vim.g.loaded_nvim_treesitter = true

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('sahin.treesitter', { clear = true }),
  desc = 'Start treesitter highlighting when a parser is installed',
  callback = function(ev)
    if vim.b[ev.buf].bigfile then return end
    local lang = vim.treesitter.language.get_lang(ev.match) or ev.match
    -- No parser (Debian 12, no C compiler): keep the regex syntax.
    local ok, loaded = pcall(vim.treesitter.language.add, lang)
    if not (ok and loaded) then return end
    -- A parser without a highlights query would switch syntax off for nothing.
    local ok_query, query = pcall(vim.treesitter.query.get, lang, 'highlights')
    if not (ok_query and query) then return end
    pcall(vim.treesitter.start, ev.buf, lang)
  end,
})

return {}
