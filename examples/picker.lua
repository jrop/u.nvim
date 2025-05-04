local utils = require 'u.utils'
local Buffer = require 'u.buffer'
local Renderer = require('u.renderer').Renderer
local h = require('u.renderer').h
local TreeBuilder = require('u.renderer').TreeBuilder
local tracker = require 'u.tracker'

local M = {}

local S_EDITOR_DIMENSIONS =
  tracker.create_signal(utils.get_editor_dimensions(), 's:editor_dimensions')
vim.api.nvim_create_autocmd('VimResized', {
  callback = function()
    local new_dim = utils.get_editor_dimensions()
    S_EDITOR_DIMENSIONS:set(new_dim)
  end,
})

--- @param low number
--- @param x number
--- @param high number
local function clamp(low, x, high)
  x = math.max(low, x)
  x = math.min(x, high)
  return x
end

--- @generic T
--- @param arr `T`[]
--- @return T[]
local function shallow_copy_arr(arr) return vim.iter(arr):totable() end

--------------------------------------------------------------------------------
-- BEGIN create_picker
--
-- This is the star of the show (in this file, anyway).
-- In summary, the outline of this function is:
-- 1. Setup signals/memos for computing the picker size, and window positions
-- 2. Create the two windows:
--   a. The picker input. This is where the filter is typed
--   b. The picker list. This is where the items are displayed
-- 3. Setup event handlers that respond to user input
-- 4. Render the list. After all the prework above, this is probably the
--    shortest portion of this function.
--------------------------------------------------------------------------------

--- @alias SelectController {
---   get_items: fun(): T[];
---   set_items: fun(items: T[]);
---   set_filter_text: fun(filter_text: string);
---   get_selected_indices: fun(): number[];
---   get_selected_items: fun(): T[];
---   set_selected_indices: fun(indicies: number[], ephemeral?: boolean);
---   close: fun();
--- }
--- @alias SelectOpts<T> {
---   items: `T`[];
---   multi?: boolean;
---   format_item?: fun(item: T): Tree;
---   on_finish?: fun(items: T[], indicies: number[]);
---   on_selection_changed?: fun(items: T[], indicies: number[]);
---   mappings?: table<string, fun(select: SelectController)>;
--- }

--- @generic T
--- @param opts SelectOpts<T>
function M.create_picker(opts) -- {{{
  local is_in_insert_mode = vim.api.nvim_get_mode().mode:sub(1, 1) == 'i'
  local stopinsert = not is_in_insert_mode

  if opts.multi == nil then opts.multi = false end

  local H = {}

  --- Runs a function `fn`, and if it fails, cleans up the UI by calling
  --- `H.finish`
  ---
  --- @generic T
  --- @param fn fun(): `T`
  --- @return T
  local function safe_run(fn, ...)
    local ok, result_or_error = pcall(fn, ...)
    if not ok then
      pcall(H.finish, true, result_or_error)
      error(result_or_error .. '\n' .. debug.traceback())
    end
    return result_or_error
  end

  --- Creates a function that safely calls the given function, cleaning up the
  --- UI if it ever fails
  ---
  --- @generic T
  --- @param fn `T`
  --- @return T
  local function safe_wrap(fn)
    return function(...) return safe_run(fn, ...) end
  end

  --
  -- Compute the positions of the input bar and the list:
  --

  -- Reactively compute the space available for the picker based on the size of
  -- the editor
  local s_editor_dimensions = S_EDITOR_DIMENSIONS:clone()
  local s_picker_space_available = tracker.create_memo(safe_wrap(function()
    local editor_dim = s_editor_dimensions:get()
    local width = math.floor(editor_dim.width * 0.75)
    local height = math.floor(editor_dim.height * 0.75)
    local row = math.floor((editor_dim.height - height) / 2)
    local col = math.floor((editor_dim.width - width) / 2)
    return { width = width, height = height, row = row, col = col }
  end))

  -- Reactively compute the size of the prompt (input) bar
  local s_w_input_coords = tracker.create_memo(safe_wrap(function()
    local picker_coords = s_picker_space_available:get()
    return {
      width = picker_coords.width,
      height = 1,
      row = picker_coords.row,
      col = picker_coords.col,
    }
  end))

  -- Reactively compute the size of the list view
  local s_w_list_coords = tracker.create_memo(safe_wrap(function()
    local picker_coords = s_picker_space_available:get()
    return {
      width = picker_coords.width,
      height = picker_coords.height - 3,
      row = picker_coords.row + 3,
      col = picker_coords.col,
    }
  end))

  --
  -- Create resources (i.e., windows):
  --

  local w_input_cfg = {
    width = s_w_input_coords:get().width,
    height = s_w_input_coords:get().height,
    row = s_w_input_coords:get().row,
    col = s_w_input_coords:get().col,
    relative = 'editor',
    focusable = true,
    border = vim.o.winborder or 'rounded',
  }
  local w_input_buf = Buffer.create(false, true)
  local w_input = vim.api.nvim_open_win(w_input_buf.bufnr, false, w_input_cfg)
  vim.wo[w_input][0].cursorline = false
  vim.wo[w_input][0].list = false
  vim.wo[w_input][0].number = false
  vim.wo[w_input][0].relativenumber = false

  -- The following option is a signal to other plugins like 'cmp' to not mess
  -- with this buffer:
  vim.bo[w_input_buf.bufnr].buftype = 'prompt'
  vim.fn.prompt_setprompt(w_input_buf.bufnr, '')

  vim.api.nvim_set_current_win(w_input)
  tracker.create_effect(safe_wrap(function()
    -- update window position/size every time the editor is resized:
    w_input_cfg = vim.tbl_deep_extend('force', w_input_cfg, s_w_input_coords:get())
    vim.api.nvim_win_set_config(w_input, w_input_cfg)
  end))

  local w_list_cfg = {
    width = s_w_list_coords:get().width,
    height = s_w_list_coords:get().height,
    row = s_w_list_coords:get().row,
    col = s_w_list_coords:get().col,
    relative = 'editor',
    focusable = true,
    border = 'rounded',
  }
  local w_list_buf = Buffer.create(false, true)
  local w_list = vim.api.nvim_open_win(w_list_buf.bufnr, false, w_list_cfg)
  vim.wo[w_list][0].number = false
  vim.wo[w_list][0].relativenumber = false
  vim.wo[w_list][0].scrolloff = 0
  tracker.create_effect(safe_wrap(function()
    -- update window position/size every time the editor is resized:
    w_list_cfg = vim.tbl_deep_extend('force', w_list_cfg, s_w_list_coords:get())
    vim.api.nvim_win_set_config(w_list, w_list_cfg)
  end))

  -- Now that we have created the window with the prompt in it, start insert
  -- mode so that the user can type immediately:
  vim.cmd.startinsert()

  --
  -- State:
  --

  local s_items_raw = tracker.create_signal(opts.items, 's:items')
  local s_items = s_items_raw:debounce(100)
  local s_selected_indices = tracker.create_signal({}, 's:selected_indices')
  local s_top_offset = tracker.create_signal(0, 's:top_offset')
  local s_cursor_index = tracker.create_signal(1, 's:cursor_index')

  local s_filter_text_undebounced = tracker.create_signal('', 's:filter_text')
  w_input_buf:autocmd('TextChangedI', {
    callback = safe_wrap(
      function() s_filter_text_undebounced:set(vim.api.nvim_get_current_line()) end
    ),
  })
  local s_filter_text = s_filter_text_undebounced:debounce(50)

  --
  -- Derived State:
  --

  local s_formatted_items = tracker.create_memo(function()
    local function _format_item(item)
      return opts.format_item and opts.format_item(item) or tostring(item)
    end

    local items = s_items:get()
    return vim
      .iter(items)
      :map(function(item) return { item = item, formatted = _format_item(item) } end)
      :totable()
  end)

  -- When the filter text changes, update the filtered items:
  local s_filtered_items = tracker.create_memo(
    safe_wrap(function()
      local formatted_items = s_formatted_items:get()
      local filter_text = vim.trim(s_filter_text:get()):lower()

      --- @type string
      local filter_pattern
      --- @type boolean
      local use_plain_pattern
      if #formatted_items > 250 and #filter_text <= 3 then
        filter_pattern = filter_text
        use_plain_pattern = true
      elseif #formatted_items > 1000 then
        filter_pattern = filter_text
        use_plain_pattern = true
      else
        filter_pattern = '('
          .. vim.iter(vim.split(filter_text, '')):map(function(c) return c .. '.*' end):join ''
          .. ')'
        use_plain_pattern = false
      end
      filter_pattern = filter_pattern:lower()

      --- @type table<integer, string>
      local formatted_strings = {}
      --- @type table<integer, string>
      local matches = {}

      local new_filtered_items = vim
        .iter(formatted_items)
        :enumerate()
        :map(
          function(i, inf) return { orig_idx = i, item = inf.item, formatted = inf.formatted } end
        )
        :filter(function(inf)
          if filter_text == '' then return true end
          local formatted_as_string = Renderer.markup_to_string({ tree = inf.formatted }):lower()

          formatted_strings[inf.orig_idx] = formatted_as_string
          if use_plain_pattern then
            local x, y = formatted_as_string:find(filter_pattern, 1, true)
            if x ~= nil and y ~= nil then matches[inf.orig_idx] = formatted_as_string:sub(x, y) end
          else
            matches[inf.orig_idx] = string.match(formatted_as_string, filter_pattern)
          end

          return matches[inf.orig_idx] ~= nil
        end)
        :totable()

      -- Don't sort if there are over 500 items:
      if #new_filtered_items <= 500 then
        table.sort(new_filtered_items, function(a_inf, b_inf)
          local a = formatted_strings[a_inf.orig_idx]
          local b = formatted_strings[b_inf.orig_idx]
          if a == b then return false end

          local a_match = matches[a_inf.orig_idx]
          local b_match = matches[b_inf.orig_idx]
          return #a_match < #b_match
        end)
      end

      s_top_offset:set(0)
      s_cursor_index:set(1)
      return new_filtered_items
    end),
    'e:(filter_text=>filtered_items)'
  )

  -- Visible items, are _just_ the items that fit into the current viewport.
  -- This is an optimization so that we are not rendering thousands of lines of
  -- items on each state-change.
  local s_visible_items = tracker.create_memo(
    safe_wrap(function()
      return vim
        .iter(s_filtered_items:get())
        :enumerate()
        :skip(s_top_offset:get())
        :take(s_w_list_coords:get().height)
        :map(
          function(i, inf)
            return {
              filtered_idx = i,
              orig_idx = inf.orig_idx,
              item = inf.item,
              formatted = inf.formatted,
            }
          end
        )
        :totable()
    end),
    'm:visible_items'
  )

  -- Track selection information:
  local s_selection_info = tracker.create_memo(
    safe_wrap(function()
      local items = s_items:get()
      local selected_indices = s_selected_indices:get()
      --- @type { orig_idx: number; item: T }[]
      local filtered_items = s_filtered_items:get()
      local cursor_index = s_cursor_index:get()
      local indices = shallow_copy_arr(selected_indices)
      if #indices == 0 and #filtered_items > 0 then
        indices = { filtered_items[cursor_index].orig_idx }
      end
      return {
        items = vim.iter(indices):map(function(i) return items[i] end):totable(),
        indices = indices,
      }
    end),
    'm:selection_info'
  )

  --- When it is time to close the picker, this is the main cleanup routine
  --- that runs in all cases:
  ---
  --- @param esc? boolean Whether the user pressed <Esc> or not
  --- @param err? any Any error that occurred
  function H.finish(esc, err)
    -- s_editor_dimensions is the only signal that is cloned from a global,
    -- one. It is therefore the only one that needs to be manually disposed.
    -- The other ones should get cleaned up by the GC
    s_editor_dimensions:dispose()
    -- If we happen to have any async state-changes coming down the pipeline,
    -- we can say right now that we are done rendering new UI (to avoid
    -- "invalid window ID" errors):
    H.unsubscribe_render_effect()
    -- buftype=prompt buffers are not "temporary", so delete the buffer manually:
    vim.api.nvim_buf_delete(w_input_buf.bufnr, { force = true })
    -- The following is not needed, since the buffer is deleted above:
    -- vim.api.nvim_win_close(w_input, false)
    vim.api.nvim_win_close(w_list, false)
    if stopinsert then vim.cmd.stopinsert() end
    local inf = s_selection_info:get()
    if not err and opts.on_finish then
      -- If on_finish opens another picker, the closing of this one can happen
      -- in _too_ quick succession, so put a small delay in there.
      --
      -- TODO: figure out _why_ this is actually happening, and then a better
      -- way to handle this.
      vim.defer_fn(function()
        if esc then
          opts.on_finish({}, {})
        else
          opts.on_finish(inf.items, inf.indices)
        end
      end, 100)
    end
  end

  -- On selection info changed:
  tracker.create_effect(
    safe_wrap(function()
      local inf = s_selection_info:get()
      if opts.on_selection_changed then opts.on_selection_changed(inf.items, inf.indices) end
    end),
    'e:selection_changed'
  )

  --
  -- Public API (i.e., `controller`):
  -- We will fill in the methods further down, but we need this variable in scope so that it can be
  -- closed over by some of the event handlers:
  --
  local controller = {}

  --
  -- Events
  --
  vim.keymap.set('i', '<Esc>', function() H.finish(true) end, { buffer = w_input_buf.bufnr })

  vim.keymap.set('i', '<CR>', function() H.finish() end, { buffer = w_input_buf.bufnr })

  local function action_next_line()
    local max_line = #s_filtered_items:get()
    local next_cursor_index = clamp(1, s_cursor_index:get() + 1, max_line)
    if next_cursor_index - s_top_offset:get() > s_w_list_coords:get().height then
      s_top_offset:set(s_top_offset:get() + 1)
    end
    s_cursor_index:set(next_cursor_index)
  end
  vim.keymap.set(
    'i',
    '<C-n>',
    safe_wrap(action_next_line),
    { buffer = w_input_buf.bufnr, desc = 'Picker: next' }
  )
  vim.keymap.set(
    'i',
    '<Down>',
    safe_wrap(action_next_line),
    { buffer = w_input_buf.bufnr, desc = 'Picker: next' }
  )

  local function action_prev_line()
    local max_line = #s_filtered_items:get()
    local next_cursor_index = clamp(1, s_cursor_index:get() - 1, max_line)
    if next_cursor_index - s_top_offset:get() < 1 then s_top_offset:set(s_top_offset:get() - 1) end
    s_cursor_index:set(next_cursor_index)
  end
  vim.keymap.set(
    'i',
    '<C-p>',
    safe_wrap(action_prev_line),
    { buffer = w_input_buf.bufnr, desc = 'Picker: previous' }
  )
  vim.keymap.set(
    'i',
    '<Up>',
    safe_wrap(action_prev_line),
    { buffer = w_input_buf.bufnr, desc = 'Picker: previous' }
  )

  vim.keymap.set(
    'i',
    '<Tab>',
    safe_wrap(function()
      if not opts.multi then return end

      local index = s_filtered_items:get()[s_cursor_index:get()].orig_idx
      if vim.tbl_contains(s_selected_indices:get(), index) then
        s_selected_indices:set(
          vim.iter(s_selected_indices:get()):filter(function(i) return i ~= index end):totable()
        )
      else
        local new_selected_indices = shallow_copy_arr(s_selected_indices:get())
        table.insert(new_selected_indices, index)
        s_selected_indices:set(new_selected_indices)
      end
      action_next_line()
    end),
    { buffer = w_input_buf.bufnr }
  )

  for key, fn in pairs(opts.mappings or {}) do
    vim.keymap.set(
      'i',
      key,
      safe_wrap(function() return fn(controller) end),
      { buffer = w_input_buf.bufnr }
    )
  end

  -- Render:
  H.unsubscribe_render_effect = tracker.create_effect(
    safe_wrap(function()
      local selected_indices = s_selected_indices:get()
      local top_offset = s_top_offset:get()
      local cursor_index = s_cursor_index:get()
      --- @type { filtered_idx: number; orig_idx: number; item: T; formatted: string }[]
      local visible_items = s_visible_items:get()

      -- The above has to run in the execution context for the signaling to work, but
      -- the following cannot run in a NeoVim loop-callback:
      vim.schedule(function()
        w_list_buf:render(TreeBuilder.new()
          :nest(function(tb)
            for loop_idx, inf in ipairs(visible_items) do
              local is_cur_line = inf.filtered_idx == cursor_index
              local is_selected = vim.tbl_contains(selected_indices, inf.orig_idx)

              tb:put(loop_idx > 1 and '\n')
              tb:put(is_cur_line and h('text', { hl = 'Structure' }, '❯') or ' ')
              tb:put(is_selected and h('text', { hl = 'Comment' }, '* ') or '  ')
              tb:put(inf.formatted)
            end
          end)
          :tree())

        -- set the window viewport to have the first line in view:
        pcall(vim.api.nvim_win_call, w_list, function() vim.fn.winrestview { topline = 1 } end)
        pcall(vim.api.nvim_win_set_cursor, w_list, { cursor_index - top_offset, 0 })
      end)
    end),
    'e:render'
  )

  --
  -- Populate the public API:
  --
  function controller.get_items()
    return safe_run(function() return s_items_raw:get() end)
  end

  --- @param items T[]
  function controller.set_items(items)
    return safe_run(function() s_items_raw:set(items) end)
  end

  function controller.set_filter_text(filter_text)
    return safe_run(function()
      vim.api.nvim_win_call(w_input, function() vim.api.nvim_set_current_line(filter_text) end)
    end)
  end

  function controller.get_selected_indices()
    return safe_run(function() return s_selection_info:get().indices end)
  end

  function controller.get_selected_items()
    return safe_run(function() return s_selection_info:get().items end)
  end

  --- @param indicies number[]
  --- @param ephemeral? boolean
  function controller.set_selected_indices(indicies, ephemeral)
    return safe_run(function()
      if ephemeral == nil then ephemeral = false end

      if ephemeral and #indicies == 1 then
        local matching_filtered_item_idx, _ = vim.iter(s_filtered_items:get()):enumerate():find(
          function(_idx, inf) return inf.orig_idx == indicies[1] end
        )
        if matching_filtered_item_idx ~= nil then s_cursor_index:set(indicies[1]) end
      else
        if not opts.multi then
          local err = 'Cannot set multiple selected indices on a single-select picker'
          H.finish(true, err)
          error(err)
        end
        s_selected_indices:set(indicies)
      end
    end)
  end

  function controller.close()
    return safe_run(function() H.finish(true) end)
  end

  return controller --[[@as SelectController]]
end -- }}}

--------------------------------------------------------------------------------
-- END create_picker
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- vim.ui.select override
--------------------------------------------------------------------------------

local ORIGINAL_UI_SELECT
function M.register_ui_select()
  ORIGINAL_UI_SELECT = vim.ui.select
  --- @generic T
  --- @param items `T`[]
  --- @param opts { prompt?: string, kind?: any, format_item?: fun(item: T):string }
  --- @param cb fun(item: T|nil):any
  --- @diagnostic disable-next-line: duplicate-set-field
  function vim.ui.select(items, opts, cb)
    M.create_picker {
      items = items,
      format_item = function(item)
        local s = opts.format_item and opts.format_item(item) or tostring(item)
        s = s:gsub('<', '&lt;')
        return s
      end,
      on_finish = function(sel_items)
        if #sel_items == 0 then cb(nil) end
        cb(sel_items[#sel_items])
      end,
    }
  end
end
function M.unregister_ui_select()
  if not ORIGINAL_UI_SELECT then return end

  vim.ui.select = ORIGINAL_UI_SELECT
  ORIGINAL_UI_SELECT = nil
end

--------------------------------------------------------------------------------
-- Built-in pickers
-- 1. files
-- 2. buffers
-- 3. code-symbols
--------------------------------------------------------------------------------

--- @param opts? { limit?: number }
function M.files(opts) -- {{{
  opts = opts or {}
  opts.limit = opts.limit or 10000

  local cmd = {}
  if vim.fn.executable 'rg' then
    cmd = {
      'rg',
      '--color=never',
      '--files',
      '--hidden',
      '--follow',
      '-g',
      '!.git',
      '-g',
      '!node_modules',
      '-g',
      '!target',
    }
  elseif vim.fn.executable 'fd' then
    cmd = {
      'fd',
      '--color=never',
      '--type',
      'f',
      '--hidden',
      '--follow',
      '--exclude',
      '.git',
      '--exclude',
      'node_modules',
      '--exclude',
      'target',
    }
  elseif vim.fn.executable 'find' then
    cmd = {
      'find',
      '-type',
      'f',
      '-not',
      '-path',
      "'*/.git/*'",
      '-not',
      '-path',
      "'*/node_modules/*'",
      '-not',
      '-path',
      "'*/target/*'",
      '-printf',
      "'%P\n'",
    }
  end

  if #cmd == 0 then
    vim.notify('rg/fd/find executable not found: cannot list files', vim.log.levels.ERROR)
    return
  end

  -- Keep track of the job that will list files independent from the picker. We
  -- will stream lines from this process to the picker as they come in:
  local job_inf = { id = 0, proc_lines = {}, notified_over_limit = false }

  -- Initially, create the picker with no items:
  local picker = M.create_picker {
    multi = true,
    items = {},

    --- @params items string[]
    on_finish = function(items)
      pcall(vim.fn.jobstop, job_inf.id)

      if #items == 0 then return end
      if #items == 1 then
        vim.cmd.edit(items[1])
      else
        -- populate quickfix:
        vim.fn.setqflist(vim
          .iter(items)
          :map(
            function(item)
              return {
                filename = item,
                lnum = 1,
                col = 1,
              }
            end
          )
          :totable())
        vim.cmd.copen()
      end
    end,

    mappings = {
      ['<C-t>'] = function(sel)
        sel.close()
        --- @type string[]
        local items = sel.get_selected_items()

        -- open in new tab:
        for _, item in ipairs(items) do
          vim.cmd.tabnew(item)
        end
      end,

      ['<C-v>'] = function(sel)
        sel.close()
        --- @type string[]
        local items = sel.get_selected_items()

        -- open in vertical split:
        for _, item in ipairs(items) do
          vim.cmd.vsplit(item)
        end
      end,

      ['<C-s>'] = function(sel)
        sel.close()
        --- @type string[]
        local items = sel.get_selected_items()

        -- open in horizontal split:
        for _, item in ipairs(items) do
          vim.cmd.split(item)
        end
      end,
    },
  }

  -- Kick off the process that lists the files. As lines come in, send them to
  -- the picker:
  job_inf.id = vim.fn.jobstart(cmd, {
    --- @param data string[]
    on_stdout = vim.schedule_wrap(function(_chanid, data, _name)
      local lines = job_inf.proc_lines
      local function set_lines_as_items_state()
        picker.set_items(vim
          .iter(lines)
          :enumerate()
          :filter(function(idx, item)
            -- Filter out an incomplete last line:
            local is_last_line = idx == #lines
            if is_last_line and item == '' then return false end
            return true
          end)
          :map(function(_, item) return item end)
          :totable())
      end

      -- It's just not a good idea to process large lists with Lua. The default
      -- limit is 10,000 items, and even crunching through this is iffy on a
      -- fast laptop. Show a warning and truncate the list in this case.
      if #lines >= opts.limit then
        if not job_inf.notified_over_limit then
          vim.notify(
            'Picker list is too large (truncating list to ' .. opts.limit .. ' items)',
            vim.log.levels.WARN
          )
          pcall(vim.fn.jobstop, job_inf.id)
          job_inf.notified_over_limit = true
        end
        return
      end

      -- :help channel-lines

      local eof = #data == 1 and data[1] == ''
      if eof then set_lines_as_items_state() end

      -- Complete the previous line:
      if #lines > 0 then lines[#lines] = lines[#lines] .. table.remove(data, 1) end

      for _, l in ipairs(data) do
        table.insert(lines, l)
      end

      set_lines_as_items_state()
    end),
  })
end -- }}}

function M.buffers() -- {{{
  local cwd = vim.fn.getcwd()
  -- ensure that `cwd` ends with a trailing slash:
  if cwd[#cwd] ~= '/' then cwd = cwd .. '/' end

  --- @type { name: string; changed: number; bufnr: number }[]
  local bufs = vim.fn.getbufinfo { buflisted = 1 }

  M.create_picker {
    multi = true,
    items = bufs,

    --- @param item { name: string; changed: number; bufnr: number }
    format_item = function(item)
      local item_name = item.name
      if item_name == '' then item_name = '[No Name]' end
      -- trim leading `cwd` from the buffer name:
      if item_name:sub(1, #cwd) == cwd then item_name = item_name:sub(#cwd + 1) end

      return TreeBuilder.new():put(item.changed == 1 and '[+] ' or '    '):put(item_name):tree()
    end,

    --- @params items { bufnr: number }[]
    on_finish = function(items)
      if #items == 0 then return end
      if #items == 1 then
        vim.cmd.buffer(items[1].bufnr)
      else
        -- populate quickfix:
        vim.fn.setqflist(vim
          .iter(items)
          :map(
            function(item)
              return {
                bufnr = item.bufnr,
                filename = item.name,
                lnum = 1,
                col = 1,
              }
            end
          )
          :totable())
        vim.cmd.copen()
      end
    end,

    mappings = {
      ['<C-t>'] = function(sel)
        sel.close()
        --- @type { bufnr: number }[]
        local items = sel.get_selected_items()

        -- open in new tab:
        for _, item in ipairs(items) do
          vim.cmd.tabnew()
          vim.cmd.buffer(item.bufnr)
        end
      end,

      ['<C-v>'] = function(sel)
        sel.close()
        --- @type { bufnr: number }[]
        local items = sel.get_selected_items()

        -- open in new vertial split:
        for _, item in ipairs(items) do
          vim.cmd.vsplit()
          vim.cmd.buffer(item.bufnr)
        end
      end,

      ['<C-s>'] = function(sel)
        sel.close()
        --- @type { bufnr: number }[]
        local items = sel.get_selected_items()

        -- open in horizontal split:
        for _, item in ipairs(items) do
          vim.cmd.split()
          vim.cmd.buffer(item.bufnr)
        end
      end,

      ['<C-x>'] = function(sel)
        local selected_items = sel.get_selected_items()
        for _, item in ipairs(selected_items) do
          -- delete the buffer
          vim.cmd.bdelete(item.bufnr)
        end

        sel.set_selected_indices {}
        sel.set_items(
          vim
            .iter(sel.get_items())
            :filter(function(item) return not vim.tbl_contains(selected_items, item) end)
            :totable()
        )
      end,
    },
  }
end -- }}}

local IS_CODE_SYMBOL_RUNNING = false
function M.lsp_code_symbols() -- {{{
  if IS_CODE_SYMBOL_RUNNING then return end
  IS_CODE_SYMBOL_RUNNING = true

  -- Avoid callback-hell with a wizard-based "steps"-system. Define each "step"
  -- sequentially in the code, and wire up the callbacks to call the next step:
  -- a simple, yet powerful, and easy to understand pattern/approach.
  local STEPS = {}

  --- @param info vim.lsp.LocationOpts.OnList
  function STEPS._1_on_symbols(info)
    M.create_picker {
      items = info.items,
      --- @param item { text: string }
      format_item = function(item)
        local s = item.text:gsub('<', '&lt;')
        return s
      end,
      on_finish = STEPS._2_on_symbol_picked,
    }
  end

  --- @param items { filename: string, lnum: integer, col: integer }[]
  function STEPS._2_on_symbol_picked(items)
    if #items == 0 then return STEPS._finally() end

    local item = items[1]

    -- Jump to the file/buffer:
    local buf = vim
      .iter(vim.fn.getbufinfo { buflisted = 1 })
      :find(function(b) return b.name == item.filename end)
    if buf ~= nil then
      vim.api.nvim_win_set_buf(0, buf.bufnr)
    else
      vim.cmd.edit(item.filename)
    end

    -- Jump to the specific location:
    vim.api.nvim_win_set_cursor(0, { item.lnum, item.col - 1 })
    vim.cmd.normal 'zz'

    STEPS._finally()
  end

  function STEPS._finally() IS_CODE_SYMBOL_RUNNING = false end

  -- Kick off the async operation:
  vim.lsp.buf.document_symbol { on_list = STEPS._1_on_symbols }
end -- }}}

function M.setup()
  utils.ucmd('Files', M.files)
  utils.ucmd('Buffers', M.buffers)
  utils.ucmd('Lspcodesymbols', M.lsp_code_symbols)
end

return M
