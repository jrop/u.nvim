local Range = require 'u.range'
local Renderer = require('u.renderer').Renderer

--- @class u.Buffer
--- @field bufnr number
--- @field b vim.var_accessor
--- @field bo vim.bo
--- @field private renderer u.Renderer
local Buffer = {}
Buffer.__index = Buffer

--- @param bufnr? number
--- @return u.Buffer
function Buffer.from_nr(bufnr)
  if bufnr == nil or bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  local renderer = Renderer.new(bufnr)
  return setmetatable({
    bufnr = bufnr,
    b = vim.b[bufnr],
    bo = vim.bo[bufnr],
    renderer = renderer,
  }, Buffer)
end

--- @return u.Buffer
function Buffer.current() return Buffer.from_nr(0) end

--- @param listed boolean
--- @param scratch boolean
--- @return u.Buffer
function Buffer.create(listed, scratch)
  return Buffer.from_nr(vim.api.nvim_create_buf(listed, scratch))
end

function Buffer:set_tmp_options()
  self.bo.bufhidden = 'delete'
  self.bo.buflisted = false
  self.bo.buftype = 'nowrite'
end

function Buffer:line_count() return vim.api.nvim_buf_line_count(self.bufnr) end

function Buffer:all() return Range.from_buf_text(self.bufnr) end

function Buffer:is_empty() return self:line_count() == 1 and self:line(1):text() == '' end

--- @param line string
function Buffer:append_line(line)
  local start = -1
  if self:is_empty() then start = -2 end
  vim.api.nvim_buf_set_lines(self.bufnr, start, -1, false, { line })
end

--- @param num number 1-based line index
function Buffer:line(num)
  if num < 0 then num = self:line_count() + num + 1 end
  return Range.from_line(self.bufnr, num)
end

--- @param start number 1-based line index
--- @param stop number 1-based line index
function Buffer:lines(start, stop) return Range.from_lines(self.bufnr, start, stop) end

--- @param motion string
--- @param opts? { contains_cursor?: boolean; pos?: u.Pos }
function Buffer:motion(motion, opts)
  opts = vim.tbl_extend('force', opts or {}, { bufnr = self.bufnr })
  return Range.from_motion(motion, opts)
end

--- @param event string|string[]
--- @diagnostic disable-next-line: undefined-doc-name
--- @param opts vim.api.keyset.create_autocmd
function Buffer:autocmd(event, opts)
  vim.api.nvim_create_autocmd(event, vim.tbl_extend('force', opts, { buffer = self.bufnr }))
end

--- @param tree u.renderer.Tree
function Buffer:render(tree) return self.renderer:render(tree) end

--- Filter buffer content through an external command (like Vim's :%!)
--- @param cmd string[] Command to run (with arguments)
--- @param opts? {cwd?: string, preserve_cursor?: boolean}
--- @return nil
--- @throws string Error message if command fails
--- @note Special placeholders in cmd:
---   - $FILE: replaced with the buffer's filename (if any)
---   - $DIR: replaced with the buffer's directory (if any)
function Buffer:filter_cmd(cmd, opts)
  opts = opts or {}
  local cwd = opts.cwd or vim.uv.cwd()
  local old_lines = self:all():lines()
  -- Save cursor position if needed, defaulting to true
  local save_pos = opts.preserve_cursor ~= false and vim.fn.winsaveview()

  -- Run the command
  local result = vim
    .system(
      -- Replace special placeholders in `cmd` with their values:
      vim
        .iter(cmd)
        :map(function(x)
          if x == '$FILE' then return vim.api.nvim_buf_get_name(self.bufnr) end
          if x == '$DIR' then return vim.fs.dirname(vim.api.nvim_buf_get_name(self.bufnr)) end
          return x
        end)
        :totable(),
      {
        cwd = cwd,
        stdin = old_lines,
        text = true,
      }
    )
    :wait()

  -- Check for command failure
  if result.code ~= 0 then error('Command failed: ' .. (result.stderr or '')) end

  -- Process and apply the result
  local new_lines = vim.split(result.stdout, '\n')
  if new_lines[#new_lines] == '' then table.remove(new_lines) end
  Renderer.patch_lines(self.bufnr, old_lines, new_lines)

  -- Restore cursor position if saved
  if save_pos then vim.fn.winrestview(save_pos) end
end

return Buffer
