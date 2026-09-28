-- Security regression tests (see SECURITY.md).
-- Run: NVIM_APPNAME=nvim-test nvim --headless -i NONE -c 'luafile tests/security_spec.lua'
-- Child Neovims run in a throwaway HOME: config = this repo (symlink named
-- after the profile), data dir empty (no plugins), NVIM_OFFLINE=1 (no clone).
---@diagnostic disable: duplicate-set-field (APIs are stubbed on purpose)
local T = dofile('tests/helpers.lua')

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
local appname = vim.env.NVIM_APPNAME or 'nvim'

local function write(path, text, mode)
  local f = assert(io.open(path, 'w'))
  f:write(text)
  f:close()
  if mode then vim.uv.fs_chmod(path, mode) end
end

--- A fake executable that only records that it ran (marker file in $MARKER_DIR).
local function fake_bin(dir, name)
  vim.fn.mkdir(dir, 'p')
  write(dir .. '/' .. name, '#!/bin/sh\n: > "$MARKER_DIR/' .. name .. '"\nexit 1\n', tonumber('755', 8))
end

--- Start a child Neovim; probe is Lua whose returned table comes back decoded.
--- opts: name, probe, appname?, cwd?, env?, args?
local function child(opts)
  local home = tmp .. '/home-' .. opts.name
  local config = home .. '/.config'
  local link = config .. '/' .. (opts.appname or appname)
  vim.fn.mkdir(config, 'p')
  vim.uv.fs_symlink(T.repo .. '/nvim', link)
  local script = home .. '/probe.lua'
  write(
    script,
    'local ok, res = pcall(function()\n'
      .. opts.probe
      .. '\nend)\n'
      .. "io.stdout:write('PROBE' .. vim.json.encode(ok and res or { error = tostring(res) }) .. '\\n')\n"
      .. "vim.cmd('qa!')\n"
  )
  local env = {
    HOME = home,
    PATH = vim.env.PATH,
    TMPDIR = tmp,
    XDG_CONFIG_HOME = config,
    NVIM_APPNAME = opts.appname or appname,
    NVIM_OFFLINE = '1',
  }
  for k, v in pairs(opts.env or {}) do
    env[k] = v
  end
  local argv = { vim.v.progpath, '--headless', '-i', 'NONE', '-n' }
  vim.list_extend(argv, opts.args or {})
  vim.list_extend(argv, { '-c', 'luafile ' .. vim.fn.fnameescape(script) })
  local res = vim.system(argv, { cwd = opts.cwd or home, env = env, clear_env = true, text = true }):wait(30000)
  vim.uv.fs_unlink(link) -- cleanup must never walk into the repo
  local json = (res.stdout or ''):match('PROBE([^\n]*)')
  local ok, data = pcall(vim.json.decode, json or '')
  return ok and data or {}, res
end

local function started(r, res, what)
  T.ok(res.code == 0, what .. ': child exited 0', ('code %s, stderr: %s'):format(res.code, res.stderr))
  T.ok(r.error == nil, what .. ': probe ran without error', r.error)
end

-- (a) ---------------------------------------------------------------------
T.it('(a) hostile cwd: planted modules never run', function()
  local markers = tmp .. '/markers-a'
  vim.fn.mkdir(markers, 'p')
  fake_bin(tmp .. '/bin-a', 'git') -- any git call at startup would leave a marker
  local r, res = child({
    name = 'a',
    cwd = T.fixtures .. '/hostile_cwd',
    env = {
      HOSTILE_MARKER_DIR = markers,
      MARKER_DIR = markers,
      PATH = tmp .. '/bin-a:' .. vim.env.PATH,
    },
    probe = [[
      vim.cmd('silent! edit notes.md')
      vim.cmd('silent! Doctor')
      vim.wait(200)
      local function has_cwd(p)
        for entry in p:gmatch('[^;]+') do
          if entry:match('^%./') then return true end
        end
        return false
      end
      vim.cmd('silent! wincmd p')
      return {
        cwd_on_path = has_cwd(package.path) or has_cwd(package.cpath),
        messages = vim.api.nvim_exec2('messages', { output = true }).output,
        tabstop = vim.bo.tabstop,
        name = vim.fn.expand('%:t'),
      }
    ]],
  })
  started(r, res, '(a)')
  T.eq(vim.fn.readdir(markers), {}, '(a) no planted file ran and no git command started')
  T.eq(r.cwd_on_path, false, '(a) package.path/cpath have no ./ entries')
  T.ok(not (r.messages or ''):find('E%d+:'), '(a) no E-number errors at startup', r.messages)
  T.eq(r.name, 'notes.md', '(a) the fixture note was opened')
  T.ok(r.tabstop ~= 13, '(a) modeline in the note was ignored', r.tabstop)
end)

-- (b) ---------------------------------------------------------------------
T.it('(b) untrusted profile (nvu)', function()
  local r, res = child({
    name = 'b',
    appname = 'nvim-untrusted',
    probe = [[
      local out = { globals = {}, groups = {} }
      for _, g in ipairs({ 'loaded_zipPlugin', 'loaded_zip', 'loaded_tarPlugin', 'loaded_tar',
                           'loaded_gzip', 'loaded_netrwPlugin', 'loaded_netrw' }) do
        out.globals[g] = vim.g[g] ~= nil
      end
      out.modeline = vim.o.modeline
      out.editorconfig = vim.g.editorconfig
      out.taskcycle = vim.fn.exists(':TaskCycle')
      out.json = vim.fn.exists(':Json')
      for _, au in ipairs(vim.api.nvim_get_autocmds({})) do
        if au.group_name and au.group_name:find('^sahin') then out.groups[au.group_name] = true end
      end
      vim.cmd('enew')
      vim.bo.buftype = 'nofile'
      vim.bo.filetype = 'markdown'
      out.cr = vim.fn.maparg('<CR>', 'n') .. vim.fn.maparg('<CR>', 'x')
      -- Never call vim.pack.get() here: it would install the lockfile plugins.
      out.pack_dirs = vim.fn.glob(vim.fn.stdpath('data') .. '/site/pack/*/opt/*', false, true)
      out.rtp_has_pack = vim.o.runtimepath:find('pack/core/opt', 1, true) ~= nil
      out.pack_loaded = package.loaded['sahin.pack'] ~= nil
      out.doctor = require('sahin.doctor').report()[1]
      return out
    ]],
  })
  started(r, res, '(b)')
  T.eq(r.modeline, false, '(b) modeline off')
  for g, isset in pairs(r.globals or {}) do
    T.ok(isset, '(b) g:' .. g .. ' set')
  end
  T.eq(vim.tbl_count(r.globals or {}), 7, '(b) all 7 loaded_ globals checked')
  T.eq(r.editorconfig, false, '(b) editorconfig off')
  T.eq(r.taskcycle, 0, '(b) no :TaskCycle')
  T.eq(r.json, 2, '(b) :Json exists')
  for group in pairs(r.groups or {}) do
    T.ok(group == 'sahin.options' or group == 'sahin.security', '(b) only core augroups: ' .. group)
  end
  T.eq(r.cr, '', '(b) markdown <CR> unmapped')
  T.eq(r.pack_dirs, {}, '(b) no plugin installed')
  T.eq(r.rtp_has_pack, false, '(b) no plugin on the runtimepath')
  T.eq(r.pack_loaded, false, '(b) sahin.pack never loaded')
  T.ok((r.doctor or ''):find('UNTRUSTED'), '(b) :Doctor shows the untrusted banner', r.doctor)
end)

-- (c) ---------------------------------------------------------------------
T.it('(c) vim.ui.open only opens http/https/mailto', function()
  local spawned = {}
  local real_system, real_notify = vim.system, vim.notify
  vim.system = function(cmd)
    spawned[#spawned + 1] = cmd
    return { wait = function() return { code = 0 } end }
  end
  vim.notify = function() end
  local ok, err = pcall(function()
    for _, url in ipairs({ 'file:///etc/passwd', 'smb://x', 'javascript:alert(1)', 'FILE:///etc/passwd', '/etc/passwd' }) do
      local obj, e = vim.ui.open(url)
      T.ok(obj == nil and e == 'blocked scheme', '(c) blocked: ' .. url, e)
    end
    -- The stubbed vim.system means nothing is opened for real.
    for _, url in ipairs({ 'https://example.com/?q=$(touch PWNED)', 'mailto:a@example.com' }) do
      local obj, e = vim.ui.open(url, { cmd = { 'open-stub' } })
      T.ok(obj ~= nil and e == nil, '(c) allowed: ' .. url, e)
    end
  end)
  vim.system, vim.notify = real_system, real_notify
  if not ok then error(err) end
  T.eq(#spawned, 2, '(c) only the two allowed URLs reached vim.system')
  T.eq(spawned[1], { 'open-stub', 'https://example.com/?q=$(touch PWNED)' }, '(c) URL is one argv element')
end)

-- (d) ---------------------------------------------------------------------
T.it('(d) inspect helpers: injection strings stay text', function()
  local fx = T.fixtures .. '/inspect/'
  local payloads = vim.fn.readfile(fx .. 'payloads.txt')
  local work = tmp .. '/inject'
  vim.fn.mkdir(work, 'p')
  local old_cwd = vim.fn.getcwd()
  vim.cmd.cd(vim.fn.fnameescape(work))

  -- Any process start fails loudly and is recorded.
  local spawned, notes = {}, {}
  local saved = {
    system = vim.system,
    fsystem = vim.fn.system,
    fsystemlist = vim.fn.systemlist,
    jobstart = vim.fn.jobstart,
    popen = io.popen,
    execute = os.execute,
    notify = vim.notify,
  }
  local function spy(name)
    return function()
      spawned[#spawned + 1] = name
      error('blocked in test: ' .. name)
    end
  end
  vim.system, vim.fn.system, vim.fn.systemlist, vim.fn.jobstart =
    spy('vim.system'), spy('system'), spy('systemlist'), spy('jobstart')
  io.popen, os.execute = spy('io.popen'), spy('os.execute')
  vim.notify = function(msg, level) notes[#notes + 1] = { msg = msg, level = level } end

  local ok, err = pcall(function()
    local inspect = require('sahin.inspect')
    local b
    -- Round trips through every in-place helper, per payload line.
    for _, p in ipairs(payloads) do
      b = T.buf({ p })
      vim.cmd('B64e')
      T.ok(T.lines(b)[1] ~= p, '(d) B64e changed the text: ' .. p)
      vim.cmd('B64d')
      T.eq(T.lines(b), { p }, '(d) B64e+B64d round trip: ' .. p)
      vim.cmd('UrlEncode')
      T.ok(not T.lines(b)[1]:find('[%s$`;|&"]'), '(d) UrlEncode escapes $ ` ; | & " and spaces: ' .. p)
      vim.cmd('UrlDecode')
      T.eq(T.lines(b), { p }, '(d) UrlEncode+UrlDecode round trip: ' .. p)
      vim.cmd('Hex')
      T.ok(#T.lines() >= 1 and vim.bo.filetype == 'xxd', '(d) Hex opened a dump: ' .. p)
      vim.cmd('only!')
    end

    -- Multi-line text survives base64 (newline inside the payload).
    b = T.buf({ payloads[1], payloads[2] })
    vim.cmd('B64e')
    T.eq(#T.lines(b), 1, '(d) B64e of two lines gives one line')
    vim.cmd('B64d')
    T.eq(T.lines(b), { payloads[1], payloads[2] }, '(d) two lines round trip')

    -- JSON: exact pretty-print (key order, big int, escapes kept), then minify back.
    local minified = vim.fn.readfile(fx .. 'payload.json')
    b = T.buf(minified)
    vim.bo[b].shiftwidth = 2
    vim.cmd('Json')
    T.eq(T.lines(b), vim.fn.readfile(fx .. 'payload.pretty.json'), '(d) :Json output matches fixture')
    vim.cmd('JsonMin')
    T.eq(T.lines(b), minified, '(d) :JsonMin restores the original text')

    -- Invalid input: one clear error, buffer unchanged, no traceback.
    b = T.buf({ payloads[1] })
    notes = {}
    vim.cmd('Json')
    T.eq(T.lines(b), { payloads[1] }, '(d) invalid JSON leaves the buffer alone')
    T.ok(#notes == 1 and notes[1].msg:find('^Json: not valid JSON'), '(d) invalid JSON: one clear error', notes[1])
    T.ok(not vim.inspect(notes):find('traceback'), '(d) no traceback')

    -- Binary result: shown as hex dump, buffer unchanged.
    b = T.buf({ vim.base64.encode('\0\1\255 PWNED') })
    local before = T.lines(b)
    notes = {}
    vim.cmd('B64d')
    T.eq(T.lines(b), before, '(d) binary B64d result is not written into the buffer')
    T.ok(vim.bo.filetype == 'xxd', '(d) binary B64d shows a hex dump')
    T.ok(notes[1] and notes[1].level == vim.log.levels.WARN, '(d) binary B64d warns', notes[1])
    vim.cmd('only!')

    -- base64url without padding.
    b = T.buf({ 'JCh0b3VjaCBQV05FRCk_Pz8' })
    vim.cmd('B64d')
    T.eq(T.lines(b), { '$(touch PWNED)???' }, '(d) base64url without padding decodes')

    -- Visual map: exact charwise selection inside a line.
    b = T.buf({ 'id=' .. vim.base64.encode(payloads[3]) .. ' end' })
    vim.api.nvim_win_set_cursor(0, { 1, 3 })
    T.feed('vE<leader>ib')
    T.eq(T.lines(b), { 'id=' .. payloads[3] .. ' end' }, '(d) x-mode <leader>ib decodes only the selection')

    -- JWT whose claims carry the payloads; built here so no token sits in the repo.
    local function b64url(s) return (vim.base64.encode(s):gsub('=+$', ''):gsub('%+', '-'):gsub('/', '_')) end
    local claims = vim.json.encode({ sub = payloads[1], tick = payloads[2], exp = 1700000000 })
    local token = b64url('{"alg":"none","typ":"JWT"}') .. '.' .. b64url(claims) .. '.'
    b = T.buf({ 'Authorization: Bearer ' .. token })
    vim.api.nvim_win_set_cursor(0, { 1, 30 })
    vim.cmd('Jwt')
    local out = table.concat(T.lines(), '\n')
    T.ok(out:find('NOT verified', 1, true), '(d) Jwt says the signature is not verified', out)
    T.ok(out:find(payloads[1], 1, true) and out:find('2023-11-14T22:13:20Z (expired)', 1, true), '(d) Jwt decoded', out)
    vim.cmd('only!')
    T.eq(inspect.find_jwt('no token here'), nil, '(d) find_jwt: nothing to find')
  end)

  vim.system, vim.fn.system, vim.fn.systemlist, vim.fn.jobstart =
    saved.system, saved.fsystem, saved.fsystemlist, saved.jobstart
  io.popen, os.execute, vim.notify = saved.popen, saved.execute, saved.notify
  vim.cmd.cd(vim.fn.fnameescape(old_cwd))
  if not ok then error(err) end
  T.eq(spawned, {}, '(d) no process was started')
  T.eq(vim.fn.readdir(work), {}, '(d) nothing was created in the working directory')
  T.eq(vim.fn.filereadable(T.repo .. '/PWNED'), 0, '(d) no PWNED file in the repo')
end)

-- (e) ---------------------------------------------------------------------
T.it('(e) git never runs a repo-controlled core.fsmonitor', function()
  local n = tonumber(vim.env.GIT_CONFIG_COUNT) or 0
  local found = false
  for i = 0, n - 1 do
    if vim.env['GIT_CONFIG_KEY_' .. i] == 'core.fsmonitor' and vim.env['GIT_CONFIG_VALUE_' .. i] == 'false' then
      found = true
    end
  end
  T.ok(found, '(e) this Neovim has core.fsmonitor=false in GIT_CONFIG_*', n)

  local probe = [[
    local r = vim.system({ 'git', 'config', '--get', 'core.fsmonitor' }, { text = true }):wait(10000)
    local c = vim.system({ 'git', 'config', '--get', 'color.ui' }, { text = true }):wait(10000)
    return {
      count = vim.env.GIT_CONFIG_COUNT,
      k0 = vim.env.GIT_CONFIG_KEY_0, v0 = vim.env.GIT_CONFIG_VALUE_0,
      k1 = vim.env.GIT_CONFIG_KEY_1, v1 = vim.env.GIT_CONFIG_VALUE_1,
      git_fsmonitor = vim.trim(r.stdout or ''), git_color = vim.trim(c.stdout or ''),
    }
  ]]
  local r, res = child({ name = 'e1', probe = probe })
  started(r, res, '(e) clean env')
  T.eq({ r.count, r.k0, r.v0 }, { '1', 'core.fsmonitor', 'false' }, '(e) clean env: entry 0 is core.fsmonitor=false')
  T.eq(r.git_fsmonitor, 'false', '(e) clean env: git itself sees core.fsmonitor=false')

  r, res = child({
    name = 'e2',
    probe = probe,
    env = { GIT_CONFIG_COUNT = '1', GIT_CONFIG_KEY_0 = 'color.ui', GIT_CONFIG_VALUE_0 = 'never' },
  })
  started(r, res, '(e) parent GIT_CONFIG_COUNT=1')
  T.eq({ r.count, r.k0, r.v0, r.k1, r.v1 }, { '2', 'color.ui', 'never', 'core.fsmonitor', 'false' }, '(e) appended')
  T.eq({ r.git_fsmonitor, r.git_color }, { 'false', 'never' }, '(e) git sees both entries')

  r, res = child({
    name = 'e3',
    probe = probe,
    env = { GIT_CONFIG_COUNT = '1', GIT_CONFIG_KEY_0 = 'core.fsmonitor', GIT_CONFIG_VALUE_0 = 'false' },
  })
  started(r, res, '(e) nested Neovim')
  T.eq(r.count, '1', '(e) nested Neovim does not add a duplicate entry')

  r, res = child({
    name = 'e4',
    probe = probe,
    env = { GIT_CONFIG_COUNT = '1', GIT_CONFIG_KEY_0 = 'core.fsMonitor', GIT_CONFIG_VALUE_0 = 'true' },
  })
  started(r, res, '(e) parent sets core.fsMonitor=true')
  T.eq({ r.count, r.git_fsmonitor }, { '2', 'false' }, '(e) a later core.fsmonitor=false overrides it')
end)

-- (f) ---------------------------------------------------------------------
T.it('(f) netrw remote handlers are gone, local browsing stays', function()
  T.ok(not pcall(vim.api.nvim_get_autocmds, { group = 'Network' }), '(f) no netrw Network augroup')
  T.eq(vim.fn.exists('#FileExplorer'), 1, '(f) netrw FileExplorer augroup (local :Explore) still there')

  local markers = tmp .. '/markers-f'
  vim.fn.mkdir(markers, 'p')
  local bin = tmp .. '/bin-f'
  fake_bin(bin, 'scp')
  local env = { MARKER_DIR = markers, PATH = bin .. ':' .. vim.env.PATH }
  -- Control: stock Neovim (--clean) really runs scp for scp:// names.
  local _, res = child({ name = 'f1', args = { '--clean' }, env = env, probe = "vim.cmd('silent! edit scp://x/y')" })
  T.ok(vim.deep_equal(vim.fn.readdir(markers), { 'scp' }), '(f) control: stock netrw runs scp', res.stderr)
  vim.fn.delete(markers .. '/scp')

  -- This config, in a child so netrw's history file lands in its temp HOME.
  local r
  r, res = child({
    name = 'f2',
    env = env,
    probe = [[
      local ok = pcall(vim.cmd, 'silent! edit scp://x/y')
      local out = { edit_ok = ok, name = vim.fn.bufname(), lines = vim.api.nvim_buf_get_lines(0, 0, -1, false) }
      vim.cmd('enew!')
      vim.cmd('Explore ' .. vim.fn.fnameescape(vim.env.HOME))
      out.explore_ft = vim.bo.filetype
      return out
    ]],
  })
  started(r, res, '(f)')
  T.eq(vim.fn.readdir(markers), {}, '(f) :edit scp://x/y started no process')
  T.eq({ r.edit_ok, r.name, r.lines }, { true, 'scp://x/y', { '' } }, '(f) scp://x/y is just an empty buffer')
  T.eq(r.explore_ft, 'netrw', '(f) :Explore still lists a local directory')
end)

-- (g) ---------------------------------------------------------------------
T.it('(g) OSC 52 clipboard is opt-in', function()
  T.eq((vim.g.termfeatures or {}).osc52, false, '(g) OSC 52 terminal auto-detection is off')
  local probe = 'return { provider = tostring(vim.g.clipboard), option = vim.o.clipboard }'
  local ssh = { SSH_TTY = '/dev/pts/9' } -- SSH session, no tmux
  local r, res = child({ name = 'g1', env = ssh, probe = probe })
  started(r, res, '(g) SSH default')
  T.eq({ r.provider, r.option }, { 'nil', '' }, '(g) SSH without vim.g.osc52: no provider, no unnamedplus')
  r, res = child({ name = 'g2', env = ssh, args = { '--cmd', 'let g:osc52 = v:true' }, probe = probe })
  started(r, res, '(g) SSH opt-in')
  T.eq({ r.provider, r.option }, { 'osc52', '' }, '(g) SSH with vim.g.osc52 = true: OSC 52 provider')
end)

-- (h) ---------------------------------------------------------------------
--- In-process LSP server that only answers initialize (with hover) and shutdown.
local function hover_server(dispatchers)
  local closing = false
  local function reply(callback, result)
    vim.schedule(function() callback(nil, result) end)
  end
  return {
    request = function(method, _, callback)
      if method == 'initialize' then reply(callback, { capabilities = { hoverProvider = true } }) end
      if method == 'shutdown' then reply(callback, vim.NIL) end
      return true, 1
    end,
    notify = function(method)
      if method == 'exit' then dispatchers.on_exit(0, 15) end
      return true
    end,
    is_closing = function() return closing end,
    terminate = function() closing = true end,
  }
end

T.it('(h) K never runs pydoc (it imports modules from the cwd)', function()
  -- The hostile clone ships utils.py; app.py says `import utils`.
  for _, app in ipairs({ appname, 'nvim-untrusted' }) do
    local markers = tmp .. '/markers-h-' .. app
    vim.fn.mkdir(markers, 'p')
    local r, res = child({
      name = 'h-' .. app,
      appname = app,
      cwd = T.fixtures .. '/hostile_cwd',
      env = { HOSTILE_MARKER_DIR = markers },
      probe = [[
        local out = { kp = {} }
        for _, ft in ipairs({ 'python', 'pyrex', 'bzl' }) do -- all three use the python ftplugin
          vim.cmd('enew')
          vim.bo.filetype = ft
          out.kp[ft] = vim.bo.keywordprg
        end
        vim.cmd('edit app.py')
        vim.fn.search('^import utils')
        vim.cmd('normal! w')
        out.word = vim.fn.expand('<cword>')
        pcall(vim.cmd.normal, 'K')
        -- An external K program runs in a terminal buffer: let it finish.
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          if vim.bo[b].buftype == 'terminal' then vim.fn.jobwait({ vim.bo[b].channel }, 10000) end
        end
        return out
      ]],
    })
    started(r, res, '(h) ' .. app)
    T.eq(r.word, 'utils', '(h) ' .. app .. ': cursor on the imported name')
    for ft, kp in pairs(r.kp or {}) do
      T.ok(not kp:find('pydoc', 1, true), '(h) ' .. app .. ': ' .. ft .. " 'keywordprg' is not pydoc", kp)
    end
    T.eq(vim.fn.readdir(markers), {}, '(h) ' .. app .. ': K did not import the planted utils.py')
  end

  -- An LSP with hover still gets K: 0.12 maps it only while 'keywordprg' is
  -- empty or a runtime default, which is why it is emptied, not set to :help.
  vim.cmd.edit(vim.fn.fnameescape(tmp .. '/hover.py'))
  local buf = vim.api.nvim_get_current_buf()
  T.eq(vim.bo[buf].keywordprg, '', "(h) python buffer: 'keywordprg' is empty")
  local id = vim.lsp.start({ name = 'hover-stub', cmd = hover_server, root_dir = tmp }, { bufnr = buf })
  local mapped = vim.wait(
    5000,
    function() return vim.fn.maparg('K', 'n', false, true).desc == 'vim.lsp.buf.hover()' end
  )
  T.ok(mapped, '(h) with an LSP attached, K is hover', vim.inspect(vim.fn.maparg('K', 'n', false, true)))
  if id then vim.lsp.get_client_by_id(id):stop(true) end
  vim.cmd('bwipeout!')
end)

-- (i) ---------------------------------------------------------------------
T.it('(i) :Json accepts only RFC 8259 JSON and refuses huge results', function()
  local inspect = require('sahin.inspect')
  -- lua-cjson (vim.json.decode) accepts all of these; strict parsers do not.
  local bad = { '[NaN]', '[-Infinity]', '[inf]', '[0x10]', '[-0x1p3]', '[+1]', '[01]', '[-01]', '[1.]', '[1.e5]' }
  vim.list_extend(bad, { '[-.5]', '["a\tb"]', '["a\nb"]', '[1]\0' })
  for _, text in ipairs(bad) do
    local out, err = inspect.json(text, '  ')
    T.ok(out == nil and (err or ''):find('^not valid JSON'), '(i) refused: ' .. vim.inspect(text), out)
  end
  local good = { '[0]', '[-0]', '[-0.0e-0]', '[1E+5]', '[1.5e-3]', '[123456789012345678901234567890]' }
  vim.list_extend(good, { '["\\u0000\\t"]', '{"a":[true,false,null]}' })
  for _, text in ipairs(good) do
    T.eq(inspect.json(text, ''), text, '(i) accepted: ' .. text)
  end
  -- Nesting close to cjson's limit (1000) puts ~1800 spaces before every
  -- element: 60 kB of input would become 54 MB.
  local deep = ('['):rep(900) .. ('1,'):rep(30000) .. '1' .. (']'):rep(900)
  local out, err = inspect.json(deep, '  ')
  T.ok(out == nil and (err or ''):find('50 MB', 1, true), '(i) a result over 50 MB is refused', out and #out)
  T.ok(inspect.json(deep, '') ~= nil, '(i) minifying the same input still works')
end)

vim.fs.rm(tmp, { recursive = true, force = true })
T.finish('security_spec')
