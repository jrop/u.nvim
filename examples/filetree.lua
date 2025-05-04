--------------------------------------------------------------------------------
-- File Tree Viewer Module
--
-- Future Enhancements:
-- - Consider implementing additional features like searching for files,
--   filtering displayed nodes, or adding support for more file types.
-- - Improve user experience with customizable UI elements and enhanced
--   navigation options.
-- - Implement a file watcher to automatically update the file tree when files
--   change on the underlying filesystem.
--------------------------------------------------------------------------------

--- @alias FsDir { kind: 'dir'; path: string; expanded: boolean; children: FsNode[] }
--- @alias FsFile { kind: 'file'; path: string }
--- @alias FsNode FsDir | FsFile
--- @alias ShowOpts { root_path?: string, width?: number, focus_path?: string }

local Buffer = require 'u.buffer'
local Renderer = require('u.renderer').Renderer
local TreeBuilder = require('u.renderer').TreeBuilder
local h = require('u.renderer').h
local tracker = require 'u.tracker'

local logger = require('u.logger').Logger.new 'filetree'

local M = {}
local H = {}

--------------------------------------------------------------------------------
-- Helpers:
--------------------------------------------------------------------------------

--- Splits the given path into a list of path components.
--- @param path string
function H.split_path(path)
  local parts = {}
  local curr = path
  while #curr > 0 and curr ~= '.' and curr ~= '/' do
    table.insert(parts, 1, vim.fs.basename(curr))
    curr = vim.fs.dirname(curr)
  end
  return parts
end

--- Normalizes the given path to an absolute path.
--- @param path string
function H.normalize(path) return vim.fs.abspath(vim.fs.normalize(path)) end

--- Computes the relative path from `base` to `path`.
--- @param path string
--- @param base string
function H.relative(path, base)
  path = H.normalize(path)
  base = H.normalize(base)
  if path:sub(1, #base) == base then path = path:sub(#base + 1) end
  if vim.startswith(path, '/') then path = path:sub(2) end
  return path
end

--- @param root_path string
--- @return { tree: FsDir; path_to_node: table<string, FsNode> }
function H.get_tree_inf(root_path)
  logger:info { 'get_tree_inf', root_path }
  --- @type table<string, FsNode>
  local path_to_node = {}

  --- @type FsDir
  local tree = {
    kind = 'dir',
    path = H.normalize(root_path or '.'),
    expanded = true,
    children = {},
  }
  path_to_node[tree.path] = tree

  H.populate_dir_children(tree, path_to_node)
  return { tree = tree, path_to_node = path_to_node }
end

--- @param tree FsDir
--- @param path_to_node table<string, FsNode>
function H.populate_dir_children(tree, path_to_node)
  tree.children = {}

  for child_path, kind in vim.iter(vim.fs.dir(tree.path, { depth = 1 })) do
    child_path = H.normalize(vim.fs.joinpath(tree.path, child_path))
    local prev_node = path_to_node[child_path]

    if kind == 'directory' then
      local new_node = {
        kind = 'dir',
        path = child_path,
        expanded = prev_node and prev_node.expanded or false,
        children = prev_node and prev_node.children or {},
      }
      path_to_node[new_node.path] = new_node
      table.insert(tree.children, new_node)
    else
      local new_node = {
        kind = 'file',
        path = child_path,
      }
      path_to_node[new_node.path] = new_node
      table.insert(tree.children, new_node)
    end
  end

  table.sort(tree.children, function(a, b)
    -- directories first:
    if a.kind ~= b.kind then return a.kind == 'dir' end
    return a.path < b.path
  end)
end

--- @param opts {
---   bufnr: number;
---   prev_winnr: number;
---   root_path: string;
---   focus_path?: string;
--- }
---
--- @return { expand: fun(path: string), collapse: fun(path: string) }
local function _render_in_buffer(opts)
  local winnr = vim.api.nvim_buf_call(
    opts.bufnr,
    function() return vim.api.nvim_get_current_win() end
  )
  local s_tree_inf = tracker.create_signal(H.get_tree_inf(opts.root_path))
  local s_focused_path = tracker.create_signal(H.normalize(opts.focus_path or opts.root_path))

  tracker.create_effect(function()
    local focused_path = s_focused_path:get()

    s_tree_inf:update(function(tree_inf)
      local parts = H.split_path(H.relative(focused_path, tree_inf.tree.path))
      local path_to_node = tree_inf.path_to_node

      --- @param node FsDir
      --- @param child_names string[]
      local function expand_to(node, child_names)
        if #child_names == 0 then return end
        node.expanded = true

        local next_child_name = table.remove(child_names, 1)
        for _, child in ipairs(node.children) do
          if child.kind == 'dir' and vim.fs.basename(child.path) == next_child_name then
            H.populate_dir_children(child, path_to_node)
            expand_to(child, child_names)
          end
        end
      end
      expand_to(tree_inf.tree, parts)
      return tree_inf
    end)
  end)

  --
  -- :help watch-file
  --
  local watcher = vim.uv.new_fs_event()
  if watcher ~= nil then
    --- @diagnostic disable-next-line: unused-local
    watcher:start(opts.root_path, { recursive = true }, function(_err, fname, _status)
      fname = H.normalize(fname)

      local dir_path = vim.fs.dirname(fname)
      local dir = s_tree_inf:get().path_to_node[dir_path]
      if not dir then return end

      s_tree_inf:schedule_update(function(tree_inf)
        H.populate_dir_children(dir, tree_inf.path_to_node)
        return tree_inf
      end)
    end)
  end
  vim.api.nvim_create_autocmd('WinClosed', {
    once = true,
    pattern = tostring(winnr),
    callback = function()
      if watcher == nil then return end

      watcher:stop()
      watcher = nil
    end,
  })

  local controller = {}

  --- @param path string
  function controller.focus_path(path) s_focused_path:set(H.normalize(path)) end

  function controller.refresh() s_tree_inf:set(H.get_tree_inf(opts.root_path)) end

  --- @param path string
  function controller.expand(path)
    path = H.normalize(path)
    local path_to_node = s_tree_inf:get().path_to_node

    local node = path_to_node[path]
    if node == nil then return end

    if node.kind == 'dir' then
      s_tree_inf:update(function(tree_inf2)
        H.populate_dir_children(node, path_to_node)
        tree_inf2.path_to_node[node.path].expanded = true
        return tree_inf2
      end)
      if #node.children == 0 then
        s_focused_path:set(node.path)
      else
        s_focused_path:set(node.children[1].path)
      end
    else
      if node.kind == 'file' then
        -- open file:
        vim.api.nvim_win_call(opts.prev_winnr, function() vim.cmd.edit(node.path) end)
        vim.api.nvim_set_current_win(opts.prev_winnr)
      end
    end
  end

  --- @param path string
  function controller.collapse(path)
    path = H.normalize(path)
    local path_to_node = s_tree_inf:get().path_to_node

    local node = path_to_node[path]
    if node == nil then return end

    if node.kind == 'dir' then
      if node.expanded then
        -- collapse self/node:
        s_focused_path:set(node.path)
        s_tree_inf:update(function(tree_inf2)
          tree_inf2.path_to_node[node.path].expanded = false
          return tree_inf2
        end)
      else
        -- collapse parent:
        local parent_dir = path_to_node[vim.fs.dirname(node.path)]
        if parent_dir ~= nil then
          s_focused_path:set(parent_dir.path)
          s_tree_inf:update(function(tree_inf2)
            tree_inf2.path_to_node[parent_dir.path].expanded = false
            return tree_inf2
          end)
        end
      end
    elseif node.kind == 'file' then
      local parent_dir = path_to_node[vim.fs.dirname(node.path)]
      if parent_dir ~= nil then
        s_focused_path:set(parent_dir.path)
        s_tree_inf:update(function(tree_inf2)
          tree_inf2.path_to_node[parent_dir.path].expanded = false
          return tree_inf2
        end)
      end
    end
  end

  --- @param root_path string
  function controller.new(root_path)
    vim.ui.input({
      prompt = 'New: ',
      completion = 'file',
    }, function(input)
      if input == nil then return end
      local new_path = vim.fs.joinpath(root_path, input)

      if vim.endswith(input, '/') then
        -- Create a directory:
        vim.fn.mkdir(new_path, input, 'p')
      else
        -- Create a file:

        -- First, make sure the parent directory exists:
        vim.fn.mkdir(vim.fs.dirname(new_path), 'p')

        -- Now create an empty file:
        local uv = vim.loop or vim.uv
        local fd = uv.fs_open(new_path, 'w', 438)
        if fd then uv.fs_write(fd, '') end
      end

      controller.refresh()
      controller.focus_path(new_path)
    end)
  end

  --- @param path string
  function controller.rename(path)
    path = H.normalize(path)
    local root_path = vim.fs.dirname(path)
    vim.ui.input({
      prompt = 'Rename: ',
      default = vim.fs.basename(path),
      completion = 'file',
    }, function(input)
      if input == nil then return end

      local new_path = vim.fs.joinpath(root_path, input);
      (vim.loop or vim.uv).fs_rename(path, new_path)
      controller.refresh()
      controller.focus_path(new_path)
    end)
  end

  --
  -- Render:
  --
  local renderer = Renderer.new(opts.bufnr)
  tracker.create_effect(function()
    --- @type { tree: FsDir; path_to_node: table<string, FsNode> }
    local tree_inf = s_tree_inf:get()
    local tree = tree_inf.tree

    --- @type string
    local focused_path = s_focused_path:get()

    --- As we render the tree, keep track of what line each node is on, so that
    --- we have an easy way to make the cursor jump to each node (i.e., line)
    --- at will:
    --- @type table<string, number>
    local node_lines = {}
    local current_line = 0

    --- The UI is rendered as a list of hypserscript elements:
    local tb = TreeBuilder.new()

    --- Since the filesystem is a recursive tree of nodes, we need to
    --- recursively render each node. This function does just that:
    --- @param node FsNode
    --- @param level number
    local function render_node(node, level)
      local name = vim.fs.basename(node.path)
      current_line = current_line + 1
      node_lines[node.path] = current_line

      local nmaps = {
        h = function()
          vim.schedule(function() controller.collapse(node.path) end)
          return ''
        end,
        l = function()
          vim.schedule(function() controller.expand(node.path) end)
          return ''
        end,
        n = function()
          vim.schedule(
            function()
              controller.new(node.kind == 'file' and vim.fs.dirname(node.path) or node.path)
            end
          )
          return ''
        end,
        r = function()
          vim.schedule(function() controller.rename(node.path) end)
          return ''
        end,
        y = function()
          vim.fn.setreg([["]], H.relative(node.path, tree.path))
          return ''
        end,
      }

      if node.kind == 'dir' then
        --
        -- Render a directory node:
        --
        local icon = node.expanded and '' or ''
        tb:put {
          current_line > 1 and '\n',
          h(
            'text',
            { hl = 'Constant', nmap = nmaps },
            { string.rep('  ', level), icon, ' ', name }
          ),
        }
        if node.expanded then
          for _, child in ipairs(node.children) do
            render_node(child, level + 1)
          end
        end
      elseif node.kind == 'file' then
        tb:put {
          current_line > 1 and '\n',
          h('text', { nmap = nmaps }, { string.rep('  ', level), '󰈔 ', name }),
        }
      end
    end
    render_node(tree, 0)

    -- The following modifies buffer contents, so it needs to be scheduled:
    vim.schedule(function()
      renderer:render(tb:tree())

      local cpos = vim.api.nvim_win_get_cursor(winnr)
      pcall(vim.api.nvim_win_set_cursor, winnr, { node_lines[focused_path], cpos[2] })
    end)
  end, 's:tree')

  return controller
end

--------------------------------------------------------------------------------
-- Public API functions:
--------------------------------------------------------------------------------

--- @type {
---   bufnr: number;
---   winnr: number;
---   controller: { expand: fun(path: string), collapse: fun(path: string) };
--- } | nil
local current_inf = nil

--- Show the filetree:
--- @param opts? ShowOpts
function M.show(opts)
  if current_inf ~= nil then return current_inf.controller end
  opts = opts or {}

  local prev_winnr = vim.api.nvim_get_current_win()

  vim.cmd 'vnew'
  local buf = Buffer.from_nr(vim.api.nvim_get_current_buf())
  buf:set_tmp_options()

  local winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-w>H', true, true, true), 'x', false)
  vim.api.nvim_win_set_width(0, opts.width or 30)
  vim.api.nvim_create_autocmd('WinClosed', {
    once = true,
    pattern = tostring(winnr),
    callback = M.hide,
  })

  vim.wo[0][0].number = false
  vim.wo[0][0].relativenumber = false

  local bufnr = vim.api.nvim_get_current_buf()

  local controller = _render_in_buffer(vim.tbl_extend('force', opts, {
    bufnr = bufnr,
    prev_winnr = prev_winnr,
    root_path = opts.root_path or H.normalize '.',
  }))
  current_inf = { bufnr = bufnr, winnr = winnr, controller = controller }
  return controller
end

--- Hide the filetree:
function M.hide()
  if current_inf == nil then return end
  pcall(vim.cmd.bdelete, current_inf.bufnr)
  current_inf = nil
end

--- Toggle the filetree:
--- @param opts? ShowOpts
function M.toggle(opts)
  if current_inf == nil then
    M.show(opts)
  else
    M.hide()
  end
end

return M
