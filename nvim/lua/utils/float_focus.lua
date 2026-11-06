-- Hover and diagnostic boxes take the cursor when they open, so j/k, <C-d>,
-- ... move and scroll inside them. q or <Esc> closes the box, and so does
-- leaving it.
local M = {}

---@param win? integer the box
function M.enter(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local function close()
    pcall(vim.api.nvim_win_close, win, true)
  end
  for _, key in ipairs { "q", "<Esc>" } do
    vim.keymap.set("n", key, close, { buffer = buf, nowait = true, desc = "Close" })
  end
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(close)
    end,
  })
  vim.api.nvim_set_current_win(win)
end

-- The buffer a hover was asked from, until its box opens. The reply comes
-- later, so the box is caught where Neovim opens it.
local hover_from

--- LSP hover in a box the cursor moves into; K (keywordprg) where no
--- language server offers hover
function M.hover()
  if #vim.lsp.get_clients { bufnr = 0, method = "textDocument/hover" } == 0 then
    return vim.cmd "normal! K"
  end
  hover_from = vim.api.nvim_get_current_buf()
  vim.lsp.buf.hover()
end

function M.setup()
  local open = vim.lsp.util.open_floating_preview
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.lsp.util.open_floating_preview = function(contents, syntax, opts)
    local from = vim.api.nvim_get_current_buf()
    local buf, win = open(contents, syntax, opts)
    if hover_from == from and opts and opts.focus_id == "textDocument/hover" then
      hover_from = nil
      M.enter(win)
    end
    return buf, win
  end
end

return M
