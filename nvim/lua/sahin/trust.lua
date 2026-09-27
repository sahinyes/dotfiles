-- LSP trust gate. See SECURITY.md.
--
-- Policy: silent deny. A language server starts only for files inside a
-- directory you trusted with :TrustProject. Nothing prompts when a file opens,
-- so opening a hostile clone never runs its language tooling.
--
-- Storage: Neovim's own trust database (vim.secure, stdpath('state')/trust).
-- It stores directories by name as "directory <path>" lines.
local M = {}

-- Equal priority (nested list), so the NEAREST repo wins: a .jj/.hg repo
-- inside a git repo gets its own key instead of inheriting the outer one.
local VCS = { { '.git', '.hg', '.jj' } }
local DEFAULT_NEVER = { '~/Downloads/**', '~/bb/**', '~/CTF-Lab/**', '~/targets/**', '/tmp/**' }

local servers = {} -- names passed to setup(), shown by :TrustProject
local wrapped = {} -- server name -> true once its root_dir is gated

local function realpath(p)
  if type(p) ~= 'string' or p == '' then return nil end
  return vim.uv.fs_realpath(vim.fs.normalize(p))
end

local function under(path, root) return path == root or vim.startswith(path, root == '/' and '/' or root .. '/') end

local function notes_root() return realpath(vim.g.notes_dir or '~/notes') end

--- Resolved path of a buffer's file (a new file: resolved directory + name).
--- Symlinks are resolved so a link inside a trusted repo cannot borrow its trust.
local function buf_file(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' or name:match('^%a[%w+.-]*://') then return nil end
  local real = vim.uv.fs_realpath(name)
  if real then return real end
  local dir = vim.uv.fs_realpath(vim.fs.dirname(name))
  return dir and vim.fs.joinpath(dir, vim.fs.basename(name)) or nil
end

local function read_db()
  local entries = {}
  local f = io.open(vim.fn.stdpath('state') .. '/trust', 'r')
  if not f then return entries end
  for line in f:lines() do
    local hash, path = line:match('^(%S+) (.+)$')
    if hash then entries[path] = hash end
  end
  f:close()
  return entries
end

--- Realpath of the VCS root of a buffer's file, or nil. Files under the
--- notes dir are keyed by the notes dir even when it has no .git.
function M.key(bufnr)
  if bufnr == nil or bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  local file = buf_file(bufnr)
  if not file then return nil end
  local vcs = realpath(vim.fs.root(file, VCS))
  local notes = notes_root()
  if notes and under(file, notes) and (not vcs or #vcs < #notes) then return notes end
  return vcs
end

function M.is_trusted(dir)
  if vim.g.untrusted then return false end
  local root = realpath(dir)
  return root ~= nil and read_db()[root] == 'directory'
end

function M.buf_trusted(bufnr)
  local key = M.key(bufnr)
  return key ~= nil and M.is_trusted(key)
end

--- May server `name` run for trust key `key`? The notes dir allows marksman only.
function M.allowed(key, name)
  if not M.is_trusted(key) then return false end
  if realpath(key) == notes_root() then return name == 'marksman' end
  return true
end

-- Why `root` may not be trusted without force, or nil.
local function refused(root)
  if root == '/' or root == realpath('~') then return root .. ' is / or your home directory' end
  for _, pat in ipairs(vim.g.never_trust_globs or DEFAULT_NEVER) do
    local glob = vim.fs.normalize(pat)
    local candidates = { glob }
    -- Also match the resolved form of the glob's fixed prefix (/tmp is
    -- /private/tmp on macOS) because `root` is a realpath.
    local prefix = glob:match('^([^*?[{]*)/') or ''
    local real_prefix = realpath(prefix)
    if real_prefix and real_prefix ~= prefix then candidates[2] = real_prefix .. glob:sub(#prefix + 1) end
    for _, g in ipairs(candidates) do
      if vim.glob.to_lpeg(g):match(root .. '/') then return ('%s matches never_trust_globs %q'):format(root, pat) end
    end
  end
  return nil
end

local function allowed_servers(root)
  local names = {}
  for _, name in ipairs(servers) do
    if root ~= notes_root() or name == 'marksman' then names[#names + 1] = name end
  end
  return #names > 0 and table.concat(names, ' ') or '(none installed)'
end

local function apply_editorconfig(buf)
  vim.b[buf].editorconfig = true
  local ok, editorconfig = pcall(require, 'editorconfig')
  if ok then editorconfig.config(buf) end
end

-- Stop or detach every client that no longer serves a trusted buffer.
local function stop_clients(root)
  for _, client in ipairs(vim.lsp.get_clients()) do
    local client_root = realpath(client.root_dir)
    if client_root and under(client_root, root) then
      client:stop()
    else
      for _, buf in ipairs(vim.tbl_keys(client.attached_buffers)) do
        local key = M.key(buf)
        if not (key and M.allowed(key, client.name)) then vim.lsp.buf_detach_client(buf, client.id) end
      end
    end
  end
end

local function changed(root, trusted)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local file = vim.api.nvim_buf_is_loaded(buf) and buf_file(buf)
    if file and under(file, root) then
      -- A nested root only counts when the buffer's own key is trusted too.
      local ok = M.buf_trusted(buf)
      if trusted and ok then
        apply_editorconfig(buf)
        -- Re-run only vim.lsp.enable's handler (not ftplugins) so LSP starts.
        if vim.fn.exists('#nvim.lsp.enable#FileType') == 1 then
          vim.api.nvim_exec_autocmds('FileType', { group = 'nvim.lsp.enable', buffer = buf, modeline = false })
        end
      elseif not trusted then
        vim.b[buf].editorconfig = ok
      end
    end
  end
  if not trusted then stop_clients(root) end
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'SahinTrustChanged',
    data = { root = root, trusted = trusted },
    modeline = false,
  })
end

--- Trust exactly `dir` (a realpath is stored). opts.force skips the
--- never-trust check; opts.silent skips the confirmation prompt.
function M.grant(dir, opts)
  opts = opts or {}
  local root = realpath(dir)
  if not root then return false, 'no such directory: ' .. tostring(dir) end
  if vim.fn.isdirectory(root) == 0 then return false, 'not a directory: ' .. root end
  -- The database is line based; a newline in a name could forge an entry.
  if root:find('%c') then return false, 'refusing a path with control characters' end
  if not opts.force then
    local why = refused(root)
    if why then return false, why .. ' (use :TrustProject! to override)' end
  end
  if not opts.silent then
    local msg = ('Trust %s ?\nLSP servers that may start there: %s'):format(root, allowed_servers(root))
    if vim.fn.confirm(msg, '&Yes\n&No', 2) ~= 1 then return false, 'cancelled' end
  end
  local ok, err = vim.secure.trust({ action = 'allow', path = root })
  if not ok then return false, err end
  changed(root, true)
  return true
end

function M.revoke(dir)
  local root = realpath(dir)
  if not root then return false, 'no such directory: ' .. tostring(dir) end
  local ok, err = vim.secure.trust({ action = 'remove', path = root })
  if not ok then return false, err end
  changed(root, false)
  return true
end

--- Gate each server: its root_dir runs only when the buffer's key is trusted
--- and allowed, and a server root that differs from the key (for example a
--- nested .luarc.json) must be trusted on its own. Returns the gated names;
--- only those may be passed to vim.lsp.enable.
function M.setup(names)
  local gated = {}
  for _, name in ipairs(names or {}) do
    local ok, base = pcall(function() return vim.lsp.config[name] end)
    if ok and base and not wrapped[name] then
      wrapped[name] = true
      servers[#servers + 1] = name
      local orig, markers = base.root_dir, base.root_markers
      vim.lsp.config(name, {
        root_dir = function(bufnr, on_dir)
          local key = M.key(bufnr)
          if not (key and M.allowed(key, name)) then return end
          local function guarded(root)
            local r = root and realpath(root) or nil
            if root == nil then r = key end -- no server root found: use the key
            if r and (r == key or M.allowed(r, name)) then on_dir(r) end
          end
          if type(orig) == 'function' then return orig(bufnr, guarded) end
          if type(orig) == 'string' then return guarded(orig) end
          local file = buf_file(bufnr)
          guarded(markers and file and vim.fs.root(file, markers) or nil)
        end,
      })
    end
    if wrapped[name] then gated[#gated + 1] = name end
  end
  return gated
end

-- Default root for the commands: the current file's key, or the cwd's repo
-- when the current buffer has no file.
local function current_root(arg)
  if arg ~= '' then return arg end
  if vim.api.nvim_buf_get_name(0) ~= '' and vim.bo.buftype == '' then return M.key(0) end
  return realpath(vim.fs.root(vim.fn.getcwd(), VCS))
end

vim.api.nvim_create_user_command('TrustProject', function(o)
  local dir = current_root(o.args)
  if not dir then return vim.notify('TrustProject: no VCS root here; pass a directory', vim.log.levels.WARN) end
  local ok, err = M.grant(dir, { force = o.bang })
  if ok then
    vim.notify('Trusted ' .. realpath(dir))
  else
    vim.notify('TrustProject: ' .. err, vim.log.levels.WARN)
  end
end, { bang = true, nargs = '?', complete = 'dir', desc = 'Trust a project root for LSP and gitsigns' })

vim.api.nvim_create_user_command('UntrustProject', function(o)
  local dir = current_root(o.args)
  if not dir then return vim.notify('UntrustProject: no VCS root here; pass a directory', vim.log.levels.WARN) end
  local ok, err = M.revoke(dir)
  if ok then
    vim.notify('Untrusted ' .. realpath(dir))
  else
    vim.notify('UntrustProject: ' .. err, vim.log.levels.WARN)
  end
end, { nargs = '?', complete = 'dir', desc = 'Remove a project root from the trust list' })

-- editorconfig is off globally (security.lua). Turn it on per buffer, before
-- the bundled editorconfig plugin's own BufNewFile/BufRead/BufFilePost handler
-- runs (this autocmd is created during init.lua, before plugin/ scripts load).
vim.api.nvim_create_autocmd({ 'BufReadPre', 'BufNewFile', 'BufFilePost' }, {
  group = vim.api.nvim_create_augroup('sahin.trust', { clear = true }),
  callback = function(ev) vim.b[ev.buf].editorconfig = M.buf_trusted(ev.buf) end,
})

return M
