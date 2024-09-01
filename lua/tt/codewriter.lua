local Buffer = require 'tt.buffer'

---@class CodeWriter
---@field lines string[]
---@field indent_level number
---@field indent_str string
local CodeWriter = {}

---@param indent_level? number
---@param indent_str? string
---@return CodeWriter
function CodeWriter.new(indent_level, indent_str)
  if indent_level == nil then indent_level = 0 end
  if indent_str == nil then indent_str = '  ' end

  local cw = {
    lines = {},
    indent_level = indent_level,
    indent_str = indent_str,
  }
  setmetatable(cw, { __index = CodeWriter })
  return cw
end

---@param p Pos
function CodeWriter.from_pos(p)
  local line = Buffer.new(p.buf):line0(p.lnum):text()
  return CodeWriter.from_line(line, p.buf)
end

---@param line string
---@param buf? number
function CodeWriter.from_line(line, buf)
  if buf == nil then buf = vim.api.nvim_get_current_buf() end

  local ws = line:match '^%s*'
  local expandtab = vim.api.nvim_get_option_value('expandtab', { buf = buf })
  local shiftwidth = vim.api.nvim_get_option_value('shiftwidth', { buf = buf })

  local indent_level = 0
  local indent_str = ''
  if expandtab then
    while #indent_str < shiftwidth do
      indent_str = indent_str .. ' '
    end
    indent_level = #ws / shiftwidth
  else
    indent_str = '\t'
    indent_level = #ws
  end

  return CodeWriter.new(indent_level, indent_str)
end

---@param line string
function CodeWriter:write_raw(line)
  if line:find '\n' then error 'line contains newline character' end
  line = line:gsub('^\n+', '')
  line = line:gsub('\n+$', '')
  table.insert(self.lines, line)
end

---@param line string
function CodeWriter:write(line) self:write_raw(self.indent_str:rep(self.indent_level) .. line) end

---@param f? fun(cw: CodeWriter):any
function CodeWriter:indent(f)
  local cw = {
    lines = self.lines,
    indent_level = self.indent_level + 1,
    indent_str = self.indent_str,
  }
  setmetatable(cw, { __index = CodeWriter })
  if f ~= nil then f(cw) end
  return cw
end

return CodeWriter
