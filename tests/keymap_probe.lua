-- Keymap probe, loaded by tests/keymaps.lua in a child Neovim:
--   nvim --headless -i NONE --cmd 'luafile tests/keymap_probe.lua'
-- --cmd runs before init.lua, so every map this config creates goes through
-- the wrappers below. Lua maps report sid=-8/lnum=0, so maparg() cannot say
-- who made a map; the caller's source file can. After startup it opens a
-- markdown and a lua file inside a trusted temp git repo (ftplugin, gitsigns
-- and LSP maps), writes JSON to $KEYMAP_PROBE_OUT and quits.
local out_file = assert(vim.env.KEYMAP_PROBE_OUT, 'KEYMAP_PROBE_OUT is not set')

local cfg = vim.fn.stdpath('config')
local roots = { cfg .. '/', (vim.uv.fs_realpath(cfg) or cfg) .. '/' }

--- Path relative to the config dir, or nil for code outside it.
local function in_config(source)
  local path = source:gsub('^@', '')
  for _, root in ipairs(roots) do
    if vim.startswith(path, root) then return path:sub(#root + 1) end
  end
end

local records = {}

--- Record a map when the function calling the wrapped API lives in the config.
local function record(api, mode, lhs, opts, buffer)
  local caller = debug.getinfo(3, 'Sl')
  local rel = caller and in_config(caller.source)
  if not rel then return end
  -- Report the first frame outside the util.map helper.
  local where = rel .. ':' .. caller.currentline
  for level = 4, 20 do
    if not rel:match('sahin/util%.lua$') then break end
    local info = debug.getinfo(level, 'Sl')
    local r = info and in_config(info.source)
    if not r then break end
    rel, where = r, r .. ':' .. info.currentline
  end
  opts = opts or {}
  if buffer == nil then buffer = opts.buffer or opts.buf end
  if buffer == true or buffer == 0 then buffer = vim.api.nvim_get_current_buf() end
  local scope, bufname, ft = 'global', nil, nil
  if buffer then
    scope = buffer
    bufname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buffer), ':t')
    ft = vim.bo[buffer].filetype
  end
  records[#records + 1] = {
    api = api,
    mode = mode,
    lhs = lhs,
    desc = opts.desc,
    scope = scope,
    bufname = bufname,
    filetype = ft,
    where = where,
  }
end

local keymap_set = vim.keymap.set
vim.keymap.set = function(mode, lhs, rhs, opts)
  record('vim.keymap.set', mode, lhs, opts)
  return keymap_set(mode, lhs, rhs, opts)
end

local set_keymap = vim.api.nvim_set_keymap
vim.api.nvim_set_keymap = function(mode, lhs, rhs, opts)
  record('nvim_set_keymap', mode, lhs, opts, false)
  return set_keymap(mode, lhs, rhs, opts)
end

local buf_set_keymap = vim.api.nvim_buf_set_keymap
vim.api.nvim_buf_set_keymap = function(buf, mode, lhs, rhs, opts)
  record('nvim_buf_set_keymap', mode, lhs, opts, buf)
  return buf_set_keymap(buf, mode, lhs, rhs, opts)
end

-- git without the user's global/system config (no signing, no hooks).
local function git(dir, args)
  local cmd = { 'git', '-C', dir, '-c', 'user.name=probe', '-c', 'user.email=probe', '-c', 'commit.gpgsign=false' }
  vim.list_extend(cmd, args)
  return vim.system(cmd, { env = { GIT_CONFIG_GLOBAL = '/dev/null', GIT_CONFIG_NOSYSTEM = '1' } }):wait(10000)
end

local function exercise()
  local info = { trust = false, gitsigns = {}, lsp = {} }
  local repo = vim.uv.fs_realpath(vim.fn.tempname()) or vim.fn.tempname()
  vim.fn.mkdir(repo, 'p')
  vim.fn.writefile({ '# Probe', '', '- [ ] task' }, repo .. '/probe.md')
  vim.fn.writefile({ 'local x = 1', 'return x' }, repo .. '/probe.lua')
  git(repo, { 'init', '-q' })
  git(repo, { 'add', '.' })
  git(repo, { 'commit', '-q', '-m', 'probe' })

  -- Trust the repo (state dir is a temp dir, see tests/keymaps.lua) so
  -- gitsigns and LSP attach and their buffer maps are recorded too.
  local ok, trust = pcall(require, 'sahin.trust')
  if ok and type(trust) == 'table' and type(trust.grant) == 'function' then
    info.trust = pcall(trust.grant, repo, { force = true, silent = true })
  end

  for _, name in ipairs({ 'probe.md', 'probe.lua' }) do
    vim.cmd.edit(vim.fn.fnameescape(repo .. '/' .. name))
    local buf = vim.api.nvim_get_current_buf()
    if info.trust then
      -- gitsigns' on_attach (buffer maps) runs at the end of its async attach.
      info.gitsigns[name] = vim.wait(
        5000,
        function() return vim.fn.maparg('<leader>hs', 'n', false, true).buffer == 1 end,
        50
      )
      info.lsp[name] = vim.wait(3000, function() return #vim.lsp.get_clients({ bufnr = buf }) > 0 end, 50)
    end
  end
  return info
end

vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    vim.schedule(function()
      local ok, info = pcall(exercise)
      local f = assert(io.open(out_file, 'w'))
      f:write(vim.json.encode({ records = records, info = ok and info or { error = tostring(info) } }))
      f:close()
      vim.cmd('qa!')
    end)
  end,
})
