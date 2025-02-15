local utils = require 'u.utils'
local str = require 'u.utils.string'

--------------------------------------------------------------------------------
-- Renderer class
--------------------------------------------------------------------------------
--- @alias RendererHighlight { group: string; start: [number, number]; stop: [number, number ] }

--- @class Renderer
--- @field bufnr number
--- @field ns number
--- @field changedtick number
--- @field old { lines: string[]; hls: RendererHighlight[] }
--- @field curr { lines: string[]; hls: RendererHighlight[] }
local Renderer = {}
Renderer.__index = Renderer

--- @param bufnr number|nil
function Renderer.new(bufnr)
  if bufnr == nil then bufnr = vim.api.nvim_get_current_buf() end

  local self = setmetatable({
    bufnr = bufnr,
    ns = vim.api.nvim_create_namespace '',
    changedtick = 0,
    old = { lines = {}, hls = {} },
    curr = { lines = {}, hls = {} },
  }, Renderer)
  return self
end

--- @param markup string
function Renderer:render(markup)
  local changedtick = vim.b[self.bufnr].changedtick
  if changedtick ~= self.changedtick then
    self.curr = { lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false), hls = {} }
    self.changedtick = changedtick
  end

  local nodes = self._parse_markup(markup)

  --- @type string[]
  local lines = {}
  --- @type RendererHighlight[]
  local hls = {}

  local curr_line1 = 1
  local curr_col1 = 1 -- exclusive: sits one position **beyond** the last inserted text
  --- @param s string
  local function put(s)
    lines[curr_line1] = (lines[curr_line1] or '') .. s
    curr_col1 = #lines[curr_line1] + 1
  end
  local function put_line()
    table.insert(lines, '')
    curr_line1 = curr_line1 + 1
    curr_col1 = 1
  end

  for _, node in ipairs(nodes) do
    if node.kind == 'text' then
      local node_lines = vim.split(node.value, '\n')
      for lnum, s in ipairs(node_lines) do
        if lnum > 1 then put_line() end
        put(s)
      end
    elseif node.kind == 'tag' then
      local function attr_num(nm)
        if not node.attributes[nm] then return end
        return tonumber(node.attributes[nm])
      end
      local function attr_bool(nm)
        if not node.attributes[nm] then return end
        return node.attributes[nm] and true or false
      end

      if node.name == 't' then
        local value = node.attributes.value
        if type(value) == 'string' then
          local start0 = { curr_line1 - 1, curr_col1 - 1 }
          local value_lines = vim.split(value, '\n')
          for lnum, value_line in ipairs(value_lines) do
            if lnum > 1 then put_line() end
            put(value_line)
          end
          local stop0 = { curr_line1 - 1, curr_col1 - 1 }

          local group = node.attributes.hl
          if type(group) == 'string' then
            local local_exists = #vim.tbl_keys(vim.api.nvim_get_hl(self.ns, { name = group })) > 0
            local global_exists = #vim.tbl_keys(vim.api.nvim_get_hl(0, { name = group }))
            local exists = local_exists or global_exists

            if not exists or attr_bool 'hl:force' then
              vim.api.nvim_set_hl_ns(self.ns)
              vim.api.nvim_set_hl(self.ns, group, {
                fg = node.attributes['hl:fg'],
                bg = node.attributes['hl:bg'],
                sp = node.attributes['hl:sp'],
                blend = attr_num 'hl:blend',
                bold = attr_bool 'hl:bold',
                standout = attr_bool 'hl:standout',
                underline = attr_bool 'hl:underline',
                undercurl = attr_bool 'hl:undercurl',
                underdouble = attr_bool 'hl:underdouble',
                underdotted = attr_bool 'hl:underdotted',
                underdashed = attr_bool 'hl:underdashed',
                strikethrough = attr_bool 'hl:strikethrough',
                italic = attr_bool 'hl:italic',
                reverse = attr_bool 'hl:reverse',
                nocombine = attr_bool 'hl:nocombine',
                link = node.attributes['hl:link'],
                default = attr_bool 'hl:default',
                ctermfg = attr_num 'hl:ctermfg',
                ctermbg = attr_num 'hl:ctermbg',
                cterm = node.attributes['hl:cterm'],
                force = attr_bool 'hl:force',
              })
            end
          end
          if type(group) == 'string' then table.insert(hls, { group = group, start = start0, stop = stop0 }) end
        end
      end
    end
  end

  self.old = self.curr
  self.curr = { lines = lines, hls = hls }
  self:_reconcile()
end

--- @private
--- @param info string
--- @param start integer
--- @param end_ integer
--- @param strict_indexing boolean
--- @param replacement string[]
function Renderer:_set_lines(info, start, end_, strict_indexing, replacement)
  self:_log { 'set_lines', self.bufnr, start, end_, strict_indexing, replacement }
  vim.api.nvim_buf_set_lines(self.bufnr, start, end_, strict_indexing, replacement)
  self:_log { 'after(' .. info .. ')', vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false) }
end

--- @private
--- @param info string
--- @param start_row integer
--- @param start_col integer
--- @param end_row integer
--- @param end_col integer
--- @param replacement string[]
function Renderer:_set_text(info, start_row, start_col, end_row, end_col, replacement)
  self:_log { 'set_text', self.bufnr, start_row, start_col, end_row, end_col, replacement }
  vim.api.nvim_buf_set_text(self.bufnr, start_row, start_col, end_row, end_col, replacement)
  self:_log { 'after(' .. info .. ')', vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false) }
end

--- @private
function Renderer:_log(...)
  --
  -- vim.print(...)
end

--- @private
function Renderer:_reconcile()
  local line_changes = utils.levenshtein(self.old.lines, self.curr.lines)
  self.old = self.curr

  self:_log { line_changes = line_changes }
  for _, line_change in ipairs(line_changes) do
    local lnum0 = line_change.index - 1

    if line_change.kind == 'add' then
      self:_set_lines('add-line', lnum0, lnum0, true, { line_change.item })
    elseif line_change.kind == 'change' then
      -- Compute inter-line diff, and apply:
      self:_log '--------------------------------------------------------------------------------'
      local col_changes = utils.levenshtein(vim.split(line_change.from, ''), vim.split(line_change.to, ''))

      for _, col_change in ipairs(col_changes) do
        local cnum0 = col_change.index - 1
        self:_log { line_change = col_change, cnum = cnum0, lnum = lnum0 }
        if col_change.kind == 'add' then
          self:_set_text('add-char', lnum0, cnum0, lnum0, cnum0, { col_change.item })
        elseif col_change.kind == 'change' then
          self:_set_text('change-char', lnum0, cnum0, lnum0, cnum0 + 1, { col_change.to })
        elseif col_change.kind == 'delete' then
          self:_set_text('del-char', lnum0, cnum0, lnum0, cnum0 + 1, {})
        else
          -- No change
        end
      end
    elseif line_change.kind == 'delete' then
      self:_set_lines('del-line', lnum0, lnum0 + 1, true, {})
    else
      -- No change
    end
  end

  -- vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, self.curr.lines)
  vim.api.nvim_buf_clear_namespace(self.bufnr, self.ns, 0, -1)
  for _, hl in ipairs(self.curr.hls) do
    vim.highlight.range(self.bufnr, self.ns, hl.group, hl.start, hl.stop, {
      inclusive = false,
      priority = vim.highlight.priorities.user,
      regtype = 'charwise',
    })
  end

  self.changedtick = vim.b[self.bufnr].changedtick
end

--- @private
--- @param markup string e.g., [[Something <t hl="My highlight" value="my text" />]]
function Renderer._parse_markup(markup)
  --- @type ({ kind: 'text'; value: string } | { kind: 'tag'; name: string; attributes: table<string, string|boolean> })[]
  local nodes = {}

  --- @type 'text' | 'tag'
  local mode = 'text'
  local pos = 1
  local watchdog = 0

  local function skip_whitespace()
    local _, new_pos = str.eat_while(markup, pos, str.is_whitespace)
    pos = new_pos
  end
  local function check_infinite_loop()
    watchdog = watchdog + 1
    if watchdog > #markup then
      vim.print('ERROR', {
        num_nodes = #nodes,
        last_node = nodes[#nodes],
        pos = pos,
        len = #markup,
      })
      error 'infinite loop'
    end
  end

  while pos <= #markup do
    check_infinite_loop()

    if mode == 'text' then
      --
      -- Parse contiguous regions of text
      --
      local eaten, new_pos = str.eat_while(markup, pos, function(c) return c ~= '<' end)
      if #eaten > 0 then table.insert(nodes, { kind = 'text', value = eaten:gsub('&lt;', '<') }) end
      pos = new_pos

      if markup:sub(pos, pos) == '<' then mode = 'tag' end
    elseif mode == 'tag' then
      --
      -- Parse self-closing tags
      --
      if markup:sub(pos, pos) == '<' then pos = pos + 1 end
      local tag_name, new_pos = str.eat_while(markup, pos, function(c) return not str.is_whitespace(c) end)
      pos = new_pos

      if tag_name == '/>' then
        -- empty tag
        table.insert(nodes, { kind = 'tag', name = '', attributes = {} })
      else
        local node = { kind = 'tag', name = tag_name, attributes = {} }
        skip_whitespace()

        while markup:sub(pos, pos + 1) ~= '/>' do
          check_infinite_loop()
          if pos > #markup then error 'unexpected end of markup' end

          local attr_name
          attr_name, new_pos = str.eat_while(markup, pos, function(c) return c ~= '=' and not str.is_whitespace(c) end)
          pos = new_pos

          local attr_value = nil
          if markup:sub(pos, pos) == '=' then
            pos = pos + 1
            if markup:sub(pos, pos) == '"' then
              pos = pos + 1
              attr_value, new_pos = str.eat_while(markup, pos, function(c, i, s)
                local prev_c = s:sub(i - 1, i - 1)
                return c ~= '"' or (prev_c == '\\' and c == '"')
              end)
              pos = new_pos + 1 -- skip the closing '"'
            else
              attr_value, new_pos = str.eat_while(markup, pos, function(c) return not str.is_whitespace(c) end)
              pos = new_pos
            end
          end

          node.attributes[attr_name] = (attr_value and attr_value:gsub('\\"', '"')) or true
          skip_whitespace()
        end
        pos = pos + 2 -- skip the '/>'

        table.insert(nodes, node)
      end

      mode = 'text'
    end
  end

  return nodes
end

return Renderer
