local Range = require 'tt.range'
local Pos = require 'tt.pos'
local withbuf = require '__tt_test_tools'

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
      local range = Range.new(Pos.new(nil, 0, 1), Pos.new(nil, 0, 3), 'v')
      local lines = range:lines()
      assert.are.same({ 'ine' }, lines)

      local text = range:text()
      assert.are.same('ine', text)
    end)
  end)

  it('get from positions: v across multiple lines', function()
    withbuf({ 'pre line', 'the quick brown fox', 'jumps over a lazy dog', 'post line' }, function()
      local range = Range.new(Pos.new(nil, 1, 4), Pos.new(nil, 2, 4), 'v')
      local lines = range:lines()
      assert.are.same({ 'quick brown fox', 'jumps' }, lines)
    end)
  end)

  it('get from positions: V', function()
    withbuf({ 'line one', 'and line two' }, function()
      local range = Range.new(Pos.new(nil, 0, 0), Pos.new(nil, 0, Pos.MAX_COL), 'V')
      local lines = range:lines()
      assert.are.same({ 'line one' }, lines)

      local text = range:text()
      assert.are.same('line one', text)
    end)
  end)

  it('get from positions: V across multiple lines', function()
    withbuf({ 'pre line', 'the quick brown fox', 'jumps over a lazy dog', 'post line' }, function()
      local range = Range.new(Pos.new(nil, 1, 0), Pos.new(nil, 2, Pos.MAX_COL), 'V')
      local lines = range:lines()
      assert.are.same({ 'the quick brown fox', 'jumps over a lazy dog' }, lines)
    end)
  end)

  it('get from line', function()
    withbuf({ 'line one', 'and line two' }, function()
      local range = Range.from_line(nil, 0)
      local lines = range:lines()
      assert.are.same({ 'line one' }, lines)

      local text = range:text()
      assert.are.same('line one', text)
    end)
  end)

  it('get from lines', function()
    withbuf({ 'line one', 'and line two', 'and line 3' }, function()
      local range = Range.from_lines(nil, 0, 1)
      local lines = range:lines()
      assert.are.same({ 'line one', 'and line two' }, lines)

      local text = range:text()
      assert.are.same('line one\nand line two', text)
    end)
  end)

  it('replace within line', function()
    withbuf({ 'pre line', 'the quick brown fox', 'jumps over a lazy dog', 'post line' }, function()
      local range = Range.new(Pos.new(nil, 1, 4), Pos.new(nil, 1, 8), 'v')
      range:replace 'quack'

      local text = Range.from_line(nil, 1):text()
      assert.are.same('the quack brown fox', text)
    end)
  end)

  it('delete within line', function()
    withbuf({ 'pre line', 'the quick brown fox', 'jumps over a lazy dog', 'post line' }, function()
      local range = Range.new(Pos.new(nil, 1, 4), Pos.new(nil, 1, 9), 'v')
      range:replace ''

      local text = Range.from_line(nil, 1):text()
      assert.are.same('the brown fox', text)
    end)

    withbuf({ 'pre line', 'the quick brown fox', 'jumps over a lazy dog', 'post line' }, function()
      local range = Range.new(Pos.new(nil, 1, 4), Pos.new(nil, 1, 9), 'v')
      range:replace(nil)

      local text = Range.from_line(nil, 1):text()
      assert.are.same('the brown fox', text)
    end)
  end)

  it('replace across multiple lines: v', function()
    withbuf({ 'pre line', 'the quick brown fox', 'jumps over a lazy dog', 'post line' }, function()
      local range = Range.new(Pos.new(nil, 1, 4), Pos.new(nil, 2, 4), 'v')
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
      local range = Range.from_line(nil, 1)
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
      local range = Range.from_lines(nil, 1, 2)
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
      local range = Range.from_line(nil, 1)
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
      local range = Range.from_lines(nil, 1, 2)
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
      assert.are.same('quick ', Range.from_text_object('aw'):text())

      vim.fn.setpos('.', { 0, 1, 5, 0 })
      assert.are.same('quick', Range.from_text_object('iw'):text())
    end)
  end)

  it('text object: quote', function()
    withbuf({ [[the "quick" brown fox]] }, function()
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      assert.are.same('"quick"', Range.from_text_object('a"'):text())

      vim.fn.setpos('.', { 0, 1, 6, 0 })
      assert.are.same('quick', Range.from_text_object('i"'):text())
    end)

    withbuf({ [[the 'quick' brown fox]] }, function()
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      assert.are.same("'quick'", Range.from_text_object([[a']]):text())

      vim.fn.setpos('.', { 0, 1, 6, 0 })
      assert.are.same('quick', Range.from_text_object([[i']]):text())
    end)

    withbuf({ [[the `quick` brown fox]] }, function()
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      assert.are.same('`quick`', Range.from_text_object([[a`]]):text())

      vim.fn.setpos('.', { 0, 1, 6, 0 })
      assert.are.same('quick', Range.from_text_object([[i`]]):text())
    end)
  end)

  it('text object: block', function()
    withbuf({ 'this is a {', 'block', '} here' }, function()
      vim.fn.setpos('.', { 0, 2, 1, 0 })
      assert.are.same('{\nblock\n}', Range.from_text_object('a{'):text())

      vim.fn.setpos('.', { 0, 2, 1, 0 })
      assert.are.same('block', Range.from_text_object('i{'):text())
    end)
  end)

  it('text object: restores cursor position', function()
    withbuf({ 'this is a {block} here' }, function()
      vim.fn.setpos('.', { 0, 1, 13, 0 })
      assert.are.same('{block}', Range.from_text_object('a{'):text())
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

  it('line0', function()
    withbuf({
      'this is a {',
      'block',
      '} here',
    }, function()
      local range = Range.new(Pos.new(0, 0, 5), Pos.new(0, 1, 4), 'v')
      local lfirst = range:line0(0)
      assert.are.same(5, lfirst.idx0.start)
      assert.are.same(10, lfirst.idx0.stop)
      assert.are.same(0, lfirst.lnum)
      assert.are.same('is a {', lfirst.text())
      assert.are.same('is a {', lfirst.range():text())
      assert.are.same(Pos.new(0, 0, 5), lfirst.range().start)
      assert.are.same(Pos.new(0, 0, 10), lfirst.range().stop)
      assert.are.same('block', range:line0(1).text())
    end)
  end)
end)
