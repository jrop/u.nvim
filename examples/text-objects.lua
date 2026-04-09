--
-- Custom text objects:
--   ag   - whole file
--   a.   - current line
--   aq/iq - nearest quote (any type)
--   a"/i", a'/i', a`/i` - specific quotes
--   al"/il", al'/il', al`/il` - "last" quote (searches backward)
--   alB/ilB, al]/il], alb/ilb, al>/il> - "last" bracket objects
--
local u = require 'u'
local Pos = u.Pos
local Range = u.Range

local M = {}

function M.setup()
  -- Select whole file:
  u.define_txtobj('ag', function() return Range.from_buf_text(0) end)

  -- Select current line:
  u.define_txtobj('a.', function() return Range.from_line(0, Pos.from_pos('.').lnum) end)

  -- Select the nearest quote:
  u.define_txtobj('aq', function() return Range.find_nearest_quotes() end)
  u.define_txtobj('iq', function()
    local range = Range.find_nearest_quotes()
    if range == nil then return end
    return range:shrink(1)
  end)

  ---Selects the next quote object (searches forward)
  --- @param q string
  local function define_quote_obj(q)
    local function select_around() return Range.from_motion('a' .. q) end

    u.define_txtobj('a' .. q, function() return select_around() end)
    u.define_txtobj('i' .. q, function()
      local range = select_around()
      if range == nil or range:is_empty() then return range end

      local start_next = range.start:next(1) or range.start
      local stop_prev = range.stop:next(-1)
      if start_next > stop_prev then return Range.new(start_next) end
      return range:shrink(1) or range
    end)
  end
  define_quote_obj [["]]
  define_quote_obj [[']]
  define_quote_obj [[`]]

  ---Selects the "last" quote object (searches backward)
  --- @param q string
  local function define_last_quote_obj(q)
    local function select_around()
      local curr = Pos.from_pos('.'):find_next(-1, q)
      if not curr then return end
      -- Reset visual selection to current context:
      curr:save_to_pos '.'
      return Range.from_motion('a' .. q)
    end

    u.define_txtobj('al' .. q, function() return select_around() end)
    u.define_txtobj('il' .. q, function()
      local range = select_around()
      if range == nil or range:is_empty() then return range end

      local start_next = range.start:next(1) or range.start
      local stop_prev = range.stop:next(-1)
      if start_next > stop_prev then return Range.new(start_next) end

      return range:shrink(1) or range
    end)
  end
  define_last_quote_obj [["]]
  define_last_quote_obj [[']]
  define_last_quote_obj [[`]]

  -- Selects the "last" bracket object (searches backward):
  local function define_last_bracket_obj(b, ...)
    local function select_around()
      local curr = Pos.from_pos('.'):find_next(-1, b)
      if not curr then return end

      local other = curr:find_match(1000)
      if not other then return end

      return Range.new(curr, other)
    end

    local keybinds = { ... }
    table.insert(keybinds, b)
    for _, k in ipairs(keybinds) do
      u.define_txtobj('al' .. k, function() return select_around() end)
      u.define_txtobj('il' .. k, function()
        local range = select_around()
        return range and range:shrink(1)
      end)
    end
  end
  define_last_bracket_obj('}', 'B')
  define_last_bracket_obj ']'
  define_last_bracket_obj(')', 'b')
  define_last_bracket_obj '>'
end
return M
