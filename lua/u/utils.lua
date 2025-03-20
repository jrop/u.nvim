local M = {}

--
-- Types
--

---@alias QfItem { col: number, filename: string, kind: string, lnum: number, text: string }
---@alias KeyMaps table<string, fun(): any | string> }
---@alias CmdArgs { args: string; bang: boolean; count: number; fargs: string[]; line1: number; line2: number; mods: string; name: string; range: 0|1|2; reg: string; smods: any; info: Range|nil }

--- @generic T
--- @param x `T`
--- @param message? string
--- @return T
function M.dbg(x, message)
  local t = {}
  if message ~= nil then table.insert(t, message) end
  table.insert(t, x)
  vim.print(t)
  return x
end

--- A utility for creating user commands that also pre-computes useful information
--- and attaches it to the arguments.
---
--- ```lua
--- -- Example:
--- ucmd('MyCmd', function(args)
---   -- print the visually selected text:
---   vim.print(args.info:text())
---   -- or get the vtext as an array of lines:
---   vim.print(args.info:lines())
--- end, { nargs = '*', range = true })
--- ```
---@param name string
---@param cmd string | fun(args: CmdArgs): any
---@param opts? { nargs?: 0|1|'*'|'?'|'+'; range?: boolean|'%'|number; count?: boolean|number, addr?: string; completion?: string }
function M.ucmd(name, cmd, opts)
  local Range = require 'u.range'

  opts = opts or {}
  local cmd2 = cmd
  if type(cmd) == 'function' then
    cmd2 = function(args)
      args.info = Range.from_cmd_args(args)
      return cmd(args)
    end
  end
  vim.api.nvim_create_user_command(name, cmd2, opts or {})
end

---@param key_seq string
---@param fn fun(key_seq: string):Range|Pos|nil
---@param opts? { buffer: number|nil }
function M.define_text_object(key_seq, fn, opts)
  local Range = require 'u.range'
  local Pos = require 'u.pos'

  if opts ~= nil and opts.buffer == 0 then opts.buffer = vim.api.nvim_get_current_buf() end

  local function handle_visual()
    local range_or_pos = fn(key_seq)
    if range_or_pos == nil then return end
    if Range.is(range_or_pos) and range_or_pos:is_empty() then range_or_pos = range_or_pos.start end

    if Range.is(range_or_pos) then
      local range = range_or_pos --[[@as Range]]
      range:set_visual_selection()
    else
      vim.cmd { cmd = 'normal', args = { '<Esc>' }, bang = true }
    end
  end
  vim.keymap.set({ 'x' }, key_seq, handle_visual, opts and { buffer = opts.buffer } or nil)

  local function handle_normal()
    local State = require 'u.state'

    -- enter visual mode:
    vim.cmd { cmd = 'normal', args = { 'v' }, bang = true }

    local range_or_pos = fn(key_seq)
    if range_or_pos == nil then return end
    if Range.is(range_or_pos) and range_or_pos:is_empty() then range_or_pos = range_or_pos.start end

    if Range.is(range_or_pos) then
      range_or_pos:set_visual_selection()
    elseif Pos.is(range_or_pos) then
      local p = range_or_pos --[[@as Pos]]
      State.run(0, function(s)
        s:track_global_option 'eventignore'
        vim.go.eventignore = 'all'

        -- insert a single space, so we can select it:
        vim.api.nvim_buf_set_text(0, p.lnum, p.col, p.lnum, p.col, { ' ' })
        -- select the space:
        Range.new(p, p, 'v'):set_visual_selection()
      end)
    end
  end
  vim.keymap.set({ 'o' }, key_seq, handle_normal, opts and { buffer = opts.buffer } or nil)
end

---@type fun(): nil|(fun():any)
local __U__RepeatableOpFunc_rhs = nil

--- This is the global utility function used for operatorfunc
--- in repeatablemap
---@type nil|fun(range: Range): fun():any|nil
-- selene: allow(unused_variable)
function __U__RepeatableOpFunc()
  if __U__RepeatableOpFunc_rhs ~= nil then __U__RepeatableOpFunc_rhs() end
end

function M.repeatablemap(mode, lhs, rhs, opts)
  vim.keymap.set(mode, lhs, function()
    __U__RepeatableOpFunc_rhs = rhs
    vim.o.operatorfunc = 'v:lua.__U__RepeatableOpFunc'
    return 'g@ '
  end, vim.tbl_extend('force', opts or {}, { expr = true }))
end

function M.get_editor_dimensions() return { width = vim.go.columns, height = vim.go.lines } end

return M
