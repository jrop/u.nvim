local M = {}

--------------------------------------------------------------------------------
-- Local helpers
--------------------------------------------------------------------------------

local ESC = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)
local NS = vim.api.nvim_create_namespace 'u.range'

--- @param bufnr integer
--- @param lnum integer 1-based
local function line_text(bufnr, lnum)
  return vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
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

--- @param bufnr? number
--- @param lnum number 1-based
--- @param col number 1-based
--- @param off? number
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

--- @param bufnr? number
--- @param lnum0 number 1-based
--- @param col0 number 1-based
--- @param off? number
function Pos.from00(bufnr, lnum0, col0, off) return Pos.new(bufnr, lnum0 + 1, col0 + 1, off) end

--- @param bufnr? number
--- @param lnum0 number 1-based
--- @param col1 number 1-based
--- @param off? number
function Pos.from01(bufnr, lnum0, col1, off) return Pos.new(bufnr, lnum0 + 1, col1, off) end

--- @param bufnr? number
--- @param lnum1 number 1-based
--- @param col0 number 1-based
--- @param off? number
function Pos.from10(bufnr, lnum1, col0, off) return Pos.new(bufnr, lnum1, col0 + 1, off) end

function Pos.invalid() return Pos.new(0, 0, 0, 0) end

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
function Pos.__add(x, y)
  if type(x) == 'number' then
    x, y = y, x
  end
  if getmetatable(x) ~= Pos or type(y) ~= 'number' then return nil end
  return x:next(y)
end
function Pos.__sub(x, y)
  if type(x) == 'number' then
    x, y = y, x
  end
  if getmetatable(x) ~= Pos or type(y) ~= 'number' then return nil end
  return x:next(-y)
end

--- @param bufnr number
--- @param lnum number
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

--- Normalize the position to a real position (take into account vim.v.maxcol).
function Pos:as_real()
  local maxlen = #line_text(self.bufnr, self.lnum)
  local col = self.col
  if col > maxlen then
    -- We could use utilities in this file to get the given line, but
    -- since this is a low-level function, we are going to optimize and
    -- use the API directly:
    col = maxlen
  end
  return Pos.new(self.bufnr, self.lnum, col, self.off)
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
function Pos:char()
  local line = line_text(self.bufnr, self.lnum)
  if line == nil then return '' end
  return line:sub(self.col, self.col)
end

function Pos:line() return line_text(self.bufnr, self.lnum) end

--- @param dir? -1|1
--- @param must? boolean
--- @return u.Pos|nil
function Pos:next(dir, must)
  if must == nil then must = false end

  if dir == nil or dir == 1 then
    -- Next:
    local num_lines = vim.api.nvim_buf_line_count(self.bufnr)
    local last_line = line_text(self.bufnr, num_lines)
    if self.lnum == num_lines and self.col == #last_line then
      if must then error 'error in Pos:next(): Pos:next() returned nil' end
      return nil
    end

    local col = self.col + 1
    local line = self.lnum
    local line_max_col = #line_text(self.bufnr, self.lnum)
    if col > line_max_col then
      col = 1
      line = line + 1
    end
    return Pos.new(self.bufnr, line, col, self.off)
  else
    -- Previous:
    if self.col == 1 and self.lnum == 1 then
      if must then error 'error in Pos:next(): Pos:next() returned nil' end
      return nil
    end

    local col = self.col - 1
    local line = self.lnum
    local prev_line_max_col = #(line_text(self.bufnr, self.lnum - 1) or '')
    if col < 1 then
      col = math.max(prev_line_max_col, 1)
      line = line - 1
    end
    return Pos.new(self.bufnr, line, col, self.off)
  end
end

--- @param dir? -1|1
function Pos:must_next(dir)
  local next = self:next(dir, true)
  if next == nil then error 'unreachable' end
  return next
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
--- Algorithm: Scans forward (for openers) or backward (for closers) until we find
--- a matching character. When encountering a nested bracket of the same type, we
--- recursively find its match first, then continue scanning. This handles deeply
--- nested structures correctly.
---
--- @param max_chars? number|nil Safety limit to prevent infinite loops
--- @param invocations? u.Pos[] Tracks positions to prevent infinite recursion
--- @return u.Pos|nil
function Pos:find_match(max_chars, invocations)
  if invocations == nil then invocations = {} end
  if vim.tbl_contains(invocations, function(p) return self == p end, { predicate = true }) then
    return nil
  end
  table.insert(invocations, self)

  local openers = { '{', '[', '(', '<' }
  local closers = { '}', ']', ')', '>' }
  local c = self:char()
  local is_opener = vim.tbl_contains(openers, c)
  local is_closer = vim.tbl_contains(closers, c)
  if not is_opener and not is_closer then return nil end

  local i, _ = vim
    .iter(is_opener and openers or closers)
    :enumerate()
    :find(function(_, c2) return c == c2 end)
  -- Store the character we will be looking for:
  local c_match = (is_opener and closers or openers)[i]

  --- @type u.Pos|nil
  local cur = self
  --- `adv` is a helper that moves the current position backward or forward,
  --- depending on whether we are looking for an opener or a closer. It returns
  --- nil if 1) the watch-dog `max_chars` falls bellow 0, or 2) if we have gone
  --- beyond the beginning/end of the file.
  --- @return u.Pos|nil
  local function adv()
    if cur == nil then return nil end

    if max_chars ~= nil then
      max_chars = max_chars - 1
      if max_chars < 0 then return nil end
    end

    return cur:next(is_opener and 1 or -1)
  end

  -- scan until we find `c_match`:
  cur = adv()
  while cur ~= nil and cur:char() ~= c_match do
    cur = adv()
    if cur == nil then break end

    local c2 = cur:char()
    if c2 == c_match then break end

    if vim.tbl_contains(openers, c2) or vim.tbl_contains(closers, c2) then
      cur = cur:find_match(max_chars, invocations)
      cur = adv() -- move past the match
    end
  end

  return cur
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

  local r = { start = start, stop = stop, mode = mode or 'v' }

  setmetatable(r, Range)
  return r
end

--- @param ranges (u.Range|nil)[]
function Range.smallest(ranges)
  --- @type u.Range[]
  ranges = vim.iter(ranges):filter(function(r) return r ~= nil and not r:is_empty() end):totable()
  if #ranges == 0 then return nil end

  -- find smallest match
  local smallest = ranges[1]
  for _, r in ipairs(ranges) do
    local start, stop = r.start, r.stop
    if start > smallest.start and stop < smallest.stop then smallest = r end
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

--- @param bufnr? number
function Range.from_buf_text(bufnr)
  if bufnr == nil or bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  local num_lines = vim.api.nvim_buf_line_count(bufnr)

  local start = Pos.new(bufnr, 1, 1)
  local stop = Pos.new(bufnr, num_lines, vim.v.maxcol)
  return Range.new(start, stop, 'V')
end

--- @param bufnr? number
--- @param line number 1-based line index
function Range.from_line(bufnr, line) return Range.from_lines(bufnr, line, line) end

--- @param bufnr? number
--- @param start_line number based line index
--- @param stop_line number based line index
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

--- @param motion string
--- @param opts? { bufnr?: number, contains_cursor?: boolean, pos?: u.Pos, user_defined?: boolean, max_lines?: number, max_col?: number }
--- @return u.Range|nil
function Range.from_motion(motion, opts)
  -- SECTION: Normalize options
  opts = opts or {}
  if opts.bufnr == nil or opts.bufnr == 0 then opts.bufnr = vim.api.nvim_get_current_buf() end
  if opts.contains_cursor == nil then opts.contains_cursor = false end
  if opts.user_defined == nil then opts.user_defined = false end

  -- SECTION: Parse motion string
  --- @type 'a'|'i', string
  local scope, motion_rest = motion:sub(1, 1), motion:sub(2)
  local is_txtobj = scope == 'a' or scope == 'i'
  local is_quote_txtobj = is_txtobj and vim.tbl_contains({ "'", '"', '`' }, motion_rest)
  local is_bracket_txtobj = is_txtobj and BRACKET_MAP[motion_rest] ~= nil

  -- SECTION: Capture original state for restoration
  local original_state = {
    winview = vim.fn.winsaveview(),
    unnamed_register = vim.fn.getreg '"',
    cursor = vim.fn.getpos '.',
    mark_lbracket = vim.fn.getpos "'[",
    mark_rbracket = vim.fn.getpos "']",
    opfunc = vim.go.operatorfunc,
    prev_captured_range = _G.Range__from_motion_opfunc_captured_range,
    prev_mode = vim.fn.mode(),
    vinf = Range.from_vtext(),
  }
  --- @type u.Range|nil
  _G.Range__from_motion_opfunc_captured_range = nil

  -- SECTION: Execute motion and capture result
  vim.api.nvim_buf_call(opts.bufnr, function()
    if opts.pos ~= nil then opts.pos:save_to_pos '.' end

    -- Pre-check: skip expensive g@ when target char not found within bounds
    if
      (is_bracket_txtobj or is_quote_txtobj)
      and type(opts.max_lines) == 'number'
      and opts.max_lines > 0
    then
      local cur = vim.fn.line '.'
      local line_start = math.max(1, cur - opts.max_lines)
      local line_end = math.min(vim.api.nvim_buf_line_count(opts.bufnr), cur + opts.max_lines)
      local chunk = vim.api.nvim_buf_get_lines(opts.bufnr, line_start - 1, line_end, false)
      local target = is_bracket_txtobj and BRACKET_MAP[motion_rest] or motion_rest
      local max_col = opts.max_col
      local found = false
      for _, line in ipairs(chunk) do
        local pos = line:find(target, 1, true)
        if pos and (max_col == nil or pos <= max_col) then
          found = true
          break
        end
      end
      if not found then return end
    end

    _G.Range__from_motion_opfunc = function(ty)
      _G.Range__from_motion_opfunc_captured_range = Range.from_op_func(ty)
    end
    local old_eventignore = vim.o.eventignore
    vim.o.eventignore = 'all'
    vim.go.operatorfunc = 'v:lua.Range__from_motion_opfunc'
    vim.cmd(
      'keepjumps normal' .. (not opts.user_defined and '!' or '') .. ' ' .. ESC .. 'g@' .. motion,
      { mods = { silent = true } }
    )
    vim.o.eventignore = old_eventignore
  end)
  local captured_range = _G.Range__from_motion_opfunc_captured_range

  -- SECTION: Restore state
  vim.fn.winrestview(original_state.winview)
  vim.fn.setreg('"', original_state.unnamed_register)
  vim.fn.setpos('.', original_state.cursor)
  vim.fn.setpos("'[", original_state.mark_lbracket)
  vim.fn.setpos("']", original_state.mark_rbracket)
  if original_state.prev_mode ~= 'n' then original_state.vinf:set_visual_selection() end
  vim.go.operatorfunc = original_state.opfunc
  _G.Range__from_motion_opfunc_captured_range = original_state.prev_captured_range

  if not captured_range then return nil end

  -- SECTION: Fixup edge cases (quote text objects, 'it' tag)
  if
    -- I have no idea why, but when yanking `i"`, the stop-mark is
    -- placed on the ending quote. For other text-objects, the stop-
    -- mark is placed before the closing character.
    (is_quote_txtobj and scope == 'i' and captured_range.stop:char() == motion_rest)
    -- *Sigh*, this also sometimes happens for `it` as well.
    or (motion == 'it' and captured_range.stop:char() == '<')
  then
    captured_range.stop = captured_range.stop:next(-1) or captured_range.stop
  end
  if is_quote_txtobj and scope == 'a' then
    captured_range.start = captured_range.start:find_next(1, motion_rest) or captured_range.start
    captured_range.stop = captured_range.stop:find_next(-1, motion_rest) or captured_range.stop
  end

  -- SECTION: Validate cursor containment
  if
    opts.contains_cursor and not captured_range:contains(Pos.new(unpack(original_state.cursor)))
  then
    return nil
  end

  return captured_range
end

--- @param opts? { contains_cursor?: boolean }
function Range.from_tsquery_caps(bufnr, query, opts)
  opts = opts or { contains_cursor = true }

  local ranges = Range.from_buf_text(bufnr):tsquery(query)
  if not ranges then return end
  if not opts.contains_cursor then return ranges end

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
  return r
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
--- @param args unknown
--- @return u.Range|nil
function Range.from_cmd_args(args)
  if args.range == 0 then return nil end

  local bufnr = vim.api.nvim_get_current_buf()
  if args.range == 1 then
    return Range.new(Pos.new(bufnr, args.line1, 1), Pos.new(bufnr, args.line1, vim.v.maxcol), 'V')
  end

  local is_visual = vim.fn.histget('cmd', -1):sub(1, 5) == [['<,'>]]
  --- @type 'v'|'V'
  local mode = is_visual and vim.fn.visualmode() or 'V'

  if is_visual then
    return Range.new(Pos.from_pos "'<", Pos.from_pos "'>", mode)
  else
    return Range.new(Pos.new(bufnr, args.line1, 1), Pos.new(bufnr, args.line2, vim.v.maxcol), mode)
  end
end

--- @param opts? { max_lines?: number, max_col?: number }
--- @return u.Range|nil
function Range.find_nearest_brackets(opts)
  opts = opts or {}
  local copts = { contains_cursor = true, max_lines = opts.max_lines, max_col = opts.max_col }
  return Range.smallest {
    Range.from_motion('a<', copts),
    Range.from_motion('a[', copts),
    Range.from_motion('a(', copts),
    Range.from_motion('a{', copts),
  }
end

--- @param opts? { max_lines?: number, max_col?: number }
--- @return u.Range|nil
function Range.find_nearest_quotes(opts)
  opts = opts or {}
  local copts = { contains_cursor = true, max_lines = opts.max_lines, max_col = opts.max_col }
  return Range.smallest {
    Range.from_motion([[a']], copts),
    Range.from_motion([[a"]], copts),
    Range.from_motion([[a`]], copts),
  }
end

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
    return not self:is_empty() and x >= self.start and x <= self.stop
  elseif getmetatable(x) == Range then
    return self:contains(x.start) and self:contains(x.stop)
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

  local left
  if outer.start ~= inner.start then
    local stop = inner.start:clone() - 1
    left = Range.new(outer.start, stop)
  else
    left = Range.new(outer.start) -- empty range
  end

  local right
  if inner.stop ~= outer.stop then
    local start = inner.stop:clone() + 1
    right = Range.new(start, outer.stop)
  else
    right = Range.new(inner.stop) -- empty range
  end

  return left, right
end

--- @param left string
--- @param right string
function Range:save_to_pos(left, right)
  self.start:save_to_pos(left);
  (self:is_empty() and self.start or self.stop):save_to_pos(right)
end

--- @param left string
--- @param right string
function Range:save_to_marks(left, right)
  self.start:save_to_mark(left);
  (self:is_empty() and self.start or self.stop):save_to_mark(right)
end

function Range:save_to_extmark() return Extmark.from_range(self, NS) end

function Range:set_visual_selection()
  if self:is_empty() then return end
  if vim.api.nvim_get_current_buf() ~= self.start.bufnr then
    error 'Range:set_visual_selection() called on a buffer other than the current buffer'
  end

  local curr_mode = vim.fn.mode()
  if curr_mode ~= self.mode then vim.cmd.normal { args = { self.mode }, bang = true } end

  self.start:save_to_pos '.'
  vim.cmd.normal { args = { 'o' }, bang = true }
  self.stop:save_to_pos '.'
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
  local tree = parser:parse()[1]
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
    if range.stop.lnum > vim.api.nvim_buf_line_count(bufnr) then
      range.stop = range.stop:must_next(-1)
    end

    local capture_name = q.captures[id]
    if not ranges[capture_name] then ranges[capture_name] = {} end
    if self:contains(range) then table.insert(ranges[capture_name], range) end
  end

  return ranges
end

function Range:length()
  if self:is_empty() then return 0 end

  local line_positions =
    vim.fn.getregionpos(self.start:as_real():as_vim(), self.stop:as_real():as_vim(), { type = 'v' })

  local len = 0
  for linenr, line in ipairs(line_positions) do
    if linenr > 1 then len = len + 1 end -- each newline is counted as a char
    local line_start_col = line[1][3]
    local line_stop_col = line[2][3]
    local line_len = line_stop_col - line_start_col + 1
    len = len + line_len
  end
  return len
end

function Range:line_count()
  if self:is_empty() then return 0 end
  return self.stop.lnum - self.start.lnum + 1
end

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

--- @param i number 1-based
--- @param j? number 1-based
function Range:sub(i, j)
  local line_positions =
    vim.fn.getregionpos(self.start:as_real():as_vim(), self.stop:as_real():as_vim(), { type = 'v' })

  --- @param idx number 1-based
  --- @return u.Pos|nil
  local function get_pos(idx)
    if idx < 0 then return get_pos(self:length() + idx + 1) end

    -- find the position of the first line that contains the i-th character:
    local curr_len = 0
    for linenr, line in ipairs(line_positions) do
      if linenr > 1 then curr_len = curr_len + 1 end -- each newline is counted as a char
      local line_start_col = line[1][3]
      local line_stop_col = line[2][3]
      local line_len = line_stop_col - line_start_col + 1

      if curr_len + line_len >= idx then
        return Pos.new(self.start.bufnr, line[1][2], line_start_col + (idx - curr_len) - 1)
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
  return vim.fn.getregion(self.start:as_vim(), self.stop:as_vim(), { type = self.mode })
end

--- @return string
function Range:text() return vim.fn.join(self:lines(), '\n') end

--- @param l number
function Range:line(l)
  if l < 0 then l = self:line_count() + l + 1 end
  if l > self:line_count() then return end

  local line_indices =
    vim.fn.getregionpos(self.start:as_vim(), self.stop:as_vim(), { type = self.mode })
  local line_bounds = line_indices[l]

  local start = Pos.new(unpack(line_bounds[1]))
  local stop = Pos.new(unpack(line_bounds[2]))
  return Range.new(start, stop)
end

--- @param replacement nil|string|string[]
function Range:replace(replacement)
  if replacement == nil then replacement = {} end
  if type(replacement) == 'string' then replacement = vim.fn.split(replacement, '\n') end

  local bufnr = self.start.bufnr
  local replace_type = (self:is_empty() and 'insert') or (self.mode == 'v' and 'region') or 'lines'

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
      self.stop = Pos.new(bufnr, new_last_line_num + 1, vim.v.maxcol, self.stop.off)
    end
    self.mode = 'v'
  end

  if replace_type == 'insert' then
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
  elseif replace_type == 'region' then
    -- Fixup the bounds:
    local max_col = #self.stop:line()

    -- Indexing is zero-based. Row indices are end-inclusive, and column indices
    -- are end-exclusive.
    vim.api.nvim_buf_set_text(
      bufnr,
      self.start.lnum - 1,
      self.start.col - 1,
      self.stop.lnum - 1,
      math.min(self.stop.col, max_col),
      replacement
    )
    update_stop_non_linewise()
  elseif replace_type == 'lines' then
    -- Indexing is zero-based, end-exclusive.
    vim.api.nvim_buf_set_lines(bufnr, self.start.lnum - 1, self.stop.lnum, true, replacement)
    update_stop_linewise()
  else
    error 'unreachable'
  end
end

--- @param amount number
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

--- @param amount number
function Range:must_shrink(amount)
  local shrunk = self:shrink(amount)
  if shrunk == nil or shrunk:is_empty() then
    error 'error in Range:must_shrink: Range:shrink() returned nil'
  end
  return shrunk
end

--- @param group string
--- @param opts? { timeout?: number, priority?: number, on_macro?: boolean }
--- @return { ns: integer, clear: fun() }
function Range:highlight(group, opts)
  if self:is_empty() then return { ns = 0, clear = function() end } end

  opts = opts or { on_macro = false }
  if opts.on_macro == nil then opts.on_macro = false end

  local in_macro = vim.fn.reg_executing() ~= ''
  if not opts.on_macro and in_macro then return { ns = 0, clear = function() end } end

  local ns = vim.api.nvim_create_namespace ''

  local winview = vim.fn.winsaveview()
  vim.hl.range(
    self.start.bufnr,
    ns,
    group,
    { self.start.lnum - 1, self.start.col - 1 },
    { self.stop.lnum - 1, self.stop.col - 1 },
    {
      inclusive = true,
      priority = opts.priority,
      timeout = opts.timeout,
      regtype = self.mode,
    }
  )
  if not in_macro then vim.fn.winrestview(winview) end
  vim.cmd.redraw()

  return {
    ns = ns,
    clear = function()
      vim.api.nvim_buf_clear_namespace(self.start.bufnr, ns, self.start.lnum - 1, self.stop.lnum)
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
--- @type fun(range: u.Range): nil|(fun():any)
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
--- @diagnostic disable-next-line: undefined-doc-name
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
-- txtobj
--------------------------------------------------------------------------------

local txtobj = {}

--- @param key_seq string
--- @param fn fun(key_seq: string):u.Range|nil
--- @param opts? { buffer: number|nil }
function txtobj.define(key_seq, fn, opts)
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
--- @type function|nil
local REPEAT_ACTION = nil

local function is_repeatable_last_mutator() return vim.b.changedtick <= (vim.b.my_changedtick or 0) end

--- @param f fun()
function repeat_.run_repeatable(f)
  REPEAT_ACTION = f
  ---@diagnostic disable-next-line: need-check-nil
  REPEAT_ACTION()
  vim.b.my_changedtick = vim.b.changedtick
end

function repeat_.is_repeating() return IS_REPEATING end

function repeat_.setup()
  vim.keymap.set('n', '.', function()
    IS_REPEATING = true
    for _ = 1, vim.v.count1 do
      if is_repeatable_last_mutator() and type(REPEAT_ACTION) == 'function' then
        repeat_.run_repeatable(REPEAT_ACTION)
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
-- utils
--------------------------------------------------------------------------------

local utils = {}

--
-- Types
--

--- @class u.utils.QfItem
--- @field col number
--- @field filename string
--- @field kind string
--- @field lnum number
--- @field text string

--- @class u.utils.RawCmdArgs
--- @field args string
--- @field bang boolean
--- @field count number
--- @field fargs string[]
--- @field line1 number
--- @field line2 number
--- @field mods string
--- @field name string
--- @field range 0|1|2
--- @field reg string
--- @field smods any

--- @class u.utils.CmdArgs: u.utils.RawCmdArgs
--- @field info u.Range|nil

--- @class u.utils.UcmdArgs
--- @field nargs? 0|1|'*'|'?'|'+'
--- @field range? boolean|'%'|number
--- @field count? boolean|number
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
--- utils.ucmd('MyCmd', function(args)
---   -- Print the visually selected text:
---   vim.print(args.info:text())
---   -- Or get the selection as an array of lines:
---   vim.print(args.info:lines())
--- end, { nargs = '*', range = true })
---
--- -- Create a command that processes the current line:
--- utils.ucmd('ProcessLine', function(args)
---   local line_text = args.info:text()
---   -- Process the line...
--- end, { range = '%' })
---
--- -- Create a command with arguments:
--- utils.ucmd('SearchReplace', function(args)
---   local pattern, replacement = args.fargs[1], args.fargs[2]
---   local text = args.info:text()
---   -- Perform search and replace...
--- end, { nargs = 2, range = true })
--- ```
function utils.ucmd(name, cmd, opts)
  opts = opts or {}
  local cmd2 = cmd
  if type(cmd) == 'function' then
    cmd2 = function(args)
      args.info = Range.from_cmd_args(args)
      return cmd(args)
    end
  end
  vim.api.nvim_create_user_command(name, cmd2, opts or {} --[[@as any]])
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
--- utils.ucmd('MyEdit', function(args)
---   local delegated_args = utils.create_delegated_cmd_args(args)
---   -- Add custom logic here...
---   vim.cmd.edit(delegated_args)
--- end, { nargs = '*', range = true, bang = true })
---
--- -- Implement :MySubstitute that delegates to :substitute:
--- utils.ucmd('MySubstitute', function(args)
---   -- Pre-process arguments
---   local pattern = preprocess_pattern(args.fargs[1])
---
---   local delegated_args = utils.create_delegated_cmd_args(args)
---   delegated_args.args = { pattern, args.fargs[2] }
---
---   vim.cmd.substitute(delegated_args)
--- end, { nargs = 2, range = true, bang = true })
--- ```
function utils.create_delegated_cmd_args(current_args)
  --- @type vim.api.keyset.cmd
  local args = {
    range = current_args.range == 1 and { current_args.line1 }
      or current_args.range == 2 and { current_args.line1, current_args.line2 }
      or nil,
    count = (current_args.count ~= -1 and current_args.range == 0) and current_args.count or nil,
    reg = current_args.reg ~= '' and current_args.reg or nil,
    bang = current_args.bang or nil,
    args = #current_args.fargs > 0 and current_args.fargs or nil,
    mods = current_args.smods,
  }
  return args
end

--------------------------------------------------------------------------------
-- Exports
--------------------------------------------------------------------------------

M.Pos = Pos
M.Extmark = Extmark
M.Range = Range
M.opkeymap = opkeymap
M.define_txtobj = txtobj.define
M.repeat_ = repeat_
M.ucmd = utils.ucmd
M.create_delegated_cmd_args = utils.create_delegated_cmd_args

return M
