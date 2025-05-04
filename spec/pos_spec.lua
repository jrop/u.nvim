local Pos = require 'u.pos'
local withbuf = loadfile './spec/withbuf.lua'()

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
