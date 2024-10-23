local Range = require 'u.range'

---@class Buffer
---@field buf number
local Buffer = {}

---@param buf? number
---@return Buffer
function Buffer.from_nr(buf)
  if buf == nil or buf == 0 then buf = vim.api.nvim_get_current_buf() end
  local b = { buf = buf }
  setmetatable(b, { __index = Buffer })
  return b
end

---@return Buffer
function Buffer.current() return Buffer.from_nr(0) end

---@param listed boolean
---@param scratch boolean
---@return Buffer
function Buffer.create(listed, scratch) return Buffer.from_nr(vim.api.nvim_create_buf(listed, scratch)) end

function Buffer:set_tmp_options()
  self:set_option('bufhidden', 'delete')
  self:set_option('buflisted', false)
  self:set_option('buftype', 'nowrite')
end

---@param nm string
function Buffer:get_option(nm) return vim.api.nvim_get_option_value(nm, { buf = self.buf }) end

---@param nm string
function Buffer:set_option(nm, val) return vim.api.nvim_set_option_value(nm, val, { buf = self.buf }) end

---@param nm string
function Buffer:get_var(nm) return vim.api.nvim_buf_get_var(self.buf, nm) end

---@param nm string
function Buffer:set_var(nm, val) return vim.api.nvim_buf_set_var(self.buf, nm, val) end

function Buffer:line_count() return vim.api.nvim_buf_line_count(self.buf) end

function Buffer:all() return Range.from_buf_text(self.buf) end

function Buffer:is_empty() return self:line_count() == 1 and self:line0(0):text() == '' end

---@param line string
function Buffer:append_line(line)
  local start = -1
  if self:is_empty() then start = -2 end
  vim.api.nvim_buf_set_lines(self.buf, start, -1, false, { line })
end

---@param num number 0-based line index
function Buffer:line0(num)
  if num < 0 then return self:line0(self:line_count() + num) end
  return Range.from_line(self.buf, num)
end

---@param start number 0-based line index
---@param stop number 0-based line index
function Buffer:lines(start, stop) return Range.from_lines(self.buf, start, stop) end

---@param txt_obj string
---@param opts? { contains_cursor?: boolean; pos?: Pos }
function Buffer:text_object(txt_obj, opts)
  opts = vim.tbl_extend('force', opts or {}, { buf = self.buf })
  return Range.from_text_object(txt_obj, opts)
end

return Buffer
