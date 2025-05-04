local MAX_COL = vim.v.maxcol

--- @param bufnr number
--- @param lnum number 1-based
local function line_text(bufnr, lnum)
  return vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
end

--- @class u.Pos
--- @field bufnr number buffer number
--- @field lnum number 1-based line index
--- @field col number 1-based column index
--- @field off number
local Pos = {}
Pos.__index = Pos
Pos.MAX_COL = MAX_COL

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
  local pos = {
    bufnr = bufnr,
    lnum = lnum,
    col = col,
    off = off,
  }
  setmetatable(pos, Pos)
  return pos
end

function Pos.invalid() return Pos.new(0, 0, 0, 0) end

function Pos.__lt(a, b) return a.lnum < b.lnum or (a.lnum == b.lnum and a.col < b.col) end
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

--- @param name string
--- @return u.Pos
function Pos.from_pos(name)
  local p = vim.fn.getpos(name)
  return Pos.new(p[1], p[2], p[3], p[4])
end

function Pos:is_invalid() return self.lnum == 0 and self.col == 0 and self.off == 0 end

function Pos:clone() return Pos.new(self.bufnr, self.lnum, self.col, self.off) end

--- @return boolean
function Pos:is_col_max() return self.col == MAX_COL end

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

--- @param pos string
function Pos:save_to_pos(pos) vim.fn.setpos(pos, { self.bufnr, self.lnum, self.col, self.off }) end

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
--- @param max_chars? number|nil
--- @param invocations? u.Pos[]
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

return Pos
