local CodeWriter = require 'tt.codewriter'

describe('CodeWriter', function()
  it('should write with indentation', function()
    local cw = CodeWriter.new()
    cw:write '{'
    cw:indent(function(cw2) cw2:write 'x: 123' end)
    cw:write '}'

    assert.are.same(cw.lines, { '{', '  x: 123', '}' })
  end)

  it('should keep relative indentation', function()
    local cw = CodeWriter.new()
    cw:write '{'
    cw:indent(function(cw2)
      cw2:write 'x: 123'
      cw2:write '  y: 123'
    end)
    cw:write '}'

    assert.are.same(cw.lines, {
      '{',
      '  x: 123',
      '    y: 123',
      '}',
    })
  end)
end)
