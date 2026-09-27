-- :Doctor: a scratch report of what this machine and profile really have.
-- Paste it into an issue or a note when something behaves differently on the
-- other machine. It only reads: optional modules are loaded with pcall, and
-- vim.pack.get() is only called when nothing is missing (it would install).
local M = {}

local function yn(value) return value and 'yes' or 'no' end
local function set(name) return (vim.env[name] or '') ~= '' and 'set' or 'unset' end
local function show(name) return vim.env[name] or '-' end

local function local_bin_on_path()
  local want = vim.fs.normalize('~/.local/bin')
  for dir in (vim.env.PATH or ''):gmatch('[^:]+') do
    if vim.fs.normalize(dir) == want then return true end
  end
  return false
end

--- Smulx is the terminfo capability for undercurl (spelling, diagnostics).
local function smulx()
  local ok, res = pcall(function() return vim.system({ 'infocmp', '-x' }, { text = true }):wait(3000) end)
  if not ok then return 'unknown (infocmp not found)' end
  if res.code ~= 0 then return 'unknown (infocmp failed for TERM=' .. show('TERM') .. ')' end
  if res.stdout:find('Smulx=') then return 'yes (undercurl works)' end
  return 'no: undercurl falls back to underline (Mac + tmux: scripts/terminfo-mac.sh)'
end

local function clipboard()
  local ok, cb = pcall(require, 'sahin.clipboard')
  if ok and type(cb) == 'table' and type(cb.provider) == 'function' then return cb.provider() end
  return 'unknown (sahin.clipboard unavailable)'
end

local function parsers()
  local names = {}
  for _, path in ipairs(vim.api.nvim_get_runtime_file('parser/*.so', true)) do
    names[vim.fn.fnamemodify(path, ':t:r')] = true
  end
  local list = vim.tbl_keys(names)
  table.sort(list)
  return #list > 0 and table.concat(list, ' ') or 'none'
end

local function spell_missing()
  local ok, spell = pcall(require, 'sahin.spell')
  if ok and type(spell) == 'table' and type(spell.missing) == 'function' then
    local ok2, miss = pcall(spell.missing)
    if ok2 and type(miss) == 'table' then return #miss > 0 and table.concat(miss, ' ') or 'none' end
  end
  -- Fallback: the word lists behind spelllang=en,de_ch,tr.
  local miss = {}
  for _, lang in ipairs({ 'en', 'de', 'tr' }) do
    if #vim.api.nvim_get_runtime_file('spell/' .. lang .. '.utf-8.spl', false) == 0 then miss[#miss + 1] = lang end
  end
  return #miss > 0 and table.concat(miss, ' ') or 'none'
end

local function trust()
  if vim.g.untrusted then return 'n/a (untrusted profile: no LSP, no gitsigns)' end
  local ok, mod = pcall(require, 'sahin.trust')
  if not ok or type(mod) ~= 'table' or type(mod.is_trusted) ~= 'function' then
    return 'sahin.trust unavailable: every project counts as untrusted'
  end
  local root = vim.fs.root(vim.fn.getcwd(), { '.git', '.hg', '.jj' })
  root = root and vim.uv.fs_realpath(root)
  if not root then return 'cwd is not inside a git/hg/jj repository' end
  local ok2, trusted = pcall(mod.is_trusted, root)
  local shown = vim.fn.fnamemodify(root, ':~')
  if not (ok2 and trusted == true) then return shown .. ' NOT trusted (LSP and gitsigns off; :TrustProject)' end
  local allowed = {}
  local ok3, configs = pcall(vim.lsp.get_configs, { enabled = true })
  for _, cfg in ipairs(ok3 and configs or {}) do
    local ok4, yes = pcall(mod.allowed, root, cfg.name)
    if ok4 and yes then allowed[#allowed + 1] = cfg.name end
  end
  table.sort(allowed)
  return ('%s trusted; servers allowed: %s'):format(shown, #allowed > 0 and table.concat(allowed, ' ') or 'none')
end

local function plugins()
  if vim.g.untrusted then return 'none by design (untrusted profile)' end
  local pack = package.loaded['sahin.pack']
  if type(pack) ~= 'table' or type(pack.missing) ~= 'function' or type(pack.lock_count) ~= 'function' then
    return 'unknown (sahin.pack not loaded)'
  end
  local miss = pack.missing()
  local line = ('%d in lockfile, %d missing'):format(pack.lock_count(), #miss)
  if #miss > 0 then return line .. ': ' .. table.concat(miss, ' ') .. ' (run install.sh or :PackSync)' end
  local ok, list = pcall(vim.pack.get)
  if not ok then return line end
  return line .. ('; %d active'):format(#vim.tbl_filter(function(p) return p.active end, list))
end

--- The report as lines.
function M.report()
  local lines = {}
  if vim.g.untrusted then
    lines[#lines + 1] =
      '!! UNTRUSTED PROFILE (nvu): no plugins, LSP, gitsigns, notes, netrw, gzip/zip/tar, editorconfig'
  end
  local rows = {
    { 'neovim', ('%s (running %s)'):format(tostring(vim.version()), vim.fn.fnamemodify(vim.v.progpath, ':~')) },
    { "exepath('nvim')", vim.fn.fnamemodify(vim.fn.exepath('nvim'), ':~') },
    { '~/.local/bin on PATH', yn(local_bin_on_path()) },
    { 'NVIM_APPNAME', show('NVIM_APPNAME') },
    { 'TERM / COLORTERM', show('TERM') .. ' / ' .. show('COLORTERM') },
    { 'TMUX / SSH_TTY', set('TMUX') .. ' / ' .. set('SSH_TTY') },
    { 'VTE_VERSION', show('VTE_VERSION') },
    { 'Smulx (undercurl)', smulx() },
    { 'clipboard', clipboard() },
    { 'nerd font', yn(vim.g.have_nerd_font) },
    { 'treesitter parsers', parsers() },
    { 'spell files missing', spell_missing() },
    { 'cwd trust', trust() },
    { 'plugins', plugins() },
  }
  for _, row in ipairs(rows) do
    lines[#lines + 1] = ('%-22s %s'):format(row[1], row[2])
  end
  return lines
end

function M.open()
  local lines = M.report()
  vim.cmd('botright new')
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false
  vim.api.nvim_win_set_height(0, #lines + 1)
end

vim.api.nvim_create_user_command('Doctor', M.open, { desc = 'Report terminal, clipboard, parsers, trust, plugins' })

return M
