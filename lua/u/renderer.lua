local M = {}
local H = {}

--- @alias Tag { kind: 'tag'; name: string, attributes: table<string, unknown>, children: Tree }
--- @alias Node nil | boolean | string | Tag
--- @alias Tree Node | Node[]

--- @param name string
--- @param attributes? table<string, any>
--- @param children? Node | Node[]
--- @return Tag
function M.h(name, attributes, children)
  return {
    kind = 'tag',
    name = name,
    attributes = attributes or {},
    children = children,
  }
end

-- Renderer {{{
--- @alias RendererExtmark { id?: number; start: [number, number]; stop: [number, number]; opts: any; tag: any }

--- @class Renderer
--- @field bufnr number
--- @field ns number
--- @field changedtick number
--- @field old { lines: string[]; extmarks: RendererExtmark[] }
--- @field curr { lines: string[]; extmarks: RendererExtmark[] }
local Renderer = {}
Renderer.__index = Renderer
M.Renderer = Renderer

--- @private
--- @param x any
--- @return boolean
function Renderer.is_tag(x) return type(x) == 'table' and x.kind == 'tag' end

--- @private
--- @param x any
--- @return boolean
function Renderer.is_tag_arr(x)
  if type(x) ~= 'table' then return false end
  return #x == 0 or not Renderer.is_tag(x)
end
--- @param bufnr number|nil
function Renderer.new(bufnr) -- {{{
  if bufnr == nil then bufnr = vim.api.nvim_get_current_buf() end

  if vim.b[bufnr]._renderer_ns == nil then
    vim.b[bufnr]._renderer_ns = vim.api.nvim_create_namespace('my.renderer:' .. tostring(bufnr))
  end

  local self = setmetatable({
    bufnr = bufnr,
    ns = vim.b[bufnr]._renderer_ns,
    changedtick = 0,
    old = { lines = {}, extmarks = {} },
    curr = { lines = {}, extmarks = {} },
  }, Renderer)
  return self
end -- }}}

--- @param opts {
---   tree: Tree;
---   on_tag?: fun(tag: Tag, start0: [number, number], stop0: [number, number]): any;
--- }
function Renderer.markup_to_lines(opts) -- {{{
  --- @type string[]
  local lines = {}

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

  --- @param node Node
  local function visit(node) -- {{{
    if node == nil or type(node) == 'boolean' then return end

    if type(node) == 'string' then
      local node_lines = vim.split(node, '\n')
      for lnum, s in ipairs(node_lines) do
        if lnum > 1 then put_line() end
        put(s)
      end
    elseif Renderer.is_tag(node) then
      local start0 = { curr_line1 - 1, curr_col1 - 1 }

      -- visit the children:
      if Renderer.is_tag_arr(node.children) then
        for _, child in
          ipairs(node.children --[[@as Node[] ]])
        do
          -- newlines are not controlled by array entries, do NOT output a line here:
          visit(child)
        end
      else
        visit(node.children)
      end

      local stop0 = { curr_line1 - 1, curr_col1 - 1 }
      if opts.on_tag then opts.on_tag(node, start0, stop0) end
    elseif Renderer.is_tag_arr(node) then
      for _, child in ipairs(node) do
        -- newlines are not controlled by array entries, do NOT output a line here:
        visit(child)
      end
    end
  end -- }}}
  visit(opts.tree)

  return lines
end -- }}}

--- @param opts {
---   tree: string;
---   format_tag?: fun(tag: Tag): string;
--- }
function Renderer.markup_to_string(opts) return table.concat(Renderer.markup_to_lines(opts), '\n') end

--- @param tree Tree
function Renderer:render(tree) -- {{{
  local changedtick = vim.b[self.bufnr].changedtick
  if changedtick ~= self.changedtick then
    self.curr = { lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false) }
    self.changedtick = changedtick
  end

  --- @type RendererExtmark[]
  local extmarks = {}

  --- @type string[]
  local lines = Renderer.markup_to_lines {
    tree = tree,

    on_tag = function(tag, start0, stop0) -- {{{
      if tag.name == 'text' then
        local hl = tag.attributes.hl
        if type(hl) == 'string' then
          tag.attributes.extmark = tag.attributes.extmark or {}
          tag.attributes.extmark.hl_group = tag.attributes.extmark.hl_group or hl
        end

        local extmark = tag.attributes.extmark

        -- Set any necessary keymaps:
        for _, mode in ipairs { 'i', 'n', 'v', 'x', 'o' } do
          for lhs, _ in pairs(tag.attributes[mode .. 'map'] or {}) do
            -- Force creating an extmark if there are key handlers. To accurately
            -- sense the bounds of the text, we need an extmark:
            extmark = extmark or {}
            vim.keymap.set(
              'n',
              lhs,
              function() return self:_expr_map_callback('n', lhs) end,
              { buffer = self.bufnr, expr = true, replace_keycodes = true }
            )
          end
        end

        if extmark then
          table.insert(extmarks, {
            start = start0,
            stop = stop0,
            opts = extmark,
            tag = tag,
          })
        end
      end
    end, -- }}}
  }

  self.old = self.curr
  self.curr = { lines = lines, extmarks = extmarks }
  self:_reconcile()
end -- }}}

--- @private
--- @param start integer
--- @param end_ integer
--- @param strict_indexing boolean
--- @param replacement string[]
function Renderer:_set_lines(start, end_, strict_indexing, replacement)
  vim.api.nvim_buf_set_lines(self.bufnr, start, end_, strict_indexing, replacement)
end

--- @private
--- @param start_row integer
--- @param start_col integer
--- @param end_row integer
--- @param end_col integer
--- @param replacement string[]
function Renderer:_set_text(start_row, start_col, end_row, end_col, replacement)
  vim.api.nvim_buf_set_text(self.bufnr, start_row, start_col, end_row, end_col, replacement)
end

--- @private
function Renderer:_reconcile() -- {{{
  local line_changes = H.levenshtein(self.old.lines, self.curr.lines)
  self.old = self.curr

  --
  -- Step 1: morph the text to the desired state:
  --
  for _, line_change in ipairs(line_changes) do
    local lnum0 = line_change.index - 1

    if line_change.kind == 'add' then
      self:_set_lines(lnum0, lnum0, true, { line_change.item })
    elseif line_change.kind == 'change' then
      -- Compute inter-line diff, and apply:
      local col_changes = H.levenshtein(vim.split(line_change.from, ''), vim.split(line_change.to, ''))

      for _, col_change in ipairs(col_changes) do
        local cnum0 = col_change.index - 1
        if col_change.kind == 'add' then
          self:_set_text(lnum0, cnum0, lnum0, cnum0, { col_change.item })
        elseif col_change.kind == 'change' then
          self:_set_text(lnum0, cnum0, lnum0, cnum0 + 1, { col_change.to })
        elseif col_change.kind == 'delete' then
          self:_set_text(lnum0, cnum0, lnum0, cnum0 + 1, {})
        else
          -- No change
        end
      end
    elseif line_change.kind == 'delete' then
      self:_set_lines(lnum0, lnum0 + 1, true, {})
    else
      -- No change
    end
  end
  self.changedtick = vim.b[self.bufnr].changedtick

  --
  -- Step 2: reconcile extmarks:
  --
  -- Clear current extmarks:
  vim.api.nvim_buf_clear_namespace(self.bufnr, self.ns, 0, -1)
  -- Set current extmarks:
  for _, extmark in ipairs(self.curr.extmarks) do
    extmark.id = vim.api.nvim_buf_set_extmark(
      self.bufnr,
      self.ns,
      extmark.start[1],
      extmark.start[2],
      vim.tbl_extend('force', {
        id = extmark.id,
        end_row = extmark.stop[1],
        end_col = extmark.stop[2],
      }, extmark.opts)
    )
  end
end -- }}}

--- @private
--- @param mode string
--- @param lhs string
function Renderer:_expr_map_callback(mode, lhs) -- {{{
  -- find the tag with the smallest intersection that contains the cursor:
  local pos0 = vim.api.nvim_win_get_cursor(0)
  pos0[1] = pos0[1] - 1 -- make it actually 0-based
  local pos_infos = self:get_pos_infos(pos0)

  if #pos_infos == 0 then return lhs end

  -- Find the first tag that is listening for this event:
  local cancel = false
  for _, pos_info in ipairs(pos_infos) do
    local tag = pos_info.tag

    -- is the tag listening?
    local f = vim.tbl_get(tag.attributes, mode .. 'map', lhs)
    if type(f) == 'function' then
      local result = f()
      if result == '' then
        -- bubble-up to the next tag, but set cancel to true, in case there are
        -- no more tags to bubble up to:
        cancel = true
      else
        return result
      end
    end
  end

  -- Resort to default behavior:
  return cancel and '' or lhs
end -- }}}

--- Returns pairs of extmarks and tags associate with said extmarks. The
--- returned tags/extmarks are sorted smallest (innermost) to largest
--- (outermost).
---
--- @private (private for now)
--- @param pos0 [number; number]
--- @return { extmark: RendererExtmark; tag: Tag; }[]
function Renderer:get_pos_infos(pos0) -- {{{
  local cursor_line0, cursor_col0 = pos0[1], pos0[2]

  -- The cursor (block) occupies **two** extmark spaces: one for it's left
  -- edge, and one for it's right. We need to do our own intersection test,
  -- because the NeoVim API is over-inclusive in what it returns:
  --- @type RendererExtmark[]
  local intersecting_extmarks = vim
    .iter(vim.api.nvim_buf_get_extmarks(self.bufnr, self.ns, pos0, pos0, { details = true, overlap = true }))
    --- @return RendererExtmark
    :map(function(ext)
      --- @type number, number, number, { end_row?: number; end_col?: number }|nil
      local id, line0, col0, details = unpack(ext)
      local start = { line0, col0 }
      local stop = { line0, col0 }
      if details and details.end_row ~= nil and details.end_col ~= nil then
        stop = { details.end_row, details.end_col }
      end
      return { id = id, start = start, stop = stop, opts = details }
    end)
    --- @param ext RendererExtmark
    :filter(function(ext)
      if ext.stop[1] ~= nil and ext.stop[2] ~= nil then
        return cursor_line0 >= ext.start[1]
          and cursor_col0 >= ext.start[2]
          and cursor_line0 <= ext.stop[1]
          and cursor_col0 < ext.stop[2]
      else
        return true
      end
    end)
    :totable()

  -- Sort the tags into smallest (inner) to largest (outer):
  table.sort(
    intersecting_extmarks,
    --- @param x1 RendererExtmark
    --- @param x2 RendererExtmark
    function(x1, x2)
      if
        x1.start[1] == x2.start[1]
        and x1.start[2] == x2.start[2]
        and x1.stop[1] == x2.stop[1]
        and x1.stop[2] == x2.stop[2]
      then
        return x1.id < x2.id
      end

      return x1.start[1] >= x2.start[1]
        and x1.start[2] >= x2.start[2]
        and x1.stop[1] <= x2.stop[1]
        and x1.stop[2] <= x2.stop[2]
    end
  )

  -- When we set the extmarks in the step above, we captured the IDs of the
  -- created extmarks in self.curr.extmarks, which also has which tag each
  -- extmark is associated with. Cross-reference with that list to get a list
  -- of tags that we need to fire events for:
  --- @type { extmark: RendererExtmark; tag: Tag }[]
  local matching_tags = vim
    .iter(intersecting_extmarks)
    --- @param ext RendererExtmark
    :map(function(ext)
      for _, extmark_cache in ipairs(self.curr.extmarks) do
        if extmark_cache.id == ext.id then return { extmark = ext, tag = extmark_cache.tag } end
      end
    end)
    :totable()

  return matching_tags
end -- }}}
-- }}}

-- TreeBuilder {{{
--- @class TreeBuilder
--- @field private nodes Node[]
local TreeBuilder = {}
TreeBuilder.__index = TreeBuilder
M.TreeBuilder = TreeBuilder

function TreeBuilder.new()
  local self = setmetatable({ nodes = {} }, TreeBuilder)
  return self
end

--- @param nodes Tree
--- @return TreeBuilder
function TreeBuilder:put(nodes)
  table.insert(self.nodes, nodes)
  return self
end

--- @param name string
--- @param attributes? table<string, any>
--- @param children? Node | Node[]
--- @return TreeBuilder
function TreeBuilder:put_h(name, attributes, children)
  local tag = M.h(name, attributes, children)
  table.insert(self.nodes, tag)
  return self
end

--- @param fn fun(TreeBuilder): any
--- @return TreeBuilder
function TreeBuilder:nest(fn)
  local nested_writer = TreeBuilder.new()
  fn(nested_writer)
  table.insert(self.nodes, nested_writer.nodes)
  return self
end

--- @return Tree
function TreeBuilder:tree() return self.nodes end
-- }}}

-- Levenshtein utility {{{
--- @alias LevenshteinChange<T> ({ kind: 'add'; item: T; index: number; } | { kind: 'delete'; item: T; index: number; } | { kind: 'change'; from: T; to: T; index: number; })
--- @private
--- @generic T
--- @param x `T`[]
--- @param y T[]
--- @param cost? { of_delete?: fun(x: T): number; of_add?: fun(x: T): number; of_change?: fun(x: T, y: T): number; }
--- @return LevenshteinChange<T>[]
function H.levenshtein(x, y, cost)
  -- At the moment, this whole `cost` plumbing is not used. Deletes have the
  -- same cost as Adds or Changes. I can imagine a future, however, where
  -- fudging with the costs of operations produces a more optimized change-set
  -- that is tailored to working better with how NeoVim manipulates text. I've
  -- done no further investigation in this area, however, so it's impossible to
  -- tell if such tuning would produce real benefit. For now, I'm leaving this
  -- in here even though it's not actively used. Hopefully having this
  -- callback-based plumbing does not cause too much of a performance hit to
  -- the renderer.
  cost = cost or {}
  local cost_of_delete_f = cost.of_delete or function() return 1 end
  local cost_of_add_f = cost.of_add or function() return 1 end
  local cost_of_change_f = cost.of_change or function() return 1 end

  local m, n = #x, #y
  -- Initialize the distance matrix
  local dp = {}
  for i = 0, m do
    dp[i] = {}
    for j = 0, n do
      dp[i][j] = 0
    end
  end

  -- Fill the base cases
  for i = 0, m do
    dp[i][0] = i
  end
  for j = 0, n do
    dp[0][j] = j
  end

  -- Compute the Levenshtein distance dynamically
  for i = 1, m do
    for j = 1, n do
      if x[i] == y[j] then
        dp[i][j] = dp[i - 1][j - 1] -- no cost if items are the same
      else
        local costDelete = dp[i - 1][j] + cost_of_delete_f(x[i])
        local costAdd = dp[i][j - 1] + cost_of_add_f(y[j])
        local costChange = dp[i - 1][j - 1] + cost_of_change_f(x[i], y[j])
        dp[i][j] = math.min(costDelete, costAdd, costChange)
      end
    end
  end

  -- Backtrack to find the changes
  local i = m
  local j = n
  --- @type LevenshteinChange[]
  local changes = {}

  while i > 0 or j > 0 do
    local default_cost = dp[i][j]
    local cost_of_change = (i > 0 and j > 0) and dp[i - 1][j - 1] or default_cost
    local cost_of_add = j > 0 and dp[i][j - 1] or default_cost
    local cost_of_delete = i > 0 and dp[i - 1][j] or default_cost

    --- @param u number
    --- @param v number
    --- @param w number
    local function is_first_min(u, v, w) return u <= v and u <= w end

    if is_first_min(cost_of_change, cost_of_add, cost_of_delete) then
      -- potential change
      if x[i] ~= y[j] then
        --- @type LevenshteinChange
        local change = { kind = 'change', from = x[i], index = i, to = y[j] }
        table.insert(changes, change)
      end
      i = i - 1
      j = j - 1
    elseif is_first_min(cost_of_add, cost_of_change, cost_of_delete) then
      -- addition
      --- @type LevenshteinChange
      local change = { kind = 'add', item = y[j], index = i + 1 }
      table.insert(changes, change)
      j = j - 1
    elseif is_first_min(cost_of_delete, cost_of_change, cost_of_add) then
      -- deletion
      --- @type LevenshteinChange
      local change = { kind = 'delete', item = x[i], index = i }
      table.insert(changes, change)
      i = i - 1
    else
      error 'unreachable'
    end
  end

  return changes
end
-- }}}

return M
