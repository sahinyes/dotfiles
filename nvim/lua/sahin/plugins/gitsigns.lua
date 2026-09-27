-- Git hunks and blame, only inside roots trusted with :TrustProject.
-- Why: every git command honours the repo's own .git/config, which a hostile
-- clone controls. So gitsigns never attaches on its own (auto_attach=false);
-- this file attaches it to trusted buffers and detaches on :UntrustProject.
local util = require('sahin.util')
local gitsigns = util.try_require('gitsigns.nvim', 'gitsigns')
if not gitsigns then return {} end

local markers = { '.git', '.hg', '.jj' }

--- The trust module, or nil when it is missing or broken (= untrusted).
local function trust()
  local ok, t = pcall(require, 'sahin.trust')
  return ok and type(t) == 'table' and t or nil
end

local function buf_trusted(buf)
  local t = trust()
  if not (t and type(t.buf_trusted) == 'function') then return false end
  local ok, res = pcall(t.buf_trusted, buf)
  return ok and res == true
end

local function dir_trusted(dir)
  local t = trust()
  local root = t and type(t.is_trusted) == 'function' and dir and vim.fs.root(dir, markers)
  root = root and vim.uv.fs_realpath(root)
  if not root then return false end
  local ok, res = pcall(t.is_trusted, root)
  return ok and res == true
end

-- Defence in depth: gitsigns also runs `git rev-parse` for the current
-- directory (branch name) at startup and on :cd, outside any attach.
-- Repo.get_info() is where it discovers a repo, so it answers "not a repo"
-- for untrusted directories and no git process starts there.
local ok_repo, Repo = pcall(require, 'gitsigns.git.repo')
if ok_repo and type(Repo.get_info) == 'function' then
  local get_info = Repo.get_info
  Repo.get_info = function(dir, gitdir, worktree, ...)
    if not dir_trusted(worktree or dir or vim.uv.cwd()) then return nil, 'untrusted directory' end
    return get_info(dir, gitdir, worktree, ...)
  end
else
  util.warn('gitsigns: repo guard not installed (plugin internals changed); review with :PackDiff')
end

-- Buffer maps, created when gitsigns attaches (kickstart's set).
local function hunk_maps()
  local function nav(key, direction)
    return function()
      if vim.wo.diff then
        vim.cmd.normal({ key, bang = true }) -- keep the built-in diff-mode motion
      else
        gitsigns.nav_hunk(direction)
      end
    end
  end
  local function range(action)
    return function() gitsigns[action]({ vim.fn.line('.'), vim.fn.line('v') }) end
  end
  return {
    { 'n', ']c', nav(']c', 'next'), 'Git: next hunk' },
    { 'n', '[c', nav('[c', 'prev'), 'Git: previous hunk' },
    { 'n', '<leader>hs', gitsigns.stage_hunk, 'Git hunk: stage' },
    { 'n', '<leader>hr', gitsigns.reset_hunk, 'Git hunk: reset' },
    { 'x', '<leader>hs', range('stage_hunk'), 'Git hunk: stage selected lines' },
    { 'x', '<leader>hr', range('reset_hunk'), 'Git hunk: reset selected lines' },
    { 'n', '<leader>hS', gitsigns.stage_buffer, 'Git hunk: stage buffer' },
    { 'n', '<leader>hR', gitsigns.reset_buffer, 'Git hunk: reset buffer' },
    { 'n', '<leader>hp', gitsigns.preview_hunk, 'Git hunk: preview' },
    { 'n', '<leader>hb', function() gitsigns.blame_line({ full = true }) end, 'Git hunk: blame line' },
    { 'n', '<leader>hd', gitsigns.diffthis, 'Git hunk: diff against index' },
    { 'n', '<leader>hq', gitsigns.setqflist, 'Git hunk: hunks to quickfix' },
    { { 'o', 'x' }, 'ih', gitsigns.select_hunk, 'Git: inner hunk' },
    { 'n', '<leader>tb', gitsigns.toggle_current_line_blame, 'Toggle: git blame of current line' },
  }
end

local function on_attach(buf)
  -- Attaching is async: give up if trust was revoked in the meantime.
  if not buf_trusted(buf) then return false end
  for _, m in ipairs(hunk_maps()) do
    util.map(m[1], m[2], m[3], m[4], { buffer = buf })
  end
  -- mini.clue triggers must be the newest buffer maps (:h MiniClue).
  if _G.MiniClue then _G.MiniClue.ensure_buf_triggers(buf) end
end

local function detach(buf)
  gitsigns.detach(buf)
  for _, m in ipairs(hunk_maps()) do
    pcall(vim.keymap.del, m[1], m[2], { buffer = buf })
  end
end

gitsigns.setup({ auto_attach = false, on_attach = on_attach })

local group = vim.api.nvim_create_augroup('sahin.gitsigns', { clear = true })

vim.api.nvim_create_autocmd('BufReadPost', {
  group = group,
  desc = 'Attach gitsigns in trusted roots only',
  callback = function(ev)
    if buf_trusted(ev.buf) then gitsigns.attach(ev.buf) end
  end,
})

-- :TrustProject / :UntrustProject: follow the change in open buffers.
vim.api.nvim_create_autocmd('User', {
  group = group,
  pattern = 'SahinTrustChanged',
  desc = 'Attach/detach gitsigns when trust changes',
  callback = function(ev)
    local root = type(ev.data) == 'table' and ev.data.root
    if type(root) ~= 'string' then return end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(buf)
      local path = name ~= '' and (vim.uv.fs_realpath(name) or name)
      if vim.api.nvim_buf_is_loaded(buf) and path and vim.fs.relpath(root, path) then
        if buf_trusted(buf) then
          gitsigns.attach(buf)
        else
          detach(buf)
        end
      end
    end
  end,
})

return {}
