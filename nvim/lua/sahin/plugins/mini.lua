-- mini.nvim modules: text objects, surround, statusline, icons, word highlights.
-- mini.clue is set up in sahin/clue.lua, after every other plugin made its maps.
local util = require('sahin.util')

local function setup(module, opts)
  local mod = util.try_require('mini.nvim', module)
  if mod then mod.setup(opts) end
  return mod
end

-- Extra a/i text objects (va), ci', yiiq ...). Neovim 0.12 uses an/in for
-- treesitter selection, so "next object" moves to aa/ii (as in kickstart).
setup('mini.ai', { mappings = { around_next = 'aa', inside_next = 'ii' }, n_lines = 500 })

-- sa/sd/sr: add, delete, replace surroundings (saiw) sd' sr)').
setup('mini.surround', {})

-- ASCII icons unless local.lua says a Nerd Font is installed.
local icons = setup('mini.icons', { style = vim.g.have_nerd_font and 'glyph' or 'ascii' })
if icons then icons.mock_nvim_web_devicons() end -- telescope asks for nvim-web-devicons

setup('mini.statusline', { use_icons = vim.g.have_nerd_font == true })

-- Highlight marker words (also in notes) and #rrggbb colours.
local hipatterns = util.try_require('mini.nvim', 'mini.hipatterns')
if hipatterns then
  local function word(w) return '%f[%w]()' .. w .. '()%f[%W]' end
  hipatterns.setup({
    highlighters = {
      fixme = { pattern = word('FIXME'), group = 'MiniHipatternsFixme' },
      hack = { pattern = word('HACK'), group = 'MiniHipatternsHack' },
      todo = { pattern = word('TODO'), group = 'MiniHipatternsTodo' },
      note = { pattern = word('NOTE'), group = 'MiniHipatternsNote' },
      hex_color = hipatterns.gen_highlighter.hex_color(),
    },
  })
end

return {}
