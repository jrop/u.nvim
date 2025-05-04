# u.nvim

Welcome to **u.nvim** - a powerful Lua library designed to enhance your text
manipulation experience in NeoVim, focusing on text-manipulation utilities.
This includes a `Range` utility, allowing you to work efficiently with text
selections based on various conditions, as well as a declarative `Render`-er,
making coding and editing more intuitive and productive.

This is meant to be used as a **library**, not a plugin. On its own, `u.nvim`
does nothing. It is meant to be used by plugin authors, to make their lives
easier based on the variety of utilities I found I needed while growing my
NeoVim config. To get an idea of what a plugin built on top of `u.nvim` would
look like, check out the [examples/](./examples/) directory.

## Features

- **Rendering System**: a utility that can declaratively render NeoVim-specific
  hyperscript into a buffer, supporting creating/managing extmarks, highlights,
  and key-event handling (requires NeoVim >0.11)
- **Signals**: a simple dependency tracking system that pairs well with the
  rendering utilities for creating reactive/interactive UIs in NeoVim.
- **Range Utility**: Get context-aware selections with ease. Replace regions
  with new text. Think of it as a programmatic way to work with visual
  selections (or regions of text).
- **Code Writer**: Write code with automatic indentation and formatting.
- **Operator Key Mapping**: Flexible key mapping that works with the selected
  text.
- **Text and Position Utilities**: Convenient functions to manage text objects
  and cursor positions.

### Installation

This being a library, and not a proper plugin, it is recommended that you
vendor the specific version of this library that you need, including it in your
code. Package managers are a developing landscape for Lua in the context of
NeoVim. Perhaps in the future, `lux` will eliminate the need to vendor this
library in your application code.

## Signal and Rendering Usage

### Overview

The Signal and Rendering mechanisms are two subsystems of u.nvim, that, while
simplistic, [compose](./examples/counter.lua) [together](./examples/filetree.lua)
[powerfully](./examples/picker.lua) to create a system for interactive and
responsive user interfaces. Here is a quick example that show-cases how easy it
is to dive in to make any buffer an interactive UI:

<details>
<summary>Example Code: counter.lua</summary>

```lua
local tracker = require 'u.tracker'
local Buffer = require 'u.buffer'
local h = require('u.renderer').h

-- Create an buffer for the UI
vim.cmd.vnew()
local ui_buf = Buffer.current()
ui_buf:set_tmp_options()

local s_count = tracker.create_signal(0)

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
            vim.schedule(function()
              s_count:update(function(n) return n - 1 end)
            end)
            -- Also equivalent: s_count:set(s_count:get() - 1)
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
            vim.schedule(function()
              s_count:update(function(n) return n + 1 end)
            end)
            -- Also equivalent: s_count:set(s_count:get() - 1)
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
```

</details>

### `u.tracker`

The `u.tracker` module provides a simple API for creating reactive variables.
These can be composed in Effects and Memos utilizing Execution Contexts that
track what signals are used by effects/memos.

```lua
local tracker = require('u.tracker')

local s_number = tracker.Signal:new(0)
-- auto-compute the double of the number each time it changes:
local s_doubled = tracker.create_memo(function() return s_number:get() * 2 end)
tracker.create_effect(function()
  local n = s_doubled:get()
  -- ...
  -- whenever s_doubled changes, this function gets run
end)
```

**Note**: circular dependencies are **not** supported.

### `u.renderer`

The renderer library renders hyperscript into a buffer. Each render performs a
minimal set of changes in order to transform the current buffer text into the
desired state.

**Hyperscript** is just 1) _text_ 2) `<text>` tags, which can be nested in 3)
Lua tables for readability:

```lua
local h = require('u.renderer').h
-- Hyperscript can be organized into tables:
{
  "Hello, ",
  {
    "I am ", { "a" }, " nested table.",
  },
  '\n', -- newlines must be explicitly specified

  -- booleans/nil are ignored:
  some_conditional_flag and 'This text only shows when the flag is true',
  -- e.g., use the above to show newlines in lists:
  idx > 1 and '\n',

  -- <text> tags are specified like so:
  -- h('text', attributes, children)
  h('text', {}, "I am a text node."),

  -- <text> tags can be highlighted:
  h('text', { hl = 'Comment' }, "I am highlighted."),

  -- <text> tags can respond to key events:
  h('text', {
    hl = 'Keyword',
    nmap = {
      ["<CR>"] = function()
        print("Hello World")
        -- Return '' to swallow the event:
        return ''
      end,
    },
  }, "I am a text node."),
}
```

Managing complex tables of hyperscript can be done more ergonomically using the
`TreeBuilder` helper class:

```lua
local TreeBuilder = require('u.renderer').TreeBuilder

-- ...
renderer:render(
  TreeBuilder.new()
    -- text:
    :put('some text')
    -- hyperscript tables:
    :put({ 'some text', 'more hyperscript' })
    -- hyperscript tags:
    :put_h('text', { --[[attributes]] }, { --[[children]] })
    -- callbacks:
    --- @param tb TreeBuilder
    :nest(function(tb)
      tb:put('some text')
    end)
    :tree()
)
```

**Rendering**: The renderer library provides a `render` function that takes
hyperscript in, and converts it to formatted buffer text:

```lua
local Renderer = require('u.renderer').Renderer
local renderer = Renderer:new(0 --[[buffer number]])
renderer:render {
  -- ...hyperscript...
}

-- or, if you already have a buffer:
local Buffer = require('u.buffer')
local buf = Buffer.current()
buf:render {
  -- ...hyperscript...
}
```

## Range Usage

### A note on indices

<blockquote>
<del>
I love NeoVim. I am coming to love Lua. I don't like 1-based indices; perhaps I
am too old. Perhaps I am too steeped in the history of loving the elegance of
simple pointer arithmetic. Regardless, the way positions are addressed in
NeoVim/Vim is (terrifyingly) mixed. Some methods return 1-based, others accept
only 0-based. In order to stay sane, I had to make a choice to store everything
in one, uniform representation in this library. I chose (what I humbly think is
the only sane way) to stick with the tried-and-true 0-based index scheme. That
abstraction leaks into the public API of this library.
</del>
</blockquote>

<br />
<b>This has changed in v2</b>. After much thought, I realized that:

1. The 0-based indexing in NeoVim is prevelant in the `:api`, which is designed
   to be exposed to many languages. As such, it makes sense for this interface
   to use 0-based indexing. However, many internal Vim functions use 1-based
   indexing.
2. This is a Lua library (surprise, surprise, duh) - the idioms of the language
   should take precedence over my preference
3. There were subtle bugs in the code where indices weren't being normalized to
   0-based, anyways. Somehow it worked most of the time.

As such, this library now uses 1-based indexing everywhere, doing the necessary
interop conversions when calling `:api` functions.

### 1. Creating a Range

The `Range` utility is the main feature upon which most other things in this
library are built, aside from a few standalone utilities. Ranges can be
constructed manually, or preferably, obtained based on a variety of contexts.

```lua
local Range = require 'u.range'
local start = Pos.new(0, 1, 1) -- Line 1, first column
local stop = Pos.new(0, 3, 1) -- Line 3, first column

Range.new(start, stop, 'v') -- charwise selection
Range.new(start, stop, 'V') -- linewise selection
```

This is usually not how you want to obtain a `Range`, however. Usually you want
to get the corresponding context of an edit operation and just "get me the
current Range that represents this context".

```lua
-- get the first line in a buffer:
Range.from_line(bufnr, 1)

-- Text Objects (any text object valid in your configuration is supported):
-- get the word the cursor is on:
Range.from_motion('iw')
-- get the WORD the cursor is on:
Range.from_motion('iW')
-- get the "..." the cursor is within:
Range.from_motion('a"')

-- Get the currently visually selected text:
-- NOTE: this does NOT work within certain contexts; more specialized utilities
-- are more appropriate in certain circumstances
Range.from_vtext()

--
-- Get the operated on text obtained from a motion:
-- (HINT: use the opkeymap utility to make this less verbose)
--
--- @param ty 'char'|'line'|'block'
function MyOpFunc(ty)
  local range = Range.from_op_func(ty)
  -- do something with the range
end
-- Try invoking this with: `<Leader>toaw`, and the current word will be the
-- context:
vim.keymap.set('<Leader>to', function()
  vim.g.operatorfunc = 'v:lua.MyOpFunc'
  return 'g@'
end, { expr = true })

--
-- Commands:
--
-- When executing commands in a visual context, getting the selected text has
-- to be done differently:
vim.api.nvim_create_user_command('MyCmd', function(args)
  local range = Range.from_cmd_args(args)
  if range == nil then
    -- the command was executed in normal mode
  else
    -- ...
  end
end, { range = true })
```

So far, that's a lot of ways to _get_ a `Range`. But what can you do with a
range once you have one? Plenty, it turns out!

```lua
local range = ...
range:lines() -- get the lines in the range's region
range:text() -- get the text (i.e., string) in the range's region
range:line(1) -- get the first line within this range
range:line(-1) -- get the last line within this range
-- replace with new contents:
range:replace {
  'replacement line 1',
  'replacement line 2',
}
range:replace 'with a string'
-- delete the contents of the range:
range:replace(nil)
```

### 2. Defining Key Mappings over Motions

Define custom (dot-repeatable) key mappings for text objects:

```lua
local opkeymap = require 'u.opkeymap'

-- invoke this function by typing, for example, `<leader>riw`:
-- `range` will contain the bounds of the motion `iw`.
opkeymap('n', '<leader>r', function(range)
  print(range:text()) -- Prints the text within the selected range
end)
```

### 3. Working with Code Writer

To write code with indentation, use the `CodeWriter` class:

```lua
local CodeWriter = require 'u.codewriter'
local cw = CodeWriter.new()
cw:write('{')
cw:indent(function(innerCW)
  innerCW:write('x: 123')
end)
cw:write('}')
```

### 4. Utility Functions

#### Custom Text Objects

Simply by returning a `Range` or a `Pos`, you can easily and quickly define
your own text objects:

```lua
local txtobj = require 'u.txtobj'
local Range = require 'u.range'

-- Select whole file:
txtobj.define('ag', function()
  return Range.from_buf_text()
end)
```

#### Buffer Management

Access and manipulate buffers easily:

```lua
local Buffer = require 'u.buffer'
local buf = Buffer.current()
buf.b.<option>        -- get buffer-local variables
buf.b.<option>  = ... -- set buffer-local variables
buf.bo.<option>       -- get buffer options
buf.bo.<option> = ... -- set buffer options
buf:line_count()      -- the number of lines in the current buffer
buf:all()             -- returns a Range representing the entire buffer
buf:is_empty()        -- returns true if the buffer has no text
buf:append_line '...'
buf:line(1)           -- returns a Range representing the first line in the buffer
buf:line(-1)          -- returns a Range representing the last line in the buffer
buf:lines(1, 2)       -- returns a Range representing the first two lines in the buffer
buf:lines(2, -2)      -- returns a Range representing all but the first and last lines of a buffer
buf:txtobj('iw')      -- returns a Range representing the text object 'iw' in the give buffer
```

## License (MIT)

Copyright (c) 2024 jrapodaca@gmail.com

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
