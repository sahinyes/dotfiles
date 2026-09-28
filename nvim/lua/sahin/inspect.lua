-- Bug-bounty inspection helpers (<leader>i). Loaded in the untrusted profile too.
-- Pure Lua: buffer text never reaches a shell or an external program, so
-- payloads like $(cmd), `cmd` or ;rm stay inert text.
--
-- Commands take a range (default: whole buffer) and replace the text in place
-- (one undo step). The visual-mode maps use the exact selection (V and CTRL-V
-- use whole lines). :Hex and :Jwt open a scratch split. When a helper turns
-- text into binary (B64d, UrlDecode) the buffer is left alone and a hex dump
-- is shown instead.
local M = {}

local ERROR, WARN = vim.log.levels.ERROR, vim.log.levels.WARN

local function notify(cmd, msg, level) vim.notify(cmd .. ': ' .. msg, level or ERROR) end

--- True for valid UTF-8 without NUL bytes (overlong forms are not rejected).
function M.is_text(s)
  if s:find('%z') then return false end
  local i = 1
  while true do
    i = s:find('[\128-\255]', i)
    if not i then return true end
    local c = s:byte(i)
    local len = (c >= 0xC2 and c <= 0xDF) and 2 or (c >= 0xE0 and c <= 0xEF) and 3 or (c >= 0xF0 and c <= 0xF4) and 4
    if not len then return false end
    for j = i + 1, i + len - 1 do
      local b = s:byte(j)
      if not b or b < 0x80 or b > 0xBF then return false end
    end
    i = i + len
  end
end

-- JSON ----------------------------------------------------------------------
-- vim.json.decode only validates. Decoding and re-encoding would reorder keys
-- and round big integers (12345678901234567890 becomes 9.2233720368548e+18),
-- so the output is rebuilt token by token from the original text.

--- Split valid JSON into tokens, each keeping its original spelling.
local function json_tokens(s)
  local toks, i = {}, 1
  while true do
    i = s:find('[^ \t\r\n]', i)
    if not i then return toks end
    local c, j = s:sub(i, i), i
    if c == '"' then
      j = i + 1
      while true do
        local q = assert(s:find('["\\]', j))
        if s:sub(q, q) == '"' then
          j = q
          break
        end
        j = q + 2 -- skip the escaped character
      end
    elseif not c:find('[{}%[%],:]') then
      j = (s:find('[ \t\r\n{}%[%],:"]', i) or #s + 1) - 1 -- number, true, false, null
    end
    toks[#toks + 1] = s:sub(i, j)
    i = j + 1
  end
end

--- True for an RFC 8259 number, true, false or null.
local function json_literal(tok)
  if tok == 'true' or tok == 'false' or tok == 'null' then return true end
  local int, rest = tok:match('^%-?(%d+)(.*)$')
  if not int or int:match('^0%d') then return false end -- no leading zeros
  rest = rest:gsub('^%.%d+', '') -- fraction
  rest = rest:gsub('^[eE][+-]?%d+', '') -- exponent
  return rest == ''
end

--- What vim.json.decode (lua-cjson) lets through but RFC 8259 does not:
--- NaN, Infinity, 0x10, +1, 01, 1. and raw control characters in strings.
--- @return string? err
local function json_strict_error(toks)
  for _, t in ipairs(toks) do
    if t:sub(1, 1) == '"' then
      if t:find('[%z\1-\31]') then return 'raw control character (tab, newline, ...) in a string' end
    elseif not t:find('^[{}%[%],:]$') and not json_literal(t) then
      return 'not a JSON number or literal: ' .. vim.inspect(t:sub(1, 40))
    end
  end
end

-- Nesting close to cjson's limit (1000 levels) puts up to 1000 indents before
-- every element, so a small payload could grow to gigabytes.
local MAX_JSON_OUTPUT = 50 * 1024 * 1024

local function json_indent(toks, indent)
  local out, depth, size = {}, 0, 0
  local function add(s)
    out[#out + 1] = s
    size = size + #s
  end
  local function newline() add('\n' .. indent:rep(depth)) end
  for k, t in ipairs(toks) do
    if size > MAX_JSON_OUTPUT then
      return nil, ('result is larger than %d MB (deeply nested?): refused'):format(MAX_JSON_OUTPUT / 1024 / 1024)
    end
    if t == '{' or t == '[' then
      add(t)
      if toks[k + 1] ~= '}' and toks[k + 1] ~= ']' then -- keep {} and [] on one line
        depth = depth + 1
        newline()
      end
    elseif t == '}' or t == ']' then
      if toks[k - 1] ~= '{' and toks[k - 1] ~= '[' then
        depth = depth - 1
        newline()
      end
      add(t)
    elseif t == ',' then
      add(',')
      newline()
    elseif t == ':' then
      add(': ')
    else
      add(t)
    end
  end
  return table.concat(out)
end

--- Pretty-print (indent ~= '') or minify (indent == '') JSON text.
--- @return string? result, string? err
function M.json(text, indent)
  local ok, err = pcall(vim.json.decode, text)
  if not ok then return nil, 'not valid JSON: ' .. tostring(err) end
  local toks = json_tokens(text)
  local strict_err = json_strict_error(toks)
  if strict_err then return nil, 'not valid JSON: ' .. strict_err end
  if indent == '' then return table.concat(toks) end
  return json_indent(toks, indent)
end

-- Base64 / URL --------------------------------------------------------------

--- Decode base64 or base64url; whitespace and missing padding are fine.
--- @return string? result, string? err
function M.b64decode(text)
  local s = text:gsub('%s', ''):gsub('%-', '+'):gsub('_', '/'):gsub('=+$', '')
  if s:find('[^%w+/]') then return nil, 'not base64 (unexpected character)' end
  if #s % 4 == 1 then return nil, 'not base64 (bad length)' end
  local ok, out = pcall(vim.base64.decode, s .. ('='):rep((4 - #s % 4) % 4))
  if not ok then return nil, 'not base64 (' .. tostring(out) .. ')' end
  return out
end

--- Like JavaScript's encodeURIComponent: everything but A-Z a-z 0-9 -_.!~*'().
function M.url_encode(text) return (vim.uri_encode(text, 'rfc2396'):gsub('%%%x%x', string.upper)) end

-- Hex dump / JWT --------------------------------------------------------------

--- xxd-style dump: offset, 16 bytes in groups of two, printable ASCII.
function M.hexdump(bytes)
  local lines = {}
  for off = 0, #bytes - 1, 16 do
    local chunk = bytes:sub(off + 1, off + 16)
    local hex = chunk:gsub('..?', function(pair)
      return pair:gsub('.', function(c) return ('%02x'):format(c:byte()) end) .. ' '
    end)
    lines[#lines + 1] = ('%08x: %-40s %s'):format(off, hex, (chunk:gsub('[^ -~]', '.')))
  end
  return #lines > 0 and lines or { '(empty)' }
end

local JWT = 'eyJ[%w_-]*%.[%w_-]+%.[%w_-]*'

--- The JWT covering byte column col (1-based) of text, else the first one.
function M.find_jwt(text, col)
  local first
  for s, token, e in text:gmatch('()(' .. JWT .. ')()') do
    if col and col >= s and col < e then return token end
    first = first or token
  end
  return first
end

local function jwt_part(part, name)
  local raw, err = M.b64decode(part)
  if not raw then return nil, name .. ' is ' .. err end
  local pretty, jerr = M.json(raw, '  ')
  if not pretty then return nil, name .. ' is ' .. jerr end
  return pretty, vim.json.decode(raw)
end

--- Decoded header and payload as lines. The signature is NOT verified.
--- @return string[]? lines, string? err
function M.jwt(token)
  local h, p, sig = token:match('^([^.]+)%.([^.]+)%.?(.*)$')
  if not h then return nil, 'not a JWT (need header.payload.signature)' end
  local header, herr = jwt_part(h, 'header')
  if not header then return nil, herr end
  local payload, claims = jwt_part(p, 'payload')
  if not payload then return nil, claims end
  local lines = { '// JWT decoded. The signature is NOT verified: anyone can forge these claims.', '// header' }
  vim.list_extend(lines, vim.split(header, '\n', { plain = true }))
  lines[#lines + 1] = '// payload'
  vim.list_extend(lines, vim.split(payload, '\n', { plain = true }))
  local now = os.time()
  for _, claim in ipairs({ 'iat', 'nbf', 'exp' }) do
    local v = type(claims) == 'table' and claims[claim]
    if type(v) == 'number' then
      local ok, date = pcall(os.date, '!%Y-%m-%dT%H:%M:%SZ', v)
      local note = ''
      if claim == 'exp' then note = v < now and ' (expired)' or ' (not expired)' end
      if claim == 'nbf' and v > now then note = ' (not valid yet)' end
      lines[#lines + 1] = ('// %s = %s%s'):format(claim, ok and date or '(out of range)', note)
    end
  end
  lines[#lines + 1] = ('// signature: %d characters, not checked'):format(#sig)
  return lines
end

-- Buffer plumbing -------------------------------------------------------------
-- A region uses 0-based API positions: whole lines [sr, er) or exact text.

local function line_region(l1, l2)
  return { buf = vim.api.nvim_get_current_buf(), sr = l1 - 1, er = l2, linewise = true }
end

--- Region of the current visual selection; leaves visual mode.
local function visual_region()
  local mode = vim.fn.mode()
  local p1, p2 = vim.fn.getpos('v'), vim.fn.getpos('.')
  vim.cmd('normal! \27')
  if mode ~= 'v' then return line_region(math.min(p1[2], p2[2]), math.max(p1[2], p2[2])) end
  local buf = vim.api.nvim_get_current_buf()
  local pos = vim.fn.getregionpos(p1, p2, { type = 'v', eol = true })
  local s, e = pos[1][1], pos[#pos][2]
  local first = vim.api.nvim_buf_get_lines(buf, s[2] - 1, s[2], false)[1]
  local last = vim.api.nvim_buf_get_lines(buf, e[2] - 1, e[2], false)[1]
  -- getregionpos gives 1-based inclusive columns; the end excludes the newline.
  return { buf = buf, sr = s[2] - 1, sc = math.min(s[3] - 1, #first), er = e[2] - 1, ec = math.min(e[3], #last) }
end

local function get_text(r)
  local lines = r.linewise and vim.api.nvim_buf_get_lines(r.buf, r.sr, r.er, false)
    or vim.api.nvim_buf_get_text(r.buf, r.sr, r.sc, r.er, r.ec, {})
  return table.concat(lines, '\n')
end

local function put_text(r, text)
  local new = vim.split(text, '\n', { plain = true })
  if r.linewise then
    if #new > 1 and new[#new] == '' then new[#new] = nil end -- a final newline just ends the last line
    vim.api.nvim_buf_set_lines(r.buf, r.sr, r.er, false, new)
  else
    vim.api.nvim_buf_set_text(r.buf, r.sr, r.sc, r.er, r.ec, new)
  end
end

local function scratch(lines, ft)
  vim.cmd('botright new')
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false
  vim.bo[buf].filetype = ft
  return buf
end

local function json_indent_unit() return vim.bo.expandtab and (' '):rep(vim.fn.shiftwidth()) or '\t' end

-- In-place transforms: text -> result or nil, err.
local transforms = {
  Json = function(text) return M.json(text, json_indent_unit()) end,
  JsonMin = function(text) return M.json(text, '') end,
  B64d = M.b64decode,
  B64e = vim.base64.encode,
  UrlDecode = vim.uri_decode,
  UrlEncode = M.url_encode,
}

local function transform(name, r)
  local input = get_text(r)
  local out, err = transforms[name](input)
  if not out then return notify(name, err) end
  if not M.is_text(out) and M.is_text(input) then
    scratch(M.hexdump(out), 'xxd')
    return notify(name, ('result is binary (%d bytes): hex dump shown, buffer unchanged'):format(#out), WARN)
  end
  if not vim.bo[r.buf].modifiable then
    scratch(vim.split(out, '\n', { plain = true }), vim.bo[r.buf].filetype)
    return notify(name, 'buffer is not modifiable: result shown in a scratch split', vim.log.levels.INFO)
  end
  put_text(r, out)
end

local actions = {
  Hex = function(r) scratch(M.hexdump(get_text(r) .. (r.linewise and '\n' or '')), 'xxd') end,
  Jwt = function(r, col)
    local token = M.find_jwt(get_text(r), col)
    if not token then return notify('Jwt', 'no JWT (eyJ….….…) found') end
    local lines, err = M.jwt(token)
    if not lines then return notify('Jwt', err) end
    scratch(lines, 'jsonc')
  end,
}

--- Run a helper on a region; nil region = whole buffer (Jwt: token under cursor).
--- Errors become one notification, never a traceback.
function M.run(name, r)
  local ok, err = pcall(function()
    local col
    if not r and name == 'Jwt' then
      local row = vim.api.nvim_win_get_cursor(0)[1]
      r, col = line_region(row, row), vim.api.nvim_win_get_cursor(0)[2] + 1
    end
    r = r or line_region(1, vim.api.nvim_buf_line_count(0))
    if actions[name] then return actions[name](r, col) end
    transform(name, r)
  end)
  if not ok then notify(name, tostring(err)) end
end

local helpers = {
  { 'j', 'Json', 'pretty-print JSON' },
  { 'm', 'JsonMin', 'minify JSON' },
  { 'h', 'Hex', 'hex dump (scratch split)' },
  { 'b', 'B64d', 'base64/base64url decode' },
  { 'B', 'B64e', 'base64 encode' },
  { 'u', 'UrlDecode', 'URL decode' },
  { 'U', 'UrlEncode', 'URL encode (component)' },
  { 'w', 'Jwt', 'decode JWT (signature NOT verified)' },
}

local map = require('sahin.util').map
for _, d in ipairs(helpers) do
  local key, name, desc = d[1], d[2], d[3]
  vim.api.nvim_create_user_command(
    name,
    function(o) M.run(name, (name ~= 'Jwt' or o.range > 0) and line_region(o.line1, o.line2) or nil) end,
    { range = '%', desc = 'Inspect: ' .. desc }
  )
  map('n', '<leader>i' .. key, function() M.run(name) end, 'Inspect: ' .. desc)
  map('x', '<leader>i' .. key, function() M.run(name, visual_region()) end, 'Inspect: ' .. desc)
end

-- :DiffTool {left} {right} from the bundled nvim.difftool package, loaded on
-- first use. Only its Lua module is needed: its plugin file would replace this
-- command with one that does not expand ~ in paths.
vim.api.nvim_create_user_command('DiffTool', function(o)
  if #o.fargs ~= 2 then return notify('DiffTool', 'usage: :DiffTool {left} {right} (two files or two directories)') end
  if not package.loaded.difftool then
    vim.g.loaded_difftool = true
    vim.cmd.packadd('nvim.difftool')
  end
  local ok, err = pcall(require('difftool').open, vim.fs.normalize(o.fargs[1]), vim.fs.normalize(o.fargs[2]))
  if not ok then notify('DiffTool', tostring(err)) end
end, { nargs = '*', complete = 'file', desc = 'Diff two files or directories (nvim.difftool)' })
map({ 'n', 'x' }, '<leader>id', ':<C-u>DiffTool ', 'Inspect: DiffTool {left} {right}', { silent = false })

return M
