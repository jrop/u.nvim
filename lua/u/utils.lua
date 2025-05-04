local M = {}

--
-- Types
--

--- @alias QfItem { col: number, filename: string, kind: string, lnum: number, text: string }
--- @alias KeyMaps table<string, fun(): any | string> }
-- luacheck: ignore
--- @alias CmdArgs { args: string; bang: boolean; count: number; fargs: string[]; line1: number; line2: number; mods: string; name: string; range: 0|1|2; reg: string; smods: any; info: u.Range|nil }

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
--- @param name string
--- @param cmd string | fun(args: CmdArgs): any
-- luacheck: ignore
--- @param opts? { nargs?: 0|1|'*'|'?'|'+'; range?: boolean|'%'|number; count?: boolean|number, addr?: string; completion?: string }
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

function M.get_editor_dimensions() return { width = vim.go.columns, height = vim.go.lines } end

return M
