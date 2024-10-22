local M = {}

local function _normal(cmd) vim.cmd.normal { cmd = 'normal', args = { cmd }, bang = true } end

M.native_repeat = function() _normal '.' end
M.native_undo = function() _normal 'u' end

---@param cmd? string|fun():unknown
function M.set(cmd)
  local ts = vim.b.changedtick
  vim.b.tt_changedtick = ts
  if cmd ~= nil then vim.b.tt_repeatcmd = cmd end
end

local function tt_was_last_repeatable()
  local ts, tt_ts, tt_cmd = vim.b.changedtick, vim.b.tt_changedtick, vim.b.tt_repeatcmd
  return tt_ts ~= nil and ts <= tt_ts
end

---@generic T
---@param cmd string|fun():T
---@return T
function M.run(cmd)
  M.set(cmd)
  local result = cmd()
  M.set()
  return result
end

function M.do_repeat()
  local ts, tt_ts, tt_cmd = vim.b.changedtick, vim.b.tt_changedtick, vim.b.tt_repeatcmd
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
  if tt_was_last_repeatable_before_undo then
    -- Update the current TS on the next event tick,
    -- to make sure we get the latest
    M.set()
  end
end

function M.setup()
  vim.keymap.set('n', '.', M.do_repeat)
  vim.keymap.set('n', 'u', M.undo)
end

return M
