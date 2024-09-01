local Buffer = require 'tt.buffer'
local withbuf = require '__tt_test_tools'

describe('Buffer', function()
  it('should replace all lines', function()
    withbuf({}, function()
      local buf = Buffer.new()
      buf:all():replace 'bleh'
      local actual_lines = vim.api.nvim_buf_get_lines(buf.buf, 0, -1, false)
      assert.are.same({ 'bleh' }, actual_lines)
    end)
  end)
end)
