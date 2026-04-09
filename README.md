# u.nvim

Welcome to **u.nvim** - a Lua library for text manipulation in Neovim, focusing on
range-based text operations, positions, and operator-pending mappings.

This is a **single-file micro-library** meant to be vendored in your plugin or
config. On its own, `u.nvim` does nothing. It is meant to be used by plugin
authors to make their lives easier. To get an idea of what a plugin built on
top of `u.nvim` would look like, check out the [examples/](./examples/) directory.

## Features

- **Range Utility**: Get context-aware selections with ease. Replace regions with
  new text. Think of it as a programmatic way to work with visual selections.
- **Position Utilities**: Work with cursor positions, marks, and extmarks.
- **Operator Key Mapping**: Flexible key mapping that works with motions.
- **Text Object Definitions**: Define custom text objects easily.
- **User Command Helpers**: Create commands with range support.
- **Repeat Utilities**: Dot-repeat support for custom operations.

### Installation

This being a library, and not a proper plugin, it is recommended that you vendor
the specific version of this library that you need, including it in your code.
Package managers are a developing landscape for Lua in the context of NeoVim.
Perhaps in the future, `lux` will eliminate the need to vendor this library in
your application code.

#### If you are a Plugin Author

Neovim does not have a good answer for automatic management of plugin dependencies. As such, it is recommended that library authors vendor u.nvim within their plugin. **u.nvim** is implemented in a single file, so this should be relatively painless. Furthermore, `lua/u.lua` versions are published into artifact tags `artifact-vX.Y.Z` as `init.lua` so that plugin authors can add u.nvim as a submodule to their plugin.

<details>
<summary>Example git submodule setup</summary>

```bash
# In your plugin repository
git submodule add -- https://github.com/jrop/u.nvim lua/my_plugin/u
cd lua/my_plugin/u/
git checkout artifact-v0.2.0 # put whatever version of u.nvim you want to pin here
# ... commit the submodule within your repo

# This would place u.nvim@v0.2.0 at:
# lua/my_plugin/u/init.lua
```

Then in your plugin code:

```lua
local u = require('my_plugin.u')

local Pos = u.Pos
local Range = u.Range
-- etc.
```

This approach allows plugin authors to:
- Pin to specific versions of u.nvim
- Get updates by pulling/committing new **u.nvim** versions (i.e., the usual git submodule way)
- Keep the dependency explicit and version-controlled
- Avoid namespace conflicts with user-installed plugins

</details>

#### If you are a User

If you want to use u.nvim in your config directly:

<details>
<summary>vim.pack</summary>

```lua
vim.pack.add { 'https://github.com/jrop/u.nvim' }
```

</details>

<details>
<summary>lazy.nvim</summary>

```lua
{
  'jrop/u.nvim',
  lazy = true,
}
```

</details>


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

The `Range` utility is the main feature of this library. Ranges can be constructed
manually, or preferably, obtained based on a variety of contexts.

```lua
local u = require 'u'

local start = u.Pos.new(nil, 1, 1) -- Line 1, first column
local stop = u.Pos.new(nil, 3, 1)  -- Line 3, first column

u.Range.new(start, stop, 'v') -- charwise selection
u.Range.new(start, stop, 'V') -- linewise selection
```

This is usually not how you want to obtain a `Range`, however. Usually you want
to get the corresponding context of an edit operation and just "get me the
current Range that represents this context".

```lua
local u = require 'u'

-- get the first line in a buffer:
u.Range.from_line(bufnr, 1)

-- Text Objects (any text object valid in your configuration is supported):
-- get the word the cursor is on:
u.Range.from_motion('iw')
-- get the WORD the cursor is on:
u.Range.from_motion('iW')
-- get the "..." the cursor is within:
u.Range.from_motion('a"')

-- Get the currently visually selected text:
-- NOTE: this does NOT work within certain contexts; more specialized utilities
-- are more appropriate in certain circumstances
u.Range.from_vtext()

--
-- Get the operated on text obtained from a motion:
-- (HINT: use the opkeymap utility to make this less verbose)
--
--- @param ty 'char'|'line'|'block'
function MyOpFunc(ty)
  local range = u.Range.from_op_func(ty)
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
  local range = u.Range.from_cmd_args(args)
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
range:text()  -- get the text (i.e., string) in the range's region
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
local u = require 'u'

-- invoke this function by typing, for example, `<leader>riw`:
-- `range` will contain the bounds of the motion `iw`.
u.opkeymap('n', '<leader>r', function(range)
  print(range:text()) -- Prints the text within the selected range
end)
```

### 3. Utility Functions

#### Custom Text Objects

Simply by returning a `Range`, you can easily define your own text objects:

```lua
local u = require 'u'

-- Select whole file:
u.define_txtobj('ag', function()
  return u.Range.from_buf_text()
end)

-- Select content inside nearest quotes:
u.define_txtobj('iq', function()
  return u.Range.find_nearest_quotes()
end)

-- Select content inside nearest brackets:
u.define_txtobj('ib', function()
  return u.Range.find_nearest_brackets()
end)
```

#### User Commands with Range Support

Create user commands that work with visual selections:

```lua
local u = require 'u'

u.ucmd('MyCmd', function(args)
  if args.info then
    -- args.info is a Range representing the selection
    print('Selected text:', args.info:text())
  else
    -- No range provided
    print('No selection')
  end
end, { range = true })
```

#### Repeat Utilities

Enable dot-repeat for custom operations:

```lua
local u = require 'u'

-- Call this in your plugin's setup:
u.repeat_.setup()

-- Then use in your operations:
u.repeat_.run_repeatable(function()
  -- Your mutation here
  -- This will be repeatable with '.'
end)
```

## API Reference

### `u.Pos`

Position class representing a location in a buffer.

```lua
local pos = u.Pos.new(bufnr, lnum, col, off)
pos:next(1)      -- next position (forward)
pos:next(-1)     -- previous position (backward)
pos:char()       -- character at position
pos:line()       -- line text
pos:eol()        -- end of line position
pos:save_to_cursor() -- move cursor to position
```

### `u.Range`

Range class representing a text region.

```lua
local range = u.Range.new(start, stop, mode)
range:text()     -- get text content
range:lines()    -- get lines as array
range:replace(text) -- replace with new text
range:contains(pos) -- check if position is within range
range:shrink(n)  -- shrink range by n characters from each side
range:highlight('Search') -- highlight range temporarily
```

### `u.opkeymap(mode, lhs, rhs, opts)`

Create operator-pending keymaps.

### `u.define_txtobj(key_seq, fn, opts)`

Define custom text objects.

### `u.ucmd(name, cmd, opts)`

Create user commands with enhanced range support.

### `u.create_delegated_cmd_args(args)`

Create arguments for delegating between commands.

### `u.repeat_`

Module for dot-repeat support.

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
