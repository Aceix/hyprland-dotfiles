-- Toggles an SVG buffer between raw markup and a rasterized preview
-- (rendered via image.nvim + ImageMagick's rsvg-convert delegate),
-- without image.nvim's `hijack_file_patterns` which offers no way back to the code.

local M = {}

---@type table<integer, { lines: string[], image: table }>
local state = {}

local function restore_code(buf)
  local entry = state[buf]
  if not entry then return end

  entry.image:clear()
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, entry.lines)
  vim.bo[buf].modified = false
  vim.bo[buf].buftype = ""
  vim.bo[buf].filetype = "svg"
  state[buf] = nil
end

function M.toggle()
  local buf = vim.api.nvim_get_current_buf()

  if state[buf] then
    restore_code(buf)
    return
  end

  if vim.bo[buf].filetype ~= "svg" then
    vim.notify("Not an SVG buffer", vim.log.levels.WARN)
    return
  end

  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or vim.fn.filereadable(path) == 0 then
    vim.notify("SVG preview needs the buffer saved to disk first", vim.log.levels.WARN)
    return
  end

  local ok, image = pcall(require, "image")
  if not ok then
    vim.notify("image.nvim is not available", vim.log.levels.ERROR)
    return
  end

  local win = vim.api.nvim_get_current_win()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)

  local img = image.from_file(path, {
    window = win,
    buffer = buf,
    x = 0,
    y = 0,
    width = vim.api.nvim_win_get_width(win),
    height = vim.api.nvim_win_get_height(win),
  })

  if not img then
    vim.notify("Failed to rasterize SVG for preview", vim.log.levels.ERROR)
    return
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, { "" })
  vim.bo[buf].modified = false
  vim.bo[buf].buftype = "nowrite"
  vim.bo[buf].modifiable = false

  img:render()
  state[buf] = { lines = lines, image = img }
end

-- Don't leave a dangling rendered image if the preview buffer gets wiped
vim.api.nvim_create_autocmd("BufWipeout", {
  callback = function(args)
    local entry = state[args.buf]
    if entry then
      entry.image:clear()
      state[args.buf] = nil
    end
  end,
})

-- image.nvim itself clears any image whose window no longer shows its buffer
-- (on BufLeave/WinClosed/TabEnter) and has no reason to bring it back since
-- our buffer isn't in `hijack_file_patterns` -- so re-render it ourselves
-- whenever the preview buffer becomes visible again.
vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  callback = function(args)
    local entry = state[args.buf]
    if not entry then return end

    local win = vim.api.nvim_get_current_win()
    entry.image.window = win
    entry.image.geometry.width = vim.api.nvim_win_get_width(win)
    entry.image.geometry.height = vim.api.nvim_win_get_height(win)

    vim.schedule(function()
      entry.image:clear()
      entry.image:render()
    end)
  end,
})

return M
