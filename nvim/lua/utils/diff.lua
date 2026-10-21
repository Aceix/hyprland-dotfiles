-- Side-by-side diffs (diffview, the sidebar's diff, :diffsplit, tree compare)
-- behave like VS Code's diff editor:
--   * the panes in a row always split the space evenly, whatever focus.nvim
--     did to the windows before 'diff' got switched on
--   * the mouse wheel over either pane scrolls both, even the unfocused one
--     (Neovim only follows 'scrollbind' from the current window)
--   * the old side is red, the new one green (chadrc.lua's Diff* groups)
local M = {}

--- 'winhighlight' for the old (left) side of a two-way diff
M.OLD_WINHL = "DiffAdd:DiffOldAdd,DiffChange:DiffOldChange,DiffText:DiffOldText"

local function diff_wins()
  return vim.tbl_filter(function(win)
    return vim.wo[win].diff and vim.api.nvim_win_get_config(win).relative == ""
  end, vim.api.nvim_tabpage_list_wins(0))
end

--- Give the diff panes of each row of the current tab equal widths.
function M.balance()
  local rows = {}
  for _, win in ipairs(diff_wins()) do
    local row = vim.api.nvim_win_get_position(win)[1]
    rows[row] = rows[row] or {}
    table.insert(rows[row], win)
  end
  for _, wins in pairs(rows) do
    if #wins > 1 then
      table.sort(wins, function(a, b)
        return vim.api.nvim_win_get_position(a)[2] < vim.api.nvim_win_get_position(b)[2]
      end)
      local total = 0
      for _, win in ipairs(wins) do
        vim.w[win].focus_disable = true -- focus.nvim: leave the split alone
        total = total + vim.api.nvim_win_get_width(win)
      end
      local width = math.floor(total / #wins)
      for i = 1, #wins - 1 do
        vim.api.nvim_win_set_width(wins[i], width)
      end
    end
  end
end

--- Scroll the diff pane under the mouse (and so its partner) by 'mousescroll'.
--- From a diff pane, that pane scrolls instead: it's bound to the one under
--- the mouse, and scrolling that one fights 'cursorbind', which loses lines.
---@param win integer
---@param key "<C-e>"|"<C-y>"
function M.scroll(win, key)
  local lines = tonumber(vim.o.mousescroll:match "ver:(%d+)") or 3
  if vim.wo.diff and vim.wo.scrollbind then
    win = vim.api.nvim_get_current_win()
  end
  if lines > 0 and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_call(win, function()
      vim.cmd("normal! " .. lines .. vim.keycode(key))
    end)
  end
end

function M.setup()
  vim.opt.fillchars:append { diff = "╱" } -- filler lines hatched, like VS Code's
  local group = vim.api.nvim_create_augroup("DiffLayout", { clear = true })
  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = "diff",
    callback = function()
      if vim.wo.diff then
        vim.schedule(M.balance)
      else
        vim.w.focus_disable = nil -- out of diff mode: auto-resize again
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "VimResized", "WinClosed", "TabEnter" }, {
    group = group,
    callback = function()
      vim.schedule(M.balance)
    end,
  })

  for wheel, key in pairs { ["<ScrollWheelDown>"] = "<C-e>", ["<ScrollWheelUp>"] = "<C-y>" } do
    vim.keymap.set({ "n", "v", "i" }, wheel, function()
      local win = vim.fn.getmousepos().winid
      if win ~= 0 and win ~= vim.api.nvim_get_current_win() and vim.wo[win].diff and vim.wo[win].scrollbind then
        return ("<Cmd>lua require('utils.diff').scroll(%d, '%s')<CR>"):format(win, key)
      end
      return wheel
    end, { expr = true, desc = "Scroll (both sides in a diff)" })
  end
end

return M
