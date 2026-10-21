-- Opens/closes dap-ui and gets nvim-tree out of the way of its left sidebar,
-- bringing the tree back afterwards if it was showing before the session.
local M = {}

local tree_was_open = false

local function tree_api()
  local ok, api = pcall(require, "nvim-tree.api")
  return ok and api or nil
end

function M.is_open()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype:match "^dapui_" then
      return true
    end
  end
  return false
end

function M.open()
  if M.is_open() then
    return
  end
  local api = tree_api()
  tree_was_open = api ~= nil and api.tree.is_visible()
  if tree_was_open then
    api.tree.close()
  end
  require("dapui").open { reset = true }
  -- dap-ui's REPL/Console strip opens across the bottom; the panel stays below
  require("utils.layout").dock()
end

function M.close()
  require("dapui").close()
  -- An Explorer opened during the session got dap-ui's columns; keep its width
  local sidebar = require "utils.git_sidebar"
  if sidebar.is_open() then
    sidebar.set_width(sidebar.width())
  end
  local api = tree_api()
  if tree_was_open and api and not api.tree.is_visible() then
    api.tree.toggle { focus = false }
  end
  tree_was_open = false
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

return M
