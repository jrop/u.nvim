local Range = require 'u.range'
local vim_repeat = require 'u.repeat'

---@type fun(range: Range): nil|(fun():any)
local __U__OpKeymapOpFunc_rhs = nil

--- This is the global utility function used for operatorfunc
--- in opkeymap
---@type nil|fun(range: Range): fun():any|nil
---@param ty 'line'|'char'|'block'
-- selene: allow(unused_variable)
function __U__OpKeymapOpFunc(ty)
  if __U__OpKeymapOpFunc_rhs ~= nil then
    local range = Range.from_op_func(ty)
    local repeat_inject = __U__OpKeymapOpFunc_rhs(range)

    vim_repeat.set(function()
      vim.o.operatorfunc = 'v:lua.__U__OpKeymapOpFunc'
      if repeat_inject ~= nil and type(repeat_inject) == 'function' then repeat_inject() end
      vim_repeat.native_repeat()
    end)
  end
end

--- Registers a function that operates on a text-object, triggered by the given prefix (lhs).
--- It works in the following way:
--- 1. An expression-map is set, so that whatever the callback returns is executed by Vim (in this case `g@`)
---    g@: tells vim to way for a motion, and then call operatorfunc.
--- 2. The operatorfunc is set to a lua function that computes the range being operated over, that
---    then calls the original passed callback with said range.
---@param mode string|string[]
---@param lhs string
---@param rhs fun(range: Range): nil|(fun():any) This function may return another function, which is called whenever the operator is repeated
---@param opts? vim.keymap.set.Opts
local function opkeymap(mode, lhs, rhs, opts)
  vim.keymap.set(mode, lhs, function()
    __U__OpKeymapOpFunc_rhs = rhs
    vim.o.operatorfunc = 'v:lua.__U__OpKeymapOpFunc'
    return 'g@'
  end, vim.tbl_extend('force', opts or {}, { expr = true }))
end

return opkeymap
