local vim_repeat = require 'u.repeat'
local Range = require 'u.range'
local Buffer = require 'u.buffer'
local CodeWriter = require 'u.codewriter'

local M = {}

local ESC = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)

local surrounds = {
  [')'] = { left = '(', right = ')' },
  ['('] = { left = '( ', right = ' )' },
  [']'] = { left = '[', right = ']' },
  ['['] = { left = '[ ', right = ' ]' },
  ['}'] = { left = '{', right = '}' },
  ['{'] = { left = '{ ', right = ' }' },
  ['>'] = { left = '<', right = '>' },
  ['<'] = { left = '< ', right = ' >' },
  ["'"] = { left = "'", right = "'" },
  ['"'] = { left = '"', right = '"' },
  ['`'] = { left = '`', right = '`' },
}

--- @type { left: string; right: string } | nil
local CACHED_BOUNDS = nil

--- @return { left: string; right: string }|nil
local function prompt_for_bounds()
  if vim_repeat.is_repeating() then
    -- If we are repeating, we don't want to prompt for bounds, because
    -- we want to reuse the last bounds:
    return CACHED_BOUNDS
  end

  local cn = vim.fn.getchar()
  -- Check for non-printable characters:
  if type(cn) ~= 'number' or cn < 32 or cn > 126 then return end
  local c = vim.fn.nr2char(cn)

  if c == '<' then
    -- Surround with a tag:
    vim.keymap.set('c', '>', '><CR>')
    local tag = '<' .. vim.fn.input '<'
    if tag == '<' then return end
    vim.keymap.del('c', '>')
    local endtag = '</' .. tag:sub(2):match '[^ >]*' .. '>'
    -- selene: allow(global_usage)
    CACHED_BOUNDS = { left = tag, right = endtag }
    return CACHED_BOUNDS
  else
    -- Default surround:
    CACHED_BOUNDS = (surrounds)[c] or { left = c, right = c }
    return CACHED_BOUNDS
  end
end

--- @param range u.Range
--- @param bounds { left: string; right: string }
local function do_surround(range, bounds)
  local left = bounds.left
  local right = bounds.right
  if range.mode == 'V' then
    -- If we are surrounding multiple lines, we don't care about
    -- space-padding:
    left = vim.trim(left)
    right = vim.trim(right)
  end

  if range.mode == 'v' then
    range:replace(left .. range:text() .. right)
  elseif range.mode == 'V' then
    local buf = Buffer.current()
    local cw = CodeWriter.from_line(range.start:line(), buf.bufnr)

    -- write the left bound at the current indent level:
    cw:write(left)

    local curr_ident_prefix = cw.indent_str:rep(cw.indent_level)
    cw:indent(function(cw2)
      for _, line in ipairs(range:lines()) do
        -- trim the current indent prefix from the line:
        if line:sub(1, #curr_ident_prefix) == curr_ident_prefix then
          --
          line = line:sub(#curr_ident_prefix + 1)
        end

        cw2:write(line)
      end
    end)

    -- write the right bound at the current indent level:
    cw:write(right)

    range:replace(cw.lines)
  end

  range.start:save_to_pos '.'
end

-- Add surround:
--- @param ty 'line' | 'char' | 'block'
function _G.MySurroundOpFunc(ty)
  if ty == 'block' then
    -- We won't handle block-selection:
    return
  end

  local range = Range.from_op_func(ty)
  local hl
  if not vim_repeat.is_repeating() then hl = range:highlight('IncSearch', { priority = 999 }) end

  local bounds = prompt_for_bounds()
  if hl then hl.clear() end
  if bounds == nil then return end

  do_surround(range, bounds)
end

function M.setup()
  require('u.repeat').setup()

  -- Visual
  vim.keymap.set('x', 'S', function()
    local range = Range.from_vtext()
    local bounds = prompt_for_bounds()
    if bounds == nil then return end

    do_surround(range, bounds)
    -- this is a visual mapping: end in normal mode:
    vim.cmd.normal(ESC)
  end, { noremap = true, silent = true })

  -- Change
  vim.keymap.set('n', 'cs', function()
    local from_cn = vim.fn.getchar() --[[@as number]]
    -- Check for non-printable characters:
    if from_cn < 32 or from_cn > 126 then return end

    vim_repeat.run_repeatable(function()
      local from_c = vim.fn.nr2char(from_cn)
      local from = surrounds[from_c] or { left = from_c, right = from_c }
      local function get_fresh_arange()
        local arange = Range.from_motion('a' .. from_c, { user_defined = true })
        if arange == nil then return end
        if from_c == 'q' then
          from.left = arange.start:char()
          from.right = arange.stop:char()
        end
        return arange
      end

      local arange = get_fresh_arange()
      if arange == nil then return end

      local hl_info1 = vim_repeat.is_repeating() and nil
        or Range.new(arange.start, arange.start, 'v'):highlight('IncSearch', { priority = 999 })
      local hl_info2 = vim_repeat.is_repeating() and nil
        or Range.new(arange.stop, arange.stop, 'v'):highlight('IncSearch', { priority = 999 })
      local hl_clear = function()
        if hl_info1 then hl_info1.clear() end
        if hl_info2 then hl_info2.clear() end
      end

      local to = prompt_for_bounds()
      hl_clear()
      if to == nil then return end

      if from_c == 't' then
        -- For tags, we want to replace the inner text, not the tag:
        local irange = Range.from_motion('i' .. from_c, { user_defined = true })
        if arange == nil or irange == nil then return end

        local lrange, rrange = arange:difference(irange)
        if not lrange or not rrange then return end

        rrange:replace(to.right)
        lrange:replace(to.left)
      else
        -- replace `from.right` with `to.right`:
        local right_text = arange:sub(-1, -#from.right)
        right_text:replace(to.right)

        -- replace `from.left` with `to.left`:
        local left_text = arange:sub(1, #from.left)
        left_text:replace(to.left)
      end
    end)
  end, { noremap = true, silent = true })

  -- Delete
  local CACHED_DELETE_FROM = nil
  vim.keymap.set('n', 'ds', function()
    vim_repeat.run_repeatable(function()
      local txt_obj = vim_repeat.is_repeating() and CACHED_DELETE_FROM or vim.fn.getcharstr()
      CACHED_DELETE_FROM = txt_obj

      local buf = Buffer.current()
      local irange = Range.from_motion('i' .. txt_obj)
      local arange = Range.from_motion('a' .. txt_obj)
      if arange == nil or irange == nil then return end
      local starting_cursor_pos = arange.start:clone()

      -- Now, replace `arange` with the content of `irange`.  If `arange` was multiple lines,
      -- dedent the contents first, and operate in linewise mode
      if arange.start.lnum ~= arange.stop.lnum then
        -- Auto dedent:
        vim.cmd.normal('<i' .. vim.trim(txt_obj))
        -- Dedenting moves the cursor, so we need to set the cursor to a consistent starting spot:
        arange.start:save_to_pos '.'
        -- Dedenting also changed the inner text, so re-acquire it:
        arange = Range.from_motion('a' .. txt_obj)
        irange = Range.from_motion('i' .. txt_obj)
        if arange == nil or irange == nil then return end -- should never be true
        arange:replace(irange:lines())
        -- `arange:replace(..)` updates its own `stop` position, so we will use
        -- `arange` as the final resulting range that holds the modified text

        -- delete last line, if it is empty:
        local last = buf:line(arange.stop.lnum)
        if last:text():match '^%s*$' then last:replace(nil) end

        -- delete first line, if it is empty:
        local first = buf:line(arange.start.lnum)
        if first:text():match '^%s*$' then first:replace(nil) end
      else
        -- trim start:
        irange = irange:trim_start():trim_stop()
        arange:replace(irange:lines())
      end

      starting_cursor_pos:save_to_pos '.'
    end)
  end, { noremap = true, silent = true })

  vim.keymap.set('n', 'ys', function()
    vim.o.operatorfunc = 'v:lua.MySurroundOpFunc'
    return 'g@'
  end, { expr = true })
end

return M
