-- Task lines in Markdown notes (see docs/NOTES-CONVENTION.md):
--   - [ ] open   - [!] important   - [x] done   - [>] deferred
-- Subtasks are indented by 2 spaces. The line functions are pure (string in,
-- string out) so they are easy to test; the buffer functions apply them.
local M = {}

local DONE_TOKEN = '%s+done:%d%d%d%d%-%d%d%-%d%d'
local NEXT = { [' '] = '!', ['!'] = 'x', x = ' ', X = ' ' } -- any other state ([>]) -> [ ]

local function today() return os.date('%Y-%m-%d') end

--- Split a task line into prefix ('  - '), state character and the rest.
--- Returns nil when the line is not a task.
function M.parse(line) return line:match('^(%s*[-*+] )%[(.)%](.*)$') end

--- `line` as a task in `state`. Bullets and plain text become tasks; blank
--- lines, headings, rules/front matter (---) and code fences return nil.
function M.with_state(line, state)
  local prefix, _, rest = M.parse(line)
  if not prefix then
    local indent, text = line:match('^(%s*)[-*+]%s+(.*)$') -- '- note'
    if not indent then
      indent, text = line:match('^(%s*)[-*+]%s*$'), '' -- bare '-' left by Enter
    end
    if not indent then
      if line:match('^%s*$') or line:match('^%s*#') or line:match('^%s*[-*_=][-*_=%s]*$') then return nil end
      if line:match('^%s*```') or line:match('^%s*~~~') then return nil end
      indent, text = line:match('^(%s*)(.*)$')
    end
    prefix, rest = indent .. '- ', ' ' .. text
  end
  -- A task that is not done any more loses its done: date.
  if state ~= 'x' then rest = rest:gsub(DONE_TOKEN, '') end
  return prefix .. '[' .. state .. ']' .. rest
end

--- [ ] -> [!] -> [x] -> [ ]; [>] and unknown states go back to [ ].
function M.cycle_line(line)
  local _, state = M.parse(line)
  return M.with_state(line, state and NEXT[state] or ' ')
end

--- [x] plus ' done:YYYY-MM-DD' (added only once).
function M.done_line(line)
  local new = M.with_state(line, 'x')
  if new and not new:find(DONE_TOKEN) then new = new:gsub('%s+$', '') .. ' done:' .. today() end
  return new
end

-- Apply a line function to buffer lines l1..l2 (1-based, inclusive).
local function apply(l1, l2, fn)
  local lines = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
  local changed = false
  for i, line in ipairs(lines) do
    local new = fn(line)
    if new and new ~= line then
      lines[i], changed = new, true
    end
  end
  if changed then vim.api.nvim_buf_set_lines(0, l1 - 1, l2, false, lines) end
end

function M.cycle(l1, l2) apply(l1, l2, M.cycle_line) end
function M.done(l1, l2) apply(l1, l2, M.done_line) end
function M.mark(l1, l2, state)
  apply(l1, l2, function(line) return M.with_state(line, state) end)
end

local function indent(line) return #line:match('^%s*') end
local function is_heading12(line) return line:match('^##?%s') ~= nil end -- '# ' or '## '

-- First '## Done' section: heading line and last line before the next H1/H2.
local function done_section(lines)
  for i, line in ipairs(lines) do
    if line:match('^##%s+Done%s*$') then
      for j = i + 1, #lines do
        if is_heading12(lines[j]) then return i, j - 1 end
      end
      return i, #lines
    end
  end
end

--- Move finished task trees below '## Done' (created at the end if missing).
--- A tree (a list item plus every deeper-indented line after it) moves only
--- when its root and every task inside it are [x]. Nested tasks never move on
--- their own, so a done subtask under an open parent stays where it is.
--- Returns the new lines and the number of trees moved.
function M.archive_lines(lines)
  local n = #lines
  local done_first, done_last = done_section(lines)
  local trees = {} -- { first, last } ranges to move
  local i, in_fence = 1, false
  while i <= n do
    local line = lines[i]
    if i == done_first then
      i = done_last + 1 -- already archived
    elseif line:match('^%s*```') or line:match('^%s*~~~') then
      in_fence, i = not in_fence, i + 1
    elseif in_fence or not line:match('^%s*[-*+]%s') then
      i = i + 1
    else
      local last = i
      for j = i + 1, n do
        if lines[j]:match('%S') then
          if indent(lines[j]) <= indent(line) then break end
          last = j
        end
      end
      local _, root_state = M.parse(line)
      local all_done = root_state == 'x' or root_state == 'X'
      for j = i + 1, last do
        local _, state = M.parse(lines[j])
        if state and state ~= 'x' and state ~= 'X' then all_done = false end
      end
      if all_done then trees[#trees + 1] = { i, last } end
      i = last + 1
    end
  end
  if #trees == 0 then return lines, 0 end

  local keep, moved, t = {}, {}, 1
  for idx, line in ipairs(lines) do
    local tree = trees[t]
    if tree and idx >= tree[1] and idx <= tree[2] then
      moved[#moved + 1] = line
      if idx == tree[2] then t = t + 1 end
    else
      keep[#keep + 1] = line
    end
  end

  -- Insert after the last non-blank line of the Done section.
  local first, last = done_section(keep)
  local at = first
  if first then
    for j = first + 1, last do
      if keep[j]:match('%S') then at = j end
    end
  else
    if #keep > 0 and keep[#keep]:match('%S') then keep[#keep + 1] = '' end
    keep[#keep + 1] = '## Done'
    at = #keep
  end
  for m = #moved, 1, -1 do
    table.insert(keep, at + 1, moved[m])
  end
  return keep, #trees
end

--- :TaskArchive on the current buffer (one undo step).
function M.archive()
  local lines, count = M.archive_lines(vim.api.nvim_buf_get_lines(0, 0, -1, false))
  if count == 0 then
    vim.notify('Nothing to archive: a task tree moves only when all its tasks are [x]')
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { math.min(cursor[1], #lines), 0 })
  vim.notify(('Archived %d task tree(s) under ## Done'):format(count))
end

return M
