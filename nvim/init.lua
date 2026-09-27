-- Neovim config (github.com/sahinyes/dotfiles). Requires Neovim 0.12.x.
-- Load order matters; see docs/KEYMAP.md and SECURITY.md.

-- 1. Never load Lua modules from the current directory. LuaJIT's default
--    package.path/cpath start with ./?.lua and ./?.so; a missing module would
--    otherwise run a file planted in a hostile clone.
local function strip_cwd(p)
  local keep = {}
  for entry in p:gmatch('[^;]+') do
    if not entry:match('^%./') then keep[#keep + 1] = entry end
  end
  return table.concat(keep, ';')
end
package.path = strip_cwd(package.path)
package.cpath = strip_cwd(package.cpath)

vim.loader.enable()

if vim.fn.has('nvim-0.12') == 0 then
  vim.notify('This config requires Neovim >= 0.12', vim.log.levels.ERROR)
  return
end

-- 2. Hardening that must happen before runtime plugins load.
vim.g.untrusted = vim.env.NVIM_APPNAME == 'nvim-untrusted' -- alias: nvu
require('sahin.security')

-- 3. Leader and machine-local facts (lua/local.lua is gitignored).
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '
local local_file = vim.fn.stdpath('config') .. '/lua/local.lua'
if vim.uv.fs_stat(local_file) then dofile(local_file) end

-- 4. Editor core (no plugins needed).
require('sahin.options')
require('sahin.swiss')
require('sahin.keymaps')
require('sahin.inspect')
vim.cmd.colorscheme('catppuccin') -- bundled with Neovim 0.12

if vim.g.untrusted then
  require('sahin.doctor')
  return
end

-- 5. Plugins (pinned via nvim-pack-lock.json), LSP, notes.
require('sahin.pack')
for _, name in ipairs({ 'mini', 'telescope', 'gitsigns', 'render_markdown', 'treesitter', 'precognition' }) do
  require('sahin.plugins.' .. name)
end
require('sahin.clue')
require('sahin.completion')
require('sahin.lsp')
require('sahin.notes')
require('sahin.clipboard')
require('sahin.doctor')
