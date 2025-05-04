local tracker = require 'u.tracker'
local Signal = tracker.Signal
local ExecutionContext = tracker.ExecutionContext

describe('Signal', function()
  local signal

  before_each(function() signal = Signal:new(0, 'testSignal') end)

  it('should initialize with correct parameters', function()
    assert.is.equal(signal.value, 0)
    assert.is.equal(signal.name, 'testSignal')
    assert.is.not_nil(signal.subscribers)
    assert.is.equal(#signal.subscribers, 0)
    assert.is.equal(signal.changing, false)
  end)

  it('should set new value and notify subscribers', function()
    local called = false
    signal:subscribe(function(value)
      called = true
      assert.is.equal(value, 42)
    end)

    signal:set(42)
    assert.is.equal(called, true)
  end)

  it('should not notify subscribers during circular dependency', function()
    signal.changing = true
    local notified = false

    signal:subscribe(function() notified = true end)

    signal:set(42)
    assert.is.equal(notified, false) -- No notification should occur
  end)

  it('should get current value', function()
    signal:set(100)
    assert.is.equal(signal:get(), 100)
  end)

  it('should update value with function', function()
    signal:set(10)
    signal:update(function(value) return value * 2 end)
    assert.is.equal(signal:get(), 20)
  end)

  it('should dispose subscribers', function()
    local called = false
    local unsubscribe = signal:subscribe(function() called = true end)

    unsubscribe()
    signal:set(10)
    assert.is.equal(called, false) -- Should not be notified
  end)

  describe('Signal:map', function()
    it('should transform the signal value', function()
      local test_signal = Signal:new(5)
      local mapped_signal = test_signal:map(function(value) return value * 2 end)

      assert.is.equal(mapped_signal:get(), 10) -- Initial transformation
      test_signal:set(10)
      assert.is.equal(mapped_signal:get(), 20) -- Updated transformation
    end)

    it('should handle empty transformations', function()
      local test_signal = Signal:new(nil)
      local mapped_signal = test_signal:map(function(value) return value or 'default' end)

      assert.is.equal(mapped_signal:get(), 'default') -- Return default
      test_signal:set 'new value'
      assert.is.equal(mapped_signal:get(), 'new value') -- Return new value
    end)
  end)

  describe('Signal:filter', function()
    it('should only emit values that pass the filter', function()
      local test_signal = Signal:new(5)
      local filtered_signal = test_signal:filter(function(value) return value > 10 end)

      assert.is.equal(filtered_signal:get(), nil) -- Initial value should not pass
      test_signal:set(15)
      assert.is.equal(filtered_signal:get(), 15) -- Now filtered
      test_signal:set(8)
      assert.is.equal(filtered_signal:get(), 15) -- Does not pass the filter
    end)

    it('should handle empty initial values', function()
      local test_signal = Signal:new(nil)
      local filtered_signal = test_signal:filter(function(value) return value ~= nil end)

      assert.is.equal(filtered_signal:get(), nil) -- Should be nil
      test_signal:set(10)
      assert.is.equal(filtered_signal:get(), 10) -- Should pass now
    end)
  end)

  describe('create_memo', function()
    it('should compute a derived value and update when dependencies change', function()
      local test_signal = Signal:new(2)
      local memoized_signal = tracker.create_memo(function() return test_signal:get() * 2 end)

      assert.is.equal(memoized_signal:get(), 4) -- Initially compute 2 * 2

      test_signal:set(3)
      assert.is.equal(memoized_signal:get(), 6) -- Update to 3 * 2 = 6

      test_signal:set(5)
      assert.is.equal(memoized_signal:get(), 10) -- Update to 5 * 2 = 10
    end)

    it('should not recompute if the dependencies do not change', function()
      local call_count = 0
      local test_signal = Signal:new(10)
      local memoized_signal = tracker.create_memo(function()
        call_count = call_count + 1
        return test_signal:get() + 1
      end)

      assert.is.equal(memoized_signal:get(), 11) -- Compute first value
      assert.is.equal(call_count, 1) -- Should compute once

      memoized_signal:get() -- Call again, should use memoized value
      assert.is.equal(call_count, 1) -- Still should only be one call

      test_signal:set(10) -- Set the same value
      assert.is.equal(memoized_signal:get(), 11)
      assert.is.equal(call_count, 2)

      test_signal:set(20)
      assert.is.equal(memoized_signal:get(), 21)
      assert.is.equal(call_count, 3)
    end)
  end)

  describe('create_effect', function()
    it('should track changes and execute callback', function()
      local test_signal = Signal:new(5)
      local call_count = 0

      tracker.create_effect(function()
        test_signal:get() -- track as a dependency
        call_count = call_count + 1
      end)

      assert.is.equal(call_count, 1)
      test_signal:set(10)
      assert.is.equal(call_count, 2)
    end)

    it('should clean up signals and not call after dispose', function()
      local test_signal = Signal:new(5)
      local call_count = 0

      local unsubscribe = tracker.create_effect(function()
        call_count = call_count + 1
        return test_signal:get() * 2
      end)

      assert.is.equal(call_count, 1) -- Initially calls
      unsubscribe() -- Unsubscribe the effect
      test_signal:set(10) -- Update signal value
      assert.is.equal(call_count, 1) -- Callback should not be called again
    end)
  end)
end)

describe('ExecutionContext', function()
  local context

  before_each(function() context = ExecutionContext:new() end)

  it('should initialize a new context', function()
    assert.is.table(context.signals)
    assert.is.table(context.subscribers)
  end)

  it('should track signals', function()
    local signal = Signal:new(0)
    context:track(signal)

    assert.is.equal(next(context.signals), signal) -- Check if signal is tracked
  end)

  it('should subscribe to signals', function()
    local signal = Signal:new(0)
    local callback_called = false

    context:track(signal)
    context:subscribe(function() callback_called = true end)

    signal:set(100)
    assert.is.equal(callback_called, true) -- Callback should be called
  end)

  it('should dispose tracked signals', function()
    local signal = Signal:new(0)
    context:track(signal)

    context:dispose()
    assert.is.falsy(next(context.signals)) -- Should not have any tracked signals
  end)
end)
