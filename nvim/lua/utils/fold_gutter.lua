-- VS Code's folding gutter, drawn through 'statuscolumn' left of the signs:
--   * a chevron on every line that starts a fold; clicking it folds/unfolds
--   * open-fold chevrons only show while the mouse is over that window's
--     gutter, collapsed ones always do
--   * a folded line keeps its syntax highlighting, then "… N lines"
local M = {}

local OPEN, CLOSED = vim.fn.nr2char(0xeab4), vim.fn.nr2char(0xeab6) -- codicon chevron-down/right

---@type integer? window whose gutter the mouse is over
local hovered

--- Columns the fold chevrons take in `win` (utils/test_gutter.lua skips them).
function M.width(win)
  local buf = vim.api.nvim_win_get_buf(win)
  return (vim.bo[buf].buftype == "" or vim.wo[win].diff) and 2 or 0
end

-- Whether a fold starts on `lnum` of the current window
local function starts_fold(lnum)
  local level = vim.fn.foldlevel(lnum)
  if level == 0 then
    return false
  end
  if vim.wo.foldmethod == "expr" then
    -- ">N" also catches a fold starting right where a sibling ends
    local saved = vim.v.lnum
    vim.v.lnum = lnum
    local ok, expr = pcall(vim.fn.eval, vim.wo.foldexpr)
    vim.v.lnum = saved
    if ok and tostring(expr):sub(1, 1) == ">" then
      return true
    end
  end
  return level > vim.fn.foldlevel(lnum - 1)
end

--- 'statuscolumn' fold item, evaluated in the window being drawn.
function M.render()
  local win = vim.api.nvim_get_current_win()
  if M.width(win) == 0 then
    return ""
  end
  local lnum = vim.v.lnum
  if vim.v.virtnum ~= 0 then
    return "  "
  end
  if vim.fn.foldclosed(lnum) == lnum then
    return "%#FoldColumn#" .. CLOSED .. " "
  end
  if hovered == win and starts_fold(lnum) then
    return "%#FoldColumn#" .. OPEN .. " "
  end
  return "  "
end

--- %@ click handler for the fold item.
function M.click(_, _, button)
  if button ~= "l" then
    return
  end
  local m = vim.fn.getmousepos()
  if m.winid == 0 or m.line == 0 then
    return
  end
  -- The click area runs on over the sign column (terminals draw the chevron
  -- over two cells and may report its right edge as the next one), but only
  -- where that line shows no sign: a test button, breakpoint, git or
  -- diagnostic sign keeps its own click (e.g. utils/test_gutter.lua)
  if m.wincol > M.width(m.winid) then
    local buf = vim.api.nvim_win_get_buf(m.winid)
    local row = m.line - 1
    if #vim.api.nvim_buf_get_extmarks(buf, -1, { row, 0 }, { row, -1 }, { type = "sign" }) > 0 then
      return
    end
  end
  vim.api.nvim_win_call(m.winid, function()
    if vim.fn.foldclosed(m.line) ~= -1 then
      vim.cmd(m.line .. "foldopen")
    elseif starts_fold(m.line) then
      vim.cmd(m.line .. "foldclose")
    end
  end)
end

local function set_hovered(win)
  if win == hovered then
    return
  end
  local old = hovered
  hovered = win
  for _, w in pairs { old or false, win or false } do -- (ipairs stops at a nil)
    if w and vim.api.nvim_win_is_valid(w) then
      vim.api.nvim__redraw { win = w, statuscolumn = true, flush = true }
    end
  end
end

--- First line with its syntax highlighting, then "… N lines"
function M.foldtext()
  local lnum = vim.v.foldstart
  local line = vim.fn.getline(lnum)
  local chunks, text, hl = {}, "", nil
  local ok = pcall(vim.treesitter.get_parser, 0)
  for col = 1, #line do
    local caps = ok and vim.treesitter.get_captures_at_pos(0, lnum - 1, col - 1) or {}
    local cap = caps[#caps]
    local new = cap and ("@" .. cap.capture .. "." .. cap.lang) or nil
    if new ~= hl then
      table.insert(chunks, { text, hl })
      text, hl = "", new
    end
    text = text .. line:sub(col, col)
  end
  table.insert(chunks, { text, hl })
  for _, chunk in ipairs(chunks) do
    chunk[1] = chunk[1]:gsub("\t", string.rep(" ", vim.bo.tabstop))
  end
  table.insert(chunks, { ("  … %d lines"):format(vim.v.foldend - lnum + 1), "Comment" })
  return chunks
end

function M.setup()
  vim.o.statuscolumn = "%@v:lua.require'utils.fold_gutter'.click@%{%v:lua.require'utils.fold_gutter'.render()%}%s%T%l "
  vim.o.foldtext = "v:lua.require'utils.fold_gutter'.foldtext()"
  vim.opt.fillchars:append { fold = " " }
  vim.o.mousemoveevent = true

  local move = vim.keycode "<MouseMove>"
  vim.on_key(function(_, typed)
    if typed ~= move then
      return
    end
    local m = vim.fn.getmousepos()
    local win = nil
    if m.winid ~= 0 and vim.api.nvim_win_get_config(m.winid).relative == "" then
      local info = vim.fn.getwininfo(m.winid)[1]
      if info and m.wincol <= info.textoff then
        win = m.winid
      end
    end
    vim.schedule(function()
      set_hovered(win)
    end)
  end, vim.api.nvim_create_namespace "fold_gutter")
  vim.api.nvim_create_autocmd("FocusLost", {
    group = vim.api.nvim_create_augroup("FoldGutter", { clear = true }),
    callback = function()
      set_hovered(nil)
    end,
  })
end

return M
