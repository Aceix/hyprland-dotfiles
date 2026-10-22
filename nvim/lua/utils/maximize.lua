-- Maximize the current split by shrinking every other window to its minimum
-- size, then put the exact layout back. Nothing is closed or deleted, so
-- terminals, the side bar, dap-ui, ... are all still there afterwards.
-- (maximize.nvim force-deleted every buffer :mksession can't save, terminals
-- included.)
local M = {}

-- This tab page's windows, floats left out
local function normal_wins()
  return vim.tbl_filter(function(win)
    return vim.api.nvim_win_get_config(win).relative == ""
  end, vim.api.nvim_tabpage_list_wins(0))
end

function M.maximize()
  local normal = normal_wins()
  if #normal < 2 then
    return vim.notify("Already one window", vim.log.levels.WARN)
  end

  vim.t.maximized = {
    restore = vim.fn.winrestcmd(),
    wins = #normal,
    autoresize = require("utils.autoresize").enabled,
  }
  -- auto-resize would regrow whichever split is entered next
  require("utils.autoresize").enabled = false

  local fixed = {}
  for _, win in ipairs(normal) do
    fixed[win] = { vim.wo[win].winfixwidth, vim.wo[win].winfixheight }
    vim.wo[win].winfixwidth, vim.wo[win].winfixheight = false, false
  end
  vim.api.nvim_win_set_width(0, vim.o.columns)
  vim.api.nvim_win_set_height(0, vim.o.lines)
  for win, fix in pairs(fixed) do
    vim.wo[win].winfixwidth, vim.wo[win].winfixheight = fix[1], fix[2]
  end
end

function M.restore()
  local state = vim.t.maximized
  if not state then
    return
  end
  vim.t.maximized = nil
  require("utils.autoresize").enabled = state.autoresize

  local normal = normal_wins()
  if #normal == state.wins then
    -- Twice: the first pass can be clipped by windows not yet regrown
    vim.cmd(state.restore)
    vim.cmd(state.restore)
  else
    vim.cmd "wincmd =" -- windows came or went since: best effort
  end
end

function M.toggle()
  if vim.t.maximized then
    M.restore()
  else
    M.maximize()
  end
end

return M
