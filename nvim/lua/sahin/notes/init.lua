-- Notes workflow: Markdown task lists in vim.g.notes_dir (default ~/notes)
-- and per-project TODO.md files. Convention: docs/NOTES-CONVENTION.md.
-- Machine-local settings are read when a command runs, never cached.
local tasks = require('sahin.notes.tasks')
local pickers = require('sahin.notes.pickers')
local capture = require('sahin.notes.capture')
local autocommit = require('sahin.notes.autocommit')
local map = require('sahin.util').map

local M = {}

--- The notes directory (absolute, ~ expanded).
function M.dir() return vim.fs.normalize(vim.g.notes_dir or '~/notes') end

-- Resolve symlinks (e.g. /tmp -> /private/tmp) even for files not yet on disk.
local function realpath(path)
  local real = vim.uv.fs_realpath(path)
  if real then return real end
  local parent = vim.uv.fs_realpath(vim.fs.dirname(path))
  return parent and vim.fs.joinpath(parent, vim.fs.basename(path)) or path
end

--- True when `path` is inside the notes directory.
function M.contains(path)
  local dir = vim.uv.fs_realpath(M.dir())
  return dir ~= nil and path ~= '' and vim.startswith(realpath(path), dir .. '/')
end

--- A file in the notes dir changed on disk: commit it if the dir is a git repo.
function M.changed(path)
  local dir = M.dir()
  if M.contains(path) and vim.uv.fs_stat(vim.fs.joinpath(dir, '.git')) then autocommit.schedule(dir) end
end

-- [!] is captured as @markup.list.important (after/queries/markdown_inline).
-- Colorschemes do not define it, so link it again after every :colorscheme.
local function highlight() vim.api.nvim_set_hl(0, '@markup.list.important', { link = 'DiagnosticError' }) end
highlight()

local group = vim.api.nvim_create_augroup('sahin.notes', { clear = true })
vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = highlight })

-- Auto-save notes when leaving the buffer or the terminal window.
vim.api.nvim_create_autocmd({ 'BufLeave', 'FocusLost' }, {
  group = group,
  callback = function(ev)
    local buf = ev.buf
    if vim.bo[buf].buftype == '' and vim.bo[buf].modified and M.contains(vim.api.nvim_buf_get_name(buf)) then
      vim.api.nvim_buf_call(buf, function() vim.cmd('silent! update') end)
    end
  end,
})
vim.api.nvim_create_autocmd('BufWritePost', {
  group = group,
  callback = function(ev) M.changed(vim.api.nvim_buf_get_name(ev.buf)) end,
})
vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = autocommit.flush })

-- Commands
local command = vim.api.nvim_create_user_command
command('TaskCycle', function(a) tasks.cycle(a.line1, a.line2) end, {
  range = true,
  desc = 'Task: [ ] -> [!] -> [x] -> [ ]; plain lines become tasks',
})
command('TaskDone', function(a) tasks.done(a.line1, a.line2) end, {
  range = true,
  desc = 'Task: mark [x] and add done:<date>',
})
local MARKS = { ['!'] = '!', ['>'] = '>', space = ' ', [''] = ' ' }
command('TaskMark', function(a)
  local state = MARKS[a.args]
  if not state then
    vim.notify(':TaskMark expects !, > or space', vim.log.levels.ERROR)
    return
  end
  tasks.mark(a.line1, a.line2, state)
end, {
  range = true,
  nargs = '?',
  complete = function() return { '!', '>', 'space' } end,
  desc = 'Task: set state [!] important, [>] deferred or [ ] (space)',
})
command('TaskArchive', tasks.archive, { desc = 'Task: move finished task trees under ## Done' })
command('Tasks', function(a) pickers.tasks(a.args) end, {
  nargs = '?',
  complete = function() return { 'open', 'important' } end,
  desc = 'Tasks from notes + TODO.md into quickfix',
})
command('Capture', function(a)
  if a.args ~= '' then return capture.capture(a.args) end
  vim.ui.input({ prompt = 'Capture task: ' }, function(text) capture.capture(text) end)
end, { nargs = '*', desc = 'Append a task to <notes>/inbox.md' })
command('Daily', capture.daily, { desc = "Open today's daily note" })
command('Todo', capture.todo, { desc = 'Open TODO.md at the git root' })

-- Keymaps (<leader>n = Notes)
map({ 'n', 'x' }, '<leader>nx', ':TaskCycle<CR>', 'Notes: cycle task state')
map({ 'n', 'x' }, '<leader>nD', ':TaskDone<CR>', 'Notes: task done (+done: date)')
map({ 'n', 'x' }, '<leader>n!', ':TaskMark !<CR>', 'Notes: mark task important [!]')
map({ 'n', 'x' }, '<leader>nz', ':TaskMark ><CR>', 'Notes: defer task [>]')
map('n', '<leader>na', '<Cmd>TaskArchive<CR>', 'Notes: archive done task trees')
map('n', '<leader>no', '<Cmd>Tasks open<CR>', 'Notes: open tasks -> quickfix')
map('n', '<leader>ni', '<Cmd>Tasks important<CR>', 'Notes: important tasks -> quickfix')
map('n', '<leader>ns', pickers.search_tasks, 'Notes: search open tasks')
map('n', '<leader>nc', '<Cmd>Capture<CR>', 'Notes: capture task to inbox')
map('n', '<leader>nd', '<Cmd>Daily<CR>', "Notes: today's daily note")
map('n', '<leader>nt', '<Cmd>Todo<CR>', "Notes: project's TODO.md")
map('n', '<leader>nn', pickers.find_notes, 'Notes: find note')
map('n', '<leader>ng', pickers.grep_notes, 'Notes: grep notes')
for i = 1, 5 do
  map('n', '<leader>' .. i, function() capture.hot(i) end, 'Notes: hot note ' .. i)
end

return M
