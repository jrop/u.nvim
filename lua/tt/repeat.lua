local M = {}

local function _normal(cmd) vim.cmd.normal { cmd = 'normal', args = { cmd }, bang = true } end
local function _feedkeys(keys, mode)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), mode or 'nx', true)
end

M.native_repeat = function() _feedkeys '.' end
M.native_undo = function() _feedkeys 'u' end

---@param cmd? string|fun():unknown
function M.set(cmd)
  local ts = vim.b.changedtick
  vim.b.tt_changedtick = ts
  if cmd ~= nil then vim.b.tt_repeatcmd = cmd end
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
  if
    -- (force formatter break)
    tt_ts == nil
    or tt_cmd == nil
    -- has the buffer been modified after we last modified it?
    or ts > tt_ts
    or (type(tt_cmd) ~= 'function' and type(tt_cmd) ~= 'string')
  then
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
  M.native_undo()
  -- Update the current TS on the next event tick,
  -- to make sure we get the latest
  vim.schedule(M.set)
end

function M.setup()
  vim.keymap.set('n', '.', M.do_repeat)
  vim.keymap.set('n', 'u', M.undo)
end

return M
