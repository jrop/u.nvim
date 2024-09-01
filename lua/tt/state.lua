---@class State
---@field buf number
---@field registers table
---@field marks table
---@field positions table
---@field keymaps { mode: string; lhs: any, rhs: any, buffer?: number }[]
---@field global_options table<string, any>
local State = {}

---@param buf number
---@return State
function State.new(buf)
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  local s = { buf = buf, registers = {}, marks = {}, positions = {}, keymaps = {}, global_options = {} }
  setmetatable(s, { __index = State })
  return s
end

---@generic T
---@param buf number
---@param f fun(s: State):T
---@return T
function State.run(buf, f)
  local s = State.new(buf)
  local ok, result = pcall(f, s)
  s:restore()
  if not ok then error(result) end
  return result
end

---@param buf number
---@param f fun(s: State, callback: fun(): any):any
---@param callback fun():any
function State.run_async(buf, f, callback)
  local s = State.new(buf)
  f(s, function()
    s:restore()
    callback()
  end)
end

function State:track_keymap(mode, lhs)
  local old =
    -- Look up the mapping in buffer-local maps:
    vim.iter(vim.api.nvim_buf_get_keymap(self.buf, mode)):find(function(map) return map.lhs == lhs end)
    -- Look up the mapping in global maps:
    or vim.iter(vim.api.nvim_get_keymap(mode)):find(function(map) return map.lhs == lhs end)

  -- Did we find a mapping?
  if old == nil then return end

  -- Track it:
  table.insert(self.keymaps, { mode = mode, lhs = lhs, rhs = old.rhs or old.callback, buffer = old.buffer })
end

---@param reg string
function State:track_register(reg) self.registers[reg] = vim.fn.getreg(reg) end

---@param mark string
function State:track_mark(mark) self.marks[mark] = vim.api.nvim_buf_get_mark(self.buf, mark) end

---@param pos string
function State:track_pos(pos) self.positions[pos] = vim.fn.getpos(pos) end

---@param nm string
function State:track_global_option(nm) self.global_options[nm] = vim.g[nm] end

function State:restore()
  for reg, val in pairs(self.registers) do
    vim.fn.setreg(reg, val)
  end
  for mark, val in pairs(self.marks) do
    vim.api.nvim_buf_set_mark(self.buf, mark, val[1], val[2], {})
  end
  for pos, val in pairs(self.positions) do
    vim.fn.setpos(pos, val)
  end
  for _, map in ipairs(self.keymaps) do
    vim.keymap.set(map.mode, map.lhs, map.rhs, { buffer = map.buffer })
  end
  for nm, val in pairs(self.global_options) do
    vim.g[nm] = val
  end
end

return State
