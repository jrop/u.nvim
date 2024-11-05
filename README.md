# u.nvim

Welcome to **u.nvim** – a powerful Lua library designed to enhance your text manipulation experience in NeoVim, focusing primarily on a context-aware "Range" utility. This utility allows you to work efficiently with text selections based on various conditions, in a variety of contexts, making coding and editing more intuitive and productive.

This is meant to be used as a **library**, not a plugin. On its own, `u.nvim` does nothing. It is meant to be used by plugin authors, to make their lives easier based on the variety of utilities I found I needed while growing my NeoVim config.

## Features

- **Range Utility**: Get context-aware selections with ease. Replace regions with new text. Think of it as a programmatic way to work with visual selections (or regions of text).
- **Code Writer**: Write code with automatic indentation and formatting.
- **Operator Key Mapping**: Flexible key mapping that works with the selected text.
- **Text and Position Utilities**: Convenient functions to manage text objects and cursor positions.

### Installation

lazy.nvim:
```lua
-- Setting `lazy = true` ensures that the library is only loaded
-- when `require 'u.<utility>' is called.
{ 'https://codeberg.org/jrop/u.nvim', lazy = true }
```

## Usage

### A note on indices

I love NeoVim. I am coming to love Lua. I don't like 1-based indices; perhaps I am too old. Perhaps I am too steeped in the history of loving the elegance of simple pointer arithmetic. Regardless, the way positions are addressed in NeoVim/Vim is (terrifyingly) mixed. Some methods return 1-based, others accept only 0-based. In order to stay sane, I had to make a choice to store everything in one, uniform representation in this library. I chose (what I humbly think is the only sane way) to stick with the tried-and-true 0-based index scheme. That abstraction leaks into the public API of this library.

### 1. Creating a Range

The `Range` utility is the main feature upon which most other things in this library are built, aside from a few standalone utilities. Ranges can be constructed manually, or preferably, obtained based on a variety of contexts.

```lua
local Range = require 'u.range'
local start = Pos.new(0, 0, 0) -- Line 1, first column
local stop = Pos.new(0, 2, 0) -- Line 3, first column

Range.new(start, stop, 'v') -- charwise selection
Range.new(start, stop, 'V') -- linewise selection
```

This is usually not how you want to obtain a `Range`, however. Usually you want to get the corresponding context of an edit operation and just "get me the current Range that represents this context".

```lua
-- get the first line in a buffer:
Range.from_line(0, 0)

-- Text Objects (any text object valid in your configuration is supported):
-- get the word the cursor is on:
Range.from_text_object('iw')
-- get the WORD the cursor is on:
Range.from_text_object('iW')
-- get the "..." the cursor is within:
Range.from_text_object('a"')

-- Get the currently visually selected text:
-- NOTE: this does NOT work within certain contexts; more specialized utilities are more appropriate in certain circumstances
Range.from_vtext()

--
-- Get the operated on text obtained from a motion:
-- (HINT: use the opkeymap utility to make this less verbose)
--
---@param ty 'char'|'line'|'block'
function MyOpFunc(ty)
  local range = Range.from_op_func(ty)
  -- do something with the range
end
-- Try invoking this with: `<Leader>toaw`, and the current word will be the context:
vim.keymap.set('<Leader>to', function()
  vim.g.operatorfunc = 'v:lua.MyOpFunc'
  return 'g@'
end, { expr = true })

--
-- Commands:
--
-- When executing commands in a visual context, getting the selected text has to be done differently:
vim.api.nvim_create_user_command('MyCmd', function(args)
  local range = Range.from_cmd_args(args)
  if range == nil then
    -- the command was executed in normal mode
  else
    -- ...
  end
end, { range = true })
```

So far, that's a lot of ways to _get_ a `Range`. But what can you do with a range once you have one? Plenty, it turns out!

```lua
local range = ...
range:lines() -- get the lines in the range's region
range:text() -- get the text (i.e., string) in the range's region
range:line0(0) -- get the first line within this range
range:line0(-1) -- get the last line within this range
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

Simply by returning a `Range` or a `Pos`, you can easily and quickly define your own text objects:

```lua
local utils = require 'u.utils'
local Range = require 'u.range'

-- Select whole file:
utils.define_text_object('ag', function()
  return Range.from_buf_text()
end)
```

#### Buffer Management

Access and manipulate buffers easily:

```lua
local Buffer = require 'u.buffer'
local buf = Buffer.current()
buf:line_count() -- the number of lines in the current buffer
buf:get_option '...'
buf:set_option('...', ...)
buf:get_var '...'
buf:set_var('...', ...)
buf:all() -- returns a Range representing the entire buffer
buf:is_empty() -- returns true if the buffer has no text
buf:append_line '...'
buf:line0(0) -- returns a Range representing the first line in the buffer
buf:line0(-1) -- returns a Range representing the last line in the buffer
buf:lines(0, 1) -- returns a Range representing the first two lines in the buffer
buf:lines(1, -2) -- returns a Range representing all but the first and last lines of a buffer
buf:text_object('iw') -- returns a Range representing the text object 'iw' in the give buffer
```

## License (MIT)

Copyright (c) 2024 jrapodaca@gmail.com

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
