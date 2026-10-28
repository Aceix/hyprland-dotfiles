-- Where the symbol outline (outline.nvim) lives: its own pane on the right,
-- or VS Code's Outline section -- the bottom of the side bar, under the
-- Explorer (docked by configs/edgy.lua, height resizable through
-- utils/sidebar_split.lua). <leader>cO or :OutlineDock switches; the choice
-- is kept across restarts.
--
-- Docked left, the outline belongs to the Explorer: switching the side bar
-- to Source Control or hiding it (<C-b>) takes the outline with it, and it
-- comes back with the Explorer unless it was closed in the meantime.

local M = {}

local api = vim.api

-- Upper-case g: vars so shada ('!') keeps them, like the side bar's width
---@return "left"|"right"
function M.dock()
  return vim.g.OUTLINE_DOCK == "right" and "right" or "left"
end

local function split_command()
  return M.dock() == "left" and "topleft vs" or "botright vs"
end

local function find_win(ft)
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_config(win).relative == "" and vim.bo[api.nvim_win_get_buf(win)].filetype == ft then
      return win
    end
  end
end

function M.is_open()
  return find_win "Outline" ~= nil
end

-- Whether the outline should be on screen: set when one opens, cleared
-- when the user closes it (not when it leaves with the Explorer)
local wanted = false
-- Our own closes, which keep `wanted`
local closing = false
-- An open in flight: symbols come back asynchronously
local opening = false
-- The window to return to once the outline has opened
local restore_win
-- Focus the outline when the Explorer brings it up (it was asked for by key)
local focus_next = false

-- outline.nvim takes the current window as the one to outline, so open it
-- from a code window, never from the side bar
local function code_win()
  local function usable(win)
    if not api.nvim_win_is_valid(win) or api.nvim_win_get_config(win).relative ~= "" then
      return false
    end
    local bo = vim.bo[api.nvim_win_get_buf(win)]
    return bo.buftype == "" and bo.buflisted
  end
  local cur = api.nvim_get_current_win()
  if usable(cur) then
    return cur
  end
  local prev = vim.fn.win_getid(vim.fn.winnr "#")
  if usable(prev) then
    return prev
  end
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if usable(win) then
      return win
    end
  end
end

local function open_now(focus)
  if opening or M.is_open() then
    return
  end
  local prev = api.nvim_get_current_win()
  local code = code_win()
  if code then
    api.nvim_set_current_win(code)
  end
  -- outline.nvim goes back to the code window when not focusing; return to
  -- wherever the user was (e.g. the Explorer that brought the outline back)
  restore_win = not focus and prev ~= code and prev or nil
  opening = true
  vim.defer_fn(function()
    opening = false
  end, 2000)
  local win_opts = require("outline.config").o.outline_window
  win_opts.position = M.dock()
  -- outline.nvim sets its own 'winhighlight', which would wipe edgy's (the
  -- side bar's right edge and title bar): docked left, keep edgy's
  win_opts.winhl = M.dock() == "left" and require("configs.edgy").wo.winhighlight or ""
  require("outline").open_outline { focus_outline = focus, split_command = split_command() }
end

local function explorer_open()
  return find_win "NvimTree" ~= nil
end

---@param focus boolean move the cursor into the outline
function M.open(focus)
  wanted = true
  if M.dock() == "left" and not explorer_open() then
    -- The NvimTree hook in setup() opens the outline once the Explorer is up
    focus_next = focus
    require("utils.git_sidebar").show "explorer"
  else
    open_now(focus)
  end
end

-- Close the outline but keep `wanted`, and the cursor where it is
local function hide()
  local win = find_win "Outline"
  if not win then
    return
  end
  local cur = api.nvim_get_current_win()
  closing = true
  pcall(require("outline").close_outline)
  pcall(api.nvim_win_close, win, true)
  closing = false
  if cur ~= win and api.nvim_win_is_valid(cur) then
    api.nvim_set_current_win(cur)
  end
end

-- <leader>co
function M.toggle()
  if M.is_open() then
    wanted = false
    hide()
  else
    M.open(true)
  end
end

-- <leader>cO / :OutlineDock: move the outline to the other side (or `side`)
-- and show it there
---@param side? "left"|"right"
function M.switch(side)
  side = side or (M.dock() == "left" and "right" or "left")
  hide()
  vim.g.OUTLINE_DOCK = side
  vim.notify(
    side == "left" and "Outline: in the side bar, under the Explorer" or "Outline: in its own pane on the right",
    vim.log.levels.INFO
  )
  M.open(true)
end

-- === Expand / collapse all ===================================================
-- VS Code's toggle at the right of the outline's title bar: collapse all
-- while anything is expanded, else expand all. outline.nvim's
-- fold_toggle_all decides by the top level the same way.

local function any_expanded()
  local sidebar = package.loaded.outline and require("outline")._get_sidebar(false)
  local folding = require "outline.folding"
  for _, node in ipairs(sidebar and sidebar.items or {}) do
    if folding.is_foldable(node) and not folding.is_folded(node) then
      return true
    end
  end
  return false
end

function M.toggle_folds()
  require("outline")._sidebar_do "_toggle_all_fold"
end

-- For the side bar's title (configs/edgy.lua) and the right pane's winbar
function M.button()
  local icon = any_expanded() and "\u{eac5}" or "\u{eb95}" -- codicons collapse-all / expand-all
  return "%=%@v:lua.require'utils.outline_dock'.toggle_folds@ " .. icon .. " %X"
end

function M.winbar()
  return "%#WinBar# Outline" .. M.button()
end

function M.setup()
  local group = api.nvim_create_augroup("OutlineDock", { clear = true })

  api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "Outline",
    callback = function(ev)
      wanted = true
      opening = false
      -- The button follows the folds: redraw it whenever the outline changes
      api.nvim_buf_attach(ev.buf, false, {
        on_lines = function()
          vim.schedule(function()
            local win = vim.fn.bufwinid(ev.buf)
            if win ~= -1 then
              api.nvim__redraw { win = win, winbar = true }
            end
          end)
        end,
      })
      -- In the side bar edgy draws the title bar; in its own pane, ours
      vim.schedule(function()
        local win = vim.fn.bufwinid(ev.buf)
        if win ~= -1 and M.dock() == "right" then
          vim.wo[win].winbar = "%!v:lua.require'utils.outline_dock'.winbar()"
        end
      end)
      local win = restore_win
      restore_win = nil
      if win then
        vim.schedule(function()
          if api.nvim_win_is_valid(win) then
            api.nvim_set_current_win(win)
          end
        end)
      end
    end,
  })

  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      local ft = vim.bo[ev.buf].filetype
      if ft == "Outline" and not closing then
        wanted = false
      elseif ft == "NvimTree" and M.dock() == "left" then
        -- The Explorer went (Source Control, <C-b>): the outline goes with it
        vim.schedule(hide)
      end
    end,
  })

  -- The Explorer came back: so does the outline. BufWinEnter as well as
  -- FileType, as in utils/git_sidebar.lua: a hidden tree shown again doesn't
  -- re-fire FileType.
  api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
    group = group,
    callback = function(ev)
      if vim.bo[ev.buf].filetype ~= "NvimTree" then
        return
      end
      vim.schedule(function()
        if M.dock() == "left" and wanted and explorer_open() then
          local focus = focus_next
          focus_next = false
          open_now(focus)
        end
      end)
    end,
  })

  api.nvim_create_user_command("OutlineDock", function(opts)
    M.switch(opts.args ~= "" and opts.args or nil)
  end, {
    nargs = "?",
    complete = function()
      return { "left", "right" }
    end,
    desc = "Move the outline between the side bar and the right pane",
  })
end

return M
