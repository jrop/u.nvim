local Renderer = require('u.renderer').Renderer
local TreeBuilder = require('u.renderer').TreeBuilder
local tracker = require 'u.tracker'
local utils = require 'u.utils'

local TIMEOUT = 4000
local ICONS = {
  [vim.log.levels.TRACE] = { text = '󰃤', group = 'DiagnosticSignOk' },
  [vim.log.levels.DEBUG] = { text = '󰃤', group = 'DiagnosticSignOk' },
  [vim.log.levels.INFO] = { text = '', group = 'DiagnosticSignInfo' },
  [vim.log.levels.WARN] = { text = '', group = 'DiagnosticSignWarn' },
  [vim.log.levels.ERROR] = { text = '', group = 'DiagnosticSignError' },
}
local DEFAULT_ICON = { text = '', group = 'DiagnosticSignOk' }

local S_EDITOR_DIMENSIONS =
  tracker.create_signal(utils.get_editor_dimensions(), 's:editor_dimensions')
vim.api.nvim_create_autocmd('VimResized', {
  callback = function()
    local new_dim = utils.get_editor_dimensions()
    S_EDITOR_DIMENSIONS:set(new_dim)
  end,
})

--- @alias u.example.Notification {
---   kind: number;
---   id: number;
---   text: string;
---   timer: uv.uv_timer_t;
--- }

local M = {}

--- @type { win: integer, buf: integer, renderer: u.Renderer } | nil
local notifs_w

local s_notifications_raw = tracker.create_signal {}
local s_notifications = s_notifications_raw:debounce(50)

-- Render effect:
tracker.create_effect(function()
  --- @type u.example.Notification[]
  local notifs = s_notifications:get()
  --- @type { width: integer, height: integer }
  local editor_size = S_EDITOR_DIMENSIONS:get()

  if #notifs == 0 then
    if notifs_w then
      if vim.api.nvim_win_is_valid(notifs_w.win) then vim.api.nvim_win_close(notifs_w.win, true) end
      notifs_w = nil
    end
    return
  end

  local avail_width = editor_size.width
  local float_width = 40
  local float_height = math.min(#notifs, editor_size.height - 3)
  local win_config = {
    relative = 'editor',
    anchor = 'NE',
    row = 0,
    col = avail_width,
    width = float_width,
    height = float_height,
    border = 'single',
    focusable = false,
    zindex = 900,
  }
  vim.schedule(function()
    if not notifs_w or not vim.api.nvim_win_is_valid(notifs_w.win) then
      local b = vim.api.nvim_create_buf(false, true)
      local w = vim.api.nvim_open_win(b, false, win_config)
      vim.wo[w].cursorline = false
      vim.wo[w].list = false
      vim.wo[w].listchars = ''
      vim.wo[w].number = false
      vim.wo[w].relativenumber = false
      vim.wo[w].wrap = false
      notifs_w = { win = w, buf = b, renderer = Renderer.new(b) }
    else
      vim.api.nvim_win_set_config(notifs_w.win, win_config)
    end

    notifs_w.renderer:render(TreeBuilder.new()
      :nest(function(tb)
        for idx, notif in ipairs(notifs) do
          if idx > 1 then tb:put '\n' end

          local notif_icon = ICONS[notif.kind] or DEFAULT_ICON
          tb:put_h('text', { hl = notif_icon.group }, notif_icon.text)
          tb:put { '  ', notif.text }
        end
      end)
      :tree())
    vim.api.nvim_win_call(notifs_w.win, function()
      vim.fn.winrestview {
        -- scroll all the way left:
        leftcol = 0,
        -- set the bottom line to be at the bottom of the window:
        topline = vim.api.nvim_buf_line_count(notifs_w.buf) - win_config.height + 1,
      }
    end)
  end)
end)

--- @param id number
local function _delete_notif(id)
  --- @param notifs u.example.Notification[]
  s_notifications_raw:schedule_update(function(notifs)
    for i, notif in ipairs(notifs) do
      if notif.id == id then
        notif.timer:stop()
        notif.timer:close()
        table.remove(notifs, i)
        break
      end
    end
    return notifs
  end)
end

local _orig_notify

--- @param msg string
--- @param level integer|nil
--- @param opts? { id: number }
function M.notify(msg, level, opts)
  if level == nil then level = vim.log.levels.INFO end

  opts = opts or {}
  local id = opts.id or math.random(999999999)

  --- @type u.example.Notification?
  local notif = vim.iter(s_notifications_raw:get()):find(function(n) return n.id == id end)
  if not notif then
    -- Create a new notification (maybe):
    if vim.trim(msg) == '' then return id end
    if level < vim.log.levels.INFO then return id end

    local timer = assert((vim.uv or vim.loop).new_timer(), 'could not create timer')
    timer:start(TIMEOUT, 0, function() _delete_notif(id) end)
    notif = {
      id = id,
      kind = level,
      text = msg,
      timer = timer,
    }
    --- @param notifs u.example.Notification[]
    s_notifications_raw:schedule_update(function(notifs)
      table.insert(notifs, notif)
      return notifs
    end)
  else
    -- Update an existing notification:
    s_notifications_raw:schedule_update(function(notifs)
      -- We already have a copy-by-reference of the notif we want to modify:
      notif.timer:stop()
      notif.text = msg
      notif.kind = level
      notif.timer:start(TIMEOUT, 0, function() _delete_notif(id) end)

      return notifs
    end)
  end

  return id
end

local _once_msgs = {}
function M.notify_once(msg, level, opts)
  if vim.tbl_contains(_once_msgs, msg) then return false end
  table.insert(_once_msgs, msg)
  vim.notify(msg, level, opts)
  return true
end

function M.setup()
  if _orig_notify == nil then _orig_notify = vim.notify end

  vim.notify = M.notify
  vim.notify_once = M.notify_once
end

return M
