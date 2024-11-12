local Pos = require 'u.pos'
local State = require 'u.state'

local orig_on_yank = vim.highlight.on_yank
local on_yank_enabled = true;
(vim.highlight --[[@as any]]).on_yank = function(opts)
  if not on_yank_enabled then return end
  return orig_on_yank(opts)
end

---@class Range
---@field start Pos
---@field stop Pos|nil
---@field mode 'v'|'V'
local Range = {}

---@param start Pos
---@param stop Pos|nil
---@param mode? 'v'|'V'
---@return Range
function Range.new(start, stop, mode)
  if stop ~= nil and stop < start then
    start, stop = stop, start
  end

  local r = { start = start, stop = stop, mode = mode or 'v' }
  local function str()
    ---@param p Pos
    local function posstr(p)
      if p == nil then
        return 'nil'
      elseif p.off ~= 0 then
        return string.format('Pos(%d:%d){off=%d}', p.lnum, p.col, p.off)
      else
        return string.format('Pos(%d:%d)', p.lnum, p.col)
      end
    end

    local _1 = posstr(r.start)
    local _2 = posstr(r.stop)
    return string.format('Range{buf=%d, mode=%s, start=%s, stop=%s}', r.start.buf, r.mode, _1, _2)
  end
  setmetatable(r, { __index = Range, __tostring = str })
  return r
end

function Range.is(x)
  local mt = getmetatable(x)
  return mt and mt.__index == Range
end

---@param lpos string
---@param rpos string
---@return Range
function Range.from_marks(lpos, rpos)
  local start = Pos.from_pos(lpos)
  local stop = Pos.from_pos(rpos)

  ---@type 'v'|'V'
  local mode
  if stop:is_col_max() then
    mode = 'V'
  else
    mode = 'v'
  end

  return Range.new(start, stop, mode)
end

---@param buf? number
function Range.from_buf_text(buf)
  if buf == nil or buf == 0 then buf = vim.api.nvim_get_current_buf() end
  local num_lines = vim.api.nvim_buf_line_count(buf)

  local start = Pos.new(buf, 0, 0)
  local stop = Pos.new(buf, num_lines - 1, Pos.MAX_COL)
  return Range.new(start, stop, 'V')
end

---@param buf? number
---@param line number 0-based line index
function Range.from_line(buf, line) return Range.from_lines(buf, line, line) end

---@param buf? number
---@param start_line number 0-based line index
---@param stop_line number 0-based line index
function Range.from_lines(buf, start_line, stop_line)
  if buf == nil or buf == 0 then buf = vim.api.nvim_get_current_buf() end
  if stop_line < 0 then
    local num_lines = vim.api.nvim_buf_line_count(buf)
    stop_line = num_lines + stop_line
  end
  return Range.new(Pos.new(buf, start_line, 0), Pos.new(buf, stop_line, Pos.MAX_COL), 'V')
end

---@param text_obj string
---@param opts? { buf?: number; contains_cursor?: boolean; pos?: Pos, user_defined?: boolean }
---@return Range|nil
function Range.from_text_object(text_obj, opts)
  opts = opts or {}
  if opts.buf == nil then opts.buf = vim.api.nvim_get_current_buf() end
  if opts.contains_cursor == nil then opts.contains_cursor = false end
  if opts.user_defined == nil then opts.user_defined = false end

  ---@type "a" | "i"
  local selection_type = text_obj:sub(1, 1)
  local obj_type = text_obj:sub(#text_obj, #text_obj)
  local is_quote = vim.tbl_contains({ "'", '"', '`' }, obj_type)
  local cursor = Pos.from_pos '.'

  -- Yank, then read '[ and '] to know the bounds:
  ---@type { start: Pos; stop: Pos }
  local positions
  vim.api.nvim_buf_call(opts.buf, function()
    positions = State.run(0, function(s)
      s:track_winview()
      s:track_register '"'
      s:track_pos '.'
      s:track_pos "'["
      s:track_pos "']"

      if opts.pos ~= nil then opts.pos:save_to_pos '.' end

      local null_pos = Pos.new(0, 0, 0, 0)
      null_pos:save_to_pos "'["
      null_pos:save_to_pos "']"

      local prev_on_yank_enabled = on_yank_enabled
      on_yank_enabled = false
      vim.cmd.normal {
        cmd = 'normal',
        bang = not opts.user_defined,
        args = { '""y' .. text_obj },
        mods = { silent = true },
      }
      on_yank_enabled = prev_on_yank_enabled

      local start = Pos.from_pos "'["
      local stop = Pos.from_pos "']"

      if
        -- I have no idea why, but when yanking `i"`, the stop-mark is
        -- placed on the ending quote. For other text-objects, the stop-
        -- mark is placed before the closing character.
        (is_quote and selection_type == 'i' and stop:char() == obj_type)
        -- *Sigh*, this also sometimes happens for `it` as well.
        or (text_obj == 'it' and stop:char() == '<')
      then
        stop = stop:next(-1) or stop
      end
      return { start = start, stop = stop }
    end)
  end)
  local start = positions.start
  local stop = positions.stop
  if start == stop and start.lnum == 0 and start.col == 0 and start.off == 0 then return nil end
  if opts.contains_cursor and not Range.new(start, stop):contains(cursor) then return nil end

  if is_quote and selection_type == 'a' then
    start = start:find_next(1, obj_type) or start
    stop = stop:find_next(-1, obj_type) or stop
  end

  return Range.new(start, stop)
end

--- Get range information from the currently selected visual text.
--- Note: from within a command mapping or an opfunc, use other specialized
--- utilities, such as:
--- * Range.from_cmd_args
--- * Range.from_op_func
function Range.from_vtext()
  local r = Range.from_marks('v', '.')
  if vim.fn.mode() == 'V' then r = r:to_linewise() end
  return r
end

--- Get range information from the current text range being operated on
--- as defined by an operator-pending function. Infers line-wise vs. char-wise
--- based on the type, as given by the operator-pending function.
---@param type 'line'|'char'|'block'
function Range.from_op_func(type)
  if type == 'block' then error 'block motions not supported' end

  local range = Range.from_marks("'[", "']")
  if type == 'line' then range = range:to_linewise() end
  return range
end

--- Get range information from command arguments.
---@param args unknown
---@return Range|nil
function Range.from_cmd_args(args)
  ---@type 'v'|'V'
  local mode
  ---@type nil|Pos
  local start
  local stop
  if args.range == 0 then
    return nil
  else
    start = Pos.from_pos "'<"
    stop = Pos.from_pos "'>"
    if stop:is_col_max() then
      mode = 'V'
    else
      mode = 'v'
    end
  end
  return Range.new(start, stop, mode)
end

---
function Range.find_nearest_brackets()
  local a = Range.from_text_object('a<', { contains_cursor = true })
  local b = Range.from_text_object('a[', { contains_cursor = true })
  local c = Range.from_text_object('a(', { contains_cursor = true })
  local d = Range.from_text_object('a{', { contains_cursor = true })
  return Range.smallest { a, b, c, d }
end

function Range.find_nearest_quotes()
  local a = Range.from_text_object([[a']], { contains_cursor = true })
  if a ~= nil and a:is_empty() then a = nil end
  local b = Range.from_text_object([[a"]], { contains_cursor = true })
  if b ~= nil and b:is_empty() then b = nil end
  local c = Range.from_text_object([[a`]], { contains_cursor = true })
  if c ~= nil and c:is_empty() then c = nil end
  return Range.smallest { a, b, c }
end

---@param ranges (Range|nil)[]
function Range.smallest(ranges)
  ---@type Range[]
  local new_ranges = {}
  for _, r in pairs(ranges) do
    if r ~= nil then table.insert(new_ranges, r) end
  end
  ranges = new_ranges
  if #ranges == 0 then return nil end

  -- find smallest match
  local max_start = ranges[1].start
  local min_stop = ranges[1].stop
  local result = ranges[1]

  for _, r in ipairs(ranges) do
    local start, stop = r.start, r.stop
    if start > max_start and stop < min_stop then
      max_start = start
      min_stop = stop
      result = r
    end
  end

  return result
end

function Range:clone() return Range.new(self.start:clone(), self.stop ~= nil and self.stop:clone() or nil, self.mode) end
function Range:line_count()
  if self:is_empty() then return 0 end
  return self.stop.lnum - self.start.lnum + 1
end

function Range:to_linewise()
  local r = self:clone()

  r.mode = 'V'
  r.start.col = 0
  if r.stop ~= nil then r.stop.col = Pos.MAX_COL end

  return r
end

function Range:is_empty() return self.stop == nil end

function Range:trim_start()
  if self:is_empty() then return end

  local r = self:clone()
  while r.start:char():match '%s' do
    local next = r.start:next(1)
    if next == nil then break end
    r.start = next
  end
  return r
end

function Range:trim_stop()
  if self:is_empty() then return end

  local r = self:clone()
  while r.stop:char():match '%s' do
    local next = r.stop:next(-1)
    if next == nil then break end
    r.stop = next
  end
  return r
end

---@param p Pos
function Range:contains(p) return not self:is_empty() and p >= self.start and p <= self.stop end

---@return string[]
function Range:lines()
  if self:is_empty() then return {} end

  local lines = {}
  for i = 0, self.stop.lnum - self.start.lnum do
    local line = self:line0(i)
    if line ~= nil then table.insert(lines, line.text()) end
  end
  return lines
end

---@return string
function Range:text() return vim.fn.join(self:lines(), '\n') end

---@param i number 1-based
---@param j? number 1-based
function Range:sub(i, j) return self:text():sub(i, j) end

---@param l number
---@return { line: string; idx0: { start: number; stop: number; }; lnum: number; range: fun():Range; text: fun():string }|nil
function Range:line0(l)
  if l < 0 then return self:line0(self:line_count() + l) end
  if l > self:line_count() then return end

  local line = vim.api.nvim_buf_get_lines(self.start.buf, self.start.lnum + l, self.start.lnum + l + 1, false)[1]
  if line == nil then return end

  local start = 0
  local stop = #line - 1
  if l == 0 then start = self.start.col end
  if l == self.stop.lnum - self.start.lnum then stop = self.stop.col end
  if stop == Pos.MAX_COL then stop = #line - 1 end
  local lnum = self.start.lnum + l

  return {
    line = line,
    idx0 = { start = start, stop = stop },
    lnum = lnum,
    range = function()
      return Range.new(
        Pos.new(self.start.buf, lnum, start, self.start.off),
        Pos.new(self.start.buf, lnum, stop, self.stop.off),
        'v'
      )
    end,
    text = function() return line:sub(start + 1, stop + 1) end,
  }
end

---@param replacement nil|string|string[]
function Range:replace(replacement)
  if replacement == nil then replacement = {} end
  if type(replacement) == 'string' then replacement = vim.fn.split(replacement, '\n') end

  local buf = self.start.buf
  -- convert to start-inclusive, stop-exclusive coordinates:
  local start_lnum, stop_lnum = self.start.lnum, (self.stop and self.stop.lnum or self.start.lnum) + 1
  local start_col, stop_col = self.start.col, (self.stop and self.stop.col or self.start.col) + 1

  local replace_type = (self:is_empty() and 'insert') or (self.mode == 'v' and 'region') or 'lines'

  ---@param alnum number
  ---@param acol number
  ---@param blnum number
  ---@param bcol number
  local function set_text(alnum, acol, blnum, bcol, repl)
    -- row indices are end-inclusive, and column indices are end-exclusive.
    vim.api.nvim_buf_set_text(buf, alnum, acol, blnum, bcol, repl)

    local new_last_line_num = self.start.lnum + #replacement - 1
    local new_last_col = #(replacement[#replacement] or '')
    if new_last_line_num == start_lnum then new_last_col = new_last_col + start_col - 1 end

    self.stop = Pos.new(buf, new_last_line_num, new_last_col)
  end

  ---@param alnum number
  ---@param blnum number
  local function set_lines(alnum, blnum, repl)
    -- indexing is zero-based, end-exclusive
    vim.api.nvim_buf_set_lines(buf, alnum, blnum, false, repl)

    if #repl == 0 then
      self.stop = nil
    else
      local new_last_line_num = start_lnum + #replacement - 1
      self.stop = Pos.new(self.start.buf, new_last_line_num, Pos.MAX_COL, self.stop.off)
    end
    self.mode = 'v'
  end

  if replace_type == 'insert' then
    set_text(start_lnum, start_col, start_lnum, start_col, replacement)
  elseif replace_type == 'region' then
    -- Fixup the bounds:
    local last_line = vim.api.nvim_buf_get_lines(buf, stop_lnum - 1, stop_lnum, false)[1] or ''
    local max_col = #last_line
    set_text(start_lnum, start_col, stop_lnum - 1, math.min(stop_col, max_col), replacement)
  elseif replace_type == 'lines' then
    set_lines(start_lnum, stop_lnum, replacement)
  else
    error 'unreachable'
  end
end

---@param amount number
function Range:shrink(amount)
  local start = self.start
  local stop = self.stop
  if stop == nil then return self:clone() end

  for _ = 1, amount do
    local next_start = start:next(1)
    local next_stop = stop:next(-1)
    if next_start == nil or next_stop == nil then return end
    start = next_start
    stop = next_stop
    if next_start > next_stop then break end
  end
  if start > stop then stop = nil end
  return Range.new(start, stop, self.mode)
end

---@param amount number
function Range:must_shrink(amount)
  local shrunk = self:shrink(amount)
  if shrunk == nil or shrunk:is_empty() then error 'error in Range:must_shrink: Range:shrink() returned nil' end
  return shrunk
end

---@param left string
---@param right string
function Range:save_to_pos(left, right)
  if self:is_empty() then
    self.start:save_to_pos(left)
    self.start:save_to_pos(right)
  else
    self.start:save_to_pos(left)
    self.stop:save_to_pos(right)
  end
end

---@param left string
---@param right string
function Range:save_to_marks(left, right)
  if self:is_empty() then
    self.start:save_to_mark(left)
    self.start:save_to_mark(right)
  else
    self.start:save_to_mark(left)
    self.stop:save_to_mark(right)
  end
end

function Range:set_visual_selection()
  if self:is_empty() then return end

  if vim.api.nvim_get_current_buf() ~= self.start.buf then vim.api.nvim_set_current_buf(self.start.buf) end

  State.run(self.start.buf, function(s)
    s:track_mark 'a'
    s:track_mark 'b'

    self.start:save_to_mark 'a'
    self.stop:save_to_mark 'b'
    local mode = self.mode

    local normal_cmd_args = ''
    if vim.api.nvim_get_mode().mode == 'n' then normal_cmd_args = normal_cmd_args .. mode end
    normal_cmd_args = normal_cmd_args .. '`ao`b'
    vim.cmd { cmd = 'normal', args = { normal_cmd_args }, bang = true }

    return nil
  end)
end

---@param group string
---@param opts? { timeout?: number, priority?: number, on_macro?: boolean }
function Range:highlight(group, opts)
  if self:is_empty() then return end

  opts = opts or { on_macro = false }
  if opts.on_macro == nil then opts.on_macro = false end

  local in_macro = vim.fn.reg_executing() ~= ''
  if not opts.on_macro and in_macro then return { clear = function() end } end

  local ns = vim.api.nvim_create_namespace ''
  State.run(self.start.buf, function(s)
    if not in_macro then s:track_winview() end

    vim.highlight.range(
      self.start.buf,
      ns,
      group,
      { self.start.lnum, self.start.col },
      { self.stop.lnum, self.stop.col },
      {
        inclusive = true,
        priority = opts.priority,
        regtype = self.mode,
      }
    )

    return nil
  end)
  vim.cmd.redraw()

  local function clear()
    vim.api.nvim_buf_clear_namespace(self.start.buf, ns, self.start.lnum, self.stop.lnum + 1)
    vim.cmd.redraw()
  end
  if opts.timeout ~= nil then vim.defer_fn(clear, opts.timeout) end

  return { ns = ns, clear = clear }
end

return Range
