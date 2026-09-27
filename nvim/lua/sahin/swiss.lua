-- Swiss German keyboard layer: [ ] { } ` ~ need Option/AltGr or are dead keys.
-- Identical on macOS (iTerm2, Option = Normal) and Debian (GNOME Terminal).
local map = vim.keymap.set
local nxo, xo = { 'n', 'x', 'o' }, { 'x', 'o' }

-- Layer 1: single keys with remap=true, so every mapped [ ] target resolves
-- ([d ]d [q ]q [b ]b [<Space> gitsigns ]c ...).
map(nxo, 'ö', '[', { remap = true, desc = '[ (alias)' })
map(nxo, 'ä', ']', { remap = true, desc = '] (alias)' })
map(nxo, 'é', '{', { remap = true, desc = '{ paragraph back (Shift+ö)' })
map(nxo, 'à', '}', { remap = true, desc = '} paragraph forward (Shift+ä)' })
map(nxo, '§', '`', { desc = '` exact mark jump' })
map(nxo, '°', '~', { desc = '~ toggle case' })

-- Layer 2: built-ins whose second character is read with mappings off.
-- remap=true so buffer-local [[ ]] (markdown headings, terminal prompts,
-- vim.pack confirm buffer) win over the built-in section motion.
for lhs, rhs in pairs({
  ['öö'] = '[[',
  ['ää'] = ']]',
  ['öä'] = '[]',
  ['äö'] = '][',
  ['öé'] = '[{',
  ['äà'] = ']}',
  ['§§'] = '``',
  ['§ö'] = '`[',
  ['§ä'] = '`]',
}) do
  map(nxo, lhs, rhs, { remap = true, desc = rhs .. ' (alias)' })
end

-- Layer 3: text objects (i/a read their character with mappings off).
for _, p in ipairs({ { 'ö', '[' }, { 'ä', ']' }, { 'é', '{' }, { 'à', '}' } }) do
  map(xo, 'i' .. p[1], 'i' .. p[2], { desc = 'inner ' .. p[2] .. ' block' })
  map(xo, 'a' .. p[1], 'a' .. p[2], { desc = 'a ' .. p[2] .. ' block' })
end

map('n', 'ü', '<C-]>', { remap = true, desc = 'Go to definition / tag (CTRL-])' })
map('t', '<C-q>', '<C-\\><C-n>', { desc = 'Leave terminal mode' })

-- <C-a> is the tmux prefix, so increment/decrement move to + and -.
map({ 'n', 'x' }, '+', '<C-a>', { desc = 'Increment number' })
map({ 'n', 'x' }, '-', '<C-x>', { desc = 'Decrement number' })
map('x', 'g+', 'g<C-a>', { desc = 'Increment sequentially' })
map('x', 'g-', 'g<C-x>', { desc = 'Decrement sequentially' })

-- Neovim 0.13 turns Q into multicursor; keep "replay last macro".
if vim.fn.has('nvim-0.13') == 1 then
  map('n', 'Q', function()
    local r = vim.fn.reg_recorded()
    return r == '' and '' or '@' .. r
  end, { expr = true, desc = 'Replay last recorded macro' })
end
