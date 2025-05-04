local R = require 'u.renderer'
local withbuf = loadfile './spec/withbuf.lua'()

local function getlines() return vim.api.nvim_buf_get_lines(0, 0, -1, true) end

describe('Renderer', function()
  it('should render text in an empty buffer', function()
    withbuf({}, function()
      local r = R.Renderer.new(0)
      r:render { 'hello', ' ', 'world' }
      assert.are.same(getlines(), { 'hello world' })
    end)
  end)

  it('should result in the correct text after repeated renders', function()
    withbuf({}, function()
      local r = R.Renderer.new(0)
      r:render { 'hello', ' ', 'world' }
      assert.are.same(getlines(), { 'hello world' })

      r:render { 'goodbye', ' ', 'world' }
      assert.are.same(getlines(), { 'goodbye world' })

      r:render { 'hello', ' ', 'universe' }
      assert.are.same(getlines(), { 'hello universe' })
    end)
  end)

  it('should handle tags correctly', function()
    withbuf({}, function()
      local r = R.Renderer.new(0)
      r:render {
        R.h('text', { hl = 'HighlightGroup' }, 'hello '),
        R.h('text', { hl = 'HighlightGroup' }, 'world'),
      }
      assert.are.same(getlines(), { 'hello world' })
    end)
  end)

  it('should reconcile added lines', function()
    withbuf({}, function()
      local r = R.Renderer.new(0)
      r:render { 'line 1', '\n', 'line 2' }
      assert.are.same(getlines(), { 'line 1', 'line 2' })

      -- Add a new line:
      r:render { 'line 1', '\n', 'line 2\n', 'line 3' }
      assert.are.same(getlines(), { 'line 1', 'line 2', 'line 3' })
    end)
  end)

  it('should reconcile deleted lines', function()
    withbuf({}, function()
      local r = R.Renderer.new(0)
      r:render { 'line 1', '\nline 2', '\nline 3' }
      assert.are.same(getlines(), { 'line 1', 'line 2', 'line 3' })

      -- Remove a line:
      r:render { 'line 1', '\nline 3' }
      assert.are.same(getlines(), { 'line 1', 'line 3' })
    end)
  end)

  it('should handle multiple nested elements', function()
    withbuf({}, function()
      local r = R.Renderer.new(0)
      r:render {
        R.h('text', {}, {
          'first line',
        }),
        '\n',
        R.h('text', {}, 'second line'),
      }
      assert.are.same(getlines(), { 'first line', 'second line' })

      r:render {
        R.h('text', {}, 'updated first line'),
        '\n',
        R.h('text', {}, 'third line'),
      }
      assert.are.same(getlines(), { 'updated first line', 'third line' })
    end)
  end)

  --
  -- get_pos_infos
  --

  it('should return no extmarks for an empty buffer', function()
    withbuf({}, function()
      local r = R.Renderer.new(0)
      local pos_infos = r:get_pos_infos { 0, 0 }
      assert.are.same(pos_infos, {})
    end)
  end)

  it('should return correct extmark for a given position', function()
    withbuf({}, function()
      local r = R.Renderer.new(0)
      r:render {
        R.h('text', { hl = 'HighlightGroup1' }, 'Hello'),
        R.h('text', { hl = 'HighlightGroup2' }, ' World'),
      }

      local pos_infos = r:get_pos_infos { 0, 2 }

      assert.are.same(#pos_infos, 1)
      assert.are.same(pos_infos[1].tag.attributes.hl, 'HighlightGroup1')
      assert.are.same(pos_infos[1].extmark.start, { 0, 0 })
      assert.are.same(pos_infos[1].extmark.stop, { 0, 5 })
    end)
  end)

  it('should return multiple extmarks for overlapping text', function()
    withbuf({}, function()
      local r = R.Renderer.new(0)
      r:render {
        R.h('text', { hl = 'HighlightGroup1' }, {
          'Hello',
          R.h(
            'text',
            { hl = 'HighlightGroup2', extmark = { hl_group = 'HighlightGroup2' } },
            ' World'
          ),
        }),
      }

      local pos_infos = r:get_pos_infos { 0, 5 }

      assert.are.same(#pos_infos, 2)
      assert.are.same(pos_infos[1].tag.attributes.hl, 'HighlightGroup2')
      assert.are.same(pos_infos[2].tag.attributes.hl, 'HighlightGroup1')
    end)
  end)
end)
