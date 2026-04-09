--
-- Bracket matcher: highlights the nearest matching pair of brackets (like MatchParen)
-- when the cursor is near them. Updates dynamically on CursorMoved in normal mode.
--
local u = require 'u'
local Range = u.Range

local M = {}

--- @type { clear: fun() }[]
local HIGHLIGHTS = {}
local LAST_RANGE = nil

local function clear_highlights()
  for _, hl in ipairs(HIGHLIGHTS) do
    hl.clear()
  end
  HIGHLIGHTS = {}
end

local function update()
  local mode = vim.fn.mode():sub(1, 1)
  if mode ~= 'n' then return end

  local last_range = LAST_RANGE
  local bracket_range = Range.find_nearest_brackets()
  LAST_RANGE = bracket_range

  if not bracket_range then return clear_highlights() end
  if bracket_range == last_range then return end

  clear_highlights()

  local open = Range.new(bracket_range.start, bracket_range.start, 'v')
  local close = Range.new(bracket_range.stop, bracket_range.stop, 'v')

  HIGHLIGHTS = {
    open:highlight('MatchParen', { priority = 999 }),
    close:highlight('MatchParen', { priority = 999 }),
  }
end

function M.setup()
  local group = vim.api.nvim_create_augroup('Matcher', { clear = true })
  vim.api.nvim_create_autocmd({ 'CursorMoved' }, {
    group = group,
    callback = update,
  })
end

return M
