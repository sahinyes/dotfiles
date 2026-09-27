-- LSP trust gate: silent deny, grant/revoke, nested roots, the notes
-- allow-list, never_trust_globs, SahinTrustChanged, editorconfig, and the
-- yamlls/jsonls schema beacon. Needs marksman, lua-language-server and
-- yaml-language-server on PATH; missing ones are reported as SKIP.
--   NVIM_APPNAME=nvim-test nvim --headless -i NONE -c 'luafile tests/trust_spec.lua'
local T = dofile('tests/helpers.lua')
local trust = require('sahin.trust')

vim.o.swapfile = false
local out = io.stdout
local function skip(msg) out:write('[trust_spec] SKIP ' .. msg .. '\n') end

-- Everything lives in one temp dir; trust entries are removed at the end.
local base = vim.fn.tempname() .. '-trust'
vim.fn.mkdir(base, 'p')
local tmp = assert(vim.uv.fs_realpath(base))
local db = vim.fn.stdpath('state') .. '/trust'
local db_existed = vim.uv.fs_stat(db) ~= nil
local saved = { notes_dir = vim.g.notes_dir, never = vim.g.never_trust_globs }
vim.g.notes_dir = tmp .. '/notes'
vim.g.never_trust_globs = {} -- CI temp dirs live under /tmp; globs get their own test

local events, trusted_roots = {}, {}
vim.api.nvim_create_autocmd('User', {
  pattern = 'SahinTrustChanged',
  callback = function(ev)
    events[#events + 1] = ev.data
    if ev.data.trusted then trusted_roots[#trusted_roots + 1] = ev.data.root end
  end,
})

local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local f = assert(io.open(path, 'w'))
  f:write(text)
  f:close()
  return path
end

local function fixture(name, port)
  local f = assert(io.open(T.fixtures .. '/trust/' .. name))
  local text = f:read('a'):gsub('__PORT__', tostring(port or 0))
  f:close()
  return text
end

local function repo(name)
  local dir = tmp .. '/' .. name
  vim.fn.mkdir(dir, 'p')
  if vim.fn.executable('git') == 1 then
    vim.system({ 'git', 'init', '-q', dir }):wait()
  else
    vim.fn.mkdir(dir .. '/.git', 'p')
  end
  return dir
end

local function grant(dir, opts) return trust.grant(dir, vim.tbl_extend('force', { silent = true }, opts or {})) end

local function open(path)
  vim.cmd.edit(vim.fn.fnameescape(path))
  return vim.api.nvim_get_current_buf()
end

local function clients(buf, name) return vim.lsp.get_clients({ bufnr = buf, name = name }) end

local function attaches(buf, name, ms)
  return vim.wait(ms or 15000, function() return #clients(buf, name) > 0 end, 50)
end

local function stays_detached(buf, name, ms)
  vim.wait(ms or 1500, function() return #clients(buf, name) > 0 end, 50)
  return #clients(buf, name) == 0
end

-- Does the gated root_dir hand a root to Neovim for this buffer?
local function calls_on_dir(name, buf)
  local called = false
  vim.lsp.config[name].root_dir(buf, function() called = true end)
  return called
end

local function last_event() return events[#events] or {} end

local has = {
  marksman = vim.lsp.is_enabled('marksman'),
  lua_ls = vim.lsp.is_enabled('lua_ls'),
  yamlls = vim.lsp.is_enabled('yamlls'),
  jsonls = vim.lsp.is_enabled('jsonls'),
  ruff = vim.lsp.is_enabled('ruff'),
}

T.it('servers are enabled only when their binary is on PATH, with a bare cmd', function()
  for _, name in ipairs(require('sahin.lsp').servers) do
    local cmd = vim.lsp.config[name].cmd
    T.ok(type(cmd) == 'table' and not cmd[1]:find('/'), name .. ': cmd is a bare PATH name', vim.inspect(cmd))
    T.eq(vim.lsp.is_enabled(name), vim.fn.executable(cmd[1]) == 1, name .. ': enabled iff executable')
  end
  local yaml = vim.lsp.config.yamlls
  T.eq(yaml.settings.yaml.schemaStore.enable, false, 'yamlls: SchemaStore off')
  T.eq(yaml.settings.http.proxy, 'http://127.0.0.1:9', 'yamlls: proxy kill-switch')
  T.eq(yaml.cmd_env.HTTPS_PROXY, 'http://127.0.0.1:9', 'yamlls: env kill-switch')
  for uri in pairs(yaml.settings.yaml.schemas) do
    T.ok(
      vim.startswith(uri, 'file://') and vim.uv.fs_stat(vim.uri_to_fname(uri)) ~= nil,
      'yamlls schema is a local file',
      uri
    )
  end
  T.eq(vim.lsp.config.jsonls.init_options.handledSchemaProtocols, { 'file' }, 'jsonls: file:// schemas only')
  T.eq(vim.lsp.config.gopls.cmd_env.GOTOOLCHAIN, 'local', 'gopls: GOTOOLCHAIN=local')
end)

-- 1. Untrusted repo: nothing starts, root_dir never reaches on_dir.
local repo1 = repo('repo1')
write(repo1 .. '/a.md', '# A\n\n[b](b.md)\n')
write(repo1 .. '/b.md', '# B\n')
write(repo1 .. '/top.lua', 'local x = 1\nreturn x\n')
write(repo1 .. '/.editorconfig', 'root = true\n\n[*.txt]\nindent_style = space\nindent_size = 5\n')
write(repo1 .. '/e.txt', 'text\n')
local md = open(repo1 .. '/a.md')
local txt = open(repo1 .. '/e.txt')

T.it('untrusted repo gets no LSP and no editorconfig', function()
  T.eq(trust.key(md), repo1, 'key is the realpath of the VCS root')
  vim.fn.mkdir(repo1 .. '/vendor/.hg', 'p')
  local hg = open(repo1 .. '/vendor/y.md')
  T.eq(trust.key(hg), repo1 .. '/vendor', 'nearest VCS root wins (.hg inside a git repo)')
  vim.cmd.buffer(md)
  T.eq(trust.is_trusted(repo1), false, 'new repo is untrusted')
  T.eq(trust.buf_trusted(md), false, 'buffer is untrusted')
  T.eq(calls_on_dir('marksman', md), false, 'marksman root_dir does not call on_dir')
  T.ok(vim.bo[txt].shiftwidth ~= 5, 'editorconfig not applied before trust')
  if has.marksman then
    T.ok(stays_detached(md, 'marksman'), 'marksman does not attach')
  else
    skip('marksman not installed: attach checks')
  end
end)

-- 2. Grant: event, LSP starts for open buffers, editorconfig applies.
T.it('grant trusts the repo, fires SahinTrustChanged and starts LSP', function()
  local ok, err = grant(repo1)
  T.ok(ok, 'grant succeeds', err)
  T.eq(last_event(), { root = repo1, trusted = true }, 'SahinTrustChanged data on grant')
  T.ok(trust.is_trusted(repo1) and trust.buf_trusted(md), 'repo and buffer trusted')
  T.eq(vim.bo[txt].shiftwidth, 5, 'editorconfig applied to open buffer on grant')
  local new = open(repo1 .. '/new.txt')
  T.eq(vim.bo[new].shiftwidth, 5, 'editorconfig applied to a new file in a trusted root')
  if has.marksman then
    T.ok(attaches(md, 'marksman'), 'marksman attaches after grant')
    local c = clients(md, 'marksman')[1]
    T.eq(c and c.root_dir, repo1, 'marksman root is the trusted key')
    local grd = vim.api.nvim_buf_call(md, function() return vim.fn.maparg('grd', 'n', false, true) end)
    T.ok(grd.buffer == 1 and grd.desc ~= nil, 'LspAttach maps buffer-local grd with desc')
  end
  if has.ruff then
    local py = open(write(repo1 .. '/x.py', 'x = 1\n'))
    T.ok(attaches(py, 'ruff'), 'ruff attaches in trusted repo')
    local c = clients(py, 'ruff')[1]
    T.eq(c and c.server_capabilities.hoverProvider, false, 'ruff hover is off')
  end
end)

-- 3. A nested lua_ls root (own .luarc.json) needs its own trust entry.
local nested = tmp .. '/repo1/nested'
write(nested .. '/.luarc.json', fixture('nested.luarc.json'))
write(nested .. '/x.lua', 'return 1\n')

T.it('nested .luarc.json under a trusted repo gets nothing until trusted', function()
  if not has.lua_ls then return skip('lua-language-server not installed: nested root checks') end
  local top = open(repo1 .. '/top.lua')
  T.ok(attaches(top, 'lua_ls', 20000), 'lua_ls attaches at the trusted repo root (control)')
  local x = open(nested .. '/x.lua')
  T.eq(trust.key(x), repo1, 'nested file is keyed by the trusted repo')
  T.eq(calls_on_dir('lua_ls', x), false, 'lua_ls root_dir refuses the untrusted nested root')
  T.ok(stays_detached(x, 'lua_ls', 2500), 'lua_ls does not attach in the nested dir')
  T.ok(grant(nested), 'nested dir can be trusted explicitly')
  T.ok(attaches(x, 'lua_ls', 20000), 'lua_ls attaches once the nested root is trusted')
  local c = clients(x, 'lua_ls')[1]
  T.eq(c and c.root_dir, nested, 'lua_ls root is the nested dir')
end)

-- 4. Notes dir: keyed by the notes dir (no .git needed), marksman only.
local notes = tmp .. '/notes'
write(notes .. '/inbox.md', '- [ ] task\n')
write(notes .. '/x.lua', 'return 1\n')

T.it('notes dir allows marksman only', function()
  local nmd = open(notes .. '/inbox.md')
  T.eq(trust.key(nmd), notes, 'notes file is keyed by the notes dir')
  T.eq(calls_on_dir('marksman', nmd), false, 'untrusted notes dir: marksman denied')
  T.ok(grant(notes), 'notes dir can be trusted')
  T.eq(trust.allowed(notes, 'marksman'), true, 'notes: marksman allowed')
  T.eq(trust.allowed(notes, 'lua_ls'), false, 'notes: lua_ls denied')
  T.eq(trust.allowed(repo1, 'lua_ls'), true, 'ordinary trusted repo: lua_ls allowed')
  if has.marksman then
    T.ok(attaches(nmd, 'marksman'), 'marksman attaches in the notes dir')
    local c = clients(nmd, 'marksman')[1]
    T.eq(c and c.root_dir, notes, 'marksman root is the notes dir')
  end
  local nlua = open(notes .. '/x.lua')
  T.eq(calls_on_dir('lua_ls', nlua), false, 'notes: lua_ls root_dir does not call on_dir')
  if has.lua_ls then T.ok(stays_detached(nlua, 'lua_ls', 2500), 'notes: lua_ls does not attach') end
end)

T.it('files outside any VCS root get no LSP', function()
  if vim.fs.root(tmp, { { '.git', '.hg', '.jj' } }) then return skip('temp dir is inside a repo') end
  local loose = open(write(tmp .. '/loose/x.md', '# loose\n'))
  T.eq(trust.key(loose), nil, 'no key outside a VCS root')
  T.eq(calls_on_dir('marksman', loose), false, 'marksman denied outside a VCS root')
end)

-- 5. Refusals: never_trust_globs, /, home, control characters.
T.it('never_trust_globs, home and odd paths are refused without force', function()
  local target = tmp .. '/bb/target'
  vim.fn.mkdir(target, 'p')
  vim.g.never_trust_globs = { base .. '/bb/**' } -- unresolved path: the match must still work
  local ok, err = grant(target)
  T.eq(ok, false, 'glob match refused')
  T.ok(err and err:find('never_trust_globs', 1, true), 'error names never_trust_globs', err)
  T.eq(trust.is_trusted(target), false, 'refused dir stays untrusted')
  T.ok(grant(target, { force = true }), 'force overrides the glob')
  T.ok(trust.revoke(target), 'revoke forced dir')
  vim.g.never_trust_globs = nil -- defaults include /tmp/** (a symlink on macOS)
  T.eq((grant('/tmp')), false, 'default globs refuse /tmp')
  vim.g.never_trust_globs = {}
  T.eq((grant('~')), false, 'home directory refused')
  T.eq((grant('/')), false, '/ refused')
  local evil = tmp .. '/evil\ndirectory ' .. tmp
  vim.fn.mkdir(evil, 'p')
  local ok2, err2 = grant(evil, { force = true })
  T.eq(ok2, false, 'path with a newline refused (cannot forge a db line)')
  T.ok(err2 and err2:find('control', 1, true), 'error mentions control characters', err2)
  T.eq((grant(tmp .. '/does-not-exist')), false, 'missing dir refused')
end)

-- 6. :TrustProject asks first; "No" leaves the dir untrusted.
T.it(':TrustProject prompts with root and servers; :UntrustProject revokes', function()
  local dir = repo('cmd')
  local prompts, answer, notes_seen = {}, 2, {}
  vim.fn.confirm = function(msg)
    prompts[#prompts + 1] = msg
    return answer
  end
  local notify = vim.notify
  vim.notify = function(msg) notes_seen[#notes_seen + 1] = msg end
  local ok, err = pcall(function()
    vim.cmd('TrustProject ' .. vim.fn.fnameescape(dir))
    T.eq(trust.is_trusted(dir), false, 'answering No keeps it untrusted')
    T.ok(notes_seen[1] and notes_seen[1]:find('cancelled', 1, true), 'No is reported', notes_seen[1])
    T.ok(prompts[1] and prompts[1]:find(dir, 1, true), 'prompt shows the root', prompts[1])
    if has.marksman then T.ok(prompts[1]:find('marksman', 1, true), 'prompt lists servers', prompts[1]) end
    answer = 1
    vim.cmd('TrustProject ' .. vim.fn.fnameescape(dir))
    T.eq(trust.is_trusted(dir), true, 'answering Yes trusts it')
    vim.cmd('UntrustProject ' .. vim.fn.fnameescape(dir))
    T.eq(trust.is_trusted(dir), false, ':UntrustProject revokes')
  end)
  vim.fn.confirm = nil -- back to the builtin
  vim.notify = notify
  T.ok(ok, 'command flow ran', err)
end)

-- 7. Revoke stops clients rooted under the root (nested ones too).
T.it('revoke stops clients and fires SahinTrustChanged', function()
  local before = vim.tbl_filter(function(c)
    local r = c.root_dir and vim.uv.fs_realpath(c.root_dir)
    return r ~= nil and (r == repo1 or vim.startswith(r, repo1 .. '/'))
  end, vim.lsp.get_clients())
  T.ok(trust.revoke(repo1), 'revoke succeeds')
  T.eq(last_event(), { root = repo1, trusted = false }, 'SahinTrustChanged data on revoke')
  T.eq(trust.buf_trusted(md), false, 'buffer untrusted after revoke')
  if #before == 0 then return skip('no clients were running under repo1') end
  -- Gone from get_clients() means the server process has exited.
  local stopped = vim.wait(10000, function()
    for _, c in ipairs(before) do
      if vim.lsp.get_client_by_id(c.id) then return false end
    end
    return true
  end, 50)
  T.ok(stopped, ('%d client(s) under the root stopped'):format(#before))
  if has.marksman then
    vim.api.nvim_exec_autocmds('FileType', { group = 'nvim.lsp.enable', buffer = md })
    T.ok(stays_detached(md, 'marksman'), 'marksman does not come back after revoke')
  end
end)

-- 8. Schema beacon: a `$schema` URL must never reach the network.
T.it('yamlls/jsonls never fetch remote schemas', function()
  if not (has.yamlls or has.jsonls) then return skip('yaml-language-server and jsonls not installed: beacon') end
  local hits = 0
  local server = assert(vim.uv.new_tcp())
  server:bind('127.0.0.1', 0)
  server:listen(16, function(e)
    if e then return end
    local c = assert(vim.uv.new_tcp())
    server:accept(c)
    hits = hits + 1
    c:close()
  end)
  local port = server:getsockname().port
  local dir = repo('beacon')
  -- A repo-local server binary must never be picked over the PATH one.
  local marker = dir .. '/PWNED'
  for _, bin in ipairs({ 'yaml-language-server', 'vscode-json-language-server', 'tsc' }) do
    local p = write(dir .. '/node_modules/.bin/' .. bin, '#!/bin/sh\ntouch "' .. marker .. '"\n')
    vim.uv.fs_chmod(p, 493) -- 0755
  end
  T.ok(grant(dir), 'beacon repo trusted')
  local bufs = {}
  if has.yamlls then
    for _, f in ipairs({ 'modeline.yaml', 'modeline-https.yaml', 'inline.yaml', 'intellij.yaml' }) do
      bufs[#bufs + 1] = { open(write(dir .. '/' .. f, fixture('beacon/' .. f, port))), 'yamlls' }
    end
    local compose = open(write(dir .. '/compose.yaml', fixture('compose.yaml')))
    T.ok(attaches(compose, 'yamlls'), 'yamlls attaches in trusted repo')
    local found = vim.wait(10000, function()
      for _, d in ipairs(vim.diagnostic.get(compose)) do
        if d.message:find('bogus_key', 1, true) then return true end
      end
      return false
    end, 100)
    T.ok(found, 'vendored compose schema is applied (bogus_key reported)')
  else
    skip('yaml-language-server not installed: yaml beacon')
  end
  if has.jsonls then
    local b = open(write(dir .. '/beacon.json', fixture('beacon/beacon.json', port)))
    bufs[#bufs + 1] = { b, 'jsonls' }
    T.ok(attaches(b, 'jsonls'), 'jsonls attaches in trusted repo')
  else
    skip('vscode-json-language-server not installed: json beacon')
  end
  -- Give the servers time to try: yamlls reports each failed schema load.
  vim.wait(4000, function() return false end, 100)
  T.eq(hits, 0, 'no connection reached the listener')
  T.eq(vim.uv.fs_stat(marker), nil, 'no repo-local server binary was executed')
  local called = false
  vim.lsp.config.tsc.root_dir(open(write(dir .. '/x.ts', 'export {}\n')), function() called = true end)
  T.eq(vim.uv.fs_stat(marker), nil, 'tsc root_dir executes nothing')
  T.ok(called, 'tsc root_dir still finds the project root')
  -- Control: the listener does see a real connection.
  local probe = assert(vim.uv.new_tcp())
  probe:connect('127.0.0.1', port, function() probe:close() end)
  T.ok(vim.wait(3000, function() return hits == 1 end, 20), 'listener works (control connection seen)')
  server:close()
end)

-- Cleanup: revoke every root this suite trusted, stop servers, delete files.
for i = #trusted_roots, 1, -1 do
  pcall(trust.revoke, trusted_roots[i])
end
for _, c in ipairs(vim.lsp.get_clients()) do
  c:stop()
end
vim.wait(5000, function() return #vim.lsp.get_clients() == 0 end, 50)
for _, c in ipairs(vim.lsp.get_clients()) do
  c:stop(true)
end
vim.cmd('silent! %bwipeout!')
local leftover, rest = {}, 0
local f = io.open(db)
if f then
  for line in f:lines() do
    if line:find(tmp, 1, true) or line:find(base, 1, true) then leftover[#leftover + 1] = line end
    rest = rest + 1
  end
  f:close()
end
T.eq(leftover, {}, 'trust db holds no entry from this suite')
if not db_existed and rest == 0 then os.remove(db) end
vim.fn.delete(base, 'rf')
vim.g.notes_dir, vim.g.never_trust_globs = saved.notes_dir, saved.never

T.finish('trust_spec')
