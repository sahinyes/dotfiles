-- Spell languages that are actually installed. install.sh puts de/tr spell
-- files on the runtimepath; 'en' ships with Neovim. Only languages whose .spl
-- file exists are used, so a missing file never raises an error per buffer.
local M = {}

-- 'spelllang' name -> spell file it needs ('de_ch' uses de.utf-8.spl, region ch).
local optional = {
  { lang = 'de_ch', file = 'spell/de.utf-8.spl' },
  { lang = 'tr', file = 'spell/tr.utf-8.spl' },
}

local function installed(file) return #vim.api.nvim_get_runtime_file(file, false) > 0 end

-- Word lists in 'spellfile' (*.add) only take effect once compiled to *.add.spl.
-- *.spl is gitignored, so a fresh clone has only the .add text: compile it once.
local compiled = false
local function compile_wordlists()
  if compiled then return end
  compiled = true
  for _, add in ipairs(vim.opt_global.spellfile:get()) do
    local src = vim.uv.fs_stat(add)
    local spl = vim.uv.fs_stat(add .. '.spl')
    if src and (not spl or spl.mtime.sec < src.mtime.sec) then
      pcall(vim.cmd.mkspell, { args = { add }, bang = true, mods = { silent = true } })
    end
  end
end

--- Languages for 'spelllang': always 'en', plus each optional one on disk.
function M.langs()
  compile_wordlists()
  local langs = { 'en' }
  for _, o in ipairs(optional) do
    if installed(o.file) then langs[#langs + 1] = o.lang end
  end
  return langs
end

--- Optional languages whose spell file is missing (shown by :Doctor).
function M.missing()
  local miss = {}
  for _, o in ipairs(optional) do
    if not installed(o.file) then miss[#miss + 1] = o.lang end
  end
  return miss
end

return M
