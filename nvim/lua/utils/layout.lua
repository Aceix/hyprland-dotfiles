-- VS Code's layout always keeps an editor area: closing the last code window
-- leaves the side bar and the bottom panel (utils/term.lua) at their size.
-- Here that window used to just go, so the terminal or the Explorer took the
-- whole screen, the next file opened into whatever was left (a file in the
-- terminal's window) and the next terminal split off beside the Explorer.
local M = {}

local api = vim.api

local function is_panel(win)
  return require("utils.git_sidebar").is_sidebar_win(win) or require("utils.term").is_panel_win(win)
end

-- A window in the editor area: a file, an empty buffer or the dashboard
local function is_editor(win)
  local buf = api.nvim_win_get_buf(win)
  local bo = vim.bo[buf]
  return bo.buflisted or bo.filetype == "nvdash" or (bo.buftype == "" and api.nvim_buf_get_name(buf) == "")
end

-- The most recently used listed buffer, else a new empty one
local function recent_buf()
  local bufs = vim.fn.getbufinfo { buflisted = 1 }
  table.sort(bufs, function(a, b)
    return a.lastused > b.lastused
  end)
  return bufs[1] and bufs[1].bufnr or api.nvim_create_buf(true, false)
end

--- Opens an editor window where VS Code's editor area is: above the bottom
--- panel, else right of the side bar. Shows `buf` (default: the last used
--- file) and returns the window.
---@param buf? integer
function M.new_editor(buf)
  buf = buf or recent_buf()
  local panel, sidebar
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_config(win).relative == "" then
      if require("utils.term").is_panel_win(win) then
        panel = panel or win
      elseif require("utils.git_sidebar").is_sidebar_win(win) then
        sidebar = sidebar or win
      end
    end
  end

  local win
  if panel then
    win = api.nvim_open_win(buf, true, { split = "above", win = panel })
    api.nvim_win_set_height(panel, require("utils.term").height())
  else
    win = api.nvim_open_win(buf, true, { split = "right", win = -1 })
    if sidebar then
      api.nvim_win_set_width(sidebar, require("utils.git_sidebar").width())
    end
  end
  return win
end

-- Gives the bottom panel its height (utils/term.lua's M.height) without
-- changing the split right above it, e.g. dap-ui's REPL/Console strip: the
-- lines go to or come from the editor above that instead.
local function fit_panel(panel)
  local function leaf(node)
    return node[1] == "leaf" and node[2] or leaf(node[2][1])
  end
  local function find(node)
    if node[1] == "col" then
      for i, child in ipairs(node[2]) do
        if child[1] == "leaf" and child[2] == panel then
          return node[2][i - 1], node[2][i - 2]
        end
      end
    end
    if node[1] ~= "leaf" then
      for _, child in ipairs(node[2]) do
        local above, editor = find(child)
        if above then
          return above, editor
        end
      end
    end
  end

  local above, editor = find(vim.fn.winlayout())
  local keep = above and editor and api.nvim_win_get_height(leaf(above))
  api.nvim_win_set_height(panel, require("utils.term").height())
  if keep then
    local win = leaf(editor)
    api.nvim_win_set_height(win, api.nvim_win_get_height(win) + api.nvim_win_get_height(leaf(above)) - keep)
  end
end

-- dap-ui's left layout (configs/dap.lua): the debug side bar
local DAP_SIDE = { dapui_scopes = true, dapui_watches = true, dapui_stacks = true, dapui_breakpoints = true }

-- dap-ui's open layouts (its side bar first is "vertical", the strip "horizontal")
local function dap_layouts()
  local ok, windows = pcall(require, "dapui.windows")
  return ok and package.loaded["dapui"] and windows.layouts or {}
end

local function splits()
  return vim.tbl_filter(function(win)
    return api.nvim_win_get_config(win).relative == ""
  end, api.nvim_tabpage_list_wins(0))
end

local function is_side(win)
  return DAP_SIDE[vim.bo[api.nvim_win_get_buf(win)].filetype] or require("utils.git_sidebar").is_sidebar_win(win)
end

-- Whether the panel is where VS Code keeps it: the bottom of the editor
-- column, right of a full-height side bar
local function docked(panel, side)
  local row, col = unpack(api.nvim_win_get_position(panel))
  local left = side[1] and api.nvim_win_get_width(side[1]) + 1 or 0
  if col ~= left or api.nvim_win_get_width(panel) ~= vim.o.columns - left then
    return false
  end
  for _, win in ipairs(splits()) do
    if win ~= panel and not is_side(win) and api.nvim_win_get_position(win)[1] > row then
      return false
    end
  end
  return true
end

--- Puts the bottom panel back under the editor column when a split landed
--- below it (dap-ui's REPL/Console strip) or it went under a side bar Neovim
--- doesn't keep full height itself (dap-ui's; edgy.nvim docks the Explorer).
function M.dock()
  local term = require "utils.term"
  local panel
  local side = {}
  for _, win in ipairs(splits()) do
    if term.is_panel_win(win) then
      panel = panel or win
    elseif is_side(win) then
      side[#side + 1] = win
    end
  end
  if not panel or docked(panel, side) then
    return
  end
  table.sort(side, function(a, b)
    return api.nvim_win_get_position(a)[1] < api.nvim_win_get_position(b)[1]
  end)
  local width = side[1] and api.nvim_win_get_width(side[1])

  -- Panel across the bottom, then the side bar back to full height left of it
  api.nvim_win_call(panel, function()
    vim.cmd "wincmd J"
  end)
  for i, win in ipairs(side) do
    if i == 1 then
      api.nvim_win_call(win, function()
        vim.cmd "wincmd H"
      end)
    else
      api.nvim_win_set_config(win, { split = "below", win = side[i - 1] })
    end
  end
  if width then
    api.nvim_win_set_width(side[1], width)
  end

  -- dap-ui keeps its windows' sizes (as of its last open/close) and puts them
  -- back itself; the panel then gets its own height back
  for _, layout in ipairs(dap_layouts()) do
    layout:resize()
  end
  fit_panel(panel)
end

-- In a tab with the side bar or the bottom panel but no editor left, open one.
-- Other tabs (Diffview, Neogit's views, ...) are left alone.
local function ensure_editor()
  if vim.v.exiting ~= vim.NIL or vim.fn.getcmdwintype() ~= "" then
    return
  end
  local has_panel, stray = false, nil
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_config(win).relative == "" then
      if is_panel(win) then
        has_panel = true
      elseif is_editor(win) then
        return
      elseif require("utils.term").owns(api.nvim_win_get_buf(win)) then
        -- a pane terminal outside the pane, e.g. what edgy.nvim reopened
        -- as the main window after :only from the Explorer
        stray = stray or win
      end
    end
  end
  if stray then
    api.nvim_win_set_buf(stray, recent_buf())
  elseif has_panel then
    M.new_editor()
  end
end

function M.setup()
  local group = api.nvim_create_augroup("EditorArea", { clear = true })

  -- The Explorer / Source Control opening or closing beside dap-ui gave its
  -- side bar the columns or took them (Neovim's choice, 'winfixwidth' or
  -- not), so each toggle left dap-ui a different size. Put its sizes back
  -- instead, so the editor gives or takes them; other resizes (drags) are
  -- dap-ui's new sizes.
  local sidebars = 0
  api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function()
      local count = #vim.tbl_filter(require("utils.git_sidebar").is_sidebar_win, splits())
      local toggled = count ~= sidebars
      sidebars = count
      for _, layout in ipairs(dap_layouts()) do
        if toggled then
          layout:resize()
        else
          layout:update_sizes()
        end
      end
    end,
  })

  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      -- Floats (completion menus, hovers, ...) close all the time and never
      -- hold the editor area
      local win = tonumber(args.match)
      if win and api.nvim_win_is_valid(win) and api.nvim_win_get_config(win).relative ~= "" then
        return
      end
      -- the closing window still counts until the close is done
      vim.schedule(ensure_editor)
    end,
  })
end

return M
