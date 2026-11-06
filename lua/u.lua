local M = {}

--------------------------------------------------------------------------------
-- Local helpers
--------------------------------------------------------------------------------

local ESC = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)
local NS = vim.api.nvim_create_namespace 'u.range'
local EMPTY_RANGE = 'expected a non-empty range'

local OPEN_TO_CLOSE = { ['('] = ')', ['['] = ']', ['{'] = '}', ['<'] = '>' }
local CLOSE_TO_OPEN = {}
for open, close in pairs(OPEN_TO_CLOSE) do
  CLOSE_TO_OPEN[close] = open
end

--- @param bufnr integer
--- @param lnum integer 1-based
--- @return string
local function line_text(bufnr, lnum)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
  assert(line, 'line out of range')
  return line
end

--------------------------------------------------------------------------------
-- Pos class
--------------------------------------------------------------------------------

--- @class u.Pos
--- @field bufnr integer buffer number
--- @field lnum integer 1-based line index
--- @field col integer 1-based column index
--- @field off integer
local Pos = {}
Pos.__index = Pos

function Pos.__tostring(self)
  if self.off ~= 0 then
    return string.format('Pos(%d:%d){bufnr=%d, off=%d}', self.lnum, self.col, self.bufnr, self.off)
  else
    return string.format('Pos(%d:%d){bufnr=%d}', self.lnum, self.col, self.bufnr)
  end
end

--- @param bufnr? integer
--- @param lnum integer 1-based
--- @param col integer 1-based
--- @param off? integer
--- @return u.Pos
function Pos.new(bufnr, lnum, col, off)
  if bufnr == nil or bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  if off == nil then off = 0 end
  --- @type u.Pos
  return setmetatable({
    bufnr = bufnr,
    lnum = lnum,
    col = col,
    off = off,
  }, Pos)
end

--- @param bufnr? integer
--- @param lnum0 integer 0-based line index
--- @param col0 integer 0-based column index
--- @param off? integer
function Pos.from00(bufnr, lnum0, col0, off) return Pos.new(bufnr, lnum0 + 1, col0 + 1, off) end

--- @param bufnr? integer
--- @param lnum0 integer 0-based line index
--- @param col1 integer 1-based column index
--- @param off? integer
function Pos.from01(bufnr, lnum0, col1, off) return Pos.new(bufnr, lnum0 + 1, col1, off) end

--- @param bufnr? integer
--- @param lnum1 integer 1-based line index
--- @param col0 integer 0-based column index
--- @param off? integer
function Pos.from10(bufnr, lnum1, col0, off) return Pos.new(bufnr, lnum1, col0 + 1, off) end

function Pos.invalid()
  --- Built directly instead of through `Pos.new` because `Pos.new` resolves `bufnr = 0`
  --- to the current buffer, and an invalid position must not be tied to one.
  return setmetatable({ bufnr = 0, lnum = 0, col = 0, off = 0 }, Pos)
end

function Pos.__lt(a, b)
  return a.bufnr == b.bufnr and (a.lnum < b.lnum or (a.lnum == b.lnum and a.col < b.col))
end
function Pos.__le(a, b) return a < b or a == b end
function Pos.__eq(a, b)
  return getmetatable(a) == Pos
    and getmetatable(b) == Pos
    and a.bufnr == b.bufnr
    and a.lnum == b.lnum
    and a.col == b.col
end
--- Moves `x` by `y` characters in `dir`, accepting the number on either side of the
--- operator. Returns nil for any other operand combination or when the move leaves the
--- buffer.
--- @param x u.Pos|number
--- @param y u.Pos|number
--- @param dir -1|1
--- @return u.Pos|nil
local function shift_pos(x, y, dir)
  if type(x) == 'number' then
    x, y = y, x
  end
  if getmetatable(x) ~= Pos or type(y) ~= 'number' then return nil end

  local steps = dir * y
  local step = steps < 0 and -1 or 1

  local pos = x --[[@as u.Pos]]
  for _ = 1, math.abs(steps) do
    local next_pos = pos:next(step)
    if next_pos == nil then return nil end
    pos = next_pos
  end
  return pos
end

function Pos.__add(x, y) return shift_pos(x, y, 1) end
function Pos.__sub(x, y) return shift_pos(x, y, -1) end

--- @param bufnr? integer
--- @param lnum integer
--- @return u.Pos
function Pos.from_eol(bufnr, lnum)
  if bufnr == nil or bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  local pos = Pos.new(bufnr, lnum, 0)
  pos.col = pos:line():len()
  return pos
end

--- @param name string
--- @return u.Pos
function Pos.from_pos(name)
  local p = vim.fn.getpos(name)
  return Pos.new(p[1], p[2], p[3], p[4])
end

function Pos:is_invalid() return self.lnum == 0 and self.col == 0 and self.off == 0 end

function Pos:clone() return Pos.new(self.bufnr, self.lnum, self.col, self.off) end

--- @return boolean
function Pos:is_col_max() return self.col == vim.v.maxcol end

--- Normalize the position to a real one by clamping `col` to the end of the line.
--- Vim represents "past the end of line" with `vim.v.maxcol`, so a position carrying
--- that column stays virtual until it passes through here.
function Pos:as_real()
  return Pos.new(
    self.bufnr,
    self.lnum,
    math.min(self.col, #line_text(self.bufnr, self.lnum)),
    self.off
  )
end

function Pos:as_vim() return { self.bufnr, self.lnum, self.col, self.off } end

function Pos:eol() return Pos.from_eol(self.bufnr, self.lnum) end

--- @param pos string
function Pos:save_to_pos(pos) vim.fn.setpos(pos, { self.bufnr, self.lnum, self.col, self.off }) end

--- @param winnr? integer
function Pos:save_to_cursor(winnr)
  vim.api.nvim_win_set_cursor(winnr or 0, { self.lnum, self.col - 1 })
end

--- @param mark string
function Pos:save_to_mark(mark)
  local p = self:as_real()
  vim.api.nvim_buf_set_mark(p.bufnr, mark, p.lnum, p.col - 1, {})
end

--- @return string
function Pos:char() return line_text(self.bufnr, self.lnum):sub(self.col, self.col) end

function Pos:line() return line_text(self.bufnr, self.lnum) end

--- @param dir? -1|1
--- @param must? boolean
--- @return u.Pos|nil
function Pos:next(dir, must)
  local function at_edge()
    if must then error 'error in Pos:next(): Pos:next() returned nil' end
    return nil
  end

  if dir == nil or dir == 1 then
    local num_lines = vim.api.nvim_buf_line_count(self.bufnr)
    local last_line = line_text(self.bufnr, num_lines)
    if self.lnum == num_lines and self.col == #last_line then return at_edge() end

    local col = self.col + 1
    local line = self.lnum
    local line_max_col = #line_text(self.bufnr, self.lnum)
    if col > line_max_col then
      col = 1
      line = line + 1
    end
    return Pos.new(self.bufnr, line, col, self.off)
  end

  if self.col == 1 and self.lnum == 1 then return at_edge() end

  local col = self.col - 1
  local line = self.lnum
  if col < 1 then
    col = math.max(#line_text(self.bufnr, self.lnum - 1), 1)
    line = line - 1
  end
  return Pos.new(self.bufnr, line, col, self.off)
end

--- Like `next`, but errors instead of returning nil at the edge of the buffer.
--- @param dir? -1|1
--- @return u.Pos
function Pos:must_next(dir)
  local pos = self:next(dir, true)
  assert(pos ~= nil, 'unreachable')
  return pos
end

--- @param dir -1|1
--- @param predicate fun(p: u.Pos): boolean
--- @param test_current? boolean
function Pos:next_while(dir, predicate, test_current)
  if test_current and not predicate(self) then return end
  local curr = self
  while true do
    local next = curr:next(dir)
    if next == nil or not predicate(next) then break end
    curr = next
  end
  return curr
end

--- @param dir -1|1
--- @param predicate string|fun(p: u.Pos): boolean
function Pos:find_next(dir, predicate)
  if type(predicate) == 'string' then
    local s = predicate
    predicate = function(p) return s == p:char() end
  end

  --- @type u.Pos|nil
  local curr = self
  while curr ~= nil do
    if predicate(curr) then return curr end
    curr = curr:next(dir)
  end
  return curr
end

--- Finds the matching bracket/paren for the current position.
---
--- The scan walks in the direction the bracket faces and treats a nested group as one
--- step, so a sibling group such as the `(a)` in `{(a)b}` is skipped instead of being
--- scanned again.
---
--- @param max_chars? integer|nil Safety limit on how many positions the scan may visit
--- @param invocations? u.Pos[] Tracks positions to prevent infinite recursion
--- @return u.Pos|nil
function Pos:find_match(max_chars, invocations)
  if invocations == nil then invocations = {} end
  if vim.tbl_contains(invocations, function(p) return self == p end, { predicate = true }) then
    return nil
  end
  table.insert(invocations, self)

  local c = self:char()
  local c_match = OPEN_TO_CLOSE[c] or CLOSE_TO_OPEN[c]
  if c_match == nil then return nil end

  local is_opener = OPEN_TO_CLOSE[c] ~= nil
  local dir = is_opener and 1 or -1

  local cur = self
  while true do
    if max_chars ~= nil then
      max_chars = max_chars - 1
      if max_chars < 0 then return nil end
    end

    local next_cur = cur:next(dir)
    if next_cur == nil then return nil end
    cur = next_cur

    local c2 = cur:char()
    if c2 == c_match then return cur end

    -- Skip the whole nested group in one step. Matching a closer scans backward to its
    -- opener, so the next iteration must advance from that match rather than into it.
    if (is_opener and OPEN_TO_CLOSE[c2]) or (not is_opener and CLOSE_TO_OPEN[c2]) then
      local match = cur:find_match(max_chars, invocations)
      if match == nil then return nil end
      cur = match
    end
  end
end

--- @param lines string|string[]
function Pos:insert_before(lines)
  if type(lines) == 'string' then lines = vim.split(lines, '\n') end
  vim.api.nvim_buf_set_text(
    self.bufnr,
    self.lnum - 1,
    self.col - 1,
    self.lnum - 1,
    self.col - 1,
    lines
  )
end

--------------------------------------------------------------------------------
-- Range class (forward declared for Extmark)
--------------------------------------------------------------------------------

--- @class u.Range
--- @field start u.Pos
--- @field stop u.Pos|nil
--- @field mode 'v'|'V'
local Range = {}

--------------------------------------------------------------------------------
-- Extmark class
--------------------------------------------------------------------------------

--- @class u.Extmark
--- @field bufnr integer
--- @field id integer
--- @field nsid integer
local Extmark = {}
Extmark.__index = Extmark

--- @param bufnr integer
--- @param nsid integer
--- @param id integer
function Extmark.new(bufnr, nsid, id)
  return setmetatable({
    bufnr = bufnr,
    nsid = nsid,
    id = id,
  }, Extmark)
end

--- @param range u.Range
--- @param nsid integer
function Extmark.from_range(range, nsid)
  local r = range:to_charwise()
  local stop = r.stop or r.start
  local end_row = stop.lnum - 1
  local end_col = r:is_empty() and (r.start.col - 1) or stop.col
  if range.mode == 'V' then
    end_row = end_row + 1
    end_col = 0
  end
  local id = vim.api.nvim_buf_set_extmark(r.start.bufnr, nsid, r.start.lnum - 1, r.start.col - 1, {
    right_gravity = false,
    end_right_gravity = true,
    end_row = end_row,
    end_col = end_col,
  })
  return Extmark.new(r.start.bufnr, nsid, id)
end

function Extmark:range()
  local raw_extmark =
    vim.api.nvim_buf_get_extmark_by_id(self.bufnr, self.nsid, self.id, { details = true })
  local start_row0, start_col0, details = unpack(raw_extmark)

  --- @type u.Pos
  local start = Pos.from00(self.bufnr, start_row0, start_col0)
  --- @type u.Pos?
  local stop = details
    and details.end_row
    and details.end_col
    and Pos.from01(self.bufnr, details.end_row, details.end_col)

  local n_buf_lines = vim.api.nvim_buf_line_count(self.bufnr)
  if stop and stop.lnum > n_buf_lines then
    stop.lnum = n_buf_lines
    stop = stop:eol()
  end
  if stop and stop.col == 0 then
    stop.col = 1
    stop = stop:next(-1)
  end

  return Range.new(start, stop, 'v')
end

function Extmark:delete() vim.api.nvim_buf_del_extmark(self.bufnr, self.nsid, self.id) end

--------------------------------------------------------------------------------
-- Range class (full implementation)
--------------------------------------------------------------------------------

Range.__index = Range
function Range.__tostring(self)
  --- @param p u.Pos
  local function posstr(p)
    if p == nil then
      return 'nil'
    elseif p.off ~= 0 then
      return string.format('Pos(%d:%d){off=%d}', p.lnum, p.col, p.off)
    else
      return string.format('Pos(%d:%d)', p.lnum, p.col)
    end
  end

  local start_str = posstr(self.start)
  local stop_str = posstr(self.stop)
  return string.format(
    'Range{bufnr=%d, mode=%s, start=%s, stop=%s}',
    self.start.bufnr,
    self.mode,
    start_str,
    stop_str
  )
end
function Range.__eq(a, b)
  return getmetatable(a) == Range
    and getmetatable(b) == Range
    and a.mode == b.mode
    and a.start == b.start
    and a.stop == b.stop
end

--------------------------------------------------------------------------------
-- Range constructors:
--------------------------------------------------------------------------------

--- @param start u.Pos
--- @param stop u.Pos|nil
--- @param mode? 'v'|'V'
--- @return u.Range
function Range.new(start, stop, mode)
  if stop ~= nil and stop < start then
    start, stop = stop, start
  end

  -- `u.Range` is the class of the module table (methods and statics), so the instance
  -- shape is asserted here, where the metatable makes it true:
  return setmetatable({ start = start, stop = stop, mode = mode or 'v' }, Range) --[[@as u.Range]]
end

--- @param ranges (u.Range|nil)[]
function Range.smallest(ranges)
  --- @type u.Range[]
  ranges = vim.iter(ranges):filter(function(r) return r ~= nil and not r:is_empty() end):totable()
  if #ranges == 0 then return nil end

  -- find smallest match
  local smallest = ranges[1]
  local smallest_stop = assert(smallest.stop, EMPTY_RANGE)
  for _, r in ipairs(ranges) do
    local stop = assert(r.stop, EMPTY_RANGE)
    if r.start > smallest.start and stop < smallest_stop then
      smallest = r
      smallest_stop = stop
    end
  end
  return smallest
end

--- @param lpos string
--- @param rpos string
--- @return u.Range
function Range.from_marks(lpos, rpos)
  local start = Pos.from_pos(lpos)
  local stop = Pos.from_pos(rpos)

  --- @type 'v'|'V'
  local mode
  if stop:is_col_max() then
    mode = 'V'
  else
    mode = 'v'
  end

  return Range.new(start, stop, mode)
end

--- @param bufnr? integer
function Range.from_buf_text(bufnr)
  if bufnr == nil or bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  local num_lines = vim.api.nvim_buf_line_count(bufnr)

  local start = Pos.new(bufnr, 1, 1)
  local stop = Pos.new(bufnr, num_lines, vim.v.maxcol)
  return Range.new(start, stop, 'V')
end

--- @param bufnr? integer
--- @param line integer 1-based line index
function Range.from_line(bufnr, line) return Range.from_lines(bufnr, line, line) end

--- @param bufnr? integer
--- @param start_line integer 1-based line index
--- @param stop_line integer 1-based line index; negative counts from the end
function Range.from_lines(bufnr, start_line, stop_line)
  if bufnr == nil or bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  if stop_line < 0 then
    local num_lines = vim.api.nvim_buf_line_count(bufnr)
    stop_line = num_lines + stop_line + 1
  end
  return Range.new(Pos.new(bufnr, start_line, 1), Pos.new(bufnr, stop_line, vim.v.maxcol), 'V')
end

local BRACKET_MAP = {
  ['('] = '(',
  [')'] = '(',
  ['b'] = '(',
  ['{'] = '{',
  ['}'] = '{',
  ['B'] = '{',
  ['['] = '[',
  [']'] = '[',
  ['<'] = '<',
  ['>'] = '<',
}

local QUOTE_MAP = { ["'"] = true, ['"'] = true, ['`'] = true }

--- The editor state that running a motion can disturb, saved so it can be put back.
--- @class u._MotionState
--- @field winview table
--- @field unnamed_register string
--- @field cursor integer[]
--- @field mark_lbracket integer[]
--- @field mark_rbracket integer[]
--- @field opfunc string
--- @field prev_captured_range u.Range|nil
--- @field prev_mode string
--- @field vinf u.Range
--- @field vinf_inverted boolean

--- The range captured by the most recent `g@` invocation. Vim can only reach a global
--- function by name, so the one global below is defined at module scope and writes this
--- local; ordinary code reads the local.
--- @type u.Range|nil
local captured_range = nil

--- @param ty 'line'|'char'|'block'
function _G.Range__from_motion_opfunc(ty) captured_range = Range.from_op_func(ty) end

--- @return u._MotionState
local function capture_editor_state()
  local vinf, vinf_inverted = Range.from_vtext()
  return {
    winview = vim.fn.winsaveview(),
    unnamed_register = vim.fn.getreg '"',
    cursor = vim.fn.getpos '.',
    mark_lbracket = vim.fn.getpos "'[",
    mark_rbracket = vim.fn.getpos "']",
    -- `operatorfunc` is a string option; the analyzer widens it to `string|function`
    -- because some options accept function values.
    opfunc = vim.go.operatorfunc --[[@as string]],
    prev_captured_range = captured_range,
    prev_mode = vim.fn.mode(),
    vinf = vinf,
    vinf_inverted = vinf_inverted,
  }
end

--- @param state u._MotionState
local function restore_editor_state(state)
  vim.fn.winrestview(state.winview)
  vim.fn.setreg('"', state.unnamed_register)
  vim.fn.setpos('.', state.cursor)
  vim.fn.setpos("'[", state.mark_lbracket)
  vim.fn.setpos("']", state.mark_rbracket)
  if state.prev_mode ~= 'n' then state.vinf:set_visual_selection(state.vinf_inverted) end
  vim.go.operatorfunc = state.opfunc
  captured_range = state.prev_captured_range
end

--- @class u.MotionOpts
--- @field bufnr? integer
--- @field contains_cursor? boolean
--- @field pos? u.Pos
--- @field user_defined? boolean
--- @field max_lines? integer
--- @field max_col? integer

--- Whether `target` occurs inside the window described by the bounds, i.e. whether the
--- expensive `g@` invocation can possibly find the text object. Returns true when the
--- motion has no single-character target or when no bounds are configured.
--- @param target string|nil
--- @param bufnr integer
--- @param max_lines integer|nil
--- @param max_col integer|nil
--- @return boolean
local function target_within_bounds(target, bufnr, max_lines, max_col)
  if target == nil then return true end
  if max_lines == nil or max_lines <= 0 then return true end

  local cur = vim.fn.line '.'
  local line_start = cur - max_lines
  if line_start < 1 then line_start = 1 end
  local last_line = vim.api.nvim_buf_line_count(bufnr)
  local line_end = cur + max_lines
  if line_end > last_line then line_end = last_line end

  local chunk = vim.api.nvim_buf_get_lines(bufnr, line_start - 1, line_end, false)
  for _, line in ipairs(chunk) do
    local pos = line:find(target, 1, true)
    if pos and (max_col == nil or pos <= max_col) then return true end
  end
  return false
end

--- @param motion string
--- @param opts? u.MotionOpts
--- @return u.Range|nil
function Range.from_motion(motion, opts)
  local o = opts or {}
  local bufnr = o.bufnr
  if bufnr == nil or bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  local contains_cursor = o.contains_cursor == true
  local user_defined = o.user_defined == true

  local scope, motion_rest = motion:sub(1, 1), motion:sub(2)
  local is_txtobj = scope == 'a' or scope == 'i'
  local is_quote_txtobj = is_txtobj and QUOTE_MAP[motion_rest] == true
  local is_bracket_txtobj = is_txtobj and BRACKET_MAP[motion_rest] ~= nil
  -- Only text objects have a single character that the pre-check can look for:
  local target = (is_bracket_txtobj and BRACKET_MAP[motion_rest])
    or (is_quote_txtobj and motion_rest)
    or nil

  local state = capture_editor_state()
  captured_range = nil

  vim.api.nvim_buf_call(bufnr, function()
    if o.pos ~= nil then o.pos:save_to_pos '.' end
    if not target_within_bounds(target, bufnr, o.max_lines, o.max_col) then return end

    local old_eventignore = vim.o.eventignore
    vim.o.eventignore = 'all'
    vim.go.operatorfunc = 'v:lua.Range__from_motion_opfunc'
    vim.cmd {
      cmd = 'normal',
      args = { ESC .. 'g@' .. motion },
      bang = not user_defined,
      mods = { keepjumps = true, silent = true },
    }
    vim.o.eventignore = old_eventignore
  end)
  local result = captured_range

  restore_editor_state(state)

  if not result then return nil end

  local stop = assert(result.stop, EMPTY_RANGE)

  -- Vim reports text-object bounds inconsistently, so correct the known cases:
  if
    -- I have no idea why, but when yanking `i"`, the stop-mark is
    -- placed on the ending quote. For other text-objects, the stop-
    -- mark is placed before the closing character.
    (is_quote_txtobj and scope == 'i' and stop:char() == motion_rest)
    -- *Sigh*, this also sometimes happens for `it` as well.
    or (motion == 'it' and stop:char() == '<')
  then
    stop = stop:next(-1) or stop
    result.stop = stop
  end
  if is_quote_txtobj and scope == 'a' then
    result.start = result.start:find_next(1, motion_rest) or result.start
    stop = stop:find_next(-1, motion_rest) or stop
    result.stop = stop
  end

  -- The motion can land outside the cursor, for example on a neighboring line:
  if contains_cursor and not result:contains(Pos.new(unpack(state.cursor))) then return nil end

  return result
end

--- @param bufnr? integer
--- @param query string
--- @param opts? { contains_cursor?: boolean } Defaults to filtering captures by the cursor.
function Range.from_tsquery_caps(bufnr, query, opts)
  local o = opts or {}
  local contains_cursor = o.contains_cursor ~= false

  local ranges = Range.from_buf_text(bufnr):tsquery(query)
  if not ranges then return end
  if not contains_cursor then return ranges end

  local cursor = Pos.from_pos '.'
  return vim.tbl_map(function(cap_ranges)
    return vim
      .iter(cap_ranges)
      :filter(
        --- @param r u.Range
        function(r) return r:contains(cursor) end
      )
      :totable()
  end, ranges)
end

--- Get range information from the currently selected visual text.
--- Note: from within a command mapping or an opfunc, use other specialized
--- utilities, such as:
--- * Range.from_cmd_args
--- * Range.from_op_func
function Range.from_vtext()
  local r = Range.from_marks('v', '.')
  if vim.fn.mode() == 'V' then r = r:to_linewise() end
  local inverted = Pos.from_pos '.' ~= r.stop
  return r, inverted
end

--- Get range information from the current text range being operated on
--- as defined by an operator-pending function. Infers line-wise vs. char-wise
--- based on the type, as given by the operator-pending function.
--- @param type 'line'|'char'|'block'
function Range.from_op_func(type)
  if type == 'block' then error 'block motions not supported' end

  local range = Range.from_marks("'[", "']")
  if type == 'line' then range = range:to_linewise() end
  return range
end

--- Get range information from command arguments.
--- @param args u.utils.RawCmdArgs
--- @return u.Range|nil
function Range.from_cmd_args(args)
  if args.range == 0 then return nil end

  local bufnr = vim.api.nvim_get_current_buf()
  if args.range == 1 then
    return Range.new(Pos.new(bufnr, args.line1, 1), Pos.new(bufnr, args.line1, vim.v.maxcol), 'V')
  end

  local is_visual = vim.fn.histget('cmd', -1):sub(1, 5) == [['<,'>]]
  if is_visual then
    local mode = vim.fn.visualmode() == 'V' and 'V' or 'v'
    return Range.new(Pos.from_pos "'<", Pos.from_pos "'>", mode)
  end
  return Range.new(Pos.new(bufnr, args.line1, 1), Pos.new(bufnr, args.line2, vim.v.maxcol), 'V')
end

--- @class u.NearestOpts
--- @field max_lines? integer
--- @field max_col? integer

--- @param motions string[]
--- @param opts? u.NearestOpts
--- @return u.Range|nil
local function find_nearest(motions, opts)
  local o = opts or {}
  local copts = { contains_cursor = true, max_lines = o.max_lines, max_col = o.max_col }

  local ranges = {}
  for i, motion in ipairs(motions) do
    ranges[i] = Range.from_motion(motion, copts)
  end
  return Range.smallest(ranges)
end

--- @param opts? u.NearestOpts
--- @return u.Range|nil
function Range.find_nearest_brackets(opts) return find_nearest({ 'a<', 'a[', 'a(', 'a{' }, opts) end

--- @param opts? u.NearestOpts
--- @return u.Range|nil
function Range.find_nearest_quotes(opts) return find_nearest({ [[a']], [[a"]], [[a`]] }, opts) end

--------------------------------------------------------------------------------
-- Structural utilities:
--------------------------------------------------------------------------------

function Range:clone()
  return Range.new(self.start:clone(), self.stop ~= nil and self.stop:clone() or nil, self.mode)
end

function Range:is_empty() return self.stop == nil end

function Range:to_linewise()
  local r = self:clone()

  r.mode = 'V'
  r.start.col = 1
  if r.stop ~= nil then r.stop.col = vim.v.maxcol end

  return r
end

function Range:to_charwise()
  local r = self:clone()
  r.mode = 'v'
  if r.stop and r.stop:is_col_max() then r.stop = r.stop:as_real() end
  return r
end

--- @param x u.Pos | u.Range
function Range:contains(x)
  if getmetatable(x) == Pos then
    local pos = x --[[@as u.Pos]]
    local stop = self.stop
    return stop ~= nil and pos >= self.start and pos <= stop
  elseif getmetatable(x) == Range then
    local other = x --[[@as u.Range]]
    local stop = other.stop
    if stop == nil then return false end
    return self:contains(other.start) and self:contains(stop)
  end
  return false
end

--- @param other u.Range
--- @return u.Range|nil, u.Range|nil
function Range:difference(other)
  local outer, inner = self, other
  if not outer:contains(inner) then
    outer, inner = inner, outer
  end
  if not outer:contains(inner) then return nil, nil end
  local outer_stop = assert(outer.stop, EMPTY_RANGE)
  local inner_stop = assert(inner.stop, EMPTY_RANGE)

  local left
  if outer.start ~= inner.start then
    left = Range.new(outer.start, inner.start:clone():next(-1))
  else
    left = Range.new(outer.start) -- empty range
  end

  local right
  if inner_stop ~= outer_stop then
    local start = assert(inner_stop:clone():next(1))
    right = Range.new(start, outer_stop)
  else
    right = Range.new(inner_stop) -- empty range
  end

  return left, right
end

--- @param left string
--- @param right string
function Range:save_to_pos(left, right)
  self.start:save_to_pos(left)
  local last = self.stop or self.start
  last:save_to_pos(right)
end

--- @param left string
--- @param right string
function Range:save_to_marks(left, right)
  self.start:save_to_mark(left)
  local last = self.stop or self.start
  last:save_to_mark(right)
end

function Range:save_to_extmark() return Extmark.from_range(self, NS) end

--- @param inverted boolean?
function Range:set_visual_selection(inverted)
  if self:is_empty() then return end
  if vim.api.nvim_get_current_buf() ~= self.start.bufnr then
    error 'Range:set_visual_selection() called on a buffer other than the current buffer'
  end

  local curr_mode = vim.fn.mode():sub(1, 1)
  if curr_mode ~= self.mode then vim.cmd.normal { args = { ESC .. self.mode }, bang = true } end

  local start, stop = self.start, assert(self.stop, EMPTY_RANGE)
  if inverted then
    start, stop = stop, start
  end
  start:save_to_pos '.'
  vim.cmd.normal { args = { 'o' }, bang = true }
  stop:save_to_pos '.'
end

--------------------------------------------------------------------------------
-- Text access/manipulation utilities:
--------------------------------------------------------------------------------

--- @param query string
function Range:tsquery(query)
  local bufnr = self.start.bufnr

  local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
  if lang == nil then return end
  local parser = vim.treesitter.get_parser(bufnr, lang)
  if parser == nil then return end
  local trees = parser:parse()
  local tree = trees and trees[1]
  if tree == nil then return end

  local root = tree:root()
  local q = vim.treesitter.query.parse(lang, query)
  --- @type table<string, u.Range[]>
  local ranges = {}
  for id, match, _meta in
    q:iter_captures(root, bufnr, self.start.lnum - 1, (self.stop or self.start).lnum)
  do
    local start_row0, start_col0, stop_row0, stop_col0 = match:range()
    local range = Range.new(
      Pos.new(bufnr, start_row0 + 1, start_col0 + 1),
      Pos.new(bufnr, stop_row0 + 1, stop_col0),
      'v'
    )
    local stop = assert(range.stop, EMPTY_RANGE)
    if stop.lnum > vim.api.nvim_buf_line_count(bufnr) then range.stop = stop:must_next(-1) end

    local capture_name = q.captures[id]
    if not ranges[capture_name] then ranges[capture_name] = {} end
    if self:contains(range) then table.insert(ranges[capture_name], range) end
  end

  return ranges
end

--- The per-line bounds of the range, as reported by `getregionpos`: one `{ start, stop }`
--- pair per line. The geometry is fetched once so that callers needing several offsets,
--- such as `sub`, do not walk the region again for each one.
--- @return integer[][][]
function Range:line_spans()
  local stop = assert(self.stop, EMPTY_RANGE)
  return vim.fn.getregionpos(self.start:as_real():as_vim(), stop:as_real():as_vim(), { type = 'v' })
end

--- @param bounds integer[][]
--- @return integer lnum, integer col, integer len
local function span_at(bounds)
  local start = assert(bounds[1])
  local stop = assert(bounds[2])
  local col = assert(start[3])
  return assert(start[2]), col, assert(stop[3]) - col + 1
end

--- @param spans integer[][][]
--- @return integer
local function spans_length(spans)
  if #spans == 0 then return 0 end

  local len = #spans - 1 -- one newline between each pair of lines
  for _, bounds in ipairs(spans) do
    local _, _, line_len = span_at(bounds)
    len = len + line_len
  end
  return len
end

function Range:length()
  if self:is_empty() then return 0 end
  return spans_length(self:line_spans())
end

function Range:line_count()
  if self:is_empty() then return 0 end
  local stop = assert(self.stop, EMPTY_RANGE)
  return stop.lnum - self.start.lnum + 1
end

--- Trims whitespace from one end of a copy of the range.
--- @param dir -1|1 `1` trims the start, `-1` trims the stop
--- @return u.Range|nil
function Range:_trim(dir)
  if self:is_empty() then return nil end

  local r = self:clone()
  local pos = dir == 1 and r.start or assert(r.stop)
  while pos:char():match '%s' do
    local next = pos:next(dir)
    if next == nil then break end
    pos = next
  end

  if dir == 1 then
    r.start = pos
  else
    r.stop = pos
  end
  return r
end

--- @return u.Range|nil
function Range:trim_start() return self:_trim(1) end

--- @return u.Range|nil
function Range:trim_stop() return self:_trim(-1) end

--- @param i integer 1-based
--- @param j? integer 1-based
function Range:sub(i, j)
  local spans = self:line_spans()

  --- @param idx integer 1-based
  --- @return u.Pos|nil
  local function get_pos(idx)
    if idx < 0 then return get_pos(spans_length(spans) + idx + 1) end

    -- find the position of the first line that contains the idx-th character:
    local curr_len = 0
    for linenr, bounds in ipairs(spans) do
      local lnum, col, line_len = span_at(bounds)
      if linenr > 1 then curr_len = curr_len + 1 end -- each newline is counted as a char

      if curr_len + line_len >= idx then
        return Pos.new(self.start.bufnr, lnum, col + (idx - curr_len) - 1)
      end
      curr_len = curr_len + line_len
    end
  end

  local start = get_pos(i)
  if not start then
    -- start is invalid, so return an empty range:
    return Range.new(self.start, nil, self.mode)
  end

  local stop
  if j then stop = get_pos(j) end
  if not stop then
    -- stop is invalid, so return an empty range:
    return Range.new(start, nil, self.mode)
  end
  return Range.new(start, stop, 'v')
end

--- @return string[]
function Range:lines()
  if self:is_empty() then return {} end
  local stop = assert(self.stop, EMPTY_RANGE)
  return vim.fn.getregion(self.start:as_vim(), stop:as_vim(), { type = self.mode })
end

--- @return string
function Range:text() return vim.fn.join(self:lines(), '\n') end

--- @param l integer
--- @return u.Range|nil
function Range:line(l)
  if l < 0 then l = self:line_count() + l + 1 end
  if l < 1 or l > self:line_count() then return end

  -- `line` works from the range's own mode and raw columns: `line_spans` normalizes to
  -- charwise geometry, which would clamp a column on an empty line down to zero.
  local range_stop = assert(self.stop, EMPTY_RANGE)
  local line_indices =
    vim.fn.getregionpos(self.start:as_vim(), range_stop:as_vim(), { type = self.mode })
  -- `getregionpos` returns one entry per line for a valid range:
  local line_bounds = assert(line_indices[l], 'missing bounds for range line')

  local start = Pos.new(unpack(line_bounds[1]))
  local line_end = Pos.new(unpack(line_bounds[2]))
  return Range.new(start, line_end)
end

--- @param replacement nil|string|string[]
function Range:replace(replacement)
  if replacement == nil then replacement = {} end
  if type(replacement) == 'string' then replacement = vim.fn.split(replacement, '\n') end

  local bufnr = self.start.bufnr
  local empty = self:is_empty()

  local function update_stop_non_linewise()
    local new_last_line_num = self.start.lnum + #replacement - 1
    local new_last_col = #(replacement[#replacement] or '')
    if new_last_line_num == self.start.lnum then
      new_last_col = new_last_col + self.start.col - 1
    end
    self.stop = Pos.new(bufnr, new_last_line_num, new_last_col)
  end
  local function update_stop_linewise()
    if #replacement == 0 then
      self.stop = nil
    else
      local new_last_line_num = self.start.lnum - 1 + #replacement - 1
      local stop = assert(self.stop, EMPTY_RANGE)
      self.stop = Pos.new(bufnr, new_last_line_num + 1, vim.v.maxcol, stop.off)
    end
    self.mode = 'v'
  end

  if empty then
    -- To insert text at a given `(row, column)` location, use `start_row =
    -- end_row = row` and `start_col = end_col = col`.
    vim.api.nvim_buf_set_text(
      bufnr,
      self.start.lnum - 1,
      self.start.col - 1,
      self.start.lnum - 1,
      self.start.col - 1,
      replacement
    )
    update_stop_non_linewise()
  elseif self.mode ~= 'v' then
    -- Indexing is zero-based, end-exclusive.
    local stop = assert(self.stop, EMPTY_RANGE)
    vim.api.nvim_buf_set_lines(bufnr, self.start.lnum - 1, stop.lnum, true, replacement)
    update_stop_linewise()
  else
    -- Indexing is zero-based. Row indices are end-inclusive, and column indices
    -- are end-exclusive.
    local stop = assert(self.stop, EMPTY_RANGE)
    vim.api.nvim_buf_set_text(
      bufnr,
      self.start.lnum - 1,
      self.start.col - 1,
      stop.lnum - 1,
      math.min(stop.col, #stop:line()),
      replacement
    )
    update_stop_non_linewise()
  end
end

--- @param amount integer
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

--- @param amount integer
function Range:must_shrink(amount)
  local shrunk = self:shrink(amount)
  if shrunk == nil or shrunk:is_empty() then
    error 'error in Range:must_shrink: Range:shrink() returned nil'
  end
  return shrunk
end

--- @class u.HighlightOpts
--- @field timeout? integer
--- @field priority? integer
--- @field on_macro? boolean

--- @param group string
--- @param opts? u.HighlightOpts
--- @return { ns: integer, clear: fun() }
function Range:highlight(group, opts)
  local o = opts or {}
  local on_macro = o.on_macro == true

  local in_macro = vim.fn.reg_executing() ~= ''
  if self:is_empty() or (in_macro and not on_macro) then
    return { ns = 0, clear = function() end }
  end

  local stop = assert(self.stop, EMPTY_RANGE)
  local ns = vim.api.nvim_create_namespace ''
  local winview = not in_macro and vim.fn.winsaveview()

  vim.hl.range(
    self.start.bufnr,
    ns,
    group,
    { self.start.lnum - 1, self.start.col - 1 },
    { stop.lnum - 1, stop.col - 1 },
    {
      inclusive = true,
      priority = o.priority,
      timeout = o.timeout,
      regtype = self.mode,
    }
  )
  if winview then vim.fn.winrestview(winview) end
  vim.cmd.redraw()

  return {
    ns = ns,
    clear = function()
      vim.api.nvim_buf_clear_namespace(self.start.bufnr, ns, self.start.lnum - 1, stop.lnum)
      vim.cmd.redraw()
    end,
  }
end

--------------------------------------------------------------------------------
-- opkeymap
--------------------------------------------------------------------------------

-- NOTE: These must be global because Neovim's 'operatorfunc' option only
-- accepts VimScript expressions (v:lua.FunctionName), not direct Lua
-- references. This is a Neovim API limitation.
--- @type (fun(range: u.Range): nil|(fun():any))|nil
local __U__OpKeymapOpFunc_rhs = nil

--- This is the global utility function used for operatorfunc in opkeymap
--- @param ty 'line'|'char'|'block'
-- selene: allow(unused_variable)
function _G.__U__OpKeymapOpFunc(ty)
  if __U__OpKeymapOpFunc_rhs ~= nil then
    local range = Range.from_op_func(ty)
    __U__OpKeymapOpFunc_rhs(range)
  end
end

--- Registers a function that operates on a text-object, triggered by the given prefix (lhs).
--- It works in the following way:
--- 1. An expression-map is set, so that whatever the callback returns is executed by Vim (in this case `g@`)
---    g@: tells vim to way for a motion, and then call operatorfunc.
--- 2. The operatorfunc is set to a lua function that computes the range being operated over, that
---    then calls the original passed callback with said range.
--- @param mode string|string[]
--- @param lhs string
--- @param rhs fun(range: u.Range): nil
--- @param opts? vim.keymap.set.Opts
local function opkeymap(mode, lhs, rhs, opts)
  vim.keymap.set(mode, lhs, function()
    -- We don't need to wrap the operation in a repeat, because expr mappings are
    -- repeated seamlessly by Vim anyway. In addition, the u.repeat:`.` mapping will
    -- set IS_REPEATING to true, so that callbacks can check if they should used cached
    -- values.
    __U__OpKeymapOpFunc_rhs = rhs
    vim.o.operatorfunc = 'v:lua.__U__OpKeymapOpFunc'
    return 'g@'
  end, vim.tbl_extend('force', opts or {}, { expr = true }))
end

--------------------------------------------------------------------------------
-- Text objects
--------------------------------------------------------------------------------

--- @param key_seq string
--- @param fn fun(key_seq: string):u.Range|nil
--- @param opts? { buffer?: integer }
local function define_txtobj(key_seq, fn, opts)
  if opts ~= nil and opts.buffer == 0 then opts.buffer = vim.api.nvim_get_current_buf() end

  local function handle_visual()
    local range = fn(key_seq)
    if range == nil or range:is_empty() then
      vim.cmd.normal(ESC)
      return
    end
    range:set_visual_selection()
  end
  vim.keymap.set({ 'x' }, key_seq, handle_visual, opts and { buffer = opts.buffer } or nil)

  local function handle_normal()
    local range = fn(key_seq)
    if range == nil then return end

    if not range:is_empty() then
      range:set_visual_selection()
    else
      local original_eventignore = vim.go.eventignore
      vim.go.eventignore = 'all'

      -- insert a single space, so we can select it:
      local p = range.start
      p:insert_before ' '
      vim.go.eventignore = original_eventignore

      -- select the space:
      Range.new(p, p, 'v'):set_visual_selection()
    end
  end
  vim.keymap.set({ 'o' }, key_seq, handle_normal, opts and { buffer = opts.buffer } or nil)
end

--------------------------------------------------------------------------------
-- repeat
--------------------------------------------------------------------------------

local repeat_ = {}

local IS_REPEATING = false
--- @type fun()|nil
local REPEAT_ACTION = nil

local function is_repeatable_last_mutator() return vim.b.changedtick <= (vim.b.my_changedtick or 0) end

--- @param f fun()
function repeat_.run_repeatable(f)
  local action = f
  REPEAT_ACTION = action
  action()
  vim.b.my_changedtick = vim.b.changedtick
end

function repeat_.is_repeating() return IS_REPEATING end

function repeat_.setup()
  vim.keymap.set('n', '.', function()
    IS_REPEATING = true
    for _ = 1, vim.v.count1 do
      local action = REPEAT_ACTION
      if is_repeatable_last_mutator() and action ~= nil then
        repeat_.run_repeatable(action)
      else
        vim.cmd { cmd = 'normal', args = { '.' }, bang = true }
      end
    end
    IS_REPEATING = false
  end)
  vim.keymap.set('n', 'u', function()
    local was_repeatable_last_mutator = is_repeatable_last_mutator()
    for _ = 1, vim.v.count1 do
      vim.cmd { cmd = 'normal', args = { 'u' }, bang = true }
    end
    if was_repeatable_last_mutator then vim.b.my_changedtick = vim.b.changedtick end
  end)
end

--------------------------------------------------------------------------------
-- User commands
--------------------------------------------------------------------------------

--- @class u.utils.QfItem
--- @field col integer
--- @field filename string
--- @field kind string
--- @field lnum integer
--- @field text string

--- @class u.utils.RawCmdArgs
--- @field args string
--- @field bang boolean
--- @field count integer
--- @field fargs string[]
--- @field line1 integer
--- @field line2 integer
--- @field mods string
--- @field name string
--- @field range 0|1|2
--- @field reg string
--- @field smods any

--- @class u.utils.CmdArgs: u.utils.RawCmdArgs
--- @field info u.Range|nil

--- @class u.utils.UcmdArgs
--- @field nargs? 0|1|'*'|'?'|'+'
--- @field range? boolean|'%'|integer
--- @field count? boolean|integer
--- @field addr? string
--- @field completion? string
--- @field force? boolean
--- @field preview? fun(opts: u.utils.UcmdArgs, ns: integer, buf: integer):0|1|2

--- Creates a user command with enhanced argument processing.
--- Automatically computes range information and attaches it as `args.info`.
---
--- @param name string The command name (without the leading colon)
--- @param cmd string | fun(args: u.utils.CmdArgs): any Command implementation
--- @param opts? u.utils.UcmdArgs Command options (nargs, range, etc.)
---
--- @usage
--- ```lua
--- -- Create a command that works with visual selections:
--- ucmd('MyCmd', function(args)
---   -- Print the visually selected text:
---   vim.print(args.info:text())
---   -- Or get the selection as an array of lines:
---   vim.print(args.info:lines())
--- end, { nargs = '*', range = true })
---
--- -- Create a command that processes the current line:
--- ucmd('ProcessLine', function(args)
---   local line_text = args.info:text()
---   -- Process the line...
--- end, { range = '%' })
---
--- -- Create a command with arguments:
--- ucmd('SearchReplace', function(args)
---   local pattern, replacement = args.fargs[1], args.fargs[2]
---   local text = args.info:text()
---   -- Perform search and replace...
--- end, { nargs = 2, range = true })
--- ```
local function ucmd(name, cmd, opts)
  opts = opts or {}
  if type(cmd) == 'function' then
    local impl = cmd
    cmd = function(args)
      args.info = Range.from_cmd_args(args)
      return impl(args)
    end
  end
  vim.api.nvim_create_user_command(name, cmd, opts --[[@as any]])
end

--- Creates command arguments for delegating from one command to another.
--- Preserves all relevant context (range, modifiers, bang, etc.) when
--- implementing a derived command in terms of a base command.
---
--- @param current_args vim.api.keyset.create_user_command.command_args|u.utils.RawCmdArgs The arguments from the current command
--- @return vim.api.keyset.cmd Arguments suitable for vim.cmd() calls
---
--- @usage
--- ```lua
--- -- Implement :MyEdit in terms of :edit, preserving all context:
--- ucmd('MyEdit', function(args)
---   local delegated_args = create_delegated_cmd_args(args)
---   -- Add custom logic here...
---   vim.cmd.edit(delegated_args)
--- end, { nargs = '*', range = true, bang = true })
---
--- -- Implement :MySubstitute that delegates to :substitute:
--- ucmd('MySubstitute', function(args)
---   -- Pre-process arguments
---   local pattern = preprocess_pattern(args.fargs[1])
---
---   local delegated_args = create_delegated_cmd_args(args)
---   delegated_args.args = { pattern, args.fargs[2] }
---
---   vim.cmd.substitute(delegated_args)
--- end, { nargs = 2, range = true, bang = true })
--- ```
local function create_delegated_cmd_args(current_args)
  --- @type integer[]?
  local range
  if current_args.range == 1 then
    range = { current_args.line1 }
  elseif current_args.range == 2 then
    range = { current_args.line1, current_args.line2 }
  end

  local count
  if current_args.count ~= -1 and current_args.range == 0 then count = current_args.count end

  --- @type vim.api.keyset.cmd
  return {
    range = range,
    count = count,
    reg = current_args.reg ~= '' and current_args.reg or nil,
    bang = current_args.bang or nil,
    args = #current_args.fargs > 0 and current_args.fargs or nil,
    mods = current_args.smods,
  }
end

--------------------------------------------------------------------------------
-- Exports
--------------------------------------------------------------------------------

M.Pos = Pos
M.Extmark = Extmark
M.Range = Range
M.opkeymap = opkeymap
M.define_txtobj = define_txtobj
M.repeat_ = repeat_
M.ucmd = ucmd
M.create_delegated_cmd_args = create_delegated_cmd_args

return M
