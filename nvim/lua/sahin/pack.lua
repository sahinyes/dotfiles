-- vim.pack wrapper.
-- vim.pack's first call installs every lockfile plugin missing on disk, and a
-- black-holed proxy can block startup for 120 s. So interactive starts only
-- call vim.pack.add when nothing is missing; installs happen via install.sh
-- (NVIM_BOOTSTRAP=1) or :PackSync.
local util = require('sahin.util')
local specs = require('sahin.plugins.specs')
local packdiff = require('sahin.packdiff')

local M = {}

local function lockfile_path() return vim.fn.stdpath('config') .. '/nvim-pack-lock.json' end

local function read_lock()
  local f = io.open(lockfile_path())
  if not f then return {} end
  local ok, data = pcall(vim.json.decode, f:read('a'))
  f:close()
  return ok and (data.plugins or {}) or {}
end

--- Plugin names (lockfile ∪ specs) whose directory is missing.
function M.missing()
  local names, miss = {}, {}
  for name in pairs(read_lock()) do
    names[name] = true
  end
  for _, s in ipairs(specs) do
    names[s.name] = true
  end
  for name in pairs(names) do
    if not util.has_plugin(name) then miss[#miss + 1] = name end
  end
  table.sort(miss)
  return miss
end

--- Install/realign everything to the lockfile and delete orphans.
function M.sync()
  local ok, err = pcall(vim.pack.add, specs, { confirm = false })
  if not ok then return util.warn('vim.pack: ' .. tostring(err)) end
  local want, orphans = {}, {}
  for _, s in ipairs(specs) do
    want[s.name] = true
  end
  for _, p in ipairs(vim.pack.get()) do
    if not want[p.spec.name] then orphans[#orphans + 1] = p.spec.name end
  end
  if #orphans > 0 then pcall(vim.pack.del, orphans) end
  pcall(vim.pack.update, nil, { target = 'lockfile', force = true })
end

function M.lock_count() return vim.tbl_count(read_lock()) end

local miss = M.missing()
local offline = vim.g.nvim_offline or vim.env.NVIM_OFFLINE == '1' or vim.fn.executable('git') == 0

if vim.env.NVIM_BOOTSTRAP == '1' then
  M.sync()
elseif #miss == 0 then
  local ok, err = pcall(vim.pack.add, specs, { confirm = false }) -- nothing to clone
  if not ok then util.warn('vim.pack: ' .. tostring(err)) end
elseif offline then
  for _, s in ipairs(specs) do
    if util.has_plugin(s.name) then pcall(vim.cmd.packadd, { s.name, bang = true }) end
  end
  util.warn('plugins missing (' .. table.concat(miss, ' ') .. '): run install.sh or :PackSync')
else
  local ok, err = pcall(vim.pack.add, specs, { confirm = true }) -- shows what will be cloned
  if not ok then util.warn('vim.pack: ' .. tostring(err)) end
end

-- Audit trail for every install/update/delete (no build hooks run).
vim.api.nvim_create_autocmd('PackChanged', {
  group = vim.api.nvim_create_augroup('sahin.pack', { clear = true }),
  callback = function(ev)
    local f = io.open(vim.fn.stdpath('log') .. '/pack-audit.log', 'a')
    if not f then return end
    f:write(
      ('%s %s %s %s\n'):format(
        os.date('!%Y-%m-%dT%H:%M:%SZ'),
        ev.data.kind,
        ev.data.spec.name,
        ev.data.spec.version and tostring(ev.data.spec.version) or '-'
      )
    )
    f:close()
  end,
})

vim.api.nvim_create_user_command('PackSync', M.sync, { desc = 'Install plugins at lockfile revisions' })
vim.api.nvim_create_user_command(
  'PackDiff',
  function() packdiff.open() end,
  { desc = 'Show the code diff of every update in the vim.pack confirm buffer' }
)

return M
