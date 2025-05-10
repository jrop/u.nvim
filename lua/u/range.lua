local Pos = require 'u.pos'

--- @class u.Range
--- @field start u.Pos
--- @field stop u.Pos|nil
--- @field mode 'v'|'V'
local Range = {}
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

  local _1 = posstr(self.start)
  local _2 = posstr(self.stop)
  return string.format(
    'Range{bufnr=%d, mode=%s, start=%s, stop=%s}',
    self.start.bufnr,
    self.mode,
    _1,
    _2
  )
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
  local stop = Pos.new(bufnr, num_lines, Pos.MAX_COL)
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
  return Range.new(Pos.new(bufnr, start_line, 1), Pos.new(bufnr, stop_line, Pos.MAX_COL), 'V')
end

--- @param motion string
--- @param opts? { bufnr?: number; contains_cursor?: boolean; pos?: u.Pos, user_defined?: boolean }
--- @return u.Range|nil
function Range.from_motion(motion, opts)
  -- Options handling:
  opts = opts or {}
  if opts.bufnr == nil then opts.bufnr = vim.api.nvim_get_current_buf() end
  if opts.contains_cursor == nil then opts.contains_cursor = false end
  if opts.user_defined == nil then opts.user_defined = false end

  -- Extract some information from the motion:
  --- @type 'a'|'i', string
  local scope, motion_rest = motion:sub(1, 1), motion:sub(2)
  local is_txtobj = scope == 'a' or scope == 'i'
  local is_quote_txtobj = is_txtobj and vim.tbl_contains({ "'", '"', '`' }, motion_rest)

  -- Capture the original state of the buffer for restoration later.
  local original_state = {
    winview = vim.fn.winsaveview(),
    regquote = vim.fn.getreg '"',
    cursor = vim.fn.getpos '.',
    pos_lbrack = vim.fn.getpos "'[",
    pos_rbrack = vim.fn.getpos "']",
    opfunc = vim.go.operatorfunc,
  }
  --- @type u.Range|nil
  local captured_range = nil

  vim.api.nvim_buf_call(opts.bufnr, function()
    if opts.pos ~= nil then opts.pos:save_to_pos '.' end

    _G.Range__from_motion_opfunc = function(ty) captured_range = Range.from_op_func(ty) end
    vim.go.operatorfunc = 'v:lua.Range__from_motion_opfunc'
    vim.cmd {
      cmd = 'normal',
      bang = not opts.user_defined,
      args = { 'g@' .. motion },
      mods = { silent = true },
    }
  end)

  -- Restore original state:
  vim.fn.winrestview(original_state.winview)
  vim.fn.setreg('"', original_state.regquote)
  vim.fn.setpos('.', original_state.cursor)
  vim.fn.setpos("'[", original_state.pos_lbrack)
  vim.fn.setpos("']", original_state.pos_rbrack)
  vim.go.operatorfunc = original_state.opfunc

  if not captured_range then return nil end

  -- Fixup the bounds:
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

  if
    opts.contains_cursor and not captured_range:contains(Pos.new(unpack(original_state.cursor)))
  then
    return nil
  end

  return captured_range
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
  --- @type 'v'|'V'
  local mode
  --- @type nil|u.Pos
  local start
  local stop
  if args.range == 0 then
    return nil
  else
    start = Pos.from_pos "'<"
    stop = Pos.from_pos "'>"
    mode = stop:is_col_max() and 'V' or 'v'
  end
  return Range.new(start, stop, mode)
end

function Range.find_nearest_brackets()
  return Range.smallest {
    Range.from_motion('a<', { contains_cursor = true }),
    Range.from_motion('a[', { contains_cursor = true }),
    Range.from_motion('a(', { contains_cursor = true }),
    Range.from_motion('a{', { contains_cursor = true }),
  }
end

function Range.find_nearest_quotes()
  return Range.smallest {
    Range.from_motion([[a']], { contains_cursor = true }),
    Range.from_motion([[a"]], { contains_cursor = true }),
    Range.from_motion([[a`]], { contains_cursor = true }),
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
  if r.stop ~= nil then r.stop.col = Pos.MAX_COL end

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
  if self:is_empty() then
    self.start:save_to_pos(left)
    self.start:save_to_pos(right)
  else
    self.start:save_to_pos(left)
    self.stop:save_to_pos(right)
  end
end

--- @param left string
--- @param right string
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
-- Range.from_* functions:
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Text access/manipulation utilities:
--------------------------------------------------------------------------------

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
    -- start is inalid, so return an empty range:
    return Range.new(self.start, nil, self.mode)
  end

  local stop
  if j then stop = get_pos(j) end
  if not stop then
    -- stop is inalid, so return an empty range:
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
-- luacheck: ignore
--- @return { line: string; idx0: { start: number; stop: number; }; lnum: number; range: fun():u.Range; text: fun():string }|nil
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
      self.stop = Pos.new(bufnr, new_last_line_num + 1, Pos.MAX_COL, self.stop.off)
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
function Range:highlight(group, opts)
  if self:is_empty() then return end

  opts = opts or { on_macro = false }
  if opts.on_macro == nil then opts.on_macro = false end

  local in_macro = vim.fn.reg_executing() ~= ''
  if not opts.on_macro and in_macro then return { clear = function() end } end

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

return Range
