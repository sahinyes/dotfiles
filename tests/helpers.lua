-- Minimal test harness. Load with: local T = dofile(<repo>/tests/helpers.lua)
-- Run tests with the FULL config (never `nvim -l`, which skips init.lua):
--   nvim --headless -c 'luafile tests/<name>.lua'
local T = { failures = {}, passed = 0 }

local cfg = vim.uv.fs_realpath(vim.fn.stdpath('config')) or vim.fn.stdpath('config')
T.repo = vim.fs.dirname(cfg)
T.fixtures = T.repo .. '/tests/fixtures'

function T.ok(cond, name, detail)
  if cond then
    T.passed = T.passed + 1
  else
    T.failures[#T.failures + 1] = name .. (detail and (': ' .. tostring(detail)) or '')
  end
end

function T.eq(actual, expected, name)
  T.ok(
    vim.deep_equal(actual, expected),
    name,
    ('expected %s, got %s'):format(vim.inspect(expected), vim.inspect(actual))
  )
end

--- Run fn as a named test; errors count as failures.
function T.it(name, fn)
  local ok, err = pcall(fn)
  if not ok then T.failures[#T.failures + 1] = name .. ': ' .. tostring(err) end
end

--- Scratch buffer with lines and filetype; returns bufnr.
function T.buf(lines, ft)
  vim.cmd('enew!')
  local b = vim.api.nvim_get_current_buf()
  vim.bo[b].buftype = 'nofile'
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  if ft then vim.bo[b].filetype = ft end
  return b
end

function T.lines(b) return vim.api.nvim_buf_get_lines(b or 0, 0, -1, false) end

--- Feed keys as if typed (remap on) and process them.
function T.feed(keys) vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'mx', false) end

--- Print results and exit (cquit 1 on failure).
function T.finish(suite)
  local out = io.stdout
  if #T.failures == 0 then
    out:write(('[%s] OK %d passed\n'):format(suite, T.passed))
    vim.cmd('qa!')
  else
    out:write(('[%s] FAIL %d failed, %d passed\n'):format(suite, #T.failures, T.passed))
    for _, f in ipairs(T.failures) do
      out:write('  - ' .. f .. '\n')
    end
    vim.cmd('cquit 1')
  end
end

-- First assertion of every suite: the real config was loaded.
T.ok(vim.g.mapleader == ' ', 'config loaded (mapleader is <Space>)', 'run with -c luafile, not nvim -l')

return T
