local M = {}

local function _normal(cmd) vim.cmd { cmd = 'normal', args = { cmd }, bang = true } end

M.native_repeat = function() _normal '.' end
M.native_undo = function() _normal 'u' end

local function update_ts() vim.b.tt_changedtick = vim.b.changedtick end

---@param cmd? string|fun():unknown
function M.set(cmd)
  update_ts()
  if cmd ~= nil then vim.b.tt_repeatcmd = cmd end
end

local function tt_was_last_repeatable()
  local ts, tt_ts = vim.b.changedtick, vim.b.tt_changedtick
  return tt_ts ~= nil and ts <= tt_ts
end

---@generic T
---@param cmd string|fun():T
---@return T
function M.run(cmd)
  M.set(cmd)
  local result = cmd()
  update_ts()
  return result
end

function M.do_repeat()
  local tt_cmd = vim.b.tt_repeatcmd
  if not tt_was_last_repeatable() or (type(tt_cmd) ~= 'function' and type(tt_cmd) ~= 'string') then
    return M.native_repeat()
  end

  -- execute the cached command:
  local count = vim.api.nvim_get_vvar 'count1'
  if type(tt_cmd) == 'string' then
    _normal(count .. tt_cmd --[[@as string]])
  else
    local last_return
    for _ = 1, count do
      last_return = M.run(tt_cmd --[[@as fun():any]])
    end
    return last_return
  end
end

function M.undo()
  local tt_was_last_repeatable_before_undo = tt_was_last_repeatable()
  M.native_undo()
  if tt_was_last_repeatable_before_undo then update_ts() end
end

function M.setup()
  vim.keymap.set('n', '.', M.do_repeat)
  vim.keymap.set('n', 'u', M.undo)
end

return M
