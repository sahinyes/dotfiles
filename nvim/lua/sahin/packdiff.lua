-- :PackDiff - read the code a pending plugin update brings in, before :write.
-- vim.pack.update() (<leader>uu) opens a confirm buffer that lists, for every
-- plugin with an update, "Revision before:" and "Revision after:". This runs
-- `git diff before..after` for each of them, limited to the directories Neovim
-- runs code from, in one scratch buffer, and highlights calls that start
-- programs, load code or reach the network.
local M = {}

-- Directories whose files Neovim executes (lsp/ holds nvim-lspconfig's
-- server configs, parser/ holds compiled treesitter parsers).
M.paths = {
  'lua',
  'plugin',
  'ftplugin',
  'ftdetect',
  'after',
  'autoload',
  'lsp',
  'syntax',
  'indent',
  'colors',
  'compiler',
  'parser',
}

-- Plain-text tokens that deserve a close look in added code.
M.risky = {
  'vim.system',
  'io.popen',
  'os.execute',
  'vim.fn.system',
  'jobstart',
  'termopen',
  'uv.spawn',
  'loop.spawn',
  'vim.net',
  'loadstring',
  'dofile',
  'curl',
  'wget',
  'http',
}

local ns = vim.api.nvim_create_namespace('sahin.packdiff')

--- Plugins with a pending update, from the confirm buffer's lines.
--- @param lines string[]
--- @return { name: string, path: string, before: string, after: string }[]
function M.parse(lines)
  local res, cur = {}, nil
  for _, line in ipairs(lines) do
    local name = line:match('^## (.+)$')
    if name then
      cur = { name = (name:gsub(' %(not active%)$', '')) }
    elseif line:match('^# ') then
      cur = nil -- "# Update", "# Same", "# Error" section headers
    elseif cur then
      cur.path = cur.path or line:match('^Path:%s+(.+)$')
      cur.before = cur.before or line:match('^Revision before:%s+(%x+)')
      cur.after = cur.after or line:match('^Revision after:%s+(%x+)')
      if cur.path and cur.before and cur.after then
        res[#res + 1] = cur
        cur = nil
      end
    end
  end
  return res
end

--- The open vim.pack confirm buffer, or nil.
function M.confirm_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf):match('^nvim%-pack://confirm') then
      return buf
    end
  end
end

--- `git diff` of one plugin (argv only, never a shell string).
--- @return string[] lines
local function diff(p)
  local cmd = { 'git', '-C', p.path, 'diff', '--no-color', '--no-ext-diff', '--no-textconv' }
  vim.list_extend(cmd, { p.before .. '..' .. p.after, '--' })
  vim.list_extend(cmd, M.paths)
  local ok, res = pcall(function() return vim.system(cmd, { text = true }):wait(30000) end)
  if not ok then return { '(git failed: ' .. tostring(res) .. ')' } end
  if res.code ~= 0 then return { ('(git exited %d: %s)'):format(res.code, vim.trim(res.stderr or '')) } end
  local out = vim.split(res.stdout or '', '\n', { trimempty = true })
  return #out > 0 and out or { '(no changes in ' .. table.concat(M.paths, ' ') .. ')' }
end

--- Highlight risky tokens; returns how many sit in added lines.
local function mark_risky(buf, first, lines)
  local added = 0
  for i, line in ipairs(lines) do
    for _, token in ipairs(M.risky) do
      local from = 1
      while true do
        local s, e = line:find(token, from, true)
        if not s then break end
        vim.api.nvim_buf_set_extmark(buf, ns, first + i - 1, s - 1, { end_col = e, hl_group = 'PackDiffRisky' })
        if line:match('^%+') and not line:match('^%+%+%+') then added = added + 1 end
        from = e + 1
      end
    end
  end
  return added
end

--- Show the diffs of every pending update in a scratch buffer (vertical split).
function M.open()
  local confirm = M.confirm_buf()
  if not confirm then
    vim.notify(
      'PackDiff: no vim.pack confirm buffer is open. Press <leader>uu (vim.pack.update()) first, '
        .. 'then run :PackDiff (<leader>ud) while it is open.',
      vim.log.levels.WARN
    )
    return
  end
  local plugins = M.parse(vim.api.nvim_buf_get_lines(confirm, 0, -1, false))
  if #plugins == 0 then
    vim.notify('PackDiff: the confirm buffer lists no pending updates.', vim.log.levels.INFO)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_set_hl(0, 'PackDiffRisky', { link = 'ErrorMsg', default = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'PackDiff: code changes of pending plugin updates (' .. table.concat(M.paths, ' ') .. ')',
    'Highlighted: ' .. table.concat(M.risky, ' '),
    'Read every highlighted hit, then :write in the confirm buffer (or :quit it to cancel).',
    '',
  })

  -- One summary line per plugin at the top, its diff further down.
  local summary_row = vim.api.nvim_buf_line_count(buf)
  for i, p in ipairs(plugins) do
    local lines = diff(p)
    local row = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_lines(buf, row, row, false, { '', ('## %s %s..%s'):format(p.name, p.before, p.after) })
    row = row + 2
    vim.api.nvim_buf_set_lines(buf, row, row, false, lines)
    local hits = mark_risky(buf, row, lines)
    local summary = ('%s: %d risky token(s) in added lines'):format(p.name, hits)
    vim.api.nvim_buf_set_lines(buf, summary_row + i - 1, summary_row + i - 1, false, { summary })
  end

  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'diff'
  pcall(vim.api.nvim_buf_set_name, buf, 'packdiff://pending-updates')
  vim.cmd('vertical botright sbuffer ' .. buf)
  return buf
end

return M
