-- Where the symbol outline (outline.nvim) lives: its own pane on the right,
-- or VS Code's Outline section -- the bottom of the side bar, under the
-- Explorer (docked by configs/edgy.lua, height resizable). <leader>cO or
-- :OutlineDock switches; the choice is kept across restarts.
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

-- The outline's share of the side bar's height. edgy reads it via
-- configs/edgy.lua.
function M.height()
  return vim.g.OUTLINE_HEIGHT or 0.5
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
  require("outline.config").o.outline_window.position = M.dock()
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

function M.setup()
  local group = api.nvim_create_augroup("OutlineDock", { clear = true })

  api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "Outline",
    callback = function()
      wanted = true
      opening = false
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

  -- Dragging the line between the Explorer and the outline: edgy snaps
  -- heights it didn't set back to the view's size on WinResized, so record
  -- the new share first (this runs before edgy's handler, which loads on
  -- VeryLazy). Only once edgy has placed the outline -- while it is still
  -- being docked, or when the screen itself resizes, the heights are not a
  -- drag.
  local settled = {} ---@type table<integer, boolean>
  local lines = vim.o.lines

  -- The outline and Explorer windows when both are in the side bar
  local function pair()
    local outline, tree = find_win "Outline", find_win "NvimTree"
    if
      M.dock() == "left"
      and outline
      and tree
      and api.nvim_win_get_position(outline)[2] == api.nvim_win_get_position(tree)[2]
    then
      return outline, tree
    end
  end

  local function settle()
    local outline, tree = pair()
    if outline then
      local h = api.nvim_win_get_height(outline)
      local total = h + api.nvim_win_get_height(tree)
      -- edgy's sizing: floor(total * share)
      if h == math.floor(total * M.height()) then
        settled[outline] = true
      end
    end
  end

  api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function()
      if vim.o.lines ~= lines then
        lines = vim.o.lines
      else
        local outline, tree = pair()
        if outline and settled[outline] and vim.tbl_contains(vim.v.event.windows or {}, outline) then
          local h = api.nvim_win_get_height(outline)
          local share = h / (h + api.nvim_win_get_height(tree))
          vim.g.OUTLINE_HEIGHT = math.max(0.15, math.min(share, 0.85))
        end
      end
      vim.schedule(settle)
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      settled[tonumber(ev.match)] = nil
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
