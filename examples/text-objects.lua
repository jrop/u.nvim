local utils = require 'u.utils'
local Pos = require 'u.pos'
local Range = require 'u.range'
local Buffer = require 'u.buffer'

local M = {}

function M.setup()
  -- Select whole file:
  utils.define_text_object('ag', function() return Buffer.current():all() end)

  -- Select current line:
  utils.define_text_object('a.', function()
    local lnum = Pos.from_pos('.').lnum
    return Buffer.current():line0(lnum)
  end)

  -- Select the nearest quote:
  utils.define_text_object('aq', function() return Range.find_nearest_quotes() end)
  utils.define_text_object('iq', function()
    local range = Range.find_nearest_quotes()
    if range == nil then return end
    return range:shrink(1)
  end)

  ---Selects the next quote object (searches forward)
  ---@param q string
  local function define_quote_obj(q)
    local function select_around()
      -- Operator mappings are effectively running in visual mode, the way
      -- `define_text_object` is implemented, so feed the keys `a${q}` to vim
      -- to select the appropriate text-object
      vim.cmd { cmd = 'normal', args = { 'a' .. q }, bang = true }

      -- Now check on the visually selected text:
      local range = Range.from_vtext()
      if range:is_empty() then return range.start end
      range.start = range.start:find_next(1, q) or range.start
      range.stop = range.stop:find_next(-1, q) or range.stop
      return range
    end

    utils.define_text_object('a' .. q, function() return select_around() end)
    utils.define_text_object('i' .. q, function()
      local range_or_pos = select_around()
      if Range.is(range_or_pos) then
        local start_next = range_or_pos.start:next(1)
        local stop_prev = range_or_pos.stop:next(-1)
        if start_next > stop_prev then return start_next end

        local range = range_or_pos:shrink(1)
        return range
      else
        return range_or_pos
      end
    end)
  end
  define_quote_obj [["]]
  define_quote_obj [[']]
  define_quote_obj [[`]]

  ---Selects the "last" quote object (searches backward)
  ---@param q string
  local function define_last_quote_obj(q)
    local function select_around()
      local curr = Pos.from_pos('.'):find_next(-1, q)
      if not curr then return end
      -- Reset visual selection to current context:
      Range.new(curr, curr):set_visual_selection()
      vim.cmd.normal('a' .. q)
      local range = Range.from_vtext()
      if range:is_empty() then return range.start end
      range.start = range.start:find_next(1, q) or range.start
      range.stop = range.stop:find_next(-1, q) or range.stop
      return range
    end

    utils.define_text_object('al' .. q, function() return select_around() end)
    utils.define_text_object('il' .. q, function()
      local range_or_pos = select_around()
      if range_or_pos == nil then return end

      if Range.is(range_or_pos) then
        local start_next = range_or_pos.start:next(1)
        local stop_prev = range_or_pos.stop:next(-1)
        if start_next > stop_prev then return start_next end

        local range = range_or_pos:shrink(1)
        return range
      else
        return range_or_pos
      end
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
      utils.define_text_object('al' .. k, function() return select_around() end)
      utils.define_text_object('il' .. k, function()
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
