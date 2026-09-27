-- Smoke test: the whole config starts cleanly and the core contracts hold.
-- Run: NVIM_APPNAME=nvim-test nvim --headless -i NONE -c 'luafile tests/smoke.lua'
local T = dofile('tests/helpers.lua')

-- Read startup messages before this suite adds its own; vim.wait lets
-- scheduled startup notifications land first.
vim.wait(100)
T.it('startup: no errors in :messages', function()
  local msgs = vim.api.nvim_exec2('messages', { output = true }).output
  T.ok(not msgs:find('E%d+:'), 'no E-number errors in :messages', msgs)
  T.ok(not msgs:find('stack traceback'), 'no Lua tracebacks in :messages', msgs)
end)

T.ok(vim.fn.has('nvim-0.12') == 1, 'Neovim >= 0.12', tostring(vim.version()))

T.it('every sahin.* module loads', function()
  local root = T.repo .. '/nvim/lua/'
  local count = 0
  for path, kind in vim.fs.dir(root .. 'sahin', { depth = 10 }) do
    if kind == 'file' and path:match('%.lua$') then
      local name = ('sahin/' .. path):gsub('%.lua$', ''):gsub('/init$', ''):gsub('/', '.')
      local ok, err = pcall(require, name)
      T.ok(ok, 'module loads: ' .. name, err)
      count = count + 1
    end
  end
  T.ok(count >= 10, 'found the sahin modules', count)
end)

T.it('vim.pack: every lockfile plugin is installed and active', function()
  local pack = require('sahin.pack')
  local missing = pack.missing()
  T.eq(missing, {}, 'no lockfile plugin missing on disk')
  -- vim.pack.get() would install missing plugins, so only ask when none are.
  if #missing > 0 then return end
  local plugins = vim.pack.get()
  T.eq(#plugins, pack.lock_count(), '#vim.pack.get() == lockfile plugin count')
  for _, p in ipairs(plugins) do
    T.ok(p.active, 'plugin active: ' .. p.spec.name)
  end
end)

T.it('Swiss layer', function()
  -- The global map: mini.clue adds buffer-local ö triggers that maparg() would return first.
  local rhs
  for _, m in ipairs(vim.api.nvim_get_keymap('n')) do
    if m.lhs == 'ö' then rhs = m.rhs end
  end
  T.eq(rhs, '[', 'global ö map in n mode has rhs [')
  T.buf({ '# One', 'text', 'more', '# Two', 'end' }, 'markdown')
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  T.feed('ää')
  T.eq(vim.api.nvim_win_get_cursor(0)[1], 4, 'ää from line 1 lands on the second # heading')
end)

T.it('core-security modules', function()
  for _, cmd in ipairs({
    'Json',
    'JsonMin',
    'Hex',
    'B64d',
    'B64e',
    'UrlDecode',
    'UrlEncode',
    'Jwt',
    'DiffTool',
    'Doctor',
  }) do
    T.eq(vim.fn.exists(':' .. cmd), 2, ':' .. cmd .. ' exists')
  end
  local report = require('sahin.doctor').report()
  T.ok(#report >= 10 and report[1]:find('^neovim'), ':Doctor report builds', report[1])
  T.ok(type(require('sahin.clipboard').provider()) == 'string', 'clipboard provider() is a string')
end)

T.finish('smoke')
