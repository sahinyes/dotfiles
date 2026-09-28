-- Plugin layer: modules load, telescope/clue/gitsigns/treesitter/completion
-- and :PackDiff behave as documented. Checks that need a fresh Neovim (real
-- key input, trust changes, missing plugins) run in a child Neovim that
-- executes this same file with $SAHIN_SPEC_CHILD set to a scenario name and
-- writes its observations as JSON to $SAHIN_SPEC_OUT.

--- git without the user's global/system config (no signing, no hooks).
local function git(dir, args)
  local cmd = { 'git', '-C', dir, '-c', 'user.name=spec', '-c', 'user.email=spec', '-c', 'commit.gpgsign=false' }
  vim.list_extend(cmd, args)
  local res =
    vim.system(cmd, { text = true, env = { GIT_CONFIG_GLOBAL = '/dev/null', GIT_CONFIG_NOSYSTEM = '1' } }):wait(10000)
  assert(res.code == 0, ('git %s: %s'):format(table.concat(args, ' '), res.stderr))
  return vim.trim(res.stdout or '')
end

local function feed(keys) vim.api.nvim_feedkeys(vim.keycode(keys), 'mt', false) end

--------------------------------------------------------------------------------
-- Child scenarios
--------------------------------------------------------------------------------
local scenario = vim.env.SAHIN_SPEC_CHILD
if scenario then
  local dir = assert(vim.env.SAHIN_SPEC_DIR)
  local out = {}
  local S = {}

  local function cursor_line() return vim.api.nvim_win_get_cursor(0)[1] end

  --- Text of the open mini.clue window, or nil.
  local function clue_window()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if
        vim.api.nvim_win_get_config(win).relative ~= '' and vim.api.nvim_buf_get_name(buf):find('miniclue://', 1, true)
      then
        return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
      end
    end
  end

  local function pum_words()
    local info = vim.fn.complete_info({ 'items', 'pum_visible' })
    if info.pum_visible ~= 1 then return {} end
    return vim.tbl_map(function(item) return item.word end, info.items)
  end

  -- Keys typed with nvim_feedkeys are only processed when the main loop runs,
  -- so each step runs from a timer: { delay_ms, fn } or { poll = fn, timeout = ms }.
  local function run(steps)
    local i = 0
    local function finish()
      local f = assert(io.open(assert(vim.env.SAHIN_SPEC_OUT), 'w'))
      f:write(vim.json.encode(out))
      f:close()
      vim.cmd('qa!')
    end
    local next_step
    local function call(fn)
      local ok, err = pcall(fn)
      if not ok then
        out.error = ('step %d: %s'):format(i, err)
        return finish()
      end
      next_step()
    end
    next_step = function()
      i = i + 1
      local step = steps[i]
      if not step then return finish() end
      if step.poll then
        local deadline = vim.uv.now() + step.timeout
        local function poll()
          if step.poll() or vim.uv.now() > deadline then return next_step() end
          vim.defer_fn(poll, 50)
        end
        vim.defer_fn(poll, 0)
      else
        vim.defer_fn(function() call(step[2]) end, step[1])
      end
    end
    next_step()
  end

  -- gitsigns must not run git in an untrusted repo (the child's cwd), must
  -- attach after :TrustProject and detach after :UntrustProject.
  S.gitsigns = function()
    local repo = assert(vim.uv.fs_realpath(assert(vim.uv.cwd())))
    local buf
    -- Commands of git processes that opened this repo (GIT_TRACE2_EVENT).
    local function git_in_repo()
      local f = io.open(dir .. '/trace.json')
      if not f then return {} end
      local argv, hits = {}, {}
      for line in f:lines() do
        local ok, ev = pcall(vim.json.decode, line)
        if ok and ev.event == 'start' then argv[ev.sid] = table.concat(ev.argv, ' ') end
        if ok and ev.event == 'def_repo' and ev.worktree == repo then hits[#hits + 1] = argv[ev.sid] or ev.sid end
      end
      f:close()
      return hits
    end
    local function has_buf_map(lhs)
      local m = vim.fn.maparg(lhs, 'n', false, true)
      return m.buffer == 1
    end
    return {
      {
        0,
        function()
          vim.cmd.edit(vim.fn.fnameescape(repo .. '/file.txt')) -- text: no LSP server starts on trust
          buf = vim.api.nvim_get_current_buf()
        end,
      },
      {
        1500, -- gitsigns' cwd check runs 100 ms after setup; attach takes ~100 ms
        function()
          out.untrusted = {
            attached = vim.b[buf].gitsigns_status_dict ~= nil,
            git = git_in_repo(),
            map = has_buf_map('<leader>hs'),
          }
          out.grant = { require('sahin.trust').grant(repo, { force = true, silent = true }) }
        end,
      },
      -- on_attach (the hunk maps) runs last, after the status dict is set.
      { poll = function() return has_buf_map('<leader>hs') end, timeout = 5000 },
      {
        0,
        function()
          out.trusted =
            { attached = vim.b[buf].gitsigns_status_dict ~= nil, git = #git_in_repo(), map = has_buf_map('<leader>hs') }
          out.revoke = { require('sahin.trust').revoke(repo) }
        end,
      },
      {
        poll = function() return vim.b[buf].gitsigns_status_dict == nil and not has_buf_map('<leader>hs') end,
        timeout = 3000,
      },
      {
        0,
        function() out.revoked = { attached = vim.b[buf].gitsigns_status_dict ~= nil, map = has_buf_map('<leader>hs') } end,
      },
    }
  end

  -- mini.clue: ö shows the [ family, öd still runs [d, öö and ää reach the
  -- markdown buffer-local [[ ]], <Space> shows the leader groups.
  S.clue = function()
    local file = dir .. '/clue.md'
    return {
      {
        0,
        function()
          vim.fn.writefile({ '# A', 'text a', '# B', 'text b' }, file)
          vim.cmd.edit(vim.fn.fnameescape(file))
          local ns = vim.api.nvim_create_namespace('spec')
          vim.diagnostic.set(
            ns,
            0,
            { { lnum = 0, col = 0, message = 'spec', severity = vim.diagnostic.severity.WARN } }
          )
          vim.api.nvim_win_set_cursor(0, { 4, 0 })
          feed('ö')
        end,
      },
      {
        700, -- window.delay is 300 ms
        function()
          out.o_window = clue_window()
          feed('d')
        end,
      },
      {
        300,
        function()
          out.o_d_line = cursor_line()
          out.o_window_closed = clue_window() == nil
          vim.api.nvim_win_set_cursor(0, { 4, 0 })
          feed('öö')
        end,
      },
      {
        300,
        function()
          out.oo_line = cursor_line()
          vim.api.nvim_win_set_cursor(0, { 1, 0 })
          feed('ää')
        end,
      },
      {
        300,
        function()
          out.aa_line = cursor_line()
          feed('<Space>')
        end,
      },
      {
        700,
        function()
          out.leader_window = clue_window()
          feed('<Esc>')
        end,
      },
      { 200, function() out.leader_closed = clue_window() == nil end },
    }
  end

  -- Completion with a fake in-process LSP server (always) and
  -- lua-language-server (when installed): one textDocument/completion
  -- request per trigger, prose stays manual, <C-Space> works.
  S.completion = function()
    local requests = {}
    vim.api.nvim_create_autocmd('LspRequest', {
      callback = function(ev)
        local r = ev.data.request
        if r.method == 'textDocument/completion' and r.type == 'pending' then
          local client = vim.lsp.get_client_by_id(ev.data.client_id)
          local name = client and client.name or '?'
          requests[name] = (requests[name] or 0) + 1
        end
      end,
    })
    local function count(name) return requests[name] or 0 end

    local function fake_server(dispatchers)
      local closing, id = false, 0
      return {
        request = function(method, _, callback, notify_reply)
          id = id + 1
          local rid = id
          if method == 'initialize' then
            callback(nil, { capabilities = { completionProvider = { triggerCharacters = { '.' } } } })
          elseif method == 'textDocument/completion' then
            -- Slower than the 25 ms autotrigger timer, to expose a second request.
            vim.defer_fn(function()
              callback(nil, { isIncomplete = false, items = { { label = 'alpha' }, { label = 'alpine' } } })
              if notify_reply then notify_reply(rid) end
            end, 60)
          elseif method == 'shutdown' then
            callback(nil, nil)
          end
          return true, rid
        end,
        notify = function(method)
          if method == 'exit' then dispatchers.on_exit(0, 15) end
          return true
        end,
        is_closing = function() return closing end,
        terminate = function() closing = true end,
      }
    end

    local fake, before
    local steps = {
      {
        0,
        function()
          vim.fn.writefile({ 'local foo = 1', '' }, dir .. '/c.lua')
          vim.cmd.edit(vim.fn.fnameescape(dir .. '/c.lua'))
          fake = vim.lsp.start({ name = 'fake', cmd = fake_server, root_dir = dir })
        end,
      },
      {
        poll = function()
          local c = vim.lsp.get_client_by_id(fake)
          return c and c.initialized
        end,
        timeout = 3000,
      },
      {
        100,
        function()
          vim.api.nvim_win_set_cursor(0, { 2, 0 })
          feed('ifo')
        end,
      },
      { 400, function() feed('<C-e>') end },
      {
        200,
        function()
          before = count('fake')
          feed('.')
        end,
      },
      {
        400,
        function()
          out.fake_dot = { requests = count('fake') - before, pum = pum_words() }
          feed('<Esc>')
        end,
      },
      {
        100,
        function()
          vim.fn.writefile({ '', '' }, dir .. '/c.md')
          vim.cmd.edit(vim.fn.fnameescape(dir .. '/c.md'))
          vim.lsp.buf_attach_client(0, fake)
          out.md_autocomplete = vim.bo.autocomplete
        end,
      },
      {
        200,
        function()
          before = count('fake')
          feed('ifo.')
        end,
      },
      {
        400,
        function()
          out.md_typed = { requests = count('fake') - before, pum = pum_words() }
          before = count('fake')
          feed('<C-Space>')
        end,
      },
      {
        400,
        function()
          out.md_ctrl_space = { requests = count('fake') - before, pum = pum_words() }
          feed('<Esc>')
        end,
      },
      {
        100,
        function()
          vim.cmd.enew()
          vim.bo.omnifunc = "{findstart, base -> findstart ? col('.') - 1 : ['zeta']}"
          feed('i<C-Space>')
        end,
      },
      {
        300,
        function()
          out.fallback = { pum = pum_words() }
          feed('<Esc>')
        end,
      },
    }

    if vim.fn.executable('lua-language-server') == 1 then
      local ls
      vim.list_extend(steps, {
        {
          100,
          function()
            vim.fn.writefile({ 'local tbl = { alpha = 1, beta = 2 }', '' }, dir .. '/r.lua')
            vim.cmd.edit(vim.fn.fnameescape(dir .. '/r.lua'))
            ls = vim.lsp.start({
              name = 'lua_ls',
              cmd = { 'lua-language-server', '--logpath=' .. dir .. '/ls-log', '--metapath=' .. dir .. '/ls-meta' },
              root_dir = dir,
            })
          end,
        },
        {
          poll = function()
            local c = vim.lsp.get_client_by_id(ls)
            return c and c.initialized
          end,
          timeout = 20000,
        },
        {
          1000,
          function()
            vim.api.nvim_win_set_cursor(0, { 2, 0 })
            feed('itbl')
          end,
        },
        { 1500, function() feed('<C-e>') end },
        {
          300,
          function()
            before = count('lua_ls')
            feed('.')
          end,
        },
        { poll = function() return vim.tbl_contains(pum_words(), 'alpha') end, timeout = 5000 },
        {
          300,
          function()
            out.lua_ls_dot = { requests = count('lua_ls') - before, pum = pum_words() }
            feed('<Esc>')
          end,
        },
      })
    end
    return steps
  end

  -- :PackDiff against a real vim.pack confirm buffer. Runs without the config
  -- (temp XDG_CONFIG_HOME), so vim.pack writes its lockfile into tmp.
  S.packdiff = function()
    local src = dir .. '/src'
    local confirm
    local function find_confirm()
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(b):match('^nvim%-pack://confirm') then return b end
      end
    end
    return {
      {
        0,
        function()
          vim.fn.mkdir(src .. '/lua', 'p')
          vim.fn.writefile({ 'return 1' }, src .. '/lua/p.lua')
          git(src, { 'init', '-q', '-b', 'main' })
          git(src, { 'add', '.' })
          git(src, { 'commit', '-q', '-m', 'one' })
          vim.pack.add({ { src = 'file://' .. src, name = 'p', version = 'main' } }, { confirm = false })
          vim.fn.writefile({ "local h = io.popen('id')", 'return 2' }, src .. '/lua/p.lua')
          git(src, { 'commit', '-q', '-am', 'two' })
          vim.pack.update({ 'p' })
        end,
      },
      { poll = function() return find_confirm() ~= nil end, timeout = 10000 },
      {
        0,
        function()
          confirm = find_confirm()
          local packdiff = dofile(assert(vim.env.SAHIN_SPEC_REPO) .. '/nvim/lua/sahin/packdiff.lua')
          out.parsed = packdiff.parse(vim.api.nvim_buf_get_lines(confirm, 0, -1, false))
          local buf = packdiff.open()
          out.text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
        end,
      },
    }
  end

  -- No plugins on disk (offline, partial install): startup must not error.
  S.offline = function()
    return {
      {
        200,
        function()
          out.loaded = {}
          for _, m in ipairs({ 'mini', 'telescope', 'gitsigns', 'treesitter', 'precognition' }) do
            out.loaded[m] = type(package.loaded['sahin.plugins.' .. m]) == 'table'
          end
          out.loaded.clue = type(package.loaded['sahin.clue']) == 'table'
          out.loaded.completion = type(package.loaded['sahin.completion']) == 'table'
          out.errmsg = vim.v.errmsg -- startup
          for _, ft in ipairs({ 'markdown', 'lua', 'yaml' }) do
            vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, true))
            vim.bo.filetype = ft
          end
          out.errmsg_filetype = vim.v.errmsg
          out.messages = vim.fn.execute('messages')
        end,
      },
    }
  end

  run(S[scenario]())
  return
end

--------------------------------------------------------------------------------
-- Parent suite (the full config under test)
--------------------------------------------------------------------------------
local T = dofile('tests/helpers.lua')

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
tmp = assert(vim.uv.fs_realpath(tmp)) -- macOS: /var -> /private/var, as git reports it
local spec_file = T.repo .. '/tests/plugins_spec.lua'

--- Run a child scenario in its own dir; returns its JSON result or nil, err.
local function child(name, opts)
  opts = opts or {}
  local dir = tmp .. '/' .. name
  vim.fn.mkdir(dir, 'p')
  local out = dir .. '/result.json'
  local env = vim.tbl_extend('force', {
    NVIM_APPNAME = vim.env.NVIM_APPNAME,
    SAHIN_SPEC_CHILD = name,
    SAHIN_SPEC_DIR = dir,
    SAHIN_SPEC_OUT = out,
    -- Trust db, swap, undo and logs (Neovim's and lua-language-server's) stay in tmp.
    XDG_STATE_HOME = dir .. '/state',
    XDG_CACHE_HOME = dir .. '/cache',
  }, opts.env and opts.env(dir) or {})
  local cmd = { vim.v.progpath, '--headless', '-i', 'NONE', '-c', 'luafile ' .. vim.fn.fnameescape(spec_file) }
  local res = vim.system(cmd, { cwd = opts.cwd or dir, env = env, text = true }):wait(opts.timeout or 60000)
  local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(out), '\n')) end)
  if not ok then return nil, ('exit %s: %s%s'):format(res.code, res.stdout or '', res.stderr or '') end
  if data.error then return nil, data.error end
  return data, res
end

local function contains(list, value) return type(list) == 'table' and vim.tbl_contains(list, value) end

T.it('plugin modules are set up', function()
  for _, g in ipairs({ 'MiniAi', 'MiniSurround', 'MiniStatusline', 'MiniIcons', 'MiniHipatterns', 'MiniClue' }) do
    T.ok(type(_G[g]) == 'table', g .. ' exists')
  end
  for _, m in ipairs({ 'telescope', 'gitsigns', 'precognition', 'nvim-treesitter' }) do
    T.ok(package.loaded[m] ~= nil, m .. ' loaded')
  end
  T.ok(package.loaded['nvim-web-devicons'] or package.preload['nvim-web-devicons'], 'nvim-web-devicons mocked')
  T.eq(
    _G.MiniIcons.config.style,
    vim.g.have_nerd_font and 'glyph' or 'ascii',
    'mini.icons style follows have_nerd_font'
  )
  T.ok(vim.fn.maparg('sa', 'n') ~= '', 'mini.surround sa')
  local hl = _G.MiniHipatterns.config.highlighters
  T.ok(hl.todo and hl.fixme and hl.hack and hl.note and hl.hex_color, 'mini.hipatterns words and hex colours')
end)

T.it('mini.ai keeps the 0.12 an/in selection', function()
  T.eq(vim.fn.maparg('aa', 'x', false, true).desc, 'Around next textobject', 'aa is mini.ai "next"')
  T.eq(vim.fn.maparg('ii', 'o', false, true).desc, 'Inside next textobject', 'ii is mini.ai "next"')
  T.eq(vim.fn.maparg('an', 'x', false, true).desc, 'Select parent (outer) node', 'an is still the built-in')
end)

T.it('telescope maps (kickstart names)', function()
  for _, lhs in ipairs({ 'sf', 'sg', 'sw', 'sh', 'sk', 'sd', 'sr', 's.', 'sc', 'sn', 's/', '<leader>', '/' }) do
    local m = vim.fn.maparg('<leader>' .. lhs, 'n', false, true)
    T.ok(m.desc and m.desc:match('^Search:'), '<leader>' .. lhs .. ' is a telescope map', vim.inspect(m.desc))
  end
  T.ok(vim.fn.maparg('<leader>sw', 'x') ~= '', '<leader>sw also in visual mode')
end)

T.it('telescope preview never passes a file name to the shell', function()
  local conf = require('telescope.config').values
  T.eq(conf.preview.check_mime_type, false, 'preview.check_mime_type is off')
  -- With the check on, a file without a known filetype is previewed after
  -- io.popen('file --mime-type -b "<path>"'), and sh runs $(...) in the name.
  local dir = tmp .. '/mime'
  vim.fn.mkdir(dir, 'p')
  local name = 'notes$(touch PWNED)'
  local f = assert(io.open(dir .. '/' .. name, 'w'))
  f:write('hello\n')
  f:close()
  local old_cwd = vim.fn.getcwd()
  vim.cmd.cd(vim.fn.fnameescape(dir)) -- where a PWNED file would land
  local buf = vim.api.nvim_create_buf(false, true)
  local done = false
  local opts = { preview = vim.deepcopy(conf.preview), callback = function() done = true end }
  require('telescope.previewers').buffer_previewer_maker(dir .. '/' .. name, buf, opts)
  vim.wait(5000, function() return done end, 20)
  vim.cmd.cd(vim.fn.fnameescape(old_cwd))
  T.eq(vim.api.nvim_buf_get_lines(buf, 0, 1, false), { 'hello' }, 'the file was previewed')
  vim.api.nvim_buf_delete(buf, { force = true })
  T.eq(vim.fn.readdir(dir), { name }, 'no PWNED file: the name never reached a shell')
end)

T.it('mini.clue config', function()
  T.eq(_G.MiniClue.config.window.delay, 300, 'clue window delay')
  T.eq(vim.o.timeoutlen, 1000, 'timeoutlen stays 1000')
  local keys = {}
  for _, t in ipairs(_G.MiniClue.config.triggers) do
    keys[#keys + 1] = t.keys
  end
  for _, k in ipairs({ '<Leader>', 'ö', 'ä', 'g', 'z', '"', "'", '<C-w>', '<C-x>', '<C-r>' }) do
    T.ok(vim.tbl_contains(keys, k), 'trigger ' .. k)
  end
end)

T.it('treesitter: queries on rtp, markdown highlighted, missing parsers are harmless', function()
  T.ok(vim.o.runtimepath:find('/nvim%-treesitter/runtime') ~= nil, 'nvim-treesitter/runtime on rtp')
  T.eq(vim.fn.exists(':TSUpdate') + vim.fn.exists(':TSInstall'), 0, 'no parser download commands')
  T.ok(vim.treesitter.language.get_lang('sh') == 'bash', 'nvim-treesitter filetype mappings still load')
  local md_query = vim.treesitter.query.get_files('markdown', 'highlights')[1] or ''
  T.ok(vim.startswith(md_query, vim.env.VIMRUNTIME), 'bundled markdown query wins', md_query)

  local b = T.buf({ '# Title', '', '- [ ] task' }, 'markdown')
  T.ok(vim.treesitter.highlighter.active[b] ~= nil, 'markdown buffer highlighted')

  b = T.buf({ 'int main(void) { return 0; }' }, 'c') -- bundled parser, ftplugin does not start it
  T.ok(vim.treesitter.highlighter.active[b] ~= nil, 'c buffer highlighted by the FileType autocmd')

  vim.v.errmsg = ''
  b = T.buf({ 'int x;' })
  vim.b[b].bigfile = true
  vim.bo[b].filetype = 'c'
  T.ok(vim.treesitter.highlighter.active[b] == nil, 'bigfile buffer not highlighted')

  local has_yaml = vim.treesitter.language.add('yaml') == true
  b = T.buf({ 'a: 1' }, 'yaml')
  T.eq(vim.treesitter.highlighter.active[b] ~= nil, has_yaml, 'yaml highlighted only with its parser')
  b = T.buf({ 'x' }, 'sahinnoparser')
  T.ok(vim.treesitter.highlighter.active[b] == nil, 'no parser: no highlighter')
  T.eq(vim.v.errmsg, '', 'no error for filetypes without parser')
end)

T.it('completion options', function()
  T.eq(vim.go.autocomplete, true, 'autocomplete on globally')
  T.eq(vim.o.complete, 'o^10,.^5,w^5,b^5', "'complete'")
  T.eq(vim.o.completeopt, 'menuone,noselect,fuzzy,popup', "'completeopt'")
  for _, ft in ipairs({ 'markdown', 'gitcommit' }) do
    T.buf({}, ft)
    T.eq(vim.o.autocomplete, false, 'autocomplete off in ' .. ft)
  end
  T.buf({}, 'lua')
  T.eq(vim.o.autocomplete, true, 'autocomplete on in lua')
  local orig_notify = vim.notify
  vim.notify = function() end
  local toggle = vim.fn.maparg('<leader>tc', 'n', false, true).callback
  toggle()
  T.eq(vim.o.autocomplete, false, '<leader>tc turns it off in the buffer')
  toggle()
  T.eq(vim.o.autocomplete, true, '<leader>tc turns it back on')
  vim.notify = orig_notify
  T.ok(vim.fn.maparg('<C-Space>', 'i') ~= '', 'insert <C-Space> mapped')
  -- Tab/Enter keep their meaning: only Neovim's default snippet <Tab> exists.
  T.ok((vim.fn.maparg('<Tab>', 'i', false, true).desc or ''):find('snippet') ~= nil, 'insert <Tab> is the default')
  T.eq(vim.fn.maparg('<CR>', 'i'), '', 'insert <CR> unmapped')
end)

T.it('precognition', function()
  T.ok(vim.fn.maparg('<leader>tp', 'n') ~= '', '<leader>tp mapped')
  T.eq(require('precognition').is_visible(), vim.g.precognition ~= false, 'startVisible follows vim.g.precognition')
end)

T.it(
  'gitsigns never attaches on its own',
  function() T.eq(require('gitsigns.config').config.auto_attach, false, 'auto_attach=false') end
)

T.it(':PackDiff', function()
  T.eq(vim.fn.exists(':PackDiff'), 2, ':PackDiff exists')
  local packdiff = require('sahin.packdiff')

  -- Without a confirm buffer it explains how to get one.
  local notified
  local orig_notify = vim.notify
  vim.notify = function(msg) notified = msg end
  vim.cmd('PackDiff')
  vim.notify = orig_notify
  T.ok(notified and notified:find('<leader>uu', 1, true), 'explains <leader>uu', notified)

  -- A plugin repo with one update: code with risky calls plus a README change.
  local repo = tmp .. '/plugin'
  vim.fn.mkdir(repo .. '/lua', 'p')
  vim.fn.writefile({ 'return 1' }, repo .. '/lua/x.lua')
  vim.fn.writefile({ 'old' }, repo .. '/README.md')
  git(repo, { 'init', '-q' })
  git(repo, { 'add', '.' })
  git(repo, { 'commit', '-q', '-m', 'one' })
  local before = git(repo, { 'rev-parse', 'HEAD' })
  vim.fn.writefile({ "vim.system({ 'id' })", "os.execute('id')", 'return 2' }, repo .. '/lua/x.lua')
  vim.fn.writefile({ 'new os.execute' }, repo .. '/README.md')
  git(repo, { 'commit', '-q', '-am', 'two' })
  local after = git(repo, { 'rev-parse', 'HEAD' })

  -- Same layout as vim.pack's confirm buffer (runtime/lua/vim/pack.lua).
  local lines = {
    '# Update ' .. ('─'):rep(71),
    '',
    '## x.nvim (not active)',
    'Path:            ' .. repo,
    'Source:          https://example.invalid/x.nvim',
    'Revision before: ' .. before,
    'Revision after:  ' .. after .. ' (v2.0.0)',
    '',
    'Pending updates:',
    '> two',
    '',
    '# Same ' .. ('─'):rep(73),
    '',
    '## y.nvim',
    'Path:     /nowhere',
    'Source:   https://example.invalid/y.nvim',
    'Revision: ' .. before,
  }
  T.eq(packdiff.parse(lines), { { name = 'x.nvim', path = repo, before = before, after = after } }, 'parse')

  local confirm = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(confirm, 'nvim-pack://confirm#spec')
  vim.api.nvim_buf_set_lines(confirm, 0, -1, false, lines)
  local buf = packdiff.open()
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
  T.ok(text:find("+vim.system({ 'id' })", 1, true), 'diff shows the added code', text)
  T.ok(not text:find('README', 1, true), 'non-code files are not diffed', text)
  T.ok(text:find('x.nvim: 2 risky token(s) in added lines', 1, true), 'summary counts risky tokens', text)
  local ns = vim.api.nvim_get_namespaces()['sahin.packdiff']
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  T.ok(#marks >= 2 and marks[1][4].hl_group == 'PackDiffRisky', 'risky tokens highlighted', #marks)
  vim.cmd('close')
  vim.api.nvim_buf_delete(confirm, { force = true })
end)

T.it(':PackDiff reads a real vim.pack confirm buffer (child)', function()
  local r, err = child('packdiff', {
    env = function(dir)
      return { XDG_CONFIG_HOME = dir .. '/config', XDG_DATA_HOME = dir .. '/data', SAHIN_SPEC_REPO = T.repo }
    end,
  })
  T.ok(r, 'packdiff child ran', err)
  if not r then return end
  T.eq(#r.parsed, 1, 'one pending update parsed', vim.inspect(r.parsed))
  T.eq(r.parsed[1] and r.parsed[1].name, 'p', 'plugin name')
  T.ok(r.text:find("+local h = io.popen('id')", 1, true), 'diff of the update shown', r.text)
  T.ok(r.text:find('p: 1 risky token(s) in added lines', 1, true), 'risky token counted', r.text)
end)

T.it('gitsigns: no git in an untrusted repo, attach after trust, detach after revoke', function()
  local repo = tmp .. '/untrusted-repo'
  vim.fn.mkdir(repo, 'p')
  vim.fn.writefile({ 'one' }, repo .. '/file.txt')
  git(repo, { 'init', '-q' })
  git(repo, { 'add', '.' })
  git(repo, { 'commit', '-q', '-m', 'init' })
  vim.fn.writefile({ 'two' }, repo .. '/file.txt')

  local r, err = child('gitsigns', {
    cwd = repo, -- also covers gitsigns' own git call for the current directory
    env = function(dir) return { GIT_TRACE2_EVENT = dir .. '/trace.json' } end,
  })
  T.ok(r, 'gitsigns child ran', err)
  if not r then return end
  T.eq(r.untrusted.attached, false, 'untrusted: not attached')
  T.eq(r.untrusted.git, {}, 'untrusted: no git process opened the repo')
  T.eq(r.untrusted.map, false, 'untrusted: no hunk maps')
  T.eq(r.grant[1], true, 'trust granted', vim.inspect(r.grant))
  T.eq(r.trusted.attached, true, 'trusted: attached')
  T.ok(r.trusted.git > 0, 'trusted: git ran (proves the trace works)')
  T.eq(r.trusted.map, true, 'trusted: hunk maps')
  T.eq(r.revoked.attached, false, 'revoked: detached')
  T.eq(r.revoked.map, false, 'revoked: hunk maps removed')
end)

T.it('mini.clue with ö/ä (child)', function()
  local r, err = child('clue')
  T.ok(r, 'clue child ran', err)
  if not r then return end
  local window = r.o_window or ''
  T.ok(window:find('previous diagnostic', 1, true), 'ö window lists [d', window)
  T.ok(window:find('previous misspelled word', 1, true), 'ö window lists built-in [s', window)
  T.ok(window:find('[[ (alias)', 1, true), 'ö window lists öö', window)
  T.eq(r.o_d_line, 1, 'öd runs [d (previous diagnostic)')
  T.eq(r.o_window_closed, true, 'window closed after öd')
  T.eq(r.oo_line, 3, 'öö reaches markdown [[ (previous heading)')
  T.eq(r.aa_line, 3, 'ää reaches markdown ]] (next heading)')
  local leader = r.leader_window or ''
  for _, g in ipairs({
    '+Search',
    '+Notes',
    '+Git hunk',
    '+Quickfix',
    '+Code',
    '+Toggle',
    '+Inspect',
    '+Update/plugins',
  }) do
    T.ok(leader:find(g, 1, true), 'leader window shows ' .. g, leader)
  end
  T.eq(r.leader_closed, true, '<Esc> closes the leader window')
end)

T.it('completion: one request per trigger, prose manual, <C-Space> (child)', function()
  local r, err = child('completion', { timeout = 90000 })
  T.ok(r, 'completion child ran', err)
  if not r then return end
  T.eq(r.fake_dot.requests, 1, "'.' sends exactly one completion request")
  T.ok(contains(r.fake_dot.pum, 'alpha'), 'menu shows the LSP items', vim.inspect(r.fake_dot))
  T.eq(r.md_autocomplete, false, 'markdown: autocomplete off')
  T.eq(r.md_typed.requests, 0, 'markdown: typing sends no request')
  T.eq(r.md_typed.pum, {}, 'markdown: no popup while typing')
  T.eq(r.md_ctrl_space.requests, 1, 'markdown: <C-Space> asks the server')
  T.ok(contains(r.md_ctrl_space.pum, 'alpha'), 'markdown: <C-Space> menu', vim.inspect(r.md_ctrl_space))
  T.ok(contains(r.fallback.pum, 'zeta'), '<C-Space> without LSP falls back to omni completion')
  if r.lua_ls_dot then
    T.eq(r.lua_ls_dot.requests, 1, "lua_ls: '.' sends exactly one completion request")
    T.ok(contains(r.lua_ls_dot.pum, 'alpha'), 'lua_ls: menu shows the table fields', vim.inspect(r.lua_ls_dot))
  else
    io.stdout:write('[plugins_spec] lua-language-server not installed: real-server completion check skipped\n')
  end
end)

T.it('no plugins on disk: startup does not error (child)', function()
  local r, err = child('offline', {
    env = function(dir) return { XDG_DATA_HOME = dir .. '/data', NVIM_OFFLINE = '1' } end,
  })
  T.ok(r, 'offline child ran', err)
  if not r then return end
  for m, loaded in pairs(r.loaded) do
    T.ok(loaded, m .. ' returned without error')
  end
  T.eq(r.errmsg, '', 'no error message during startup')
  T.eq(r.errmsg_filetype, '', 'no error from FileType handlers')
  T.ok(not r.messages:find('Error', 1, true), 'no error in :messages', r.messages)
end)

vim.fn.delete(tmp, 'rf')
T.finish('plugins_spec')
