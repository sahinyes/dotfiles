-- Files the notes workflow creates: inbox.md (:Capture), daily notes (:Daily),
-- a project's TODO.md (:Todo) and the hot notes on <leader>1..5.
local M = {}

local function notes() return require('sahin.notes') end
local function today() return os.date('%Y-%m-%d') end

local function front_matter(project)
  return { '---', 'project: ' .. project, 'tags: [' .. project .. ']', 'date: ' .. today(), '---', '' }
end

-- Written at the top of every new TODO.md so the convention travels with it.
local TODO_HEADER = {
  '<!--',
  'Tasks: - [ ] open  - [!] important  - [x] done  - [>] deferred',
  'Subtasks: indent 2 spaces. #tag at line end. Dates: due:/done:/added: YYYY-MM-DD',
  "Open tasks: rg -n '^\\s*- \\[[ !]\\]'",
  '-->',
  '',
  '## Tasks',
  '',
}

--- Create `path` with `lines` (mkdir -p first) unless it exists. True if created.
local function ensure(path, lines)
  if vim.uv.fs_stat(path) then return false end
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  vim.fn.writefile(lines, path)
  return true
end

local function edit(path) vim.cmd('edit ' .. vim.fn.fnameescape(path)) end

local function loaded_buf(path)
  local real = vim.uv.fs_realpath(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.api.nvim_buf_is_loaded(buf) and name ~= '' and vim.uv.fs_realpath(name) == real then return buf end
  end
end

--- Append '- [ ] <text> added:<date>' to <notes>/inbox.md.
function M.capture(text)
  text = vim.trim(text or '')
  if text == '' then return end
  local path = vim.fs.joinpath(notes().dir(), 'inbox.md')
  local header = front_matter('inbox')
  vim.list_extend(header, { '## Inbox', '' })
  ensure(path, header)
  local task = ('- [ ] %s added:%s'):format(text, today())
  local buf = loaded_buf(path)
  if buf then
    -- The inbox is open: edit the buffer so the change is not lost on reload.
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { task })
    vim.api.nvim_buf_call(buf, function() vim.cmd('silent update') end)
  else
    local lines = vim.fn.readfile(path)
    lines[#lines + 1] = task
    vim.fn.writefile(lines, path)
    notes().changed(path)
  end
  vim.notify('Captured to ' .. path)
end

--- Open (and create from a template) <notes>/daily/YYYY-MM-DD.md.
function M.daily()
  local date = today()
  local path = vim.fs.joinpath(notes().dir(), 'daily', date .. '.md')
  local lines = front_matter('daily')
  vim.list_extend(lines, { '# ' .. date, '', '## Tasks', '', '## Notes', '' })
  local created = ensure(path, lines)
  edit(path)
  if created then
    notes().changed(path)
    vim.fn.search('^## Tasks', 'cw')
  end
end

--- Open TODO.md at the git root (outside git: in the cwd, and say so).
function M.todo()
  local root = vim.fs.root(0, '.git')
  if not root then
    root = vim.uv.cwd()
    vim.notify('Not in a git repo: using TODO.md in ' .. root)
  end
  local path = vim.fs.joinpath(root, 'TODO.md')
  ensure(path, TODO_HEADER)
  edit(path)
end

local HOT_HELP =
  "Hot note %d is not set. Add it to nvim/lua/local.lua, e.g.\n  vim.g.hot_notes = { '~/notes/inbox.md' }"

--- Open vim.g.hot_notes[i] (set in nvim/lua/local.lua).
function M.hot(i)
  local path = (vim.g.hot_notes or {})[i]
  if type(path) ~= 'string' or path == '' then
    vim.notify(HOT_HELP:format(i))
    return
  end
  edit(vim.fs.normalize(path))
end

return M
