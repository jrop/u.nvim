local Buffer = require 'u.buffer'
local withbuf = loadfile './spec/withbuf.lua'()

describe('Buffer', function()
  it('should replace all lines', function()
    withbuf({}, function()
      local buf = Buffer.from_nr()
      buf:all():replace 'bleh'
      local actual_lines = vim.api.nvim_buf_get_lines(buf.buf, 0, -1, false)
      assert.are.same({ 'bleh' }, actual_lines)
    end)
  end)

  it('should replace all but first and last lines', function()
    withbuf({
      'one',
      'two',
      'three',
    }, function()
      local buf = Buffer.from_nr()
      buf:lines(1, -2):replace 'too'
      local actual_lines = vim.api.nvim_buf_get_lines(buf.buf, 0, -1, false)
      assert.are.same({
        'one',
        'too',
        'three',
      }, actual_lines)
    end)
  end)
end)
