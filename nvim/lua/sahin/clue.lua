-- Key hints (mini.clue): after a trigger key a window lists what can follow.
-- Loaded after all plugins so their maps exist. Triggers are buffer-local maps
-- that mini.clue re-creates on BufWinEnter and LspAttach; code that adds
-- buffer maps later calls MiniClue.ensure_buf_triggers() (see gitsigns.lua).
local util = require('sahin.util')
local miniclue = util.try_require('mini.nvim', 'mini.clue')
if not miniclue then return {} end

local gen = miniclue.gen_clues

-- On the Swiss keyboard [ ] { } need AltGr/Option, so swiss.lua maps ö ä é à
-- to them. Show the [ / ] families under ö / ä, with the second key typed the
-- same way (öö = [[, äà = ]}).
local alias = { ['['] = 'ö', [']'] = 'ä', ['{'] = 'é', ['}'] = 'à' }

local function rekey(keys)
  local first, rest = keys:sub(1, 1), keys:sub(2)
  -- ` is a dead key, so [` cannot be typed after ö anyway.
  if not alias[first] or rest == '' or vim.startswith(rest, '`') then return nil end
  return alias[first] .. (alias[rest] or rest)
end

-- Built-in [x motions plus every current [x / ]x map (diagnostics, quickfix,
-- gitsigns hunks, markdown [[ ...). A function, so it is re-read on each
-- trigger and buffer-local maps show up.
local function swiss_brackets()
  local clues = {}
  local function add(keys, desc)
    local k = rekey(keys)
    if k then clues[#clues + 1] = { mode = 'n', keys = k, desc = desc } end
  end
  for _, c in ipairs(gen.square_brackets()) do
    add(c.keys, c.desc)
  end
  for _, m in ipairs(vim.api.nvim_get_keymap('n')) do
    add(m.lhs, m.desc or m.rhs)
  end
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, 'n')) do
    add(m.lhs, m.desc or m.rhs)
  end
  return clues
end

local groups = {
  { 's', 'Search' },
  { 'n', 'Notes' },
  { 'h', 'Git hunk' },
  { 'x', 'Quickfix' },
  { 'c', 'Code' },
  { 't', 'Toggle' },
  { 'i', 'Inspect' },
  { 'u', 'Update/plugins' },
}
local leader_groups = {}
for _, g in ipairs(groups) do
  leader_groups[#leader_groups + 1] = { mode = { 'n', 'x' }, keys = '<Leader>' .. g[1], desc = '+' .. g[2] }
end

miniclue.setup({
  triggers = {
    { mode = { 'n', 'x' }, keys = '<Leader>' },
    { mode = 'n', keys = 'ö' },
    { mode = 'n', keys = 'ä' },
    { mode = { 'n', 'x' }, keys = 'g' },
    { mode = { 'n', 'x' }, keys = 'z' },
    { mode = { 'n', 'x' }, keys = '"' },
    { mode = { 'n', 'x' }, keys = "'" },
    { mode = 'n', keys = '<C-w>' },
    { mode = 'i', keys = '<C-x>' },
    { mode = { 'i', 'c' }, keys = '<C-r>' },
  },
  clues = {
    gen.builtin_completion(),
    gen.g(),
    gen.marks(),
    gen.registers(),
    gen.windows(),
    gen.z(),
    swiss_brackets,
    leader_groups,
  },
  -- timeoutlen stays 1000 (options.lua); the window waits 300 ms.
  window = { delay = 300, config = { width = 'auto' } },
})

return {}
