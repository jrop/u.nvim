local Buffer = require 'u.buffer'
local TreeBuilder = require('u.renderer').TreeBuilder
local tracker = require 'u.tracker'
local utils = require 'u.utils'
local Window = require 'my.window'

local TIMEOUT = 4000
local ICONS = {
  [vim.log.levels.TRACE] = { text = '󰃤', group = 'DiagnosticSignOk' },
  [vim.log.levels.DEBUG] = { text = '󰃤', group = 'DiagnosticSignOk' },
  [vim.log.levels.INFO] = { text = '', group = 'DiagnosticSignInfo' },
  [vim.log.levels.WARN] = { text = '', group = 'DiagnosticSignWarn' },
  [vim.log.levels.ERROR] = { text = '', group = 'DiagnosticSignError' },
}
local DEFAULT_ICON = { text = '', group = 'DiagnosticSignOk' }

--- @alias Notification {
---   kind: number;
---   id: number;
---   text: string;
--- }

local M = {}

--- @type Window | nil
local notifs_w

local s_notifications_raw = tracker.create_signal {}
local s_notifications = s_notifications_raw:debounce(50)

-- Render effect:
tracker.create_effect(function()
  --- @type Notification[]
  local notifs = s_notifications:get()

  if #notifs == 0 then
    if notifs_w then
      notifs_w:close(true)
      notifs_w = nil
    end
    return
  end

  vim.schedule(function()
    local editor_size = utils.get_editor_dimensions()
    local avail_width = editor_size.width
    local float_width = 40
    local win_config = {
      relative = 'editor',
      anchor = 'NE',
      row = 0,
      col = avail_width,
      width = float_width,
      height = math.min(#notifs, editor_size.height - 3),
      border = 'single',
      focusable = false,
    }
    if not notifs_w or not vim.api.nvim_win_is_valid(notifs_w.win) then
      notifs_w = Window.new(Buffer.create(false, true), win_config)
      vim.wo[notifs_w.win].cursorline = false
      vim.wo[notifs_w.win].list = false
      vim.wo[notifs_w.win].listchars = ''
      vim.wo[notifs_w.win].number = false
      vim.wo[notifs_w.win].relativenumber = false
      vim.wo[notifs_w.win].wrap = false
    else
      notifs_w:set_config(win_config)
    end

    notifs_w:render(TreeBuilder.new()
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
      -- scroll to bottom:
      vim.cmd.normal 'G'
      -- scroll all the way to the left:
      vim.cmd.normal '9999zh'
    end)
  end)
end)

local _orig_notify

--- @param msg string
--- @param level integer|nil
--- @param opts table|nil
local function my_notify(msg, level, opts)
  vim.schedule(function() _orig_notify(msg, level, opts) end)
  if level == nil then level = vim.log.levels.INFO end
  if level < vim.log.levels.INFO then return end

  local id = math.random(math.huge)

  --- @param notifs Notification[]
  s_notifications_raw:schedule_update(function(notifs)
    table.insert(notifs, { kind = level, id = id, text = msg })
    return notifs
  end)

  vim.defer_fn(function()
    --- @param notifs Notification[]
    s_notifications_raw:schedule_update(function(notifs)
      for i, notif in ipairs(notifs) do
        if notif.id == id then
          table.remove(notifs, i)
          break
        end
      end
      return notifs
    end)
  end, TIMEOUT)
end

local _once_msgs = {}
local function my_notify_once(msg, level, opts)
  if vim.tbl_contains(_once_msgs, msg) then return false end
  table.insert(_once_msgs, msg)
  vim.notify(msg, level, opts)
  return true
end

function M.setup()
  if _orig_notify == nil then _orig_notify = vim.notify end

  vim.notify = my_notify
  vim.notify_once = my_notify_once
end

return M
