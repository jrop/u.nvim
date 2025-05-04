local Range = require 'u.range'

local M = {}

local ESC = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)

--- @param key_seq string
--- @param fn fun(key_seq: string):u.Range|nil
--- @param opts? { buffer: number|nil }
function M.define(key_seq, fn, opts)
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

return M
