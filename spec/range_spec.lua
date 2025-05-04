local Range = require 'u.range'
local Pos = require 'u.pos'
local withbuf = loadfile './spec/withbuf.lua'()

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
      local range = Range.new(Pos.new(nil, 1, 1), Pos.new(nil, 1, Pos.MAX_COL), 'V')
      local lines = range:lines()
      assert.are.same({ 'line one' }, lines)

      local text = range:text()
      assert.are.same('line one', text)
    end)
  end)

  it('get from positions: V across multiple lines', function()
    withbuf({ 'pre line', 'the quick brown fox', 'jumps over a lazy dog', 'post line' }, function()
      local range = Range.new(Pos.new(nil, 2, 1), Pos.new(nil, 3, Pos.MAX_COL), 'V')
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
      assert.are.same(range.stop, Pos.new(nil, 2, Pos.MAX_COL))
      assert.are.same(range.mode, 'V')
    end)
  end)

  it('from_cmd_args', function()
    local args = { range = 1 }
    withbuf({ 'line one', 'and line two' }, function()
      local a = Pos.new(nil, 1, 1)
      local b = Pos.new(nil, 2, 2)
      a:save_to_pos "'<"
      b:save_to_pos "'>"

      local range = Range.from_cmd_args(args)
      assert.are.same(range.start, a)
      assert.are.same(range.stop, b)
      assert.are.same(range.mode, 'v')
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
      assert.are.same(linewise_range.stop.col, Pos.MAX_COL)
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
      local r = Range.new(Pos.new(b, 2, 1), Pos.new(b, 4, Pos.MAX_COL), 'V')
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
      local r = Range.new(Pos.new(b, 2, 1), Pos.new(b, 4, Pos.MAX_COL), 'V')
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
end)
