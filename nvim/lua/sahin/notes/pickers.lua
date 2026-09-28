-- Finding tasks and notes: :Tasks (quickfix, works without plugins) and
-- telescope pickers. Searched: the notes dir plus TODO.md at the git root of
-- the current buffer (or cwd). Hidden paths such as .scratch/ are skipped.
local M = {}

M.patterns = { -- same regex for ripgrep and Vim
  open = [=[^\s*- \[[ !]\]]=],
  important = [=[^\s*- \[!\]]=],
}

local function notes() return require('sahin.notes') end

--- The project's TODO.md, only if it is a regular file inside the repo. A
--- cloned repo can ship it as a symlink to /dev/zero or /proc/...: reading
--- that never ends and Neovim would hang.
local function project_todo()
  local root = vim.fs.root(0, '.git')
  if not root then return nil end
  local todo = vim.fs.joinpath(root, 'TODO.md')
  local real, real_root = vim.uv.fs_realpath(todo), vim.uv.fs_realpath(root)
  if not (real and real_root and vim.fs.relpath(real_root, real)) then return nil end -- missing or outside
  local stat = vim.uv.fs_stat(real)
  if stat and stat.type == 'file' then return todo end
end

--- Existing search roots: notes dir and the project's TODO.md.
function M.sources()
  local dir = notes().dir()
  local list = {}
  if vim.fn.isdirectory(dir) == 1 then list[1] = dir end
  local todo = project_todo()
  if todo and not notes().contains(todo) then list[#list + 1] = todo end
  return list
end

-- Fallback without ripgrep: scan visible *.md files with the same Vim regex.
local function scan(paths, pattern)
  local re = vim.regex(pattern)
  local files = {}
  for _, path in ipairs(paths) do
    if vim.fn.isdirectory(path) == 1 then
      local found = {}
      local visible = function(rel) return not vim.fs.basename(rel):match('^%.') end
      for rel, kind in vim.fs.dir(path, { depth = math.huge, skip = visible }) do
        if kind == 'file' and rel:match('%.md$') and visible(rel) then
          found[#found + 1] = vim.fs.joinpath(path, rel)
        end
      end
      table.sort(found)
      vim.list_extend(files, found)
    else
      files[#files + 1] = path
    end
  end
  local items = {}
  for _, file in ipairs(files) do
    for lnum, line in ipairs(vim.fn.readfile(file)) do
      local col = re:match_str(line)
      if col then items[#items + 1] = { filename = file, lnum = lnum, col = col + 1, text = line } end
    end
  end
  return items
end

--- :Tasks open|important -> quickfix list.
function M.tasks(kind)
  kind = (kind == nil or kind == '') and 'open' or kind
  local pattern = M.patterns[kind]
  if not pattern then
    vim.notify(':Tasks expects open or important, got ' .. kind, vim.log.levels.ERROR)
    return
  end
  local paths = M.sources()
  if #paths == 0 then
    vim.notify(('No notes dir (%s) and no TODO.md in this repo'):format(notes().dir()), vim.log.levels.WARN)
    return
  end
  local title = 'Tasks: ' .. kind
  if vim.fn.executable('rg') == 1 then
    -- --no-config: a personal ripgreprc must not add --hidden (.scratch/).
    local cmd = { 'rg', '--no-config', '--vimgrep', '--sort', 'path', '--glob', '*.md', '-e', pattern, '--' }
    local res = vim.system(vim.list_extend(cmd, paths), { text = true }):wait(10000)
    -- 1 = no match; 2 = an error (e.g. unreadable file), matches may still follow;
    -- 124 = still running after 10 s, so wait() killed it.
    if res.code == 124 then
      vim.notify('rg: stopped after 10 s, the list may be incomplete', vim.log.levels.WARN)
    elseif res.code > 1 then
      vim.notify('rg: ' .. vim.trim(res.stderr or ''), vim.log.levels.WARN)
    end
    local lines = vim.split(res.stdout or '', '\n', { trimempty = true })
    vim.fn.setqflist({}, ' ', { title = title, lines = lines, efm = '%f:%l:%c:%m' })
  else
    vim.fn.setqflist({}, ' ', { title = title, items = scan(paths, pattern) })
  end
  if #vim.fn.getqflist() == 0 then
    vim.notify('No ' .. kind .. ' tasks')
  else
    vim.cmd('botright copen')
  end
end

local function telescope()
  local ok, builtin = pcall(require, 'telescope.builtin')
  if not ok then vim.notify('telescope.nvim is not installed (run :PackSync)', vim.log.levels.WARN) end
  return ok and builtin or nil
end

-- Skip .scratch/ even if telescope is configured to search hidden files.
local NO_SCRATCH = '--glob=!.scratch'

local function notes_dir()
  local dir = notes().dir()
  if vim.fn.isdirectory(dir) == 1 then return dir end
  vim.notify('Notes dir does not exist yet: ' .. dir .. ' (:Capture or :Daily creates it)', vim.log.levels.WARN)
end

--- <leader>ns: fuzzy search over open tasks.
function M.search_tasks()
  local builtin = telescope()
  if not builtin then return end
  local paths = M.sources()
  if #paths == 0 then
    vim.notify(('No notes dir (%s) and no TODO.md in this repo'):format(notes().dir()), vim.log.levels.WARN)
    return
  end
  builtin.grep_string({
    prompt_title = 'Open tasks',
    search = M.patterns.open,
    use_regex = true,
    search_dirs = paths,
    additional_args = { '--glob=*.md', NO_SCRATCH },
  })
end

--- <leader>nn: find a note file.
function M.find_notes()
  -- Started from `nvim -c` (nn, the iTerm2 hotkey): wait until startup is
  -- done, otherwise Neovim puts the cursor back in the first window and
  -- keys go there instead of the picker's prompt.
  if vim.v.vim_did_enter == 0 then
    vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function() vim.schedule(M.find_notes) end })
    return
  end
  local builtin = telescope()
  local dir = notes_dir()
  if builtin and dir then builtin.find_files({ prompt_title = 'Notes', cwd = dir }) end
end

--- <leader>ng: live grep in notes.
function M.grep_notes()
  local builtin = telescope()
  local dir = notes_dir()
  if builtin and dir then
    builtin.live_grep({ prompt_title = 'Grep notes', cwd = dir, additional_args = { NO_SCRATCH } })
  end
end

return M
