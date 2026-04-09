--
-- Split/Join: toggles between single-line and multi-line forms for bracketed expressions.
-- Example: { a, b, c } <-> {\n  a,\n  b,\n  c\n}
-- Maps to gS in normal mode.
--
local Range = require('u').Range
local vim_repeat = require('u').repeat_

local M = {}

--- @param bracket_range u.Range
--- @param left string
--- @param right string
local function split(bracket_range, left, right)
  local bufnr = bracket_range.start.bufnr
  local first_line = Range.from_line(bufnr, bracket_range.start.lnum):text()
  local ws = first_line:match '^%s*'
  local expandtab = vim.bo[bufnr].expandtab
  local shiftwidth = vim.bo[bufnr].shiftwidth

  local indent_str, base_indent
  if expandtab then
    indent_str = string.rep(' ', shiftwidth)
    base_indent = math.floor(#ws / shiftwidth)
  else
    indent_str = '\t'
    base_indent = #ws
  end

  local lines = {}
  local function write(line, indent_offset)
    table.insert(lines, indent_str:rep(base_indent + (indent_offset or 0)) .. line)
  end

  table.insert(lines, left)

  local curr = bracket_range.start:next()
  if curr == nil then return end
  local last_start = curr

  -- Sanity check: if we "skipped" past the start/stop of the overall range, then something is wrong:
  -- This can happen with greater-/less- than signs that are mathematical, and not brackets:
  while curr > bracket_range.start and curr < bracket_range.stop do
    if vim.tbl_contains({ '{', '[', '(', '<' }, curr:char()) then
      -- skip over bracketed groups:
      local next = curr:find_match()
      if next == nil then break end
      curr = next
    else
      if vim.tbl_contains({ ',', ';' }, curr:char()) then
        -- accumulate item:
        local item = vim.trim(Range.new(last_start, curr):text())
        if item ~= '' then write(item, 1) end

        local next_last_start = curr:next()
        if next_last_start == nil then break end
        last_start = next_last_start
      end

      -- Prepare for next iteration:
      local next = curr:next()
      if next == nil then break end
      curr = next
    end
  end

  -- accumulate last, unfinished item:
  local pos_before_right = bracket_range.stop:must_next(-1)
  if last_start < pos_before_right then
    local item = vim.trim(Range.new(last_start, pos_before_right):text())
    if item ~= '' then write(item, 1) end
  end

  write(right)
  bracket_range:replace(lines)
end

--- @param bracket_range u.Range
--- @param left string
--- @param right string
local function join(bracket_range, left, right)
  local inner_range = bracket_range:shrink(1)
  if inner_range then
    local newline = vim
      .iter(inner_range:lines())
      :map(function(l) return vim.trim(l) end)
      :filter(function(l) return l ~= '' end)
      :join ' '
    bracket_range:replace { left .. newline .. right }
  else
    bracket_range:replace { left .. right }
  end
end

local function splitjoin()
  local bracket_range = Range.find_nearest_brackets()
  if bracket_range == nil then return end
  local lines = bracket_range:lines()
  local left = lines[1]:sub(1, 1) -- left bracket
  local right = lines[#lines]:sub(-1, -1) -- right bracket

  if #lines == 1 then
    split(bracket_range, left, right)
  else
    join(bracket_range, left, right)
  end
end

function M.setup()
  vim.keymap.set('n', 'gS', function() vim_repeat.run_repeatable(splitjoin) end)
end

return M
