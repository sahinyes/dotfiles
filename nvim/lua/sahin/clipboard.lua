-- System clipboard: pick the provider explicitly so :Doctor can explain it.
--   SSH without tmux -> OSC 52 only when vim.g.osc52 = true (lua/local.lua).
--     A terminal that accepts OSC 52 lets any program printing to it (curl,
--     cat of a hostile file) replace your clipboard, so it stays off by default.
--   local tool       -> 'clipboard=unnamedplus' (pbcopy, wl-copy or xclip)
--   tmux, no tool    -> tmux buffers; use "+y / <leader>y explicitly
-- The untrusted profile (nvu) does not apply this and keeps Neovim's own
-- detection (minus OSC 52, see security.lua).
local M = {}

local function set(value) return value ~= nil and value ~= '' end
local function exe(bin) return vim.fn.executable(bin) == 1 end

--- The tool Neovim's built-in detection would pick for this session, or nil.
local function local_tool()
  if vim.fn.has('mac') == 1 then return exe('pbcopy') and 'pbcopy' or nil end
  if set(vim.env.WAYLAND_DISPLAY) and exe('wl-copy') and exe('wl-paste') then return 'wl-copy' end
  if set(vim.env.DISPLAY) and exe('xclip') then return 'xclip' end
  return nil
end

--- Decide from the current environment and vim.g settings (read at call time).
--- @return string name 'osc52'|'pbcopy'|'wl-copy'|'xclip'|'tmux'|'none'
--- @return string why
function M.decide()
  local ssh, tmux = set(vim.env.SSH_TTY), set(vim.env.TMUX)
  if ssh and not tmux then
    if vim.g.osc52 == true then return 'osc52', 'SSH session, vim.g.osc52 = true' end
    return 'none', 'SSH session without tmux and OSC 52 is off (opt in: vim.g.osc52 = true in lua/local.lua)'
  end
  local tool = local_tool()
  if tool then return tool, 'clipboard=unnamedplus: every yank/delete also goes to the system clipboard' end
  if tmux and exe('tmux') then return 'tmux', 'no system clipboard tool; "+y / <leader>y copy to a tmux buffer' end
  return 'none', 'no clipboard tool found (install pbcopy, wl-copy or xclip)'
end

--- Apply the decision. Returns the provider name.
function M.apply()
  local name, why = M.decide()
  if name == 'osc52' or name == 'tmux' then
    vim.g.clipboard = name -- built-in providers accept these names (:h g:clipboard)
  elseif name ~= 'none' then
    vim.o.clipboard = 'unnamedplus'
  end
  M.applied = { name = name, why = why }
  return name
end

--- One line for :Doctor: the provider Neovim really uses, and why.
function M.provider()
  local ok, actual = pcall(vim.fn['provider#clipboard#Executable'])
  actual = (ok and actual ~= '') and actual or 'none'
  if not M.applied then return actual .. " (Neovim's built-in detection; sahin.clipboard not applied)" end
  return ('%s (%s)'):format(actual, M.applied.why)
end

if not vim.g.untrusted then M.apply() end

return M
