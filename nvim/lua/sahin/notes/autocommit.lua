-- Auto-commit for the notes repo; used only when <notes>/.git exists.
-- Saves are debounced into one commit. Only one git job runs at a time: a save
-- during a running job sets `pending`, which runs the sequence once more.
-- Never pushes. If a pre-commit hook (gitleaks) blocks the commit, its
-- (already redacted) output is shown as a warning and nothing is committed.
local M = {}

M.delay = 1500 -- ms without saves before a commit

local timer = assert(vim.uv.new_timer())
local state = { dir = nil, waiting = false, running = false, pending = false }

local function warn(msg, output)
  local lines = vim.split(vim.trim(output or ''), '\n')
  -- Keep the notification readable: the last 15 lines are enough.
  local tail = table.concat(lines, '\n', math.max(1, #lines - 14))
  vim.notify(msg .. (tail ~= '' and (':\n' .. tail) or ''), vim.log.levels.WARN)
end

local function git(dir, ...) return { 'git', '-C', dir, ... } end

local function finish()
  state.running = false
  if state.pending then
    state.pending = false
    M.run(state.dir)
  end
end

-- Run argv asynchronously; `on_exit` gets the result on the main loop.
local function spawn(argv, on_exit)
  local ok, err = pcall(vim.system, argv, { text = true, timeout = 60000 }, vim.schedule_wrap(on_exit))
  if not ok then
    warn('Notes auto-commit: cannot run git', tostring(err))
    finish()
  end
end

--- git add -A; commit if anything is staged. Serialized (see top).
function M.run(dir)
  state.dir = dir
  if state.running then
    state.pending = true
    return
  end
  state.running = true
  -- .scratch/ holds pasted tokens and payloads: excluded here as well as in
  -- the repo's .gitignore, so it is never committed.
  spawn(git(dir, 'add', '-A', '--', '.', ':(exclude).scratch'), function(add)
    if add.code ~= 0 then
      warn('Notes auto-commit: git add failed', add.stderr)
      return finish()
    end
    spawn(git(dir, 'diff', '--cached', '--quiet'), function(diff)
      if diff.code == 0 then return finish() end -- nothing staged
      -- --no-gpg-sign: these are local snapshots; a signing prompt per save would block.
      local msg = 'notes: ' .. os.date('%Y-%m-%d %H:%M:%S')
      spawn(git(dir, 'commit', '--quiet', '--no-gpg-sign', '-m', msg), function(commit)
        if commit.code ~= 0 then warn('Notes auto-commit blocked (pre-commit hook?)', commit.stderr) end
        finish()
      end)
    end)
  end)
end

--- Debounce: commit `dir` once no save happened for M.delay ms.
function M.schedule(dir)
  -- `waiting` covers the gap between the timer firing and the scheduled run.
  state.dir, state.waiting = dir, true
  timer:stop()
  timer:start(
    M.delay,
    0,
    vim.schedule_wrap(function()
      state.waiting = false
      M.run(state.dir)
    end)
  )
end

--- True while a commit is waiting or running.
function M.busy() return state.waiting or state.running end

--- Commit now and wait (used on exit so the last save is not left uncommitted).
function M.flush()
  if state.waiting then
    timer:stop()
    state.waiting = false
    M.run(state.dir)
  end
  vim.wait(10000, function() return not M.busy() end, 20)
end

return M
