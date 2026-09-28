-- Notes workflow: task commands, markdown ftplugin, :Tasks, capture files,
-- [!] highlight, render-markdown config, auto-save and auto-commit.
-- Run: NVIM_APPNAME=nvim-test nvim --headless -i NONE -c 'luafile tests/notes_spec.lua'
-- Everything is created in a temp dir; the real ~/notes is never touched.
local T = dofile('tests/helpers.lua')
local tasks = require('sahin.notes.tasks')
local pickers = require('sahin.notes.pickers')
local autocommit = require('sahin.notes.autocommit')

local today = os.date('%Y-%m-%d')
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
tmp = assert(vim.uv.fs_realpath(tmp)) -- macOS: /var -> /private/var

-- Written test files must not leave undo/swap files in the state dir.
vim.o.undofile = false
vim.o.swapfile = false

-- Collect notifications instead of printing them.
local log = {}
vim.notify = function(msg, level) log[#log + 1] = { msg = tostring(msg), level = level or vim.log.levels.INFO } end
local function logged(text, level)
  for _, e in ipairs(log) do
    if e.msg:find(text, 1, true) and (level == nil or e.level == level) then return true end
  end
  return false
end

-- Snapshot of the real ~/notes (names, sizes, mtimes) to prove it is untouched.
local real_notes = vim.fs.normalize('~/notes')
local function snapshot(dir)
  if not vim.uv.fs_stat(dir) then return 'absent' end
  local out = {}
  for rel in vim.fs.dir(dir, { depth = math.huge, skip = function(d) return d ~= '.git' end }) do
    if rel ~= '.git' then
      local st = vim.uv.fs_stat(dir .. '/' .. rel)
      out[#out + 1] = ('%s %s %s'):format(rel, st and st.size, st and st.mtime.sec .. '.' .. st.mtime.nsec)
    end
  end
  table.sort(out)
  return out
end
local real_before = snapshot(real_notes)

local function copy_tree(src, dst)
  vim.fn.mkdir(dst, 'p')
  for rel, kind in vim.fs.dir(src, { depth = math.huge }) do
    if kind == 'directory' then
      vim.fn.mkdir(dst .. '/' .. rel, 'p')
    else
      vim.fn.writefile(vim.fn.readfile(src .. '/' .. rel, 'b'), dst .. '/' .. rel, 'b')
    end
  end
end

local fixture_notes = tmp .. '/notes'
copy_tree(T.fixtures .. '/notes', fixture_notes)
vim.g.notes_dir = fixture_notes

local function edit(path) vim.cmd('edit! ' .. vim.fn.fnameescape(path)) end
local function cd(path) vim.cmd('cd ' .. vim.fn.fnameescape(path)) end

-- Start a child nvim with this config and a Lua script; returns its RESULT json.
local function child(lines, env)
  local script = vim.fn.tempname() .. '.lua'
  vim.fn.writefile(lines, script)
  local res = vim
    .system({ vim.v.progpath, '--headless', '-i', 'NONE', '-c', 'luafile ' .. script }, {
      env = env,
      text = true,
      timeout = 30000,
    })
    :wait()
  vim.fn.delete(script)
  local json = (res.stdout or ''):match('RESULT(%b{})')
  return json and vim.json.decode(json) or {}, res
end

------------------------------------------------------------------------------
T.it('task line functions', function()
  local c = tasks.cycle_line
  T.eq(c('- [ ] a'), '- [!] a', 'cycle: [ ] -> [!]')
  T.eq(c('- [!] a'), '- [x] a', 'cycle: [!] -> [x]')
  T.eq(c('- [x] a'), '- [ ] a', 'cycle: [x] -> [ ]')
  T.eq(c('- [X] a'), '- [ ] a', 'cycle: [X] -> [ ]')
  T.eq(c('- [>] a'), '- [ ] a', 'cycle: [>] resets to [ ]')
  T.eq(c('- [x] a done:2026-01-01'), '- [ ] a', 'reopened task loses its done: date')
  T.eq(c('    - [ ] sub #tag'), '    - [!] sub #tag', 'cycle keeps indent and tags')
  T.eq(c('- plain bullet'), '- [ ] plain bullet', 'bullet becomes a task')
  T.eq(c('  just text'), '  - [ ] just text', 'plain text becomes a task')
  T.eq(c('-'), '- [ ] ', "bare '-' becomes an empty task")
  T.eq(c(''), nil, 'blank line is left alone')
  T.eq(c('## Heading'), nil, 'heading is left alone')
  T.eq(c('---'), nil, 'front matter delimiter is left alone')
  T.eq(c('```lua'), nil, 'code fence is left alone')
  T.eq(tasks.done_line('- [ ] a'), '- [x] a done:' .. today, 'done adds [x] and date')
  T.eq(tasks.done_line('- [!] a #web'), '- [x] a #web done:' .. today, 'done from [!]')
  T.eq(tasks.done_line('- [x] a done:2026-01-01'), '- [x] a done:2026-01-01', 'done: date added only once')
  T.eq(tasks.done_line('b'), '- [x] b done:' .. today, 'done on plain text')
  T.eq(tasks.with_state('- [ ] a', '>'), '- [>] a', 'mark deferred')
end)

T.it(':TaskCycle on ranges, <CR> and <leader>nx', function()
  local b = T.buf({ '- [ ] a', '- [!] b', 'c', '', '## H', '- [>] d' }, 'markdown')
  vim.cmd('1,6TaskCycle')
  T.eq(T.lines(b), { '- [!] a', '- [x] b', '- [ ] c', '', '## H', '- [ ] d' }, ':1,6TaskCycle')

  local cr = vim.fn.maparg('<CR>', 'n', false, true)
  T.eq(cr.buffer, 1, '<CR> is buffer-local in markdown')
  T.ok(cr.desc ~= nil and cr.desc ~= '', '<CR> map has a desc')
  T.ok(vim.fn.maparg('<CR>', 'x') ~= '', '<CR> is mapped in visual mode')

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  T.feed('<CR>')
  T.eq(T.lines(b)[1], '- [x] a', '<CR> cycles the cursor line')
  T.feed('Vj<CR>')
  T.eq(vim.list_slice(T.lines(b), 1, 2), { '- [ ] a', '- [ ] b' }, 'visual <CR> cycles the selection')
  T.feed('2<CR>')
  T.eq(vim.list_slice(T.lines(b), 1, 3), { '- [!] a', '- [!] b', '- [ ] c' }, 'count <CR> cycles N lines')
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  T.feed('<leader>nx')
  T.eq(T.lines(b)[3], '- [!] c', '<leader>nx cycles')
end)

T.it(':TaskDone and :TaskMark', function()
  local b = T.buf({ '- [ ] a', '  - [!] b #t', 'c' }, 'markdown')
  vim.cmd('1,2TaskDone')
  T.eq(T.lines(b), { '- [x] a done:' .. today, '  - [x] b #t done:' .. today, 'c' }, ':1,2TaskDone')
  vim.cmd('1TaskDone')
  T.eq(T.lines(b)[1], '- [x] a done:' .. today, ':TaskDone twice adds the date once')

  vim.cmd('1,3TaskMark !')
  T.eq(T.lines(b), { '- [!] a', '  - [!] b #t', '- [!] c' }, ':TaskMark ! on a range')
  vim.cmd('2TaskMark >')
  T.eq(T.lines(b)[2], '  - [>] b #t', ':TaskMark >')
  vim.cmd('2TaskMark space')
  T.eq(T.lines(b)[2], '  - [ ] b #t', ':TaskMark space')
  vim.cmd('3TaskMark')
  T.eq(T.lines(b)[3], '- [ ] c', ':TaskMark without argument = space')
  log = {}
  vim.cmd('3TaskMark bogus')
  T.eq(T.lines(b)[3], '- [ ] c', ':TaskMark bogus changes nothing')
  T.ok(logged(':TaskMark expects', vim.log.levels.ERROR), ':TaskMark bogus reports an error')

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  T.feed('<leader>n!')
  T.eq(T.lines(b)[1], '- [!] a', '<leader>n! marks important')
  T.feed('<leader>nz')
  T.eq(T.lines(b)[1], '- [>] a', '<leader>nz defers')
  T.feed('<leader>nD')
  T.eq(T.lines(b)[1], '- [x] a done:' .. today, '<leader>nD marks done')
end)

T.it(':TaskArchive moves only finished task trees', function()
  local b = T.buf({
    '# Project',
    '',
    '## Tasks',
    '- [x] finished root',
    '  - [x] finished child',
    '  - a note inside the tree',
    '- [x] done parent with an open child',
    '  - [ ] open child',
    '- [ ] open parent',
    '  - [x] done child stays with its open parent',
    '- [!] important',
    '- [x] single done',
    '- a plain bullet',
    '  - [x] done task under a plain bullet stays',
    '',
    '```',
    '- [x] inside a code fence',
    '```',
  }, 'markdown')
  vim.cmd('TaskArchive')
  T.eq(T.lines(b), {
    '# Project',
    '',
    '## Tasks',
    '- [x] done parent with an open child',
    '  - [ ] open child',
    '- [ ] open parent',
    '  - [x] done child stays with its open parent',
    '- [!] important',
    '- a plain bullet',
    '  - [x] done task under a plain bullet stays',
    '',
    '```',
    '- [x] inside a code fence',
    '```',
    '',
    '## Done',
    '- [x] finished root',
    '  - [x] finished child',
    '  - a note inside the tree',
    '- [x] single done',
  }, ':TaskArchive creates ## Done and moves whole trees')

  local archived = T.lines(b)
  log = {}
  vim.cmd('TaskArchive')
  T.eq(T.lines(b), archived, 'second :TaskArchive changes nothing')
  T.ok(logged('Nothing to archive'), 'second :TaskArchive says so')

  local original = { '## Done', '- [x] old', '', '## Tasks', '- [x] new', '  - [x] sub', '- [ ] open' }
  b = T.buf(original, 'markdown')
  vim.o.undolevels = vim.o.undolevels -- start a new undo step here
  vim.cmd('TaskArchive')
  T.eq(
    T.lines(b),
    { '## Done', '- [x] old', '- [x] new', '  - [x] sub', '', '## Tasks', '- [ ] open' },
    'appends to an existing ## Done section'
  )
  vim.cmd('silent undo')
  T.eq(T.lines(b), original, ':TaskArchive is one undo step')
end)

T.it('markdown ftplugin options and continuation', function()
  local b = T.buf({ '- [ ] a' }, 'markdown')
  T.eq(vim.bo.comments, 'b:- [ ],b:-,n:>', 'comments')
  T.ok(vim.bo.formatoptions:find('r') and vim.bo.formatoptions:find('o'), 'formatoptions has r and o')
  T.eq({ vim.bo.shiftwidth, vim.bo.tabstop, vim.bo.softtabstop, vim.bo.expandtab }, { 2, 2, 2, true }, 'indent 2')
  T.eq({ vim.wo.wrap, vim.wo.linebreak, vim.wo.breakindent }, { true, true, true }, 'soft wrap')
  T.eq(vim.wo.breakindentopt, 'list:-1', 'breakindentopt')
  T.eq(vim.bo.textwidth, 0, 'textwidth')
  T.eq(
    { vim.wo.foldmethod, vim.wo.foldexpr, vim.wo.foldlevel },
    { 'expr', 'v:lua.vim.treesitter.foldexpr()', 99 },
    'treesitter folds'
  )
  T.eq(vim.wo.conceallevel, 0, 'conceallevel')
  T.eq(vim.bo.spelllang, table.concat(require('sahin.spell').langs(), ','), 'spelllang from sahin.spell')

  -- Read the new line while still in insert mode (<Esc> trims trailing blanks).
  local function after_o(first)
    T.buf({ first }, 'markdown')
    T.feed('o<Cmd>let g:notes_spec_line = getline(".")<CR><Esc>')
    return vim.g.notes_spec_line
  end
  T.eq(after_o('- [ ] a'), '- [ ] ', "o after '- [ ] a' gives '- [ ] '")
  b = T.buf({ '- [ ] a' }, 'markdown')
  T.feed('A<CR>b<Esc>')
  T.eq(T.lines(b)[2], '- [ ] b', 'Enter continues an open task')
  for _, state in ipairs({ '!', 'x', '>' }) do
    T.eq(after_o('- [' .. state .. '] a'), '- ', ("o after '- [%s] a' gives '- '"):format(state))
  end
  vim.g.notes_spec_line = nil
  b = T.buf({ '- note' }, 'markdown')
  T.feed('ob<Esc>')
  T.eq(T.lines(b)[2], '- b', 'plain bullets continue as bullets')

  b = T.buf({ '' }, 'markdown')
  vim.api.nvim_feedkeys(vim.keycode('ixd <Esc>'), 'mxt', false)
  T.eq(T.lines(b)[1], today .. ' ', 'xd<Space> inserts the date')

  -- The runtime ftplugin's buffer-local [[ ]] heading motions still work,
  -- reached through the Swiss aliases öö / ää.
  b = T.buf({ '# One', 'text', '## Two', 'text', '## Three' }, 'markdown')
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  T.feed('öö')
  T.eq(vim.api.nvim_win_get_cursor(0)[1], 3, 'öö jumps to the previous heading')
  T.feed('ää')
  T.eq(vim.api.nvim_win_get_cursor(0)[1], 5, 'ää jumps to the next heading')

  vim.bo.filetype = 'text'
  T.eq(vim.fn.maparg('<CR>', 'n'), '', 'changing filetype removes <CR>')
  T.ok(vim.bo.comments ~= 'b:- [ ],b:-,n:>', 'changing filetype resets comments')
end)

T.it('[!] is captured as @markup.list.important', function()
  local query = vim.fn.readfile(T.repo .. '/nvim/after/queries/markdown_inline/highlights.scm')
  T.eq(query[1], ';; extends', 'query file starts with ;; extends')
  local b = T.buf({ '- [!] urgent', '- [ ] open', 'text [!] mid', '> [!NOTE] callout', '- [x] done' }, 'markdown')
  vim.treesitter.get_parser(b):parse(true)
  local function important(row, col)
    for _, c in ipairs(vim.treesitter.get_captures_at_pos(b, row, col)) do
      if c.capture == 'markup.list.important' then return true end
    end
    return false
  end
  T.ok(important(0, 2) and important(0, 3) and important(0, 4), '[!] captured on [, ! and ]')
  T.ok(not important(0, 7), 'task text is not captured')
  T.ok(not important(1, 3), '[ ] is not important')
  T.ok(not important(2, 6), '[!] in the middle of text is not captured')
  T.ok(not important(3, 3), '> [!NOTE] callout is not captured')
  T.ok(not important(4, 3), '[x] is not important')

  local function link() return vim.api.nvim_get_hl(0, { name = '@markup.list.important' }).link end
  T.eq(link(), 'DiagnosticError', '@markup.list.important links to DiagnosticError')
  vim.cmd.colorscheme(vim.g.colors_name or 'default')
  T.eq(link(), 'DiagnosticError', 'link survives :colorscheme')
end)

T.it(':Tasks open|important from notes and TODO.md', function()
  local proj = tmp .. '/proj'
  vim.fn.mkdir(proj .. '/.git', 'p')
  vim.fn.writefile({ '- [ ] todo open', '- [!] todo important', '- [x] todo done' }, proj .. '/TODO.md')
  cd(proj)
  vim.cmd('enew!')

  local function entries()
    local out = {}
    for _, item in ipairs(vim.fn.getqflist()) do
      local name = vim.api.nvim_buf_get_name(item.bufnr)
      out[#out + 1] = ('%s:%d:%s'):format(vim.fs.basename(name), item.lnum, vim.trim(item.text))
    end
    table.sort(out)
    return out
  end
  local open = {
    '2026-01-03.md:11:- [ ] write SSRF notes',
    'TODO.md:1:- [ ] todo open',
    'TODO.md:2:- [!] todo important',
    'acme.md:9:- [ ] enumerate subdomains',
    'acme.md:10:- [!] check staging for IDOR',
    'inbox.md:9:- [ ] reply to triage #acme added:2026-01-05',
    'inbox.md:10:- [!] rotate test credentials #acme due:2026-01-06',
  }
  table.sort(open)
  local important = {
    'TODO.md:2:- [!] todo important',
    'acme.md:10:- [!] check staging for IDOR',
    'inbox.md:10:- [!] rotate test credentials #acme due:2026-01-06',
  }
  table.sort(important)

  vim.cmd('Tasks open')
  T.eq(entries(), open, ':Tasks open (rg): notes + TODO.md, no .scratch/ or .txt')
  T.eq(vim.fn.getqflist({ title = 0 }).title, 'Tasks: open', 'quickfix title')
  vim.cmd('Tasks important')
  T.eq(entries(), important, ':Tasks important (rg)')
  vim.cmd('Tasks')
  T.eq(#vim.fn.getqflist(), #open, ':Tasks defaults to open')

  -- Same results without ripgrep on PATH.
  local path = vim.env.PATH
  vim.env.PATH = tmp .. '/empty-bin'
  local ok = pcall(function()
    T.eq(vim.fn.executable('rg'), 0, 'rg hidden from PATH')
    vim.cmd('Tasks open')
    T.eq(entries(), open, ':Tasks open without rg')
    vim.cmd('Tasks important')
    T.eq(entries(), important, ':Tasks important without rg')
  end)
  vim.env.PATH = path
  T.ok(ok, 'fallback run finished')

  log = {}
  vim.cmd('Tasks bogus')
  T.ok(logged(':Tasks expects', vim.log.levels.ERROR), ':Tasks bogus reports an error')
  vim.cmd('cclose')
  cd(T.repo)
end)

T.it('telescope pickers (stubbed) and missing telescope', function()
  local calls = {}
  local saved = package.loaded['telescope.builtin']
  package.loaded['telescope.builtin'] = setmetatable({}, {
    __index = function(_, name)
      return function(opts) calls[#calls + 1] = { name = name, opts = opts } end
    end,
  })
  vim.g.notes_dir = fixture_notes
  T.feed('<leader>ns')
  T.feed('<leader>nn')
  T.feed('<leader>ng')
  T.eq(calls[1] and calls[1].name, 'grep_string', '<leader>ns uses grep_string')
  T.eq(calls[1] and calls[1].opts.search, pickers.patterns.open, '<leader>ns searches open tasks')
  T.ok(calls[1] and calls[1].opts.use_regex, '<leader>ns uses a regex')
  T.ok(calls[1] and vim.tbl_contains(calls[1].opts.search_dirs, fixture_notes), '<leader>ns searches the notes dir')
  T.eq(calls[2] and { calls[2].name, calls[2].opts.cwd }, { 'find_files', fixture_notes }, '<leader>nn')
  T.eq(calls[3] and { calls[3].name, calls[3].opts.cwd }, { 'live_grep', fixture_notes }, '<leader>ng')

  package.loaded['telescope.builtin'] = nil
  package.preload['telescope.builtin'] = function() error('not installed') end
  log = {}
  T.feed('<leader>nn')
  T.ok(logged('telescope.nvim is not installed', vim.log.levels.WARN), 'missing telescope is reported')
  package.preload['telescope.builtin'] = nil
  package.loaded['telescope.builtin'] = saved
end)

T.it(':Capture, :Daily and :Todo create files (mkdir -p)', function()
  local dir = tmp .. '/fresh/notes' -- does not exist yet
  vim.g.notes_dir = dir
  vim.cmd('Capture first task')
  local inbox = dir .. '/inbox.md'
  local lines = vim.fn.readfile(inbox)
  T.eq(lines[1], '---', 'inbox.md starts with front matter')
  T.ok(vim.tbl_contains(lines, 'project: inbox'), 'inbox front matter has project')
  T.eq(lines[#lines], '- [ ] first task added:' .. today, ':Capture appends a task')

  local input = vim.ui.input
  local answer = 'from prompt' ---@type string?
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.ui.input = function(_, cb) cb(answer) end
  vim.cmd('Capture')
  answer = nil -- cancelled prompt
  vim.cmd('Capture')
  vim.ui.input = input
  lines = vim.fn.readfile(inbox)
  T.eq(lines[#lines], '- [ ] from prompt added:' .. today, ':Capture without text prompts')
  T.eq(#vim.tbl_filter(function(l) return l:match('^%- %[ %]') end, lines), 2, 'cancelled prompt adds nothing')

  edit(inbox)
  vim.cmd('Capture while open')
  local want = '- [ ] while open added:' .. today
  T.eq(T.lines()[#T.lines()], want, ':Capture updates the open inbox buffer')
  lines = vim.fn.readfile(inbox)
  T.eq(lines[#lines], want, '... and the file')
  T.ok(not vim.bo.modified, '... and leaves it saved')

  vim.cmd('Daily')
  local daily = dir .. '/daily/' .. today .. '.md'
  T.eq(vim.api.nvim_buf_get_name(0), daily, ':Daily opens daily/<today>.md')
  lines = vim.fn.readfile(daily)
  T.eq(vim.list_slice(lines, 1, 5), { '---', 'project: daily', 'tags: [daily]', 'date: ' .. today, '---' }, 'template')
  T.eq(vim.api.nvim_get_current_line(), '## Tasks', 'cursor on ## Tasks')
  vim.fn.writefile({ 'kept' }, daily)
  vim.cmd('enew!')
  vim.cmd('Daily')
  T.eq(vim.fn.readfile(daily), { 'kept' }, ':Daily never overwrites')

  local repo = tmp .. '/repo'
  vim.fn.mkdir(repo .. '/.git', 'p')
  vim.fn.mkdir(repo .. '/sub', 'p')
  cd(repo .. '/sub')
  vim.cmd('enew!')
  vim.cmd('Todo')
  T.eq(vim.api.nvim_buf_get_name(0), repo .. '/TODO.md', ':Todo opens TODO.md at the git root')
  lines = vim.fn.readfile(repo .. '/TODO.md')
  T.eq(lines[1], '<!--', 'TODO.md starts with the convention comment')
  T.ok(vim.tbl_contains(lines, '## Tasks'), 'TODO.md has a ## Tasks section')

  local plain = tmp .. '/plain'
  vim.fn.mkdir(plain, 'p')
  cd(plain)
  vim.cmd('enew!')
  log = {}
  vim.cmd('Todo')
  if vim.fs.root(plain, '.git') == nil then
    T.eq(vim.api.nvim_buf_get_name(0), plain .. '/TODO.md', ':Todo outside git uses the cwd')
    T.ok(logged('Not in a git repo'), ':Todo outside git says so')
  end
  cd(T.repo)
end)

T.it('a hostile TODO.md symlink: :Tasks skips it, :Todo never writes through it', function()
  -- A cloned repo can commit TODO.md as a symlink (or unpack it as a FIFO).
  local repo = tmp .. '/hostile-todo'
  vim.fn.mkdir(repo .. '/.git', 'p')
  vim.fn.mkdir(repo .. '/docs', 'p')
  vim.fn.writefile({ '- [ ] linked task' }, repo .. '/docs/TODO.md')
  vim.fn.writefile({ '- [ ] outside task' }, tmp .. '/outside.md')
  local todo = repo .. '/TODO.md'
  cd(repo)
  vim.cmd('enew!')
  -- sources() only stats the path, so the parent can call it safely.
  local function listed(make)
    vim.fn.delete(todo)
    make()
    local list = pickers.sources()
    return list[#list] == todo
  end
  T.eq(listed(function() vim.uv.fs_symlink('/dev/zero', todo) end), false, 'TODO.md -> /dev/zero is skipped')
  T.eq(listed(function() vim.uv.fs_symlink(tmp .. '/outside.md', todo) end), false, 'a link out of the repo is skipped')
  T.eq(listed(function() vim.system({ 'mkfifo', todo }):wait() end), false, 'a FIFO is skipped')
  T.eq(listed(function() vim.uv.fs_symlink('docs/TODO.md', todo) end), true, 'a link inside the repo is used')

  -- :Tasks itself runs in a child: reading /dev/zero never ends, and the
  -- child helper kills it after 30 s.
  vim.fn.delete(todo)
  vim.uv.fs_symlink('/dev/zero', todo)
  local out, res = child({
    ('vim.g.notes_dir = %q'):format(fixture_notes),
    ('vim.cmd.cd(%q)'):format(repo),
    "vim.cmd('Tasks open')",
    "io.stdout:write('RESULT' .. vim.json.encode({ n = #vim.fn.getqflist() }))",
    "vim.cmd('qa!')",
  }, { NVIM_APPNAME = vim.env.NVIM_APPNAME })
  T.eq(res.code, 0, ':Tasks with TODO.md -> /dev/zero returns (child exited 0)')
  T.ok((out.n or 0) > 0, '... and still lists the notes tasks', vim.inspect(out))

  -- Whatever else could stall rg: :Tasks waits at most 10 s and says so.
  local system, limit = vim.system, nil
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function()
    return {
      wait = function(_, ms)
        limit = ms
        return { code = 124, stdout = '', stderr = '' } -- what wait() returns after killing rg
      end,
    }
  end
  log = {}
  local ok = pcall(function() vim.cmd('Tasks open') end)
  vim.system = system
  T.ok(ok, ':Tasks with a stalled rg did not error')
  T.eq(limit, 10000, ':Tasks gives rg 10 s')
  T.ok(logged('rg: stopped after 10 s', vim.log.levels.WARN), '... and warns when rg was stopped')

  -- A dangling link: :Todo must not create its target.
  vim.fn.delete(todo)
  vim.uv.fs_symlink(tmp .. '/planted.md', todo)
  vim.cmd('enew!')
  vim.cmd('Todo')
  T.eq(vim.uv.fs_stat(tmp .. '/planted.md'), nil, ':Todo did not write through a dangling TODO.md link')
  T.eq(vim.api.nvim_buf_get_name(0), todo, ':Todo still opens TODO.md')
  vim.cmd('enew!')
  cd(T.repo)
end)

T.it('<leader>1..5 hot notes', function()
  for i = 1, 5 do
    local m = vim.fn.maparg('<leader>' .. i, 'n', false, true)
    T.ok(m.desc ~= nil, ('<leader>%d is always mapped'):format(i))
  end
  local hot = tmp .. '/hot one.md'
  vim.g.hot_notes = { hot }
  T.feed('<leader>1')
  T.eq(vim.api.nvim_buf_get_name(0), hot, '<leader>1 opens hot_notes[1]')
  log = {}
  T.feed('<leader>2')
  T.ok(logged('Hot note 2 is not set'), 'unset hot note explains how to configure it')
  vim.g.hot_notes = nil
end)

T.it('render-markdown: task states, strikethrough, ASCII fallback, <leader>tr', function()
  local rmd = require('sahin.plugins.render_markdown')
  local ok, rm = pcall(require, 'render-markdown')
  if not ok then
    T.ok(false, 'render-markdown.nvim is installed for the tests')
    return
  end
  local live = require('render-markdown.state').config
  local want = rmd.opts(vim.g.have_nerd_font == true)
  T.eq(live.checkbox.custom.important.raw, '[!]', 'important state [!]')
  T.eq(live.checkbox.custom.deferred.raw, '[>]', 'deferred state [>]')
  T.eq(live.checkbox.custom.important.rendered, want.checkbox.custom.important.rendered, 'live config = opts()')
  T.eq(live.checkbox.checked.scope_highlight, '@markup.strikethrough', '[x] struck through')
  T.ok(vim.api.nvim_get_hl(0, { name = '@markup.strikethrough', link = false }).strikethrough, 'strikethrough group')

  -- Collect Nerd Font (private use area) glyphs in a resolved config.
  local function glyphs(t, out)
    for _, v in pairs(t) do
      if type(v) == 'table' then
        glyphs(v, out)
      elseif type(v) == 'string' then
        for _, cp in ipairs(vim.fn.str2list(v)) do
          if (cp >= 0xE000 and cp <= 0xF8FF) or cp >= 0xF0000 then out[#out + 1] = v end
        end
      end
    end
    return out
  end
  T.eq(glyphs(rm.resolve_config(rmd.opts(false)), {}), {}, 'ASCII config has no Nerd Font glyphs')
  T.ok(#glyphs(rm.resolve_config(rmd.opts(true)), {}) > 0, 'Nerd config uses glyphs')
  T.eq(rmd.opts(false).checkbox.custom.important.rendered, '[!] ', 'ASCII [!]')

  local before = rm.get()
  T.feed('<leader>tr')
  T.eq(rm.get(), not before, '<leader>tr toggles rendering')
  T.feed('<leader>tr')
  T.eq(rm.get(), before, '<leader>tr toggles back')
end)

T.it('spell languages and shared word list', function()
  local spell = require('sahin.spell')
  local langs = spell.langs()
  T.eq(langs[1], 'en', "'en' is always first")
  T.eq(#langs + #spell.missing(), 3, 'every optional language is either used or missing')
  local extra = tmp .. '/rtp'
  vim.fn.mkdir(extra .. '/spell', 'p')
  vim.fn.writefile({}, extra .. '/spell/tr.utf-8.spl')
  vim.opt.runtimepath:append(extra)
  T.ok(vim.tbl_contains(spell.langs(), 'tr'), "'tr' is used once tr.utf-8.spl is on the runtimepath")
  T.ok(not vim.tbl_contains(spell.missing(), 'tr'), "'tr' is then not missing")
  vim.opt.runtimepath:remove(extra)

  local b = T.buf({ 'SSRF via ffuf' }, 'markdown')
  vim.bo[b].spelllang = 'en'
  vim.wo.spell = true
  T.eq(vim.spell.check('SSRF via ffuf nuclei'), {}, 'shared word list (nvim/spell/en.utf-8.add) is active')
  vim.wo.spell = false
end)

T.it('auto-save notes on BufLeave/FocusLost only', function()
  local dir = tmp .. '/autosave'
  vim.fn.mkdir(dir, 'p')
  vim.g.notes_dir = dir
  local note, other = dir .. '/a.md', tmp .. '/outside.md'
  vim.fn.writefile({ 'a' }, note)
  vim.fn.writefile({ 'a' }, other)

  edit(note)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'left' })
  vim.cmd('enew')
  T.eq(vim.fn.readfile(note), { 'left' }, 'BufLeave saves a note')
  edit(note)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'focus' })
  vim.api.nvim_exec_autocmds('FocusLost', {})
  T.eq(vim.fn.readfile(note), { 'focus' }, 'FocusLost saves a note')

  edit(other)
  local ob = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'changed' })
  vim.cmd('enew')
  T.eq(vim.fn.readfile(other), { 'a' }, 'files outside the notes dir are not auto-saved')
  vim.cmd('bwipeout! ' .. ob)
end)

local function git(dir, ...) return vim.system({ 'git', '-C', dir, ... }, { text = true }):wait() end
local function commits(dir)
  local res = git(dir, 'rev-list', '--count', 'HEAD')
  return res.code == 0 and tonumber(vim.trim(res.stdout)) or 0
end
local function wait_idle()
  return vim.wait(10000, function() return not autocommit.busy() end, 20)
end
local function init_repo(dir)
  vim.fn.mkdir(dir, 'p')
  -- --template= and a local hooksPath: no hooks from the user's git setup.
  vim.system({ 'git', 'init', '-q', '--template=', dir }):wait()
  git(dir, 'config', 'user.name', 'notes-test')
  git(dir, 'config', 'user.email', 'notes-test')
  git(dir, 'config', 'core.hooksPath', '.git/hooks')
end

T.it('auto-commit: serialized, debounced, never .scratch/, hook warnings', function()
  local dir = tmp .. '/gitnotes'
  init_repo(dir)
  vim.g.notes_dir = dir
  local delay = autocommit.delay
  autocommit.delay = 200
  local function save(text)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { text })
    vim.cmd('silent write')
  end

  edit(dir .. '/a.md')
  save('1')
  save('2')
  save('3')
  T.ok(autocommit.busy(), 'a save schedules a commit')
  T.ok(wait_idle(), 'commit finished')
  vim.wait(3 * autocommit.delay)
  T.eq(commits(dir), 1, 'three quick saves -> exactly one commit')
  T.ok(vim.startswith(git(dir, 'log', '-1', '--format=%s').stdout, 'notes: '), "commit message 'notes: <time>'")
  save('4')
  save('5')
  wait_idle()
  vim.wait(3 * autocommit.delay)
  T.eq(commits(dir), 2, 'second burst -> second commit')

  vim.fn.mkdir(dir .. '/.scratch', 'p')
  vim.fn.writefile({ 'cookie=not-a-real-secret' }, dir .. '/.scratch/cookie.txt')
  save('6')
  wait_idle()
  local files = git(dir, 'ls-files').stdout or ''
  T.ok(files:find('a.md', 1, true) and not files:find('.scratch', 1, true), '.scratch/ is never committed')

  -- A save while a job is running only sets `pending`; one more run follows.
  vim.fn.writefile({ 'x' }, dir .. '/b.md')
  autocommit.run(dir)
  vim.fn.writefile({ 'y' }, dir .. '/c.md')
  autocommit.run(dir)
  T.ok(wait_idle(), 'serialized runs finish')
  local status = vim.tbl_filter(
    function(l) return not l:find('.scratch', 1, true) end,
    vim.split(git(dir, 'status', '--porcelain').stdout, '\n', { trimempty = true })
  )
  T.eq(status, {}, 'pending run commits the save made during a running job')

  -- A blocking pre-commit hook: nothing committed, its output shown as WARN.
  local hook = dir .. '/.git/hooks/pre-commit'
  vim.fn.mkdir(dir .. '/.git/hooks', 'p')
  vim.fn.writefile({ '#!/bin/sh', 'echo "leak found: REDACTED" >&2', 'exit 1' }, hook)
  vim.uv.fs_chmod(hook, tonumber('755', 8))
  local count = commits(dir)
  log = {}
  save('7')
  wait_idle()
  T.eq(commits(dir), count, 'blocked commit adds nothing')
  T.ok(logged('REDACTED', vim.log.levels.WARN), 'hook output is shown as a warning')

  vim.fn.delete(hook)
  save('8')
  autocommit.flush()
  T.eq(commits(dir), count + 1, 'flush commits a pending save right away')
  autocommit.delay = delay
  vim.cmd('enew')
end)

T.it('no auto-commit without <notes>/.git', function()
  local dir = tmp .. '/nogit'
  vim.fn.mkdir(dir, 'p')
  vim.g.notes_dir = dir
  edit(dir .. '/a.md')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'x' })
  vim.cmd('silent write')
  T.ok(not autocommit.busy(), 'nothing scheduled')
  T.ok(vim.uv.fs_stat(dir .. '/.git') == nil, 'no repo created')
  vim.cmd('enew')
end)

T.it('child nvim: quitting right after a save still commits', function()
  local dir = tmp .. '/leave'
  init_repo(dir)
  local _, res = child({
    'vim.o.undofile = false',
    'vim.o.swapfile = false',
    ('vim.g.notes_dir = %q'):format(dir),
    ('vim.cmd.edit(%q)'):format(dir .. '/a.md'),
    "vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'saved then quit' })",
    "vim.cmd('silent write')",
    "vim.cmd('qa!')",
  }, { NVIM_APPNAME = vim.env.NVIM_APPNAME })
  T.eq(res.code, 0, 'child exited cleanly')
  T.eq(commits(dir), 1, 'VimLeavePre flushed the pending commit')
end)

T.it('child nvim: default notes dir is ~/notes, resolved when used', function()
  local home = tmp .. '/home'
  vim.fn.mkdir(home, 'p')
  local out = child({
    'vim.g.notes_dir = nil',
    "vim.cmd('Capture from child')",
    "io.stdout:write('RESULT' .. vim.json.encode({ dir = require('sahin.notes').dir() }))",
    "vim.cmd('qa!')",
  }, {
    NVIM_APPNAME = vim.env.NVIM_APPNAME,
    HOME = home,
    XDG_CONFIG_HOME = vim.fs.dirname(vim.fn.stdpath('config')),
    XDG_DATA_HOME = vim.fs.dirname(vim.fn.stdpath('data')),
    XDG_STATE_HOME = tmp .. '/state',
    XDG_CACHE_HOME = tmp .. '/cache',
  })
  T.eq(out.dir, home .. '/notes', 'default is ~/notes')
  local inbox = vim.fn.filereadable(home .. '/notes/inbox.md') == 1 and vim.fn.readfile(home .. '/notes/inbox.md') or {}
  T.eq(inbox[#inbox], '- [ ] from child added:' .. today, ':Capture wrote to ~/notes of that HOME')
end)

T.it('nvu (untrusted profile): markdown options only, no notes', function()
  local xdg = tmp .. '/nvu-config'
  vim.fn.mkdir(xdg, 'p')
  vim.uv.fs_symlink(T.repo .. '/nvim', xdg .. '/nvim-untrusted')
  local out = child({
    "vim.cmd('enew')",
    "vim.bo.filetype = 'markdown'",
    'io.stdout:write("RESULT" .. vim.json.encode({',
    '  untrusted = vim.g.untrusted,',
    '  comments = vim.bo.comments,',
    "  cr = vim.fn.maparg('<CR>', 'n'),",
    "  xd = vim.fn.maparg('xd', 'i', true),",
    "  cmd = vim.fn.exists(':TaskCycle'),",
    '}))',
    "vim.cmd('qa!')",
  }, {
    -- Own XDG dirs: the profile is this repo's nvim/ and no real state is used.
    NVIM_APPNAME = 'nvim-untrusted',
    XDG_CONFIG_HOME = xdg,
    XDG_DATA_HOME = tmp .. '/nvu-data',
    XDG_STATE_HOME = tmp .. '/nvu-state',
    XDG_CACHE_HOME = tmp .. '/nvu-cache',
  })
  T.eq(out.untrusted, true, 'child runs the untrusted profile')
  T.eq(out.comments, 'b:- [ ],b:-,n:>', 'options still apply in nvu')
  T.eq({ out.cr, out.xd, out.cmd }, { '', '', 0 }, 'no <CR>/xd maps and no :TaskCycle in nvu')
end)

T.eq(snapshot(real_notes), real_before, 'the real ~/notes is untouched')

cd(T.repo)
vim.cmd('silent! %bwipeout!')
vim.fn.delete(tmp, 'rf')
T.finish('notes_spec')
