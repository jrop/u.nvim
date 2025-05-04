local M = {}

local IS_REPEATING = false
--- @type function
local REPEAT_ACTION = nil

local function is_repeatable_last_mutator() return vim.b.changedtick <= (vim.b.my_changedtick or 0) end

--- @param f fun()
function M.run_repeatable(f)
  REPEAT_ACTION = f
  REPEAT_ACTION()
  vim.b.my_changedtick = vim.b.changedtick
end

function M.is_repeating() return IS_REPEATING end

function M.setup()
  vim.keymap.set('n', '.', function()
    IS_REPEATING = true
    for _ = 1, vim.v.count1 do
      if is_repeatable_last_mutator() and type(REPEAT_ACTION) == 'function' then
        M.run_repeatable(REPEAT_ACTION)
      else
        vim.cmd { cmd = 'normal', args = { '.' }, bang = true }
      end
    end
    IS_REPEATING = false
  end)
  vim.keymap.set('n', 'u', function()
    local was_repeatable_last_mutator = is_repeatable_last_mutator()
    for _ = 1, vim.v.count1 do
      vim.cmd { cmd = 'normal', args = { 'u' }, bang = true }
    end
    if was_repeatable_last_mutator then vim.b.my_changedtick = vim.b.changedtick end
  end)
end

return M
