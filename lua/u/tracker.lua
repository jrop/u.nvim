local M = {}

M.debug = false

--------------------------------------------------------------------------------
-- class Signal
--------------------------------------------------------------------------------

--- @class u.Signal
--- @field name? string
--- @field private changing boolean
--- @field private value any
--- @field private subscribers table<function, boolean>
--- @field private on_dispose_callbacks function[]
local Signal = {}
M.Signal = Signal
Signal.__index = Signal

--- @param value any
--- @param name? string
--- @return u.Signal
function Signal:new(value, name)
  local obj = setmetatable({
    name = name,
    changing = false,
    value = value,
    subscribers = {},
    on_dispose_callbacks = {},
  }, self)
  return obj
end

--- @param value any
function Signal:set(value)
  self.value = value

  -- We don't handle cyclic updates:
  if self.changing then
    if M.debug then
      vim.notify(
        'circular dependency detected' .. (self.name and (' in ' .. self.name) or ''),
        vim.log.levels.WARN
      )
    end
    return
  end

  local prev_changing = self.changing
  self.changing = true
  local ok = true
  local err = nil
  for _, cb in ipairs(self.subscribers) do
    local ok2, err2 = pcall(cb, value)
    if not ok2 then
      ok = false
      err = err or err2
    end
  end
  self.changing = prev_changing

  if not ok then
    vim.notify(
      'error notifying' .. (self.name and (' in ' .. self.name) or '') .. ': ' .. tostring(err),
      vim.log.levels.WARN
    )
    error(err)
  end
end

function Signal:schedule_set(value)
  vim.schedule(function() self:set(value) end)
end

--- @return any
function Signal:get()
  local ctx = M.ExecutionContext.current()
  if ctx then ctx:track(self) end
  return self.value
end

--- @param fn function
function Signal:update(fn) self:set(fn(self.value)) end

--- @param fn function
function Signal:schedule_update(fn) self:schedule_set(fn(self.value)) end

--- @generic U
--- @param fn fun(value: T): U
--- @return u.Signal --<U>
function Signal:map(fn)
  local mapped_signal = M.create_memo(function()
    local value = self:get()
    return fn(value)
  end, self.name and self.name .. ':mapped' or nil)
  return mapped_signal
end

--- @return u.Signal
function Signal:clone()
  return self:map(function(x) return x end)
end

--- @param fn fun(value: T): boolean
--- @return u.Signal -- <T>
function Signal:filter(fn)
  local filtered_signal = M.create_signal(nil, self.name and self.name .. ':filtered' or nil)
  local unsubscribe_from_self = self:subscribe(function(value)
    if fn(value) then filtered_signal:set(value) end
  end)
  filtered_signal:on_dispose(unsubscribe_from_self)
  return filtered_signal
end

--- @param ms number
--- @return u.Signal -- <T>
function Signal:debounce(ms)
  local function set_timeout(timeout, callback)
    local timer = (vim.uv or vim.loop).new_timer()
    timer:start(timeout, 0, function()
      timer:stop()
      timer:close()
      callback()
    end)
    return timer
  end

  local filtered = M.create_signal(self.value, self.name and self.name .. ':debounced' or nil)

  --- @diagnostic disable-next-line: undefined-doc-name
  --- @type { queued: { value: T, ts: number }[]; timer?: uv_timer_t; }
  local state = { queued = {}, timer = nil }
  local function clear_timeout()
    if state.timer == nil then return end
    pcall(function()
      --- @diagnostic disable-next-line: undefined-field
      state.timer:stop()
      --- @diagnostic disable-next-line: undefined-field
      state.timer:close()
    end)
    state.timer = nil
  end

  local unsubscribe_from_self = self:subscribe(function(value)
    -- Stop any previously running timer:
    if state.timer then clear_timeout() end
    local now_ms = (vim.uv or vim.loop).hrtime() / 1e6

    -- If there is anything older than `ms` in our queue, emit it:
    local older_than_ms = vim
      .iter(state.queued)
      :filter(function(item) return now_ms - item.ts > ms end)
      :totable()
    local last_older_than_ms = older_than_ms[#older_than_ms]
    if last_older_than_ms then
      filtered:set(last_older_than_ms.value)
      state.queued = {}
    end

    -- overwrite anything young enough
    table.insert(state.queued, { value = value, ts = now_ms })
    state.timer = set_timeout(ms, function()
      vim.schedule(function() filtered:set(value) end)
      -- If a timer was allowed to run to completion, that means that no other
      -- item has been queued, since the timer is reset every time a new item
      -- comes in. This means we can reset the queue
      clear_timeout()
      state.queued = {}
    end)
  end)
  filtered:on_dispose(unsubscribe_from_self)

  return filtered
end

--- @param callback function
function Signal:subscribe(callback)
  table.insert(self.subscribers, callback)
  return function() self:unsubscribe(callback) end
end

--- @param callback function
function Signal:on_dispose(callback) table.insert(self.on_dispose_callbacks, callback) end

--- @param callback function
function Signal:unsubscribe(callback)
  for i, cb in ipairs(self.subscribers) do
    if cb == callback then
      table.remove(self.subscribers, i)
      break
    end
  end
end

function Signal:dispose()
  self.subscribers = {}
  for _, callback in ipairs(self.on_dispose_callbacks) do
    callback()
  end
end

--------------------------------------------------------------------------------
-- class ExecutionContext
--------------------------------------------------------------------------------

local CURRENT_CONTEXT = nil

--- @class u.ExecutionContext
--- @field signals table<u.Signal, boolean>
local ExecutionContext = {}
M.ExecutionContext = ExecutionContext
ExecutionContext.__index = ExecutionContext

--- @return u.ExecutionContext
function ExecutionContext.new()
  return setmetatable({
    signals = {},
    subscribers = {},
  }, ExecutionContext)
end

function ExecutionContext.current() return CURRENT_CONTEXT end

--- @param fn function
--- @param ctx u.ExecutionContext
function ExecutionContext.run(fn, ctx)
  local oldCtx = CURRENT_CONTEXT
  CURRENT_CONTEXT = ctx
  local result
  local success, err = pcall(function() result = fn() end)

  CURRENT_CONTEXT = oldCtx

  if not success then error(err) end

  return result
end

function ExecutionContext:track(signal) self.signals[signal] = true end

--- @param callback function
function ExecutionContext:subscribe(callback)
  local wrapped_callback = function() callback() end
  for signal in pairs(self.signals) do
    signal:subscribe(wrapped_callback)
  end

  return function()
    for signal in pairs(self.signals) do
      signal:unsubscribe(wrapped_callback)
    end
  end
end

function ExecutionContext:dispose()
  for signal, _ in pairs(self.signals) do
    signal:dispose()
  end
  self.signals = {}
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- @param value any
--- @param name? string
--- @return u.Signal
function M.create_signal(value, name) return Signal:new(value, name) end

--- @param fn function
--- @param name? string
--- @return u.Signal
function M.create_memo(fn, name)
  --- @type u.Signal
  local result
  local unsubscribe = M.create_effect(function()
    local value = fn()
    if name and M.debug then vim.notify(name) end
    if result then
      result:set(value)
    else
      result = M.create_signal(value, name and ('m.s:' .. name) or nil)
    end
  end, name)
  result:on_dispose(unsubscribe)
  return result
end

--- @param fn function
--- @param name? string
function M.create_effect(fn, name)
  local ctx = M.ExecutionContext.new()
  M.ExecutionContext.run(fn, ctx)
  return ctx:subscribe(function()
    if name and M.debug then
      local deps = vim
        .iter(vim.tbl_keys(ctx.signals))
        :map(function(s) return s.name end)
        :filter(function(nm) return nm ~= nil end)
        :join ','
      vim.notify(name .. '(deps=' .. deps .. ')')
    end
    fn()
  end)
end

return M
