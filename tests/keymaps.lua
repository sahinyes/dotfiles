-- Keymap contract (docs/KEYMAP.md) for every map this config creates:
-- no Alt/Meta, no Ctrl+Shift, no <C-i> <C-m> <C-[> <C-a>, no normal-mode
-- <Tab>, no dead keys, a desc on every map, and no lhs that is a strict
-- prefix of another lhs in the same mode and scope (it would wait for
-- 'timeoutlen'), except the Swiss aliases ö ä § (see swiss.lua).
-- The maps are recorded by tests/keymap_probe.lua in a child Neovim.
local T = dofile('tests/helpers.lua')

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
local out_file = tmp .. '/maps.json'

local probe = T.repo .. '/tests/keymap_probe.lua'
local cmd = { vim.v.progpath, '--headless', '-i', 'NONE', '--cmd', 'luafile ' .. vim.fn.fnameescape(probe) }
local child = vim
  .system(cmd, {
    cwd = tmp,
    text = true,
    -- Temp state/cache dirs: the probe grants trust to a temp repo (LSP
    -- servers start) and must not touch the real trust db, swap, undo or logs.
    env = {
      NVIM_APPNAME = vim.env.NVIM_APPNAME,
      KEYMAP_PROBE_OUT = out_file,
      XDG_STATE_HOME = tmp .. '/state',
      XDG_CACHE_HOME = tmp .. '/cache',
    },
  })
  :wait(120000)

local ok_read, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(out_file), '\n')) end)
T.ok(ok_read, 'probe wrote its JSON', ('exit %s, stderr: %s'):format(child.code, child.stderr))
data = ok_read and data or { records = {}, info = {} }

-- Normalise: one entry per (mode, scope, lhs); the last definition wins.
local expand = { [''] = { 'n', 'x', 's', 'o' }, v = { 'x', 's' }, ['!'] = { 'i', 'c' } }
local maps, index = {}, {}
for _, r in ipairs(data.records) do
  local modes = type(r.mode) == 'table' and r.mode or { r.mode }
  for _, m in ipairs(modes) do
    for _, mode in ipairs(expand[m] or { m }) do
      local raw = vim.api.nvim_replace_termcodes(r.lhs, true, true, true)
      local key = table.concat({ mode, tostring(r.scope), raw }, '\0')
      local entry = vim.tbl_extend('force', r, { mode = mode, raw = raw, keys = vim.fn.keytrans(raw) })
      if index[key] then
        maps[index[key]] = entry
      else
        maps[#maps + 1] = entry
        index[key] = #maps
      end
    end
  end
end

local function scope_name(m)
  if m.scope == 'global' then return 'global' end
  return ('buf %s (%s)'):format(m.scope, m.bufname ~= '' and m.bufname or m.filetype or '?')
end

local function describe(m) return ('%s %s [%s] from %s'):format(m.mode, m.keys, scope_name(m), m.where) end

-- 1. Forbidden chords and keys.
local forbidden_written = { '<m-', '<a-', '<c-s-', '<s-c-', '<c-i>', '<c-m>', '<c-[>', '<c-a>' }
local forbidden_keys = { -- keytrans() form, compared case-insensitively
  '<M-',
  '<A-',
  '<C-S-',
  '<C-A>',
  '<C-CR>',
  '<C-Tab>',
  '<C-BS>',
  '<C-/>',
  '<C-=>',
  '<C-\\>',
  '<C-]>',
  '<C-Left>',
  '<C-Right>',
  '<C-Up>',
  '<C-Down>',
}
local dead_keys = { '^', '`', '~', '¨', '´' }

local problems = {}
local function problem(msg) problems[#problems + 1] = msg end

for _, m in ipairs(maps) do
  local written, keys = m.lhs:lower(), m.keys:lower()
  for _, f in ipairs(forbidden_written) do
    if written:find(f, 1, true) then problem(('forbidden %s in %s'):format(f, describe(m))) end
  end
  for _, f in ipairs(forbidden_keys) do
    if keys:find(f:lower(), 1, true) then problem(('forbidden %s in %s'):format(f, describe(m))) end
  end
  if m.mode == 'n' and m.keys == '<Tab>' then problem('normal-mode <Tab> (= <C-i>, jump forward): ' .. describe(m)) end
  local plain = m.keys:gsub('<[^>]+>', '')
  for _, d in ipairs(dead_keys) do
    if plain:find(d, 1, true) then problem(('dead key %s in %s'):format(d, describe(m))) end
  end
  if type(m.desc) ~= 'string' or m.desc == '' then problem('missing desc: ' .. describe(m)) end
end

-- 2. Strict prefixes within the same mode and scope (a buffer's maps plus
--    the global ones).
local leader = vim.api.nvim_replace_termcodes('<leader>', true, true, true)
local aliases = { ['ö'] = true, ['ä'] = true, ['§'] = true } -- declared in swiss.lua
local groups = { 's', 'n', 'h', 'x', 'c', 't', 'i', 'u' } -- mini.clue leader groups
for _, a in ipairs(maps) do
  for _, g in ipairs(groups) do
    if a.raw == leader .. g then problem('lhs is a leader group prefix: ' .. describe(a)) end
  end
  if not aliases[a.raw] then
    for _, b in ipairs(maps) do
      -- Buffer maps meet the global ones in that buffer, so compare those too.
      local same_scope = a.scope == b.scope or a.scope == 'global' or b.scope == 'global'
      if a.mode == b.mode and same_scope and #b.raw > #a.raw and vim.startswith(b.raw, a.raw) then
        problem(('prefix conflict: %s is a prefix of %s'):format(describe(a), describe(b)))
      end
    end
  end
end

-- 3. The probe saw the config (guards against a silently broken probe).
local function has(mode, lhs)
  local raw = vim.api.nvim_replace_termcodes(lhs, true, true, true)
  for _, m in ipairs(maps) do
    if m.mode == mode and m.raw == raw and m.scope == 'global' then return true end
  end
  return false
end
T.ok(#maps > 40, 'probe recorded the config maps', #maps .. ' maps')
T.ok(has('n', 'ö') and has('n', '<leader>e') and has('n', '<leader>sf'), 'probe saw swiss, core and telescope maps')

T.ok(#problems == 0, 'keymap contract', #problems .. ' problem(s)')
if #problems > 0 then
  local out = io.stdout
  out:write('Keymap contract problems:\n')
  for _, p in ipairs(problems) do
    out:write('  ! ' .. p .. '\n')
  end
  table.sort(maps, function(a, b)
    local sa, sb = tostring(a.scope), tostring(b.scope)
    if sa ~= sb then return sa < sb end
    if a.mode ~= b.mode then return a.mode < b.mode end
    return a.keys < b.keys
  end)
  out:write(('All %d recorded maps (mode, lhs, scope, desc, origin):\n'):format(#maps))
  for _, m in ipairs(maps) do
    out:write(('  %-2s %-18s %-26s %-50s %s\n'):format(m.mode, m.keys, scope_name(m), m.desc or '(none)', m.where))
  end
end

local info = data.info or {}
io.stdout:write(
  ('[keymaps] exercised: trust=%s gitsigns=%s lsp=%s\n'):format(
    tostring(info.trust),
    vim.inspect(info.gitsigns or {}, { newline = '' }),
    vim.inspect(info.lsp or {}, { newline = '' })
  )
)

vim.fn.delete(tmp, 'rf')
T.finish('keymaps')
