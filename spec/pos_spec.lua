local Pos = require 'u.pos'
local withbuf = loadfile './spec/withbuf.lua'()

describe('Pos', function()
  it('get a char from a given position', function()
    withbuf({ 'asdf', 'bleh', 'a', '', 'goo' }, function()
      assert.are.same('a', Pos.new(nil, 0, 0):char())
      assert.are.same('d', Pos.new(nil, 0, 2):char())
      assert.are.same('f', Pos.new(nil, 0, 3):char())
      assert.are.same('a', Pos.new(nil, 2, 0):char())
      assert.are.same('', Pos.new(nil, 3, 0):char())
      assert.are.same('o', Pos.new(nil, 4, 2):char())
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
      assert.are.same(Pos.new(nil, 0, 1), Pos.new(nil, 0, 0):next())
      -- line 1: d => f
      assert.are.same(Pos.new(nil, 0, 3), Pos.new(nil, 0, 2):next())
      -- line 1 => 2
      assert.are.same(Pos.new(nil, 1, 0), Pos.new(nil, 0, 3):next())
      -- line 3 => 4
      assert.are.same(Pos.new(nil, 3, 0), Pos.new(nil, 2, 0):next())
      -- line 4 => 5
      assert.are.same(Pos.new(nil, 4, 0), Pos.new(nil, 3, 0):next())
      -- end returns nil
      assert.are.same(nil, Pos.new(nil, 4, 2):next())
    end)
  end)

  it('get the previous position', function()
    withbuf({ 'asdf', 'bleh', 'a', '', 'goo' }, function()
      -- line 1: s => a
      assert.are.same(Pos.new(nil, 0, 0), Pos.new(nil, 0, 1):next(-1))
      -- line 1: f => d
      assert.are.same(Pos.new(nil, 0, 2), Pos.new(nil, 0, 3):next(-1))
      -- line 2 => 1
      assert.are.same(Pos.new(nil, 0, 3), Pos.new(nil, 1, 0):next(-1))
      -- line 4 => 3
      assert.are.same(Pos.new(nil, 2, 0), Pos.new(nil, 3, 0):next(-1))
      -- line 5 => 4
      assert.are.same(Pos.new(nil, 3, 0), Pos.new(nil, 4, 0):next(-1))
      -- beginning returns nil
      assert.are.same(nil, Pos.new(nil, 0, 0):next(-1))
    end)
  end)

  it('find matching brackets', function()
    withbuf({ 'asdf ({} def <[{}]>) ;lkj' }, function()
      -- outer parens are matched:
      assert.are.same(Pos.new(nil, 0, 19), Pos.new(nil, 0, 5):find_match())
      -- outer parens are matched (backward):
      assert.are.same(Pos.new(nil, 0, 5), Pos.new(nil, 0, 19):find_match())
      -- no potential match returns nil
      assert.are.same(nil, Pos.new(nil, 0, 0):find_match())
      -- watchdog expires before an otherwise valid match is found:
      assert.are.same(nil, Pos.new(nil, 0, 5):find_match(2))
    end)
  end)
end)
