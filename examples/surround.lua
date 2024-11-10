local vim_repeat = require 'u.repeat'
local opkeymap = require 'u.opkeymap'
local Pos = require 'u.pos'
local Range = require 'u.range'
local Buffer = require 'u.buffer'
local CodeWriter = require 'u.codewriter'

local M = {}

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

---@return { left: string; right: string }|nil
local function prompt_for_bounds()
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
    return { left = tag, right = endtag }
  else
    -- Default surround:
    return (surrounds)[c] or { left = c, right = c }
  end
end

---@param range Range
---@param bounds { left: string; right: string }
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
    local cw = CodeWriter.from_line(buf:line0(range.start.lnum):text(), buf.buf)

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

function M.setup()
  require('u.repeat').setup()

  -- Visual
  vim.keymap.set('v', 'S', function()
    local c = vim.fn.getcharstr()
    local range = Range.from_vtext()
    local bounds = surrounds[c] or { left = c, right = c }
    vim_repeat.run(function()
      do_surround(range, bounds)
      -- this is a visual mapping: end in normal mode:
      vim.cmd { cmd = 'normal', args = { '' }, bang = true }
    end)
  end, { noremap = true, silent = true })

  -- Change
  vim.keymap.set('n', 'cs', function()
    local from_cn = vim.fn.getchar()
    -- Check for non-printable characters:
    if from_cn < 32 or from_cn > 126 then return end
    local from_c = vim.fn.nr2char(from_cn)
    local from = surrounds[from_c] or { left = from_c, right = from_c }

    local arange = Range.from_text_object('a' .. from_c, { user_defined = true })
    if arange == nil then return nil end
    local hl_info1 = Range.new(arange.start, arange.start, 'v'):highlight('IncSearch', { priority = 999 })
    local hl_info2 = Range.new(arange.stop, arange.stop, 'v'):highlight('IncSearch', { priority = 999 })
    local hl_clear = function()
      hl_info1.clear()
      hl_info2.clear()
    end

    local to = prompt_for_bounds()
    hl_clear()
    if to == nil then return end

    vim_repeat.run(function()
      if from_c == 't' then
        -- For tags, we want to replace the inner text, not the tag:
        local irange = Range.from_text_object('i' .. from_c, { user_defined = true })
        if arange == nil or irange == nil then return nil end

        local lrange = Range.new(arange.start, irange.start:must_next(-1))
        local rrange = Range.new(irange.stop:must_next(1), arange.stop)

        rrange:replace(to.right)
        lrange:replace(to.left)
      else
        -- replace `from.right` with `to.right`:
        local last_line = arange:line0(-1).text() --[[@as string]]
        local from_right_match = last_line:match(vim.pesc(from.right) .. '$')
        if from_right_match then
          local match_start = arange.stop:clone()
          match_start.col = match_start.col - #from_right_match + 1
          Range.new(match_start, arange.stop):replace(to.right)
        end

        -- replace `from.left` with `to.left`:
        local first_line = arange:line0(0).text() --[[@as string]]
        local from_left_match = first_line:match('^' .. vim.pesc(from.left))
        if from_left_match then
          local match_end = arange.start:clone()
          match_end.col = match_end.col + #from_left_match - 1
          Range.new(arange.start, match_end):replace(to.left)
        end
      end
    end)
  end, { noremap = true, silent = true })

  -- Delete
  vim.keymap.set('n', 'ds', function()
    local txt_obj = vim.fn.getcharstr()
    vim_repeat.run(function()
      local buf = Buffer.current()
      local irange = Range.from_text_object('i' .. txt_obj)
      local arange = Range.from_text_object('a' .. txt_obj)
      if arange == nil or irange == nil then return nil end
      local starting_cursor_pos = arange.start:clone()

      -- Now, replace `arange` with the content of `irange`.  If `arange` was multiple lines,
      -- dedent the contents first, and operate in linewise mode
      if arange.start.lnum ~= arange.stop.lnum then
        -- Auto dedent:
        vim.cmd.normal('<i' .. vim.trim(txt_obj))
        -- Dedenting moves the cursor, so we need to set the cursor to a consistent starting spot:
        arange.start:save_to_pos '.'
        -- Dedenting also changed the inner text, so re-acquire it:
        arange = Range.from_text_object('a' .. txt_obj)
        irange = Range.from_text_object('i' .. txt_obj)
        if arange == nil or irange == nil then return end -- should never be true
        arange:replace(irange:lines())

        local final_range = Range.new(
          arange.start,
          Pos.new(
            arange.stop.buf,
            irange.start.lnum + (arange.stop.lnum + arange.start.lnum),
            arange.stop.col,
            arange.stop.off
          ),
          irange.mode
        )

        -- delete last line, if it is empty:
        local last = buf:line0(final_range.stop.lnum)
        if last:text():match '^%s*$' then last:replace(nil) end

        -- delete first line, if it is empty:
        local first = buf:line0(final_range.start.lnum)
        if first:text():match '^%s*$' then first:replace(nil) end
      else
        -- trim start:
        irange = irange:trim_start():trim_stop()
        arange:replace(irange:lines())
      end

      starting_cursor_pos:save_to_pos '.'
    end)
  end, { noremap = true, silent = true })

  opkeymap('n', 'ys', function(range)
    local hl_info = range:highlight('IncSearch', { priority = 999 })

    ---@type { left: string; right: string }
    local bounds
    -- selene: allow(global_usage)
    if _G.my_surround_bounds ~= nil then
      -- This command was repeated with `.`, we don't need
      -- to prompt for the bounds:
      -- selene: allow(global_usage)
      bounds = _G.my_surround_bounds
    else
      local prompted_bounds = prompt_for_bounds()
      if prompted_bounds == nil then return hl_info.clear() end
      bounds = prompted_bounds
    end

    hl_info.clear()
    do_surround(range, bounds)
    -- selene: allow(global_usage)
    _G.my_surround_bounds = nil

    -- return repeatable injection
    return function()
      -- on_repeat, we "stage" the bounds that we were originally called with:
      -- selene: allow(global_usage)
      _G.my_surround_bounds = bounds
    end
  end)
end

return M
