local Renderer = require 'u.renderer'

--- @param markup string
local function parse(markup)
  -- call private method:
  return (Renderer --[[@as any]])._parse_markup(markup)
end

describe('Renderer', function()
  it('_parse_markup: empty string', function()
    local nodes = parse [[]]
    assert.are.same({}, nodes)
  end)

  it('_parse_markup: only string', function()
    local nodes = parse [[The quick brown fox jumps over the lazy dog.]]
    assert.are.same({
      { kind = 'text', value = 'The quick brown fox jumps over the lazy dog.' },
    }, nodes)
  end)

  it('_parse_markup: &lt;', function()
    local nodes = parse [[&lt;t value="bleh" />]]
    assert.are.same({
      { kind = 'text', value = '<t value="bleh" />' },
    }, nodes)
  end)

  it('_parse_markup: empty tag', function()
    local nodes = parse [[</>]]
    assert.are.same({ { kind = 'tag', name = '', attributes = {} } }, nodes)
  end)

  it('_parse_markup: tag', function()
    local nodes = parse [[<t value="Hello" />]]
    assert.are.same({
      {
        kind = 'tag',
        name = 't',
        attributes = {
          value = 'Hello',
        },
      },
    }, nodes)
  end)

  it('_parse_markup: attributes with quotes', function()
    local nodes = parse [[<t value="Hello \"there\"" />]]
    assert.are.same({
      {
        kind = 'tag',
        name = 't',
        attributes = {
          value = 'Hello "there"',
        },
      },
    }, nodes)
  end)
end)
