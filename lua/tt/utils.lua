local M = {}

--
-- Types
--

---@alias QfItem { col: number, filename: string, kind: string, lnum: number, text: string }
---@alias KeyMaps table<string, fun(): any | string> }

---@param keys string
---@param mode? string
function M.feedkeys(keys, mode)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), mode or 'nx', true)
end

---@alias CmdArgs { args: string; bang: boolean; count: number; fargs: string[]; line1: number; line2: number; mods: string; name: string; range: 0|1|2; reg: string; smods: any; info: Range|nil }

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
  local Range = require 'tt.range'

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
  local Range = require 'tt.range'
  local Pos = require 'tt.pos'

  if opts ~= nil and opts.buffer == 0 then opts.buffer = vim.api.nvim_get_current_buf() end

  local function handle_visual()
    local range_or_pos = fn(key_seq)
    if range_or_pos == nil then return end

    if Range.is(range_or_pos) then
      local range = range_or_pos --[[@as Range]]
      range:set_visual_selection()
    else
      M.feedkeys '<Esc>'
    end
  end
  vim.keymap.set({ 'x' }, key_seq, handle_visual, opts and { buffer = opts.buffer } or nil)

  local function handle_normal()
    local State = require 'tt.state'

    -- enter visual mode:
    M.feedkeys 'v'

    local range_or_pos = fn(key_seq)
    if range_or_pos == nil then return end

    if Range.is(range_or_pos) then
      range_or_pos:set_visual_selection()
    elseif Pos.is(range_or_pos) then
      local p = range_or_pos --[[@as Pos]]
      State.run(0, function(s)
        s:track_global_option 'eventignore'
        vim.opt_global.eventignore = 'all'

        -- insert a single space, so we can select it:
        vim.api.nvim_buf_set_text(0, p.lnum, p.col, p.lnum, p.col, { ' ' })
        -- select the space:
        Range.new(p, p, 'v'):set_visual_selection()
      end)
    end
  end
  vim.keymap.set({ 'o' }, key_seq, handle_normal, opts and { buffer = opts.buffer } or nil)
end

function M.get_editor_dimensions()
  local w = 0
  local h = 0
  local tabnr = vim.api.nvim_get_current_tabpage()
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    local tabpage = vim.api.nvim_win_get_tabpage(winid)
    if tabpage == tabnr then
      local pos = vim.api.nvim_win_get_position(winid)
      local r, c = pos[1], pos[2]
      local win_w = vim.api.nvim_win_get_width(winid)
      local win_h = vim.api.nvim_win_get_height(winid)
      local right = c + win_w
      local bottom = r + win_h
      if right > w then w = right end
      if bottom > h then h = bottom end
    end
  end
  if w == 0 or h == 0 then
    w = vim.api.nvim_win_get_width(0)
    h = vim.api.nvim_win_get_height(0)
  end
  return { width = w, height = h }
end

return M
