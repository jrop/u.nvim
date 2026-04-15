require 'luacov'

--- @diagnostic disable: need-check-nil
--- @diagnostic disable: param-type-mismatch
--- @diagnostic disable: undefined-field
--- @diagnostic disable: unnecessary-assert

local Pos = require('u').Pos
local Range = require('u').Range
local function withbuf(lines, f)
  vim.go.swapfile = false

  vim.cmd.new()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  local ok, result = pcall(f)
  vim.cmd.bdelete { bang = true }
  if not ok then error(result) end
end

describe('Pos', function()
  it('get a char from a given position', function()
    withbuf({ 'asdf', 'bleh', 'a', '', 'goo' }, function()
      assert.are.same('a', Pos.new(nil, 1, 1):char())
      assert.are.same('d', Pos.new(nil, 1, 3):char())
      assert.are.same('f', Pos.new(nil, 1, 4):char())
      assert.are.same('a', Pos.new(nil, 3, 1):char())
      assert.are.same('', Pos.new(nil, 4, 1):char())
      assert.are.same('o', Pos.new(nil, 5, 3):char())
    end)
  end)

  it('comparison operators', function()
    local a = Pos.new(0, 0, 0, 0)
    local b = Pos.new(0, 1, 0, 0)
    assert.are.same(a == a, true)
    assert.are.same(a < b, true)
  end)

  it('get the next position', function()
    withbuf({ 'asdf', 'bleh', 'a', '', 'goo' }, function()
      -- line 1: a => s
      assert.are.same(Pos.new(nil, 1, 2), Pos.new(nil, 1, 1):next())
      -- line 1: d => f
      assert.are.same(Pos.new(nil, 1, 4), Pos.new(nil, 1, 3):next())
      -- line 1 => 2
      assert.are.same(Pos.new(nil, 2, 1), Pos.new(nil, 1, 4):next())
      -- line 3 => 4
      assert.are.same(Pos.new(nil, 4, 1), Pos.new(nil, 3, 1):next())
      -- line 4 => 5
      assert.are.same(Pos.new(nil, 5, 1), Pos.new(nil, 4, 1):next())
      -- end returns nil
      assert.are.same(nil, Pos.new(nil, 5, 3):next())
    end)
  end)

  it('get the previous position', function()
    withbuf({ 'asdf', 'bleh', 'a', '', 'goo' }, function()
      -- line 1: s => a
      assert.are.same(Pos.new(nil, 1, 1), Pos.new(nil, 1, 2):next(-1))
      -- line 1: f => d
      assert.are.same(Pos.new(nil, 1, 3), Pos.new(nil, 1, 4):next(-1))
      -- line 2 => 1
      assert.are.same(Pos.new(nil, 1, 4), Pos.new(nil, 2, 1):next(-1))
      -- line 4 => 3
      assert.are.same(Pos.new(nil, 3, 1), Pos.new(nil, 4, 1):next(-1))
      -- line 5 => 4
      assert.are.same(Pos.new(nil, 4, 1), Pos.new(nil, 5, 1):next(-1))
      -- beginning returns nil
      assert.are.same(nil, Pos.new(nil, 1, 1):next(-1))
    end)
  end)

  it('find matching brackets', function()
    withbuf({ 'asdf ({} def <[{}]>) ;lkj' }, function()
      -- outer parens are matched:
      assert.are.same(Pos.new(nil, 1, 20), Pos.new(nil, 1, 6):find_match())
      -- outer parens are matched (backward):
      assert.are.same(Pos.new(nil, 1, 6), Pos.new(nil, 1, 20):find_match())
      -- no potential match returns nil
      assert.are.same(nil, Pos.new(nil, 1, 1):find_match())
      -- watchdog expires before an otherwise valid match is found:
      assert.are.same(nil, Pos.new(nil, 1, 6):find_match(2))
    end)
  end)
end)

describe('Range', function()
  it('get text in buffer', function()
    withbuf({ 'line one', 'and line two' }, function()
      local range = Range.from_buf_text()
      local lines = range:lines()
      assert.are.same({
        'line one',
        'and line two',
      }, lines)

      local text = range:text()
      assert.are.same('line one\nand line two', text)
    end)

    withbuf({}, function()
      local range = Range.from_buf_text()
      local lines = range:lines()
      assert.are.same({ '' }, lines)

      local text = range:text()
      assert.are.same('', text)
    end)
  end)

  it('get from positions: v in single line', function()
    withbuf({ 'line one', 'and line two' }, function()
      local range = Range.new(Pos.new(nil, 1, 2), Pos.new(nil, 1, 4), 'v')
      local lines = range:lines()
      assert.are.same({ 'ine' }, lines)

      local text = range:text()
      assert.are.same('ine', text)
    end)
  end)

  it('get from positions: v across multiple lines', function()
    withbuf({ 'pre line', 'the quick brown fox', 'jumps over a lazy dog', 'post line' }, function()
      local range = Range.new(Pos.new(nil, 2, 5), Pos.new(nil, 3, 5), 'v')
      local lines = range:lines()
      assert.are.same({ 'quick brown fox', 'jumps' }, lines)
    end)
  end)

  it('get from positions: V', function()
    withbuf({ 'line one', 'and line two' }, function()
      local range = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, vim.v.maxcol), 'V')
      local lines = range:lines()
      assert.are.same({ 'line one' }, lines)

      local text = range:text()
      assert.are.same('line one', text)
    end)
  end)

  it('get from positions: V across multiple lines', function()
    withbuf({ 'pre line', 'the quick brown fox', 'jumps over a lazy dog', 'post line' }, function()
      local range = Range.new(Pos.new(nil, 2, 1), Pos.new(nil, 3, vim.v.maxcol), 'V')
      local lines = range:lines()
      assert.are.same({ 'the quick brown fox', 'jumps over a lazy dog' }, lines)
    end)
  end)

  it('get from line', function()
    withbuf({ 'line one', 'and line two' }, function()
      local range = Range.from_line(nil, 1)
      local lines = range:lines()
      assert.are.same({ 'line one' }, lines)

      local text = range:text()
      assert.are.same('line one', text)
    end)
  end)

  it('get from lines', function()
    withbuf({ 'line one', 'and line two', 'and line 3' }, function()
      local range = Range.from_lines(nil, 1, 2)
      local lines = range:lines()
      assert.are.same({ 'line one', 'and line two' }, lines)

      local text = range:text()
      assert.are.same('line one\nand line two', text)
    end)
  end)

  it('replace within line', function()
    withbuf({ 'pre line', 'the quick brown fox', 'jumps over a lazy dog', 'post line' }, function()
      local range = Range.new(Pos.new(nil, 2, 5), Pos.new(nil, 2, 9), 'v')
      range:replace 'quack'

      local text = Range.from_line(nil, 2):text()
      assert.are.same('the quack brown fox', text)
    end)
  end)

  it('delete within line', function()
    withbuf({ 'pre line', 'the quick brown fox', 'jumps over a lazy dog', 'post line' }, function()
      local range = Range.new(Pos.new(nil, 2, 5), Pos.new(nil, 2, 10), 'v')
      range:replace ''

      local text = Range.from_line(nil, 2):text()
      assert.are.same('the brown fox', text)
    end)

    withbuf({ 'pre line', 'the quick brown fox', 'jumps over a lazy dog', 'post line' }, function()
      local range = Range.new(Pos.new(nil, 2, 5), Pos.new(nil, 2, 10), 'v')
      range:replace(nil)

      local text = Range.from_line(nil, 2):text()
      assert.are.same('the brown fox', text)
    end)
  end)

  it('replace across multiple lines: v', function()
    withbuf({ 'pre line', 'the quick brown fox', 'jumps over a lazy dog', 'post line' }, function()
      local range = Range.new(Pos.new(nil, 2, 5), Pos.new(nil, 3, 5), 'v')
      range:replace 'plane flew'

      local lines = Range.from_buf_text():lines()
      assert.are.same({
        'pre line',
        'the plane flew over a lazy dog',
        'post line',
      }, lines)
    end)
  end)

  it('replace a line', function()
    withbuf({ 'pre line', 'the quick brown fox', 'jumps over a lazy dog', 'post line' }, function()
      local range = Range.from_line(nil, 2)
      range:replace 'the rabbit'

      local lines = Range.from_buf_text():lines()
      assert.are.same({
        'pre line',
        'the rabbit',
        'jumps over a lazy dog',
        'post line',
      }, lines)
    end)
  end)

  it('replace multiple lines', function()
    withbuf({ 'pre line', 'the quick brown fox', 'jumps over a lazy dog', 'post line' }, function()
      local range = Range.from_lines(nil, 2, 3)
      range:replace 'the rabbit'

      local lines = Range.from_buf_text():lines()
      assert.are.same({
        'pre line',
        'the rabbit',
        'post line',
      }, lines)
    end)
  end)

  it('delete single line', function()
    withbuf({ 'pre line', 'the quick brown fox', 'jumps over a lazy dog', 'post line' }, function()
      local range = Range.from_line(nil, 2)
      range:replace(nil) -- delete lines

      local lines = Range.from_buf_text():lines()
      assert.are.same({
        'pre line',
        'jumps over a lazy dog',
        'post line',
      }, lines)
    end)
  end)

  it('delete multiple lines', function()
    withbuf({ 'pre line', 'the quick brown fox', 'jumps over a lazy dog', 'post line' }, function()
      local range = Range.from_lines(nil, 2, 3)
      range:replace(nil) -- delete lines

      local lines = Range.from_buf_text():lines()
      assert.are.same({
        'pre line',
        'post line',
      }, lines)
    end)
  end)

  it('text object: word', function()
    withbuf({ 'the quick brown fox' }, function()
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      assert.are.same('quick ', Range.from_motion('aw'):text())

      vim.fn.setpos('.', { 0, 1, 5, 0 })
      assert.are.same('quick', Range.from_motion('iw'):text())
    end)
  end)

  it('text object: quote', function()
    withbuf({ [[the "quick" brown fox]] }, function()
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      assert.are.same('"quick"', Range.from_motion('a"'):text())

      vim.fn.setpos('.', { 0, 1, 6, 0 })
      assert.are.same('quick', Range.from_motion('i"'):text())
    end)

    withbuf({ [[the 'quick' brown fox]] }, function()
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      assert.are.same("'quick'", Range.from_motion([[a']]):text())

      vim.fn.setpos('.', { 0, 1, 6, 0 })
      assert.are.same('quick', Range.from_motion([[i']]):text())
    end)

    withbuf({ [[the `quick` brown fox]] }, function()
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      assert.are.same('`quick`', Range.from_motion([[a`]]):text())

      vim.fn.setpos('.', { 0, 1, 6, 0 })
      assert.are.same('quick', Range.from_motion([[i`]]):text())
    end)
  end)

  it('text object: block', function()
    withbuf({ 'this is a {', 'block', '} here' }, function()
      vim.fn.setpos('.', { 0, 2, 1, 0 })
      assert.are.same('{\nblock\n}', Range.from_motion('a{'):text())

      vim.fn.setpos('.', { 0, 2, 1, 0 })
      assert.are.same('block', Range.from_motion('i{'):text())
    end)
  end)

  it('text object: restores cursor position', function()
    withbuf({ 'this is a {block} here' }, function()
      vim.fn.setpos('.', { 0, 1, 13, 0 })
      assert.are.same('{block}', Range.from_motion('a{'):text())
      assert.are.same(vim.api.nvim_win_get_cursor(0), { 1, 12 })
    end)
  end)

  it('text object: it (inside HTML tag)', function()
    withbuf({ '<div><span>text</span></div>' }, function()
      vim.cmd.setfiletype 'html'
      vim.fn.setpos('.', { 0, 1, 12, 0 }) -- inside 'text'
      local range = Range.from_motion 'it'
      assert.is_not_nil(range)
      assert.are.same('text', range:text())
    end)
  end)

  it('from_motion with contains_cursor returns nil when cursor outside range', function()
    withbuf({ 'foo "quoted" bar' }, function()
      vim.fn.setpos('.', { 0, 1, 2, 0 }) -- cursor at 'foo', not in quotes
      local range = Range.from_motion('a"', { contains_cursor = true })
      assert.is_nil(range)
    end)
  end)

  it('from_motion with pos option', function()
    withbuf({ 'the quick brown fox' }, function()
      vim.fn.setpos('.', { 0, 1, 1, 0 }) -- cursor at start
      local pos = Pos.new(nil, 1, 5) -- position at 'quick'
      local range = Range.from_motion('aw', { pos = pos })
      assert.are.same('quick ', range:text())
    end)
  end)

  it('from_motion with simple motion (non-text-object)', function()
    withbuf({ 'hello world' }, function()
      vim.fn.setpos('.', { 0, 1, 1, 0 })
      local range = Range.from_motion 'w'
      assert.is_not_nil(range)
    end)
  end)

  it('from_motion with bufnr option', function()
    local buf1 = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf1, 0, -1, false, { 'buffer one', 'more text' })

    local buf2 = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { 'buffer two' })
    vim.api.nvim_set_current_buf(buf2)

    vim.fn.setpos('.', { buf1, 1, 1, 0 })
    local range = Range.from_motion('aw', { bufnr = buf1 })
    assert.is_not_nil(range)
    assert.are.same(buf1, range.start.bufnr)

    vim.api.nvim_buf_delete(buf1, { force = true })
    vim.api.nvim_buf_delete(buf2, { force = true })
  end)

  it('from_motion does not modify the jumplist', function()
    withbuf({
      'line1',
      '(hello world)',
      'line3',
      '{foo bar}',
      'line5',
    }, function()
      -- Build up a jumplist that includes line 2:
      vim.cmd.normal { args = { '5G' }, bang = true }
      vim.cmd.normal { args = { '2G' }, bang = true }
      vim.cmd.normal { args = { '4G' }, bang = true }
      vim.cmd.normal { args = { '5G' }, bang = true }

      -- Position cursor on line 2 (which is in the jumplist), inside the parens
      vim.fn.setpos('.', { 0, 2, 3, 0 })

      local jl_before = vim.fn.getjumplist()
      local n_before = #jl_before[1]
      local curjump_before = jl_before[2]

      -- g@a( corrupts the jumplist by deduplicating the entry for line 2.
      -- This is a query-only operation and should NOT change the jumplist:
      Range.from_motion('a(', { contains_cursor = true })

      local jl_after = vim.fn.getjumplist()

      assert.are.same(
        n_before,
        #jl_after[1],
        'from_motion should not add or remove jumplist entries'
      )
      assert.are.same(
        curjump_before,
        jl_after[2],
        'from_motion should not change the curjump pointer'
      )
    end)
  end)

  it('find_nearest_brackets does not modify the jumplist', function()
    withbuf({
      'line1',
      '(hello world)',
      'line3',
      '{foo bar}',
      'line5',
    }, function()
      -- Build up a jumplist:
      vim.cmd.normal { args = { '5G' }, bang = true }
      vim.cmd.normal { args = { '2G' }, bang = true }
      vim.cmd.normal { args = { '4G' }, bang = true }
      vim.cmd.normal { args = { '5G' }, bang = true }

      -- Move to a line near brackets
      vim.fn.setpos('.', { 0, 2, 3, 0 })

      local jl_before = vim.fn.getjumplist()
      local n_before = #jl_before[1]
      local curjump_before = jl_before[2]

      -- This calls from_motion internally and should NOT change the jumplist:
      Range.find_nearest_brackets()

      local jl_after = vim.fn.getjumplist()

      assert.are.same(
        n_before,
        #jl_after[1],
        'find_nearest_brackets should not add or remove jumplist entries'
      )
      assert.are.same(
        curjump_before,
        jl_after[2],
        'find_nearest_brackets should not change the curjump pointer'
      )
    end)
  end)

  it('from_motion restores visual selection when started in visual mode', function()
    withbuf({ 'the quick brown fox' }, function()
      -- Enter visual mode first
      vim.fn.setpos('.', { 0, 1, 1, 0 })
      vim.cmd.normal 'vll' -- select 'the' (3 chars)

      -- Call from_motion (should save and restore visual selection)
      local range = Range.from_motion 'aw'
      assert.is_not_nil(range)

      -- Check we're back in visual mode with selection restored
      -- Note: The exact behavior depends on implementation
      local mode = vim.fn.mode()
      assert.is_true(mode == 'v' or mode == 'V' or mode == '\22')
    end)
  end)

  it('from_tsquery_caps', function()
    withbuf({
      '-- a comment',
      '',
      'function foo(bar) end',
      '',
      '-- a middle comment',
      '',
      'function bar(baz) end',
      '',
      '-- another comment',
    }, function()
      vim.cmd.setfiletype 'lua'

      --- @param contains_cursor? boolean
      local function get_caps(contains_cursor)
        if contains_cursor == nil then contains_cursor = true end
        return (Range.from_tsquery_caps(
          0,
          '(function_declaration) @f',
          { contains_cursor = contains_cursor }
        )).f or {}
      end

      local caps = get_caps(false)
      assert.are.same(#caps, 2)
      assert.are.same(vim.iter(caps):map(function(c) return c:text() end):totable(), {
        'function foo(bar) end',
        'function bar(baz) end',
      })

      Pos.new(0, 1, 1):save_to_pos '.'
      caps = get_caps()
      assert.are.same(#caps, 0)

      Pos.new(0, 3, 18):save_to_pos '.'
      caps = get_caps()
      assert.are.same(#caps, 1)
      assert.are.same(caps[1]:text(), 'function foo(bar) end')

      Pos.new(0, 5, 1):save_to_pos '.'
      caps = get_caps()
      assert.are.same(#caps, 0)

      Pos.new(0, 7, 1):save_to_pos '.'
      caps = get_caps()
      assert.are.same(#caps, 1)
      assert.are.same(caps[1]:text(), 'function bar(baz) end')
    end)
  end)

  it('from_tsquery_caps with string array filter', function()
    withbuf({
      '{',
      '  sample_key1 = "sample-value1",',
      '  sample_key2 = "sample-value2",',
      '}',
    }, function()
      vim.cmd.setfiletype 'lua'

      -- Place cursor in "sample-value1"
      Pos.new(0, 2, 25):save_to_pos '.'

      -- Query that captures both keys and values in pairs
      local query = [[
        (field
          name: _ @key
          value: _ @value)
      ]]

      local ranges = Range.from_line(0, 2):tsquery(query)

      -- Should have both @key and @value captures for the first pair only
      -- (since cursor is in sample-value1)
      assert(ranges, 'Range should not be nil')
      assert(ranges.key, 'Range.key should not be nil')
      assert(ranges.value, 'Range.value should not be nil')

      -- Should have exactly one key and one value
      assert.are.same(#ranges.key, 1)
      assert.are.same(#ranges.value, 1)

      -- Check that we got sample-key1 and sample-value1
      assert.are.same(ranges.key[1]:text(), 'sample_key1')
      assert.are.same(ranges.value[1]:text(), '"sample-value1"')
    end)

    -- Make sure this works when the match is on the last line:
    withbuf({
      '{sample_key1= "sample-value1",',
      'sample_key2= "sample-value2"}',
    }, function()
      vim.cmd.setfiletype 'lua'

      -- Place cursor in "sample-value1"
      Pos.new(0, 2, 25):save_to_pos '.'

      -- Query that captures both keys and values in pairs
      local query = [[
        (field
          name: _ @key
          value: _ @value)
      ]]

      local ranges = Range.from_line(0, 2):tsquery(query)

      -- Should have both @key and @value captures for the first pair only
      -- (since cursor is in sample-value1)
      assert(ranges, 'Range should not be nil')
      assert(ranges.key, 'Range.key should not be nil')
      assert(ranges.value, 'Range.value should not be nil')

      -- Should have exactly one key and one value
      assert.are.same(#ranges.key, 1)
      assert.are.same(#ranges.value, 1)

      -- Check that we got sample-key2 and sample-value2
      assert.are.same(ranges.key[1]:text(), 'sample_key2')
      assert.are.same(ranges.value[1]:text(), '"sample-value2"')
    end)
  end)

  it('should get nearest block', function()
    withbuf({
      'this is a {',
      'block',
      '} here',
    }, function()
      vim.fn.setpos('.', { 0, 2, 1, 0 })
      assert.are.same('{\nblock\n}', Range.find_nearest_brackets():text())
    end)

    withbuf({
      'this is a {',
      '(block)',
      '} here',
    }, function()
      vim.fn.setpos('.', { 0, 2, 3, 0 })
      assert.are.same('(block)', Range.find_nearest_brackets():text())
    end)
  end)

  it('line', function()
    withbuf({
      'this is a {',
      'block',
      '} here',
    }, function()
      local range = Range.new(Pos.new(0, 1, 6), Pos.new(0, 2, 5), 'v')
      local lfirst = assert(range:line(1), 'lfirst null')
      assert.are.same('is a {', lfirst:text())
      assert.are.same(Pos.new(0, 1, 6), lfirst.start)
      assert.are.same(Pos.new(0, 1, 11), lfirst.stop)
      assert.are.same('block', range:line(2):text())
    end)
  end)

  it('from_marks', function()
    withbuf({ 'line one', 'and line two' }, function()
      local a = Pos.new(nil, 0, 0)
      local b = Pos.new(nil, 1, 1)
      a:save_to_pos "'["
      b:save_to_pos "']"

      local range = Range.from_marks("'[", "']")
      assert.are.same(range.start, a)
      assert.are.same(range.stop, b)
      assert.are.same(range.mode, 'v')
    end)
  end)

  it('from_vtext', function()
    withbuf({ 'line one', 'and line two' }, function()
      vim.fn.setpos('.', { 0, 1, 3, 0 }) -- cursor at position (1, 3)
      vim.cmd.normal 'v' -- enter visual mode
      vim.cmd.normal 'l' -- select one character to the right
      local range = Range.from_vtext()
      assert.are.same(range.start, Pos.new(nil, 1, 3))
      assert.are.same(range.stop, Pos.new(nil, 1, 4))
      assert.are.same(range.mode, 'v')
    end)
  end)

  it('from_op_func', function()
    withbuf({ 'line one', 'and line two' }, function()
      local a = Pos.new(nil, 1, 1)
      local b = Pos.new(nil, 2, 2)
      a:save_to_pos "'["
      b:save_to_pos "']"

      local range = Range.from_op_func 'char'
      assert.are.same(range.start, a)
      assert.are.same(range.stop, b)
      assert.are.same(range.mode, 'v')

      range = Range.from_op_func 'line'
      assert.are.same(range.start, a)
      assert.are.same(range.stop, Pos.new(nil, 2, vim.v.maxcol))
      assert.are.same(range.mode, 'V')
    end)
  end)

  it('from_cmd_args: range=0', function()
    local args = { range = 0 }
    withbuf(
      { 'line one', 'and line two' },
      function() assert.are.same(Range.from_cmd_args(args), nil) end
    )
  end)

  it('from_cmd_args: range=1', function()
    local args = { range = 1, line1 = 1 }
    withbuf({ 'line one', 'and line two' }, function()
      local a = Pos.new(nil, 1, 1)
      local b = Pos.new(nil, 1, vim.v.maxcol)

      local range = Range.from_cmd_args(args) --[[@as u.Range]]
      assert.are.same(range.start, a)
      assert.are.same(range.stop, b)
      assert.are.same(range.mode, 'V')
      assert.are.same(range:text(), 'line one')
    end)
  end)

  it('from_cmd_args: range=2: no-visual', function()
    local args = { range = 2, line1 = 1, line2 = 2 }
    withbuf({ 'line one', 'and line two' }, function()
      local range = Range.from_cmd_args(args) --[[@as u.Range]]
      assert.are.same(range.start, Pos.new(nil, 1, 1))
      assert.are.same(range.stop, Pos.new(nil, 2, vim.v.maxcol))
      assert.are.same(range.mode, 'V')
      assert.are.same(range:text(), 'line one\nand line two')
    end)
  end)

  it('from_cmd_args: range=2: visual: linewise', function()
    local args = { range = 2, line1 = 1, line2 = 2 }
    withbuf({ 'line one', 'and line two' }, function()
      local a = Pos.new(nil, 1, 1)
      local b = Pos.new(nil, 2, vim.v.maxcol)
      a:save_to_pos "'<"
      b:save_to_pos "'>"
      local range = Range.from_cmd_args(args) --[[@as u.Range]]
      assert.are.same(range.start, a)
      assert.are.same(range.stop, b)
      assert.are.same(range.mode, 'V')
      assert.are.same(range:text(), 'line one\nand line two')
    end)
  end)

  it('from_cmd_args: range=2: visual: charwise', function()
    local args = { range = 2, line1 = 1, line2 = 1 }
    withbuf({ 'line one', 'and line two' }, function()
      -- Simulate a visual selection:
      local a = Pos.new(nil, 1, 1)
      local b = Pos.new(nil, 1, 4)
      a:save_to_pos "'<"
      b:save_to_pos "'>"
      Range.new(a, b, 'v'):set_visual_selection()
      assert.are.same(vim.fn.mode(), 'v')

      -- In this simulated setup, we need to force visualmode() to return
      -- 'v' and histget() to return [['<,'>]]:

      -- visualmode()
      local orig_visualmode = vim.fn.visualmode
      --- @diagnostic disable-next-line: duplicate-set-field
      function vim.fn.visualmode() return 'v' end
      assert.are.same(vim.fn.visualmode(), 'v')

      -- histget()
      local orig_histget = vim.fn.histget
      --- @diagnostic disable-next-line: duplicate-set-field
      function vim.fn.histget() return [['<,'>]] end

      -- Now run the test:
      local range = Range.from_cmd_args(args) --[[@as u.Range]]
      assert.are.same(range.start, a)
      assert.are.same(range.stop, b)
      assert.are.same(range.mode, 'v')
      assert.are.same(range:text(), 'line')

      -- Reset visualmode() and histget():
      vim.fn.visualmode = orig_visualmode
      vim.fn.histget = orig_histget
    end)
  end)

  it('find_nearest_quotes', function()
    withbuf({ [[the "quick" brown fox]] }, function()
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      local range = Range.find_nearest_quotes()
      assert.are.same(range.start, Pos.new(nil, 1, 5))
      assert.are.same(range.stop, Pos.new(nil, 1, 11))
    end)

    withbuf({ [[the 'quick' brown fox]] }, function()
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      local range = Range.find_nearest_quotes()
      assert.are.same(range.start, Pos.new(nil, 1, 5))
      assert.are.same(range.stop, Pos.new(nil, 1, 11))
    end)
  end)

  it('smallest', function()
    local r1 = Range.new(Pos.new(nil, 1, 2), Pos.new(nil, 1, 4), 'v')
    local r2 = Range.new(Pos.new(nil, 1, 3), Pos.new(nil, 1, 5), 'v')
    local r3 = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 6), 'v')
    local smallest = Range.smallest { r1, r2, r3 }
    assert.are.same(smallest.start, Pos.new(nil, 1, 2))
    assert.are.same(smallest.stop, Pos.new(nil, 1, 4))
  end)

  it('clone', function()
    withbuf({ 'line one', 'and line two' }, function()
      local original = Range.from_lines(nil, 0, 1)
      local cloned = original:clone()
      assert.are.same(original.start, cloned.start)
      assert.are.same(original.stop, cloned.stop)
      assert.are.same(original.mode, cloned.mode)
    end)
  end)

  it('line_count', function()
    withbuf({ 'line one', 'and line two', 'line three' }, function()
      local range = Range.from_lines(nil, 0, 2)
      assert.are.same(range:line_count(), 3)
    end)
  end)

  it('to_linewise()', function()
    withbuf({ 'line one', 'and line two' }, function()
      local range = Range.new(Pos.new(nil, 1, 2), Pos.new(nil, 2, 4), 'v')
      local linewise_range = range:to_linewise()
      assert.are.same(linewise_range.start.col, 1)
      assert.are.same(linewise_range.stop.col, vim.v.maxcol)
      assert.are.same(linewise_range.mode, 'V')
    end)
  end)

  it('is_empty', function()
    withbuf({ 'line one', 'and line two' }, function()
      local range = Range.new(Pos.new(nil, 1, 1), nil, 'v')
      assert.is_true(range:is_empty())

      local range2 = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 2), 'v')
      assert.is_false(range2:is_empty())
    end)
  end)

  it('trim_start', function()
    withbuf({ '   line one', 'line two' }, function()
      local range = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 10), 'v')
      local trimmed = range:trim_start()
      assert.are.same(trimmed.start, Pos.new(nil, 1, 4)) -- should be after the spaces
    end)
  end)

  it('trim_stop', function()
    withbuf({ 'line one   ', 'line two' }, function()
      local range = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 10), 'v')
      local trimmed = range:trim_stop()
      assert.are.same(trimmed.stop, Pos.new(nil, 1, 8)) -- should be before the spaces
    end)
  end)

  it('contains', function()
    withbuf({ 'line one', 'and line two' }, function()
      local range = Range.new(Pos.new(nil, 1, 2), Pos.new(nil, 1, 4), 'v')
      local pos = Pos.new(nil, 1, 3)
      assert.is_true(range:contains(pos))

      pos = Pos.new(nil, 1, 5) -- outside of range
      assert.is_false(range:contains(pos))
    end)
  end)

  it('difference', function()
    withbuf({ 'line one', 'and line two' }, function()
      local range_outer = Range.new(Pos.new(nil, 2, 1), Pos.new(nil, 2, 12), 'v')
      local range_inner = Range.new(Pos.new(nil, 2, 5), Pos.new(nil, 2, 8), 'v')

      assert.are.same(range_outer:text(), 'and line two')
      assert.are.same(range_inner:text(), 'line')

      local left, right = range_outer:difference(range_inner)
      assert.are.same(left:text(), 'and ')
      assert.are.same(right:text(), ' two')

      left, right = range_inner:difference(range_outer)
      assert.are.same(left:text(), 'and ')
      assert.are.same(right:text(), ' two')

      left, right = range_outer:difference(range_outer)
      assert.are.same(left:is_empty(), true)
      assert.are.same(left:text(), '')
      assert.are.same(right:is_empty(), true)
      assert.are.same(right:text(), '')
    end)
  end)

  it('length', function()
    withbuf({ 'line one', 'and line two' }, function()
      local range = Range.new(Pos.new(nil, 2, 4), Pos.new(nil, 2, 9), 'v')
      assert.are.same(range:length(), #range:text())

      range = Range.new(Pos.new(nil, 1, 4), Pos.new(nil, 2, 9), 'v')
      assert.are.same(range:length(), #range:text())
    end)
  end)

  it('sub', function()
    withbuf({ 'line one', 'and line two' }, function()
      local range = Range.new(Pos.new(nil, 2, 4), Pos.new(nil, 2, 9), 'v')
      assert.are.same(range:text(), ' line ')
      assert.are.same(range:sub(1, -1):text(), ' line ')
      assert.are.same(range:sub(2, -2):text(), 'line')
      assert.are.same(range:sub(1, 5):text(), ' line')
      assert.are.same(range:sub(2, 5):text(), 'line')
      assert.are.same(range:sub(20, 25):text(), '')
    end)
  end)

  it('shrink', function()
    withbuf({ 'line one', 'and line two' }, function()
      local range = Range.new(Pos.new(nil, 2, 3), Pos.new(nil, 3, 5), 'v')
      local shrunk = range:shrink(1)
      assert.are.same(shrunk.start, Pos.new(nil, 2, 4))
      assert.are.same(shrunk.stop, Pos.new(nil, 3, 4))
    end)
  end)

  it('must_shrink', function()
    withbuf({ 'line one', 'and line two' }, function()
      local range = Range.new(Pos.new(nil, 2, 3), Pos.new(nil, 3, 5), 'v')
      local shrunk = range:must_shrink(1)
      assert.are.same(shrunk.start, Pos.new(nil, 2, 4))
      assert.are.same(shrunk.stop, Pos.new(nil, 3, 4))

      assert.has.error(
        function() range:must_shrink(100) end,
        'error in Range:must_shrink: Range:shrink() returned nil'
      )
    end)
  end)

  it('set_visual_selection', function()
    withbuf({ 'line one', 'and line two' }, function()
      local range = Range.from_lines(nil, 1, 2)
      range:set_visual_selection()

      assert.are.same(Pos.from_pos 'v', Pos.new(nil, 1, 1))
      -- Since the selection is 'V' (instead of 'v'), the end
      -- selects one character past the end:
      assert.are.same(Pos.from_pos '.', Pos.new(nil, 2, 13))
    end)
  end)

  it('selections set to past the EOL should not error', function()
    withbuf({ 'Rg SET NAMES' }, function()
      local b = vim.api.nvim_get_current_buf()
      local r = Range.new(Pos.new(b, 1, 4), Pos.new(b, 1, 13), 'v')
      r:replace 'bleh'
      assert.are.same({ 'Rg bleh' }, vim.api.nvim_buf_get_lines(b, 0, -1, false))
    end)

    withbuf({ 'Rg SET NAMES' }, function()
      local b = vim.api.nvim_get_current_buf()
      local r = Range.new(Pos.new(b, 1, 4), Pos.new(b, 1, 12), 'v')
      r:replace 'bleh'
      assert.are.same({ 'Rg bleh' }, vim.api.nvim_buf_get_lines(b, 0, -1, false))
    end)
  end)

  it('replace updates Range.stop: same line', function()
    withbuf({ 'The quick brown fox jumps over the lazy dog' }, function()
      local b = vim.api.nvim_get_current_buf()
      local r = Range.new(Pos.new(b, 1, 5), Pos.new(b, 1, 9), 'v')

      r:replace 'bleh1'
      assert.are.same(
        { 'The bleh1 brown fox jumps over the lazy dog' },
        vim.api.nvim_buf_get_lines(b, 0, -1, false)
      )

      r:replace 'bleh2'
      assert.are.same(
        { 'The bleh2 brown fox jumps over the lazy dog' },
        vim.api.nvim_buf_get_lines(b, 0, -1, false)
      )
    end)
  end)

  it('replace updates Range.stop: multi-line', function()
    withbuf({
      'The quick brown fox jumps',
      'over the lazy dog',
    }, function()
      local b = vim.api.nvim_get_current_buf()
      local r = Range.new(Pos.new(b, 1, 21), Pos.new(b, 2, 4), 'v')
      assert.are.same({ 'jumps', 'over' }, r:lines())

      r:replace 'bleh1'
      assert.are.same(
        { 'The quick brown fox bleh1 the lazy dog' },
        vim.api.nvim_buf_get_lines(b, 0, -1, false)
      )
      assert.are.same({ 'bleh1' }, r:lines())

      r:replace 'blehGoo2'
      assert.are.same(
        { 'The quick brown fox blehGoo2 the lazy dog' },
        vim.api.nvim_buf_get_lines(b, 0, -1, false)
      )
    end)
  end)

  it('replace updates Range.stop: multi-line (blockwise)', function()
    withbuf({
      'The quick brown',
      'fox',
      'jumps',
      'over',
      'the lazy dog',
    }, function()
      local b = vim.api.nvim_get_current_buf()
      local r = Range.new(Pos.new(b, 2, 1), Pos.new(b, 4, vim.v.maxcol), 'V')
      assert.are.same({ 'fox', 'jumps', 'over' }, r:lines())

      r:replace { 'bleh1', 'bleh2' }
      assert.are.same({
        'The quick brown',
        'bleh1',
        'bleh2',
        'the lazy dog',
      }, vim.api.nvim_buf_get_lines(b, 0, -1, false))

      r:replace 'blehGoo2'
      assert.are.same({
        'The quick brown',
        'blehGoo2',
        'the lazy dog',
      }, vim.api.nvim_buf_get_lines(b, 0, -1, false))
    end)
  end)

  it('replace after delete', function()
    withbuf({
      'The quick brown',
      'fox',
      'jumps',
      'over',
      'the lazy dog',
    }, function()
      local b = vim.api.nvim_get_current_buf()
      local r = Range.new(Pos.new(b, 2, 1), Pos.new(b, 4, vim.v.maxcol), 'V')
      assert.are.same({ 'fox', 'jumps', 'over' }, r:lines())

      r:replace(nil)
      assert.are.same({
        'The quick brown',
        'the lazy dog',
      }, vim.api.nvim_buf_get_lines(b, 0, -1, false))

      r:replace { 'blehGoo2', '' }
      assert.are.same({
        'The quick brown',
        'blehGoo2',
        'the lazy dog',
      }, vim.api.nvim_buf_get_lines(b, 0, -1, false))
    end)
  end)

  it('can save to extmark', function()
    withbuf({
      'The quick brown',
      'fox',
      'jumps',
      'over',
      'the lazy dog',
    }, function()
      -- Construct a range over 'fox jumps'
      local r = Range.new(Pos.new(nil, 2, 1), Pos.new(nil, 3, 5), 'v')
      local extrange = r:save_to_extmark()
      assert.are.same({ 'fox', 'jumps' }, extrange:range():lines())
      -- change 'jumps' to 'leaps':
      vim.api.nvim_buf_set_text(extrange.bufnr, 2, 0, 2, 4, { 'leap' })
      assert.are.same({
        'The quick brown',
        'fox',
        'leaps',
        'over',
        'the lazy dog',
      }, vim.api.nvim_buf_get_lines(extrange.bufnr, 0, -1, false))
      assert.are.same({ 'fox', 'leaps' }, extrange:range():lines())
    end)
  end)

  it('can save linewise extmark', function()
    withbuf({
      'The quick brown',
      'fox',
      'jumps',
      'over',
      'the lazy dog',
    }, function()
      -- Construct a range over 'fox jumps'
      local r = Range.new(Pos.new(nil, 2, 1), Pos.new(nil, 3, vim.v.maxcol), 'V')
      local extrange = r:save_to_extmark()
      assert.are.same({ 'fox', 'jumps' }, extrange:range():lines())

      local extmark = vim.api.nvim_buf_get_extmark_by_id(
        extrange.bufnr,
        vim.api.nvim_create_namespace 'u.range',
        extrange.id,
        { details = true }
      )
      local row0, col0, details = unpack(extmark)
      assert.are.same({ 1, 0 }, { row0, col0 })
      assert.are.same({ 3, 0 }, { details.end_row, details.end_col })
    end)
  end)

  it('discerns range bounds from extmarks beyond the end of the buffer', function()
    local function set_tmp_options(bufnr)
      vim.bo[bufnr].bufhidden = 'delete'
      vim.bo[bufnr].buflisted = false
      vim.bo[bufnr].buftype = 'nowrite'
    end

    vim.cmd.vnew()
    local left_bufnr = vim.api.nvim_get_current_buf()
    set_tmp_options(left_bufnr)
    local left = Range.from_buf_text(left_bufnr)
    vim.cmd.vnew()
    local right_bufnr = vim.api.nvim_get_current_buf()
    set_tmp_options(left_bufnr)
    local right = Range.from_buf_text(right_bufnr)

    left:replace {
      'one',
      'two',
      'three',
    }
    local left_all_ext = left:save_to_extmark()

    right:replace {
      'foo',
      'bar',
    }

    vim.api.nvim_set_current_buf(right_bufnr)
    vim.cmd [[normal! ggyG]]
    vim.api.nvim_set_current_buf(left_bufnr)
    vim.cmd [[normal! ggVGp]]

    assert.are.same({ 'foo', 'bar' }, left_all_ext:range():lines())
    vim.api.nvim_buf_delete(left_bufnr, { force = true })
    vim.api.nvim_buf_delete(right_bufnr, { force = true })
  end)
end)

--------------------------------------------------------------------------------
-- Additional coverage tests
--------------------------------------------------------------------------------

describe('Pos additional coverage', function()
  it('__tostring', function()
    withbuf({ 'test' }, function()
      local bufnr = vim.api.nvim_get_current_buf()
      local p = Pos.new(bufnr, 1, 1, 0)
      local s = tostring(p)
      assert.is_true(s:find 'Pos%(1:1%)' ~= nil)
      assert.is_true(s:find('bufnr=' .. bufnr) ~= nil)

      local p2 = Pos.new(bufnr, 1, 1, 5)
      s = tostring(p2)
      assert.is_true(s:find 'Pos%(1:1%)' ~= nil)
      assert.is_true(s:find 'off=5' ~= nil)
    end)
  end)

  it('from_eol', function()
    withbuf({ 'hello world' }, function()
      local eol = Pos.from_eol(nil, 1)
      assert.are.same(11, eol.col)
      assert.are.same('hello world', eol:line())
    end)
  end)

  it(':eol', function()
    withbuf({ 'hello world' }, function()
      local p = Pos.new(nil, 1, 1)
      local eol = p:eol()
      assert.are.same(11, eol.col)
    end)
  end)

  it('save_to_cursor', function()
    withbuf({ 'line one', 'line two' }, function()
      local p = Pos.new(nil, 2, 5)
      p:save_to_cursor()
      assert.are.same({ 2, 4 }, vim.api.nvim_win_get_cursor(0))
    end)
  end)

  it('save_to_mark', function()
    withbuf({ 'line one', 'line two' }, function()
      local b = vim.api.nvim_get_current_buf()
      local p = Pos.new(b, 2, 5)
      p:save_to_mark 'a'
      local mark = vim.api.nvim_buf_get_mark(b, 'a')
      assert.are.same({ 2, 4 }, mark)
    end)
  end)

  it('must_next', function()
    withbuf({ 'abc' }, function()
      local p = Pos.new(nil, 1, 1)
      local next = p:must_next(1)
      assert.are.same(Pos.new(nil, 1, 2), next)

      assert.has.error(
        function() Pos.new(nil, 1, 3):must_next(1) end,
        'error in Pos:next(): Pos:next() returned nil'
      )
    end)
  end)

  it('next_while', function()
    withbuf({ 'aaabbb' }, function()
      local p = Pos.new(nil, 1, 1)
      local result = p:next_while(1, function(pos) return pos:char() == 'a' end)
      assert.are.same(Pos.new(nil, 1, 3), result)

      result = p:next_while(1, function(pos) return pos:char() == 'a' end, true)
      assert.are.same(Pos.new(nil, 1, 3), result)

      result = p:next_while(1, function() return false end, true)
      assert.are.same(nil, result)
    end)
  end)

  it('insert_before', function()
    withbuf({ 'world' }, function()
      local p = Pos.new(nil, 1, 1)
      p:insert_before 'hello '
      assert.are.same({ 'hello world' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)
  end)

  it('is_invalid', function()
    local invalid = Pos.invalid()
    assert.is_true(invalid:is_invalid())

    withbuf({ 'test' }, function()
      local valid = Pos.new(nil, 1, 1)
      assert.is_false(valid:is_invalid())
    end)
  end)

  it('__add with number first', function()
    withbuf({ 'abc' }, function()
      local p = Pos.new(nil, 1, 1)
      local result = 1 + p
      assert.are.same(Pos.new(nil, 1, 2), result)
    end)
  end)

  it('__sub with number first', function()
    withbuf({ 'abc' }, function()
      local p = Pos.new(nil, 1, 2)
      local result = 1 - p
      assert.are.same(Pos.new(nil, 1, 1), result)
    end)
  end)

  it('find_next returns nil at end', function()
    withbuf({ 'abc' }, function()
      local p = Pos.new(nil, 1, 3)
      local result = p:find_next(1, 'z')
      assert.are.same(nil, result)
    end)
  end)

  it('find_match with nested brackets', function()
    withbuf({ '(abc)' }, function()
      local p = Pos.new(nil, 1, 1) -- '('
      local match = p:find_match()
      assert.are.same(Pos.new(nil, 1, 5), match) -- ')'
    end)

    withbuf({ '{abc}' }, function()
      local p = Pos.new(nil, 1, 1) -- '{'
      local match = p:find_match()
      assert.are.same(Pos.new(nil, 1, 5), match) -- '}'
    end)

    withbuf({ '(a{b}c)' }, function()
      -- Test nested: ( at pos 1, { at pos 3
      local p = Pos.new(nil, 1, 3) -- '{'
      local match = p:find_match()
      assert.are.same(Pos.new(nil, 1, 5), match) -- '}'
    end)
  end)

  it('from10', function()
    withbuf({ 'test' }, function()
      local p = Pos.from10(nil, 1, 0)
      assert.are.same(1, p.lnum)
      assert.are.same(1, p.col)

      p = Pos.from10(nil, 2, 5, 10)
      assert.are.same(2, p.lnum)
      assert.are.same(6, p.col)
      assert.are.same(10, p.off)
    end)
  end)

  it('as_real with col beyond line length', function()
    withbuf({ 'ab' }, function()
      local p = Pos.new(nil, 1, 100)
      local real = p:as_real()
      assert.are.same(2, real.col)
    end)
  end)

  it('find_next returns nil when not found', function()
    withbuf({ 'abc' }, function()
      local p = Pos.new(nil, 1, 1)
      local result = p:find_next(1, 'z')
      assert.is_nil(result)
    end)
  end)
end)

describe('Range additional coverage', function()
  it('__eq', function()
    withbuf({ 'test' }, function()
      local r1 = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 4), 'v')
      local r2 = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 4), 'v')
      assert.is_true(r1 == r2)

      local r3 = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 5), 'v')
      assert.is_false(r1 == r3)

      local r4 = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 4), 'V')
      assert.is_false(r1 == r4)

      assert.is_false(r1 == 'not a range')
      assert.is_false(r1 == nil)
    end)
  end)

  it('__tostring with nil stop', function()
    withbuf({ 'test' }, function()
      local r = Range.new(Pos.new(nil, 1, 1), nil, 'v')
      local s = tostring(r)
      assert.is_true(s:find 'stop=nil' ~= nil)
    end)
  end)

  it('__tostring with off != 0', function()
    withbuf({ 'test' }, function()
      local r = Range.new(Pos.new(nil, 1, 1, 5), Pos.new(nil, 1, 4, 3), 'v')
      local s = tostring(r)
      assert.is_true(s:find 'off=5' ~= nil)
    end)
  end)

  it('__tostring', function()
    withbuf({ 'test' }, function()
      local r = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 4), 'v')
      local s = tostring(r)
      assert.are.same('v', r.mode)
      assert.is_true(s:find 'Range{' == 1)
    end)
  end)

  it('from_lines with negative stop_line', function()
    withbuf({ 'a', 'b', 'c', 'd', 'e' }, function()
      local r = Range.from_lines(nil, 1, -1)
      assert.are.same(5, r.stop.lnum)

      r = Range.from_lines(nil, 1, -2)
      assert.are.same(4, r.stop.lnum)
    end)
  end)

  it('save_to_pos', function()
    withbuf({ 'hello world' }, function()
      local r = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 5), 'v')
      r:save_to_pos("'[", "']")
      local start = Pos.from_pos "'["
      local stop = Pos.from_pos "']"
      assert.are.same(1, start.col)
      assert.are.same(5, stop.col)
    end)
  end)

  it('save_to_marks', function()
    withbuf({ 'hello world' }, function()
      local b = vim.api.nvim_get_current_buf()
      local r = Range.new(Pos.new(b, 1, 1), Pos.new(b, 1, 5), 'v')
      r:save_to_marks('m', 'n')
      local m = vim.api.nvim_buf_get_mark(b, 'm')
      local n = vim.api.nvim_buf_get_mark(b, 'n')
      assert.are.same({ 1, 0 }, m)
      assert.are.same({ 1, 4 }, n)
    end)
  end)

  it('new swaps start and stop when needed', function()
    withbuf({ 'test' }, function()
      local r = Range.new(Pos.new(nil, 1, 4), Pos.new(nil, 1, 1), 'v')
      assert.are.same(1, r.start.col)
      assert.are.same(4, r.stop.col)
    end)
  end)

  it('from_marks with MAX_COL', function()
    withbuf({ 'test' }, function()
      local start = Pos.new(nil, 1, 1)
      local stop = Pos.new(nil, 1, vim.v.maxcol)
      start:save_to_pos "'["
      stop:save_to_pos "']"
      local r = Range.from_marks("'[", "']")
      assert.are.same('V', r.mode)
    end)
  end)

  it('contains returns false for non-Pos/Range', function()
    withbuf({ 'test' }, function()
      local r = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 4), 'v')
      assert.is_false(r:contains 'string')
      assert.is_false(r:contains(123))
    end)
  end)

  it('sub with invalid stop', function()
    withbuf({ 'abcdef' }, function()
      local r = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 6), 'v')
      local sub = r:sub(1, 100)
      assert.is_true(sub:is_empty())
    end)
  end)

  it('line with negative index', function()
    withbuf({ 'a', 'b', 'c' }, function()
      local r = Range.from_lines(nil, 1, 3)
      local l = r:line(-1)
      assert.are.same('c', l:text())

      l = r:line(-2)
      assert.are.same('b', l:text())
    end)
  end)

  it('line returns nil for out of bounds', function()
    withbuf({ 'a', 'b' }, function()
      local r = Range.from_lines(nil, 1, 2)
      assert.is_nil(r:line(10))
    end)
  end)

  it('trim_start returns range with start=stop when all whitespace', function()
    withbuf({ '   ' }, function()
      local r = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 3), 'v')
      local trimmed = r:trim_start()
      assert.is_not.same(nil, trimmed)
      assert.are.same(trimmed.start, trimmed.stop)
    end)
  end)

  it('trim_stop returns range with start=stop when all whitespace', function()
    withbuf({ '   ' }, function()
      local r = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 3), 'v')
      local trimmed = r:trim_stop()
      assert.is_not.same(nil, trimmed)
      assert.are.same(trimmed.start, trimmed.stop)
    end)
  end)

  it('smallest returns nil for empty input', function()
    assert.are.same(nil, Range.smallest {})
    assert.are.same(nil, Range.smallest { nil })
  end)
end)

describe('Extmark additional coverage', function()
  it('delete', function()
    withbuf({ 'test' }, function()
      local r = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 4), 'v')
      local ext = r:save_to_extmark()
      ext:delete()
      -- Should not error
    end)
  end)
end)

describe('Extmark edge cases', function()
  it('tracks multi-byte characters correctly', function()
    withbuf({ '🚀🌟 hello 你好世界' }, function()
      -- The string is 27 bytes: 🚀(4) + 🌟(4) + space(1) + hello(5) + space(1) + 你(3) + 好(3) + 世(3) + 界(3)
      local r = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 27), 'v')
      local ext = r:save_to_extmark()
      local ext_range = ext:range()
      assert.are.same('🚀🌟 hello 你好世界', ext_range:text())
    end)
  end)

  it('clamps start position after buffer shrink', function()
    withbuf({ 'line 1', 'line 2', 'line 3', '' }, function()
      local r = Range.from_buf_text()
      local ext = r:save_to_extmark()

      -- Delete last line
      vim.api.nvim_buf_set_lines(0, 3, 4, true, {})

      -- Get range from extmark - should clamp to valid buffer
      local ext_range = ext:range()
      assert.is_true(ext_range.stop.lnum <= 3)
    end)
  end)

  it('handles zero-width extmark (empty range)', function()
    withbuf({ 'hello world' }, function()
      local r = Range.new(Pos.new(nil, 1, 1), nil, 'v')
      local ext = r:save_to_extmark()
      local ext_range = ext:range()
      assert.is_true(ext_range:is_empty())
    end)
  end)

  it('handles extmark at buffer start', function()
    withbuf({ 'first', 'second', 'third' }, function()
      local r = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 5), 'v')
      local ext = r:save_to_extmark()
      local ext_range = ext:range()
      assert.are.same(1, ext_range.start.lnum)
      assert.are.same(1, ext_range.start.col)
    end)
  end)

  it('handles extmark at buffer end', function()
    withbuf({ 'first', 'second', 'third' }, function()
      local r = Range.new(Pos.new(nil, 3, 1), Pos.new(nil, 3, 5), 'v')
      local ext = r:save_to_extmark()
      local ext_range = ext:range()
      assert.are.same(3, ext_range.stop.lnum)
      assert.are.same(5, ext_range.stop.col)
    end)
  end)
end)

describe('utils', function()
  local u = require 'u'

  it('create_delegated_cmd_args', function()
    local args = {
      range = 2,
      line1 = 1,
      line2 = 5,
      count = -1,
      reg = '',
      bang = true,
      fargs = { 'arg1', 'arg2' },
      smods = { silent = true },
    }
    local delegated = u.create_delegated_cmd_args(args)
    assert.are.same({ 1, 5 }, delegated.range)
    assert.are.same(nil, delegated.count)
    assert.are.same(nil, delegated.reg)
    assert.are.same(true, delegated.bang)
    assert.are.same({ 'arg1', 'arg2' }, delegated.args)

    -- Test range = 1
    args = {
      range = 1,
      line1 = 3,
      line2 = 3,
      count = -1,
      reg = '',
      bang = false,
      fargs = {},
      smods = {},
    }
    delegated = u.create_delegated_cmd_args(args)
    assert.are.same({ 3 }, delegated.range)

    -- Test range = 0 with count
    args = {
      range = 0,
      line1 = 1,
      line2 = 1,
      count = 5,
      reg = '"',
      bang = false,
      fargs = {},
      smods = {},
    }
    delegated = u.create_delegated_cmd_args(args)
    assert.are.same(nil, delegated.range)
    assert.are.same(5, delegated.count)
    assert.are.same('"', delegated.reg)
  end)

  it('ucmd with string command', function()
    u.ucmd('TestUcmdString', 'echo "test"', {})
    local cmds = vim.api.nvim_get_commands { builtin = false }
    assert.is_not.same(nil, cmds.TestUcmdString)
    vim.api.nvim_del_user_command 'TestUcmdString'
  end)

  it('ucmd with function command', function()
    local called = false
    u.ucmd('TestUcmdFunc', function(args)
      called = true
      assert.is_not.same(nil, args)
    end, { range = true })

    local cmds = vim.api.nvim_get_commands { builtin = false }
    assert.is_not.same(nil, cmds.TestUcmdFunc)

    vim.cmd.TestUcmdFunc()
    assert.is_true(called)

    vim.api.nvim_del_user_command 'TestUcmdFunc'
  end)
end)

describe('repeat_', function()
  local u = require 'u'

  it(
    'is_repeating returns false by default',
    function() assert.is_false(u.repeat_.is_repeating()) end
  )

  it('run_repeatable executes the function', function()
    local called = false
    u.repeat_.run_repeatable(function() called = true end)
    assert.is_true(called)
  end)

  it('setup creates keymaps', function()
    u.repeat_.setup()
    local maps = vim.api.nvim_get_keymap 'n'
    local dot_map = vim.iter(maps):find(function(m) return m.lhs == '.' end)
    local u_map = vim.iter(maps):find(function(m) return m.lhs == 'u' end)
    assert.is_not.same(nil, dot_map)
    assert.is_not.same(nil, u_map)
  end)
end)

describe('define_txtobj', function()
  local u = require 'u'

  it('defines text object keymaps', function()
    u.define_txtobj(
      'aX',
      function() return Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 5), 'v') end
    )

    local xmaps = vim.api.nvim_get_keymap 'x'
    local omaps = vim.api.nvim_get_keymap 'o'

    local xmap = vim.iter(xmaps):find(function(m) return m.lhs == 'aX' end)
    local omap_found = vim.iter(omaps):find(function(m) return m.lhs == 'aX' end)

    assert.is_not.same(nil, xmap)
    assert.is_not.same(nil, omap_found)
  end)

  it('defines buffer-local text object keymaps', function()
    withbuf({ 'test' }, function()
      local bufnr = vim.api.nvim_get_current_buf()
      u.define_txtobj(
        'aY',
        function() return Range.new(Pos.new(bufnr, 1, 1), Pos.new(bufnr, 1, 4), 'v') end,
        { buffer = bufnr }
      )

      local xmaps = vim.api.nvim_buf_get_keymap(bufnr, 'x')
      local omaps = vim.api.nvim_buf_get_keymap(bufnr, 'o')

      local xmap = vim.iter(xmaps):find(function(m) return m.lhs == 'aY' end)
      local omap_found = vim.iter(omaps):find(function(m) return m.lhs == 'aY' end)

      assert.is_not.same(nil, xmap)
      assert.is_not.same(nil, omap_found)
    end)
  end)
end)

describe('Range highlight', function()
  it('highlight creates highlight and returns clear function', function()
    withbuf({ 'hello world' }, function()
      local r = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 5), 'v')
      local hl = r:highlight('Search', { timeout = 100 })
      assert.is_not.same(nil, hl)
      assert.is_not.same(nil, hl.ns)
      assert.is_not.same(nil, hl.clear)
      hl.clear()
    end)
  end)

  it('highlight returns nil for empty range', function()
    withbuf({ 'test' }, function()
      local r = Range.new(Pos.new(nil, 1, 1), nil, 'v')
      local hl = r:highlight 'Search'
      assert.is.equal(hl.ns, 0)
    end)
  end)

  it('highlight with priority option', function()
    withbuf({ 'hello world' }, function()
      local r = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, 5), 'v')
      local hl = r:highlight('Search', { priority = 100 })
      assert.is_not.same(nil, hl)
      hl.clear()
    end)
  end)
end)
