local tracker = require 'u.tracker'
local Buffer = require 'u.buffer'
local h = require('u.renderer').h

-- Create an buffer for the UI
vim.cmd.vnew()
local ui_buf = Buffer.current()
ui_buf:set_tmp_options()

local s_count = tracker.create_signal(0, 'counter_signal')

-- Effect: Render
-- Setup the effect for rendering the UI whenever dependencies are updated
tracker.create_effect(function()
  -- Calling `Signal:get()` in an effect registers the given signal as a
  -- dependency of the current effect. Whenever that signal (or any other
  -- dependency) changes, the effect will rerun. In this particular case,
  -- rendering the UI is an effect that depends on one signal.
  local count = s_count:get()

  -- Markup is hyperscript, which is just 1) text, and 2) tags (i.e.,
  -- constructed with `h(...)` calls). To help organize the markup, text and
  -- tags can be nested in tables at any depth. Line breaks must be specified
  -- manually, with '\n'.
  ui_buf:render {
    'Reactive Counter Example\n',
    '========================\n\n',

    { 'Counter: ', tostring(count), '\n' },

    '\n',

    {
      h('text', {
        hl = 'DiffDelete',
        nmap = {
          ['<CR>'] = function()
            -- Update the contents of the s_count signal, notifying any
            -- dependencies (in this case, the render effect):
            s_count:schedule_update(function(n) return n - 1 end)
            -- Also equivalent: s_count:schedule_set(s_count:get() - 1)
            return ''
          end,
        },
      }, ' Decrement '),
      ' ',
      h('text', {
        hl = 'DiffAdd',
        nmap = {
          ['<CR>'] = function()
            -- Update the contents of the s_count signal, notifying any
            -- dependencies (in this case, the render effect):
            s_count:schedule_update(function(n) return n + 1 end)
            -- Also equivalent: s_count:schedule_set(s_count:get() - 1)
            return ''
          end,
        },
      }, ' Increment '),
    },

    '\n',
    '\n',
    { 'Press <CR> on each "button" above to increment/decrement the counter.' },
  }
end)
