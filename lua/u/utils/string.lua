local M = {}

--------------------------------------------------------------------------------
--- eat_while
--------------------------------------------------------------------------------

--- @param s string
--- @param pos number
--- @param predicate fun(c: string, i: number, s: string): boolean
function M.eat_while(s, pos, predicate)
  local eaten = ''
  local curr = pos
  local watchdog = 0
  while curr <= #s do
    watchdog = watchdog + 1
    if watchdog > #s then error 'infinite loop' end

    local c = s:sub(curr, curr)
    if not predicate(c, curr, s) then break end
    eaten = eaten .. c
    curr = curr + 1
  end
  return eaten, curr
end

--- @param c string
function M.is_whitespace(c) return c == ' ' or c == '\t' or c == '\n' end

return M
