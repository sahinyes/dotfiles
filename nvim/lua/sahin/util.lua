-- Small shared helpers.
local M = {}

M.opt_dir = vim.fn.stdpath('data') .. '/site/pack/core/opt/'

--- True when a vim.pack plugin directory exists on disk.
function M.has_plugin(name) return vim.uv.fs_stat(M.opt_dir .. name) ~= nil end

--- Load a plugin module only when its directory exists (no cwd fallback).
function M.try_require(plugin_dir, module)
  if not M.has_plugin(plugin_dir) then return nil end
  local ok, mod = pcall(require, module)
  if ok then return mod end
  vim.schedule(function() vim.notify(('%s: %s'):format(module, mod), vim.log.levels.WARN) end)
  return nil
end

function M.warn(msg)
  vim.schedule(function() vim.notify(msg, vim.log.levels.WARN) end)
end

function M.map(mode, lhs, rhs, desc, opts)
  opts = vim.tbl_extend('force', { desc = desc, silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

return M
