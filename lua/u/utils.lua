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

--- @alias LevenshteinChange<T> ({ kind: 'add'; item: T; index: number; } | { kind: 'delete'; item: T; index: number; } | { kind: 'change'; from: T; to: T; index: number; })
--- @private
--- @generic T
--- @param x `T`[]
--- @param y T[]
--- @param cost? { of_delete?: fun(x: T): number; of_add?: fun(x: T): number; of_change?: fun(x: T, y: T): number; }
--- @return LevenshteinChange<T>[]
function M.levenshtein(x, y, cost)
  cost = cost or {}
  local cost_of_delete_f = cost.of_delete or function() return 1 end
  local cost_of_add_f = cost.of_add or function() return 1 end
  local cost_of_change_f = cost.of_change or function() return 1 end

  local m, n = #x, #y
  -- Initialize the distance matrix
  local dp = {}
  for i = 0, m do
    dp[i] = {}
    for j = 0, n do
      dp[i][j] = 0
    end
  end

  -- Fill the base cases
  for i = 0, m do
    dp[i][0] = i
  end
  for j = 0, n do
    dp[0][j] = j
  end

  -- Compute the Levenshtein distance dynamically
  for i = 1, m do
    for j = 1, n do
      if x[i] == y[j] then
        dp[i][j] = dp[i - 1][j - 1] -- no cost if items are the same
      else
        local costDelete = dp[i - 1][j] + cost_of_delete_f(x[i])
        local costAdd = dp[i][j - 1] + cost_of_add_f(y[j])
        local costChange = dp[i - 1][j - 1] + cost_of_change_f(x[i], y[j])
        dp[i][j] = math.min(costDelete, costAdd, costChange)
      end
    end
  end

  -- Backtrack to find the changes
  local i = m
  local j = n
  --- @type LevenshteinChange[]
  local changes = {}

  while i > 0 or j > 0 do
    local default_cost = dp[i][j]
    local cost_of_change = (i > 0 and j > 0) and dp[i - 1][j - 1] or default_cost
    local cost_of_add = j > 0 and dp[i][j - 1] or default_cost
    local cost_of_delete = i > 0 and dp[i - 1][j] or default_cost

    --- @param u number
    --- @param v number
    --- @param w number
    local function is_first_min(u, v, w) return u <= v and u <= w end

    if is_first_min(cost_of_change, cost_of_add, cost_of_delete) then
      -- potential change
      if x[i] ~= y[j] then
        --- @type LevenshteinChange
        local change = { kind = 'change', from = x[i], index = i, to = y[j] }
        table.insert(changes, change)
      end
      i = i - 1
      j = j - 1
    elseif is_first_min(cost_of_add, cost_of_change, cost_of_delete) then
      -- addition
      --- @type LevenshteinChange
      local change = { kind = 'add', item = y[j], index = i + 1 }
      table.insert(changes, change)
      j = j - 1
    elseif is_first_min(cost_of_delete, cost_of_change, cost_of_add) then
      -- deletion
      --- @type LevenshteinChange
      local change = { kind = 'delete', item = x[i], index = i }
      table.insert(changes, change)
      i = i - 1
    else
      error 'unreachable'
    end
  end

  return changes
end

return M
