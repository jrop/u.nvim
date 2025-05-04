local M = {}

--- @params name string
function M.file_for_name(name)
  return vim.fs.joinpath(vim.fn.stdpath 'cache', 'u.log', name .. '.log.jsonl')
end

--------------------------------------------------------------------------------
-- Logger class
--------------------------------------------------------------------------------

--- @class u.Logger
--- @field name string
--- @field private fd number
local Logger = {}
Logger.__index = Logger
M.Logger = Logger

--- @param name string
function Logger.new(name)
  local file_path = M.file_for_name(name)
  vim.fn.mkdir(vim.fs.dirname(file_path), 'p')
  local self = setmetatable({
    name = name,
    fd = (vim.uv or vim.loop).fs_open(file_path, 'a', tonumber('644', 8)),
  }, Logger)
  return self
end

--- @private
--- @param level string
function Logger:write(level, ...)
  local data = { ... }
  if #data == 1 then data = data[1] end
  (vim.uv or vim.loop).fs_write(
    self.fd,
    vim.json.encode { ts = os.date(), level = level, data = data } .. '\n'
  )
end

function Logger:trace(...) self:write('INFO', ...) end
function Logger:debug(...) self:write('DEBUG', ...) end
function Logger:info(...) self:write('INFO', ...) end
function Logger:warn(...) self:write('WARN', ...) end
function Logger:error(...) self:write('ERROR', ...) end

function M.setup()
  vim.api.nvim_create_user_command('Logfollow', function(args)
    if #args.fargs == 0 then
      vim.print 'expected log name'
      return
    end

    local log_file_path = M.file_for_name(args.fargs[1])
    vim.fn.mkdir(vim.fs.dirname(log_file_path), 'p')
    vim.system({ 'touch', log_file_path }):wait()

    vim.cmd.new()

    local winnr = vim.api.nvim_get_current_win()
    vim.wo[winnr][0].number = false
    vim.wo[winnr][0].relativenumber = false

    vim.cmd.terminal('tail -f "' .. log_file_path .. '"')
    vim.cmd.startinsert()
  end, { nargs = '*' })
end

return M
