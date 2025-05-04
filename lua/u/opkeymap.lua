local Range = require 'u.range'

--- @type fun(range: u.Range): nil|(fun():any)
local __U__OpKeymapOpFunc_rhs = nil

--- This is the global utility function used for operatorfunc
--- in opkeymap
--- @type nil|fun(range: u.Range): fun():any|nil
--- @param ty 'line'|'char'|'block'
-- selene: allow(unused_variable)
function _G.__U__OpKeymapOpFunc(ty)
  if __U__OpKeymapOpFunc_rhs ~= nil then
    local range = Range.from_op_func(ty)
    __U__OpKeymapOpFunc_rhs(range)
  end
end

--- Registers a function that operates on a text-object, triggered by the given prefix (lhs).
--- It works in the following way:
--- 1. An expression-map is set, so that whatever the callback returns is executed by Vim (in this case `g@`)
---    g@: tells vim to way for a motion, and then call operatorfunc.
--- 2. The operatorfunc is set to a lua function that computes the range being operated over, that
---    then calls the original passed callback with said range.
--- @param mode string|string[]
--- @param lhs string
--- @param rhs fun(range: u.Range): nil
--- @diagnostic disable-next-line: undefined-doc-name
--- @param opts? vim.keymap.set.Opts
local function opkeymap(mode, lhs, rhs, opts)
  vim.keymap.set(mode, lhs, function()
    -- We don't need to wrap the operation in a repeat, because expr mappings are
    -- repeated seamlessly by Vim anyway. In addition, the u.repeat:`.` mapping will
    -- set IS_REPEATING to true, so that callbacks can check if they should used cached
    -- values.
    __U__OpKeymapOpFunc_rhs = rhs
    vim.o.operatorfunc = 'v:lua.__U__OpKeymapOpFunc'
    return 'g@'
  end, vim.tbl_extend('force', opts or {}, { expr = true }))
end

return opkeymap
