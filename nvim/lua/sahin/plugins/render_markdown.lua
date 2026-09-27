-- render-markdown.nvim: rendered headings, bullets and task states in normal
-- mode; raw text in insert mode and on the cursor line.
-- [!] important (red), [>] deferred (dim), [x] done (struck through).
local util = require('sahin.util')

local M = {}

-- Without a Nerd Font the private-use glyphs would show as boxes: use text.
local function ascii(defaults)
  local strip = function(s) return (s:gsub('^[\128-\255]+%s*', '')) end -- '󰋽 Note' -> 'Note'
  local o = {
    heading = { icons = { '# ', '## ', '### ', '#### ', '##### ', '###### ' }, signs = { '#' } },
    sign = { enabled = false },
    code = { language_icon = false },
    link = { footnote = { icon = '' }, image = '', email = '', hyperlink = '', wiki = { icon = '' }, custom = {} },
    callout = {},
    checkbox = { custom = {} },
  }
  for name in pairs(defaults.link.custom) do
    o.link.custom[name] = { icon = '' }
  end
  for name, c in pairs(defaults.callout) do
    o.callout[name] = { rendered = strip(c.rendered) }
  end
  for name, c in pairs(defaults.checkbox.custom) do
    o.checkbox.custom[name] = { rendered = c.raw .. ' ' }
  end
  return o
end

--- setup() options; `nerd` picks glyphs (true) or ASCII (false).
function M.opts(nerd)
  local function icon(glyph, text) return nerd and glyph or text end
  local opts = {
    checkbox = {
      unchecked = { icon = icon('󰄱 ', '[ ] ') },
      checked = { icon = icon('󰱒 ', '[x] '), scope_highlight = '@markup.strikethrough' },
      custom = {
        important = { raw = '[!]', rendered = icon('󰀦 ', '[!] '), highlight = 'RenderMarkdownError' },
        deferred = { raw = '[>]', rendered = icon('󰥔 ', '[>] '), highlight = 'Comment', scope_highlight = 'Comment' },
      },
    },
  }
  if nerd then return opts end
  return vim.tbl_deep_extend('force', ascii(require('render-markdown').default), opts)
end

local rm = util.try_require('render-markdown.nvim', 'render-markdown')
if not rm then return M end

rm.setup(M.opts(vim.g.have_nerd_font == true))

util.map('n', '<leader>tr', function()
  rm.toggle()
  vim.notify('render-markdown ' .. (rm.get() and 'on' or 'off'))
end, 'Toggle: render markdown')

return M
