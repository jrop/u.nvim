# Text Tools (TT)

Welcome to **Text Tools (TT)** – a powerful Lua library designed to enhance your text manipulation experience in NeoVim, focusing primarily on a context-aware "Range" utility. This utility allows you to work efficiently with text selections based on various conditions, in a variety of contexts, making coding and editing more intuitive and productive.

This is meant to be used as a **library**, not a plugin. On its own, text-tools.nvim does nothing on its own. It is meant to be used by plugin authors, to make their lives easier based on the variety of utilities I found I needed while growing my NeoVim config.

## Features

- **Range Utility**: Get context-aware selections with ease.
- **Code Writer**: Write code with automatic indentation and formatting.
- **Operator Key Mapping**: Flexible key mapping that works with the selected text.
- **Text and Position Utilities**: Convenient functions to manage text objects and cursor positions.

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/text-tools.git
   ```
2. Add the path to your `init.vim` or `init.lua`:
   ```lua
   package.path = package.path .. ';/path/to/text-tools/lua/?.lua'
   ```

## Usage

### 1. Creating a Range

To create a range, use the `Range.new(startPos, endPos, mode)` method:

```lua
local Range = require 'tt.range'
local startPos = Pos.new(0, 1, 0)  -- Line 1, first column
local endPos = Pos.new(0, 3, 0)    -- Line 3, first column
local myRange = Range.new(startPos, endPos)
```

### 2. Working with Code Writer

To write code with indentation, use the `CodeWriter` class:

```lua
local CodeWriter = require 'tt.codewriter'
local cw = CodeWriter.new()
cw:write('{')
cw:indent(function(innerCW)
    innerCW:write('x: 123')
end)
cw:write('}')
```

### 3. Defining Key Mappings

Define custom key mappings for text objects:

```lua
local opkeymap = require 'tt.opkeymap'

-- invoke this function by typing, for example, `<leader>riw`:
-- `range` will contain the bounds of the motion `iw`.
opkeymap('n', '<leader>r', function(range)
    print(range:text())  -- Prints the text within the selected range
end)
```

### 4. Utility Functions

#### Cursor Position

To manage cursor position, use the `Pos` class:

```lua
local Pos = require 'tt.pos'
local cursorPos = Pos.new(0, 1, 5)  -- Line 1, character 5
print(cursorPos:char())  -- Gets the character at the cursor position
```

#### Buffer Management

Access and manipulate buffers easily:

```lua
local Buffer = require 'tt.buffer'
local buf = Buffer.current()
print(buf:line_count())  -- Number of lines in the current buffer
```

## License (MIT)

Copyright (c) 2024 jrapodaca@gmail.com

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
