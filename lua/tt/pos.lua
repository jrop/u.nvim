local MAX_COL = vim.v.maxcol

---@param buf number
---@param lnum number
local function line_text(buf, lnum) return vim.api.nvim_buf_get_lines(buf, lnum, lnum + 1, false)[1] end

---@class Pos
---@field buf number buffer number
---@field lnum number 1-based line index
---@field col number 1-based column index
---@field off number
local Pos = {}
Pos.MAX_COL = MAX_COL

---@param buf? number
---@param lnum number
---@param col number
---@param off? number
---@return Pos
function Pos.new(buf, lnum, col, off)
  if buf == nil or buf == 0 then buf = vim.api.nvim_get_current_buf() end
  if off == nil then off = 0 end
  local pos = {
    buf = buf,
    lnum = lnum,
    col = col,
    off = off,
  }

  local function str()
    if pos.off ~= 0 then
      return string.format('Pos(%d:%d){buf=%d, off=%d}', pos.lnum, pos.col, pos.buf, pos.off)
    else
      return string.format('Pos(%d:%d){buf=%d}', pos.lnum, pos.col, pos.buf)
    end
  end
  setmetatable(pos, {
    __index = Pos,
    __tostring = str,
    __lt = Pos.__lt,
    __le = Pos.__le,
    __eq = Pos.__eq,
  })
  return pos
end

function Pos.is(x)
  local mt = getmetatable(x)
  return mt and mt.__index == Pos
end

function Pos.__lt(a, b) return a.lnum < b.lnum or (a.lnum == b.lnum and a.col < b.col) end
function Pos.__le(a, b) return a < b or a == b end
function Pos.__eq(a, b) return a.lnum == b.lnum and a.col == b.col end

---@param name string
---@return Pos
function Pos.from_pos(name)
  local p = vim.fn.getpos(name)
  local col = p[3]
  if col ~= MAX_COL then col = col - 1 end
  return Pos.new(p[1], p[2] - 1, col, p[4])
end

function Pos:clone() return Pos.new(self.buf, self.lnum, self.col, self.off) end

---@return boolean
function Pos:is_col_max() return self.col == MAX_COL end

---@return number[]
function Pos:as_vim() return { self.buf, self.lnum, self.col, self.off } end

--- Normalize the position to a real position (take into account vim.v.maxcol).
function Pos:as_real()
  local col = self.col
  if self:is_col_max() then
    -- We could use utilities in this file to get the given line, but
    -- since this is a low-level function, we are going to optimize and
    -- use the API directly:
    col = #line_text(self.buf, self.lnum) - 1
  end
  return Pos.new(self.buf, self.lnum, col, self.off)
end

---@param pos string
function Pos:save_to_pos(pos)
  if pos == '.' then
    vim.api.nvim_win_set_cursor(0, { self.lnum + 1, self.col })
    return
  end

  local p = self:as_real()
  vim.fn.setpos(pos, { p.buf, p.lnum + 1, p.col + 1, p.off })
end

---@param mark string
function Pos:save_to_mark(mark)
  local p = self:as_real()
  vim.api.nvim_buf_set_mark(p.buf, mark, p.lnum + 1, p.col, {})
end

---@return string
function Pos:char()
  local line = line_text(self.buf, self.lnum)
  if line == nil then return '' end
  return line:sub(self.col + 1, self.col + 1)
end

---@param dir? -1|1
---@param must? boolean
---@return Pos|nil
function Pos:next(dir, must)
  if must == nil then must = false end

  if dir == nil or dir == 1 then
    -- Next:
    local num_lines = vim.api.nvim_buf_line_count(self.buf)
    local last_line = line_text(self.buf, num_lines - 1) -- buf:line0(-1)
    if self.lnum == num_lines - 1 and self.col == (#last_line - 1) then
      if must then error 'error in Pos:next(): Pos:next() returned nil' end
      return nil
    end

    local col = self.col + 1
    local line = self.lnum
    local line_max_col = #line_text(self.buf, self.lnum) - 1
    if col > line_max_col then
      col = 0
      line = line + 1
    end
    return Pos.new(self.buf, line, col, self.off)
  else
    -- Previous:
    if self.col == 0 and self.lnum == 0 then
      if must then error 'error in Pos:next(): Pos:next() returned nil' end
      return nil
    end

    local col = self.col - 1
    local line = self.lnum
    local prev_line_max_col = #(line_text(self.buf, self.lnum - 1) or '') - 1
    if col < 0 then
      col = math.max(prev_line_max_col, 0)
      line = line - 1
    end
    return Pos.new(self.buf, line, col, self.off)
  end
end

---@param dir? -1|1
function Pos:must_next(dir)
  local next = self:next(dir, true)
  if next == nil then error 'unreachable' end
  return next
end

---@param dir -1|1
---@param predicate fun(p: Pos): boolean
---@param test_current? boolean
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

---@param dir -1|1
---@param predicate string|fun(p: Pos): boolean
function Pos:find_next(dir, predicate)
  if type(predicate) == 'string' then
    local s = predicate
    predicate = function(p) return s == p:char() end
  end

  ---@type Pos|nil
  local curr = self
  while curr ~= nil do
    if predicate(curr) then return curr end
    curr = curr:next(dir)
  end
  return curr
end

--- Finds the matching bracket/paren for the current position.
---@param max_chars? number|nil
---@param invocations? Pos[]
---@return Pos|nil
function Pos:find_match(max_chars, invocations)
  if invocations == nil then invocations = {} end
  if vim.tbl_contains(invocations, function(p) return self == p end, { predicate = true }) then return nil end
  table.insert(invocations, self)

  local openers = { '{', '[', '(', '<' }
  local closers = { '}', ']', ')', '>' }
  local c = self:char()
  local is_opener = vim.tbl_contains(openers, c)
  local is_closer = vim.tbl_contains(closers, c)
  if not is_opener and not is_closer then return nil end

  local i, _ = vim.iter(is_opener and openers or closers):enumerate():find(function(_, c2) return c == c2 end)
  local c_match = (is_opener and closers or openers)[i]

  ---@type Pos|nil
  local cur = self
  ---@return Pos|nil
  local function adv()
    if cur == nil then return nil end

    if max_chars ~= nil then
      max_chars = max_chars - 1
      if max_chars < 0 then return nil end
    end

    return cur:next(is_opener and 1 or -1)
  end

  -- scan until we find a match:
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

return Pos
