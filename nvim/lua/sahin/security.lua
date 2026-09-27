-- Hardening applied before runtime plugins load. See SECURITY.md.

-- Built-in plugins that fetch from the network, auto-download files or shell
-- out on archive names/contents are disabled everywhere.
for _, g in ipairs({
  'loaded_nvim_net_plugin', -- :edit https://..., auto-unpack
  'loaded_spellfile_plugin', -- spell files come from install.sh (sha256-pinned)
  'loaded_zipPlugin',
  'loaded_zip',
  'loaded_tarPlugin',
  'loaded_tar',
}) do
  vim.g[g] = 1
end

-- Language providers are not used.
for _, p in ipairs({ 'python3', 'node', 'perl', 'ruby' }) do
  vim.g['loaded_' .. p .. '_provider'] = 0
end

-- editorconfig only runs in trusted roots (trust.lua sets vim.b.editorconfig).
vim.g.editorconfig = false

if vim.g.untrusted then
  -- nvu profile: no gzip, no netrw at all.
  vim.g.loaded_gzip = 1
  vim.g.loaded_netrwPlugin = 1
  vim.g.loaded_netrw = 1
end

vim.o.modeline = false
vim.o.modelineexpr = false
vim.o.exrc = false

-- OSC 52 is opt-in only (vim.g.osc52, applied by clipboard.lua). Otherwise
-- Neovim asks the terminal at startup and, when no clipboard tool exists (SSH),
-- silently uses OSC 52 for the + register.
local termfeatures = vim.g.termfeatures or {}
termfeatures.osc52 = false
vim.g.termfeatures = termfeatures

-- Git commands started by Neovim or plugins must never run a repo-controlled
-- fsmonitor hook. Appended to any existing GIT_CONFIG_COUNT (the last entry
-- wins in git), skipped when a parent Neovim already added it.
local n = tonumber(vim.env.GIT_CONFIG_COUNT or '0') or 0
local fsmonitor
for i = 0, n - 1 do
  if (vim.env['GIT_CONFIG_KEY_' .. i] or ''):lower() == 'core.fsmonitor' then
    fsmonitor = vim.env['GIT_CONFIG_VALUE_' .. i]
  end
end
if fsmonitor ~= 'false' then
  vim.env['GIT_CONFIG_KEY_' .. n] = 'core.fsmonitor'
  vim.env['GIT_CONFIG_VALUE_' .. n] = 'false'
  vim.env.GIT_CONFIG_COUNT = tostring(n + 1)
end

-- Only http/https/mailto may be opened by gx, :Open or LSP document links.
local orig_open = vim.ui.open
local allowed = { http = true, https = true, mailto = true }
---@diagnostic disable-next-line: duplicate-set-field
vim.ui.open = function(path, opt)
  local scheme = type(path) == 'string' and path:match('^(%a[%w+.-]*):') or nil
  if not scheme or not allowed[scheme:lower()] then
    vim.notify(('blocked: refusing to open %q (only http/https/mailto)'):format(tostring(path)), vim.log.levels.WARN)
    return nil, 'blocked scheme'
  end
  if vim.g.untrusted then
    local answer = vim.fn.confirm('Open ' .. path .. ' ?', '&Yes\n&No', 2)
    if answer ~= 1 then return nil, 'cancelled' end
  end
  return orig_open(path, opt)
end
