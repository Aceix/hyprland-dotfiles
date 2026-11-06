-- A single bottom terminal pane that holds any number of terminal buffers,
-- switched through a tab bar rendered in the pane's winbar -- the same idea as
-- tabufline, but for terminals, so shells never take a slot in the buffer line
-- (they're all `buflisted = false`).
--
-- The winbar doubles as the pane's top edge: it reuses the tabufline highlight
-- groups and trails off into a heavy rule, which is what visually separates the
-- terminal from the code window above it.
--
-- Like VS Code's panel, the bottom shows one view at a time: a list (a bottom
-- Trouble list -- Problems, quickfix, ... -- or the native quickfix / location
-- list window) takes the pane's place at the same height, maximized or not,
-- with the same tab bar, and showing a terminal again puts the pane back.

local api = vim.api

local M = {}

---@type { order: integer[], lists: string[], win: integer?, active: integer?, maximized: boolean, taken_down_by: integer? }
local state = {
  order = {}, -- terminal buffers, in tab order
  -- The lists' tabs, after the terminals': Problems always, then each list
  -- opened this session (by Trouble mode), until it's closed (q, :cclose, ...)
  lists = { "diagnostics" },
  win = nil, -- the bottom pane window
  active = nil, -- buffer currently shown in the pane
  maximized = false, -- panel blown up to full height, whatever tab; see M.toggle_height()
  -- (the panel's height, shared with Problems, is vim.g.PANEL_HEIGHT; see pane_height)
  -- Buffer that was on screen when the pane window went away by itself; see the
  -- TermClose/WinClosed pair at the bottom of this file.
  taken_down_by = nil,
}

local function is_term(buf)
  return buf ~= nil and api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal"
end

-- Drop terminals whose job has exited / buffer was wiped.
local function prune()
  local kept = {}
  for _, buf in ipairs(state.order) do
    if is_term(buf) then
      kept[#kept + 1] = buf
    end
  end
  state.order = kept

  if not is_term(state.active) then
    state.active = kept[#kept]
  end
end

local function index_in(list, value)
  for i, v in ipairs(list) do
    if v == value then
      return i
    end
  end
end

local function index_of(buf)
  return index_in(state.order, buf)
end

function M.is_open()
  return state.win ~= nil and api.nvim_win_is_valid(state.win)
end

local WINBAR = "%!v:lua.require'utils.term'.winbar()"

-- The mode of a list sharing the pane's slot, nil for any other window: a
-- bottom Trouble split (w:trouble; plugins/trouble.lua hands it to M.adopt) or
-- the native quickfix / location list window (adopted on BufWinEnter below),
-- which shares its tab with Trouble's view of the same list
local function list_mode(win)
  local t = vim.w[win].trouble
  local mode
  if type(t) == "table" then
    mode = t.type == "split" and t.position == "bottom" and t.mode or nil
  else
    local kind = vim.fn.win_gettype(win)
    mode = (kind == "quickfix" or kind == "loclist") and kind or nil
  end
  return mode == "quickfix" and "qflist" or mode
end

-- The lists on screen in this tab (one, unless just opened)
local function list_wins()
  return vim.tbl_filter(list_mode, api.nvim_tabpage_list_wins(0))
end

--- Whether `win` is the bottom panel: the terminal pane or a list.
function M.is_panel_win(win)
  return win == state.win or list_mode(win) ~= nil
end

-- A list's tab name; the ones not named here after their mode
-- (lsp_incoming_calls: "Incoming Calls")
local list_names = { diagnostics = "Problems", qflist = "Quickfix", loclist = "Location List", todo = "TODOs" }
function M.list_name(mode)
  local words = mode:gsub("^lsp_", ""):gsub("_", " ")
  return list_names[mode] or (words:gsub("%f[%w]%l", string.upper))
end

-- Item counts of the lists as Trouble last showed them (M.set_count), and
-- whether there are diagnostics (kept on DiagnosticChanged, below)
local counts = {} ---@type table<string, integer>
local has_diagnostics ---@type boolean?

function M.set_count(mode, n)
  counts[mode == "quickfix" and "qflist" or mode] = n
end

-- Whether a list has anything to show: one with nothing gets no tab, unless
-- it's the one on screen
local function has_items(mode)
  if mode == "diagnostics" then
    if has_diagnostics == nil then
      has_diagnostics = next(vim.diagnostic.count()) ~= nil
    end
    return has_diagnostics
  elseif mode == "qflist" then
    return vim.fn.getqflist({ size = 0 }).size > 0
  end
  return (counts[mode] or 0) > 0
end

-- The tabs in bar order: the terminals (buffers), then the lists with a tab
-- (modes); `shown` is the list on screen
local function tabs(shown)
  local ret = vim.list_slice(state.order)
  for _, mode in ipairs(state.lists) do
    if mode == shown or has_items(mode) then
      ret[#ret + 1] = mode
    end
  end
  return ret
end

-- Closes a list on its way out of the pane's slot (another tab shown), as
-- opposed to closed for good, which takes its tab with it (WinClosed below)
local function put_away(win)
  vim.w[win].nvterm_switch = true
  pcall(api.nvim_win_close, win, false)
end

--- Highlights ---------------------------------------------------------------

-- The tabs borrow tabufline's palette (base46's `tbline` integration: TbBufOn /
-- TbBufOff / TbFill), so they read as the same widget as the buffer line and
-- follow every theme switch for free. Only the rule is ours to derive.
local hl_key

--- Re-derive our highlights when tabufline's have changed under us. Called on
--- every winbar render, so it must be a no-op once settled -- calling
--- nvim_set_hl unconditionally mid-redraw would keep dirtying the screen.
function M.sync_highlights()
  local fill = api.nvim_get_hl(0, { name = "TbFill", link = false })
  local on = api.nvim_get_hl(0, { name = "TbBufOn", link = false })
  -- the active tab's *foreground*: the rule sits on TbFill's background, so an
  -- accent taken from a tab background would be invisible against it
  local accent = on.fg or api.nvim_get_hl(0, { name = "Directory", link = false }).fg

  local key = tostring(fill.bg) .. ":" .. tostring(accent)
  if key == hl_key then
    return
  end
  hl_key = key

  api.nvim_set_hl(0, "NvTermRule", { fg = accent, bg = fill.bg, bold = true })
end

--- Tab bar ------------------------------------------------------------------

local icon = {
  term = "", -- nf-oct-terminal
  new = "", -- nf-fa-plus
  output = vim.fn.nr2char(0xeb9d), -- codicon output, for named (non-shell) tabs
  problems = vim.fn.nr2char(0xea6c), -- codicon warning
  list = vim.fn.nr2char(0xeb17), -- codicon list-unordered, the other lists
}

-- Non-shell tabs (e.g. utils/test_results.lua's "Test Results") are terminal
-- buffers with no job behind them; they name themselves with `b:nvterm_label`.
local function is_named(buf)
  return type(vim.b[buf].nvterm_label) == "string"
end

-- Prefer the title the shell reports (OSC 0/2), fall back to the command name
-- baked into the `term://cwd//pid:cmd` buffer name.
local function label(buf)
  if is_named(buf) then
    return vim.b[buf].nvterm_label
  end
  local title = vim.b[buf].term_title
  if type(title) == "string" and title ~= "" then
    title = title:match "[^%s]+$" or title
    return vim.fn.fnamemodify(title, ":t")
  end

  local name = api.nvim_buf_get_name(buf):match "term://.*:(.*)$" or "term"
  return vim.fn.fnamemodify(name:match "^%S+" or name, ":t")
end

function M.winbar()
  prune()
  M.sync_highlights()

  local parts, used = {}, 0
  local win = vim.g.statusline_winid or api.nvim_get_current_win()
  local problems = list_mode(win)

  for i, buf in ipairs(state.order) do
    local text = string.format(" %s %d %s ", is_named(buf) and icon.output or icon.term, i, label(buf))
    local hl = not problems and buf == state.active and "%#TbBufOn#" or "%#TbBufOff#"
    -- a '%' in a shell-supplied title would otherwise be read as a statusline item
    local escaped = (text:gsub("%%", "%%%%"))
    parts[#parts + 1] = string.format("%s%%%d@v:lua.__nvterm_click@%s%%X", hl, buf, escaped)
    used = used + vim.fn.strwidth(text)
  end

  for i, mode in ipairs(state.lists) do
    if mode == problems or has_items(mode) then
      local text = (" %s %s "):format(mode == "diagnostics" and icon.problems or icon.list, M.list_name(mode))
      local hl = mode == problems and "%#TbBufOn#" or "%#TbBufOff#"
      parts[#parts + 1] = ("%s%%%d@v:lua.__nvterm_problems@%s%%X"):format(hl, i, text)
      used = used + vim.fn.strwidth(text)
    end
  end

  local new_btn = " " .. icon.new .. " "
  parts[#parts + 1] = "%#TbBufOff#%0@v:lua.__nvterm_new@" .. new_btn .. "%X"
  used = used + vim.fn.strwidth(new_btn)

  -- Buttons the active tab asks for, right-aligned like VS Code's panel
  -- actions: b:nvterm_buttons = { { text = " Clear ", click = "<func>" } },
  -- `click` being a %@ click function (e.g. "v:lua.require'mod'.fn").
  local buttons, buttons_w = {}, 0
  local wanted = not problems and state.active and vim.b[state.active].nvterm_buttons
  if type(wanted) == "table" then
    for _, btn in ipairs(wanted) do
      buttons[#buttons + 1] = ("%%#TbBufOff#%%@%s@%s%%X"):format(btn.click, btn.text)
      buttons_w = buttons_w + vim.fn.strwidth(btn.text)
    end
  end

  -- Heavy rule across the remaining width: the visible boundary with the code.
  local width = api.nvim_win_get_width(api.nvim_win_is_valid(win) and win or 0)
  parts[#parts + 1] = "%#NvTermRule#" .. string.rep("━", math.max(width - used - buttons_w, 0))
  vim.list_extend(parts, buttons)

  return table.concat(parts)
end

function _G.__nvterm_click(buf)
  M.focus(buf)
end

function _G.__nvterm_new()
  M.new()
end

--- Show the list `mode` (a Trouble mode) in the pane, focused: the one on
--- screen, else opened, which gives it a tab if it has none yet.
function M.open_list(mode)
  for _, win in ipairs(list_wins()) do
    if list_mode(win) == mode then
      return api.nvim_set_current_win(win)
    end
  end
  vim.cmd(("Trouble %s open focus=true"):format(mode))
end

-- A tab from tabs(): a terminal's buffer or a list's mode
local function show_tab(tab)
  if type(tab) == "number" then
    M.focus(tab)
  else
    M.open_list(tab)
  end
end

-- The i-th list in state.lists
function _G.__nvterm_problems(i)
  if state.lists[i] then
    M.open_list(state.lists[i])
  end
end

--- Pane ---------------------------------------------------------------------

-- The one height every tab gets: as tall as Neovim allows while maximized
-- (requests are clamped to the room there is), else the last one it was
-- resized to -- kept across restarts like the side bar's splits (an
-- upper-case g: var, which shada's '!' keeps; utils/sidebar_split.lua) --
-- else 30%
local function pane_height()
  if state.maximized then
    return vim.o.lines
  end
  return vim.g.PANEL_HEIGHT or math.max(10, math.floor(vim.o.lines * 0.3))
end

local function configure_win(win)
  local wo = vim.wo[win]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.cursorline = false
  wo.spell = false
  wo.winfixheight = true
  -- Split off the side bar, the pane inherits its options; edgy's winhighlight
  -- made utils/git_sidebar.lua "scrub" it, which dropped this winbar and
  -- 'winfixheight' and put the sign column back -- a resize of the shell
  wo.winfixwidth = false
  wo.winhighlight = ""
  wo.winbar = WINBAR
  wo.statuscolumn = "" -- (utils/fold_gutter.lua's would take a column)
  wo.fillchars = "eob: "
  -- The row separating the pane from the code above is drawn by the window
  -- *above*, so a window-local 'fillchars'/'winhighlight' here cannot thicken
  -- it -- the winbar's heavy rule is what makes the boundary stand out. To get
  -- the separator row itself heavy, it has to be global, in options.lua:
  --   vim.opt.fillchars:append { horiz = "━", horizup = "┻", horizdown = "┳" }
end

local function ensure_pane()
  state.taken_down_by = nil

  if M.is_open() then
    return state.win
  end

  -- One view at a time: the terminals replace a list
  for _, win in ipairs(list_wins()) do
    put_away(win)
  end

  vim.cmd("botright " .. pane_height() .. "split")
  state.win = api.nvim_get_current_win()
  configure_win(state.win)
  require("utils.layout").dock()

  return state.win
end

-- A "code window": holds a real, listed file buffer and isn't floating. This
-- deliberately excludes the pane itself and every plugin panel (nvim-tree,
-- Trouble, outline, quickfix, help, ...), none of which are 'buflisted'.
-- "nowrite" is image.nvim's buftype for image files it displays.
local function is_code_win(win)
  if not api.nvim_win_is_valid(win) or win == state.win then
    return false
  end
  if api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  local buf = api.nvim_win_get_buf(win)
  local bt = vim.bo[buf].buftype
  return (bt == "" or bt == "nowrite") and vim.bo[buf].buflisted
end

-- Where the cursor should land when the pane goes away: the window we came from
-- if it still qualifies, else the first code window in the tab, else nil (leave
-- it to Neovim).
local function pick_code_win()
  local prev = vim.fn.win_getid(vim.fn.winnr "#")
  if prev ~= 0 and is_code_win(prev) then
    return prev
  end
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if is_code_win(win) then
      return win
    end
  end
end

---@param keep_cursor? boolean leave the cursor where it is unless it's in the pane
local function close_pane(keep_cursor)
  local in_pane = M.is_open() and api.nvim_get_current_win() == state.win
  local target = M.is_open() and (in_pane or not keep_cursor) and pick_code_win() or nil

  if M.is_open() then
    api.nvim_win_close(state.win, false)
  end
  state.win = nil
  state.taken_down_by = nil

  -- Always leave the cursor in a code window, never on nvim-tree or a panel.
  if target and api.nvim_win_is_valid(target) then
    api.nvim_set_current_win(target)
  end
end

--- Public actions -----------------------------------------------------------

--- Moves the cursor to a code window (the previous one if it qualifies) when
--- it's in the pane or a plugin panel, so a buffer switch lands there instead.
--- Stays put when there's no code window to go to.
function M.focus_code_win()
  if is_code_win(api.nvim_get_current_win()) then
    return
  end
  local target = pick_code_win()
  if target then
    api.nvim_set_current_win(target)
  end
end

--- Open a brand new terminal as an extra tab in the pane, started in `cwd`
--- when given (the nvim-tree menu's "Open in Integrated Terminal").
---@param cwd? string
function M.new(cwd)
  local win = ensure_pane()
  api.nvim_set_current_win(win)

  if cwd then
    vim.cmd "enew"
    vim.fn.jobstart(vim.o.shell, { term = true, cwd = cwd })
  else
    vim.cmd "terminal"
  end

  local buf = api.nvim_get_current_buf()
  vim.bo[buf].buflisted = false -- keep shells out of tabufline
  vim.bo[buf].bufhidden = "hide" -- survive the pane being toggled shut

  state.order[#state.order + 1] = buf
  state.active = buf
  configure_win(win)
  vim.cmd "startinsert"
end

--- Show `buf` in the pane and jump to it.
function M.focus(buf)
  prune()
  if not is_term(buf) then
    return
  end

  local win = ensure_pane()
  api.nvim_win_set_buf(win, buf)
  state.active = buf
  configure_win(win)
  api.nvim_set_current_win(win)
  if not is_named(buf) then -- nothing to type into
    vim.cmd "startinsert"
  end
end

--- Add a named terminal buffer (b:nvterm_label set, see is_named) as a tab, or
--- put it in place of `opts.replace` when that's already a tab, and bring it
--- to the front. The cursor stays where it is unless `opts.enter`.
---@param opts? { replace?: integer, enter?: boolean }
function M.show(buf, opts)
  opts = opts or {}
  prune()
  if not is_term(buf) then
    return
  end

  local idx = index_of(opts.replace)
  if idx then
    state.order[idx] = buf
  elseif not index_of(buf) then
    state.order[#state.order + 1] = buf
  end

  local from = api.nvim_get_current_win()
  local win = ensure_pane()
  api.nvim_win_set_buf(win, buf)
  state.active = buf
  configure_win(win)
  if opts.enter then
    api.nvim_set_current_win(win)
  elseif api.nvim_win_is_valid(from) then
    api.nvim_set_current_win(from)
  end
end

--- Gives a list (just opened in `win`) the pane's place: same height and tab
--- bar, with the pane put away until a terminal is shown again. Called by
--- plugins/trouble.lua and for the native quickfix / location list below.
function M.adopt(win)
  local mode = list_mode(win)
  if mode and not index_in(state.lists, mode) then
    state.lists[#state.lists + 1] = mode
  end
  vim.wo[win].winbar = WINBAR
  vim.wo[win].winfixheight = true
  vim.wo[win].winfixwidth = false -- (Trouble's) it spans the editor column
  -- Sized before the old tab goes, and again after for the rows it freed
  -- (maximized). Sized only after, when the old tab was below it (a :lopen),
  -- Neovim's first resize came out a row too tall.
  api.nvim_win_set_height(win, pane_height())
  close_pane(true)
  for _, other in ipairs(list_wins()) do
    if other ~= win then
      put_away(other)
    end
  end
  -- Focused first, like a terminal tab: maximized, the current window keeps a
  -- text line under its winbar, so sized from the code it came out a row short
  api.nvim_set_current_win(win)
  api.nvim_win_set_height(win, pane_height())
  require("utils.layout").dock()
  -- Like any panel tab, it takes the cursor (Trouble's own default is to stay)
  vim.schedule(function()
    if api.nvim_win_is_valid(win) then
      api.nvim_set_current_win(win)
    end
  end)
end

--- Whether `buf` is one of the pane's tabs.
function M.owns(buf)
  return index_of(buf) ~= nil
end

--- The bottom panel's height: everything while maximized, else the last one it
--- was resized to (kept across restarts), else 30%.
M.height = pane_height

--- Whether `buf` is the tab currently on screen in the pane.
function M.is_showing(buf)
  return M.is_open() and api.nvim_win_get_buf(state.win) == buf
end

--- Hide the pane, keeping every tab.
function M.hide()
  close_pane()
end

--- Focus the pane if it's open but not current, hide it if it is, open it
--- (creating the first terminal on demand) if there's none.
function M.toggle()
  prune()

  if M.is_open() then
    if api.nvim_get_current_win() == state.win then
      close_pane()
    else
      api.nvim_set_current_win(state.win)
      if not is_named(api.nvim_win_get_buf(state.win)) then
        vim.cmd "startinsert"
      end
    end
    return
  end

  M.open_terminal()
end

--- Show the terminal tab last shown, starting a shell if there's none.
function M.open_terminal()
  prune()
  if state.active then
    M.focus(state.active)
  else
    M.new()
  end
end

--- Flip the panel between its default height and as tall as Neovim allows,
--- whichever tab is showing; it stays that way through tab switches (and
--- hiding), like VS Code's. Closed, it's opened (and focused) maximized.
--- 'winfixheight' only blocks *automatic* resizes, so an explicit height still
--- goes through.
function M.toggle_height()
  local win = M.is_open() and state.win or list_wins()[1]
  if win then
    state.maximized = not state.maximized
    api.nvim_win_set_height(win, pane_height())
  else
    state.maximized = true
    M.toggle()
  end
end

--- Cycle through the bottom panel's tabs, terminals then lists, from the
--- one shown in the current window; `step` is +1 / -1.
function M.cycle(step)
  prune()
  local mode = list_mode(api.nvim_get_current_win())
  local all = tabs(mode)
  if #all == 0 then
    return
  end
  local idx = index_in(all, mode or state.active) or 1
  local tab = all[(idx - 1 + step) % #all + 1]
  if tab ~= mode then
    show_tab(tab)
  end
end

-- The tab after `tab` (to its right, else its left) in `all`, to show when
-- `tab` closes
local function neighbour(all, tab)
  local i = index_in(all, tab)
  return i and (all[i + 1] or all[i - 1])
end

local editing = false -- the next native quickfix / location list stays one

--- The editable quickfix / location list (quicker.nvim) in place of
--- Trouble's view of it (its `e` key), for the list of window `win`.
---@param mode string Trouble's mode: "qflist" / "quickfix" or "loclist"
function M.edit_list(mode, win)
  if win and api.nvim_win_is_valid(win) then
    api.nvim_set_current_win(win)
  end
  editing = true
  local ok, err = pcall(vim.cmd, mode == "loclist" and "lopen" or "copen")
  if not ok then
    editing = false
    vim.notify(err, vim.log.levels.WARN)
  end
end

-- Drop a terminal's tab. On screen, the tab next to it (a list too) takes its
-- place, or the pane closes with the last tab.
local function remove(buf)
  local next_tab = neighbour(tabs(), buf)
  local shown = M.is_showing(buf) or state.taken_down_by == buf
  local idx = index_of(buf)
  if idx then
    table.remove(state.order, idx)
  end
  if state.active == buf then
    state.active = type(next_tab) == "number" and next_tab or nil
  end
  prune()

  if shown then
    if type(next_tab) == "number" and M.is_open() then
      api.nvim_win_set_buf(state.win, next_tab)
    elseif next_tab then
      -- (also when Neovim deleted this shell's buffer out from under us and
      -- the pane went with it)
      show_tab(next_tab)
    else
      close_pane()
    end
  end
  state.taken_down_by = nil

  if api.nvim_buf_is_valid(buf) then
    pcall(api.nvim_buf_delete, buf, { force = true })
  end
end

--- Kill the terminal in the current tab; the tab next to it takes its place.
function M.close()
  prune()

  if state.active then
    remove(state.active)
  else
    close_pane()
  end
end

--- Wiring -------------------------------------------------------------------

local group = api.nvim_create_augroup("NvTermPane", { clear = true })

-- base46 re-applies every highlight on a theme switch, which wipes ours.
api.nvim_create_autocmd("ColorScheme", {
  group = group,
  callback = function()
    vim.schedule(M.sync_highlights)
  end,
})

api.nvim_create_autocmd("User", {
  group = group,
  pattern = "NvThemeReload", -- what base46 actually fires after a theme switch
  callback = function()
    vim.schedule(M.sync_highlights)
  end,
})

-- The lists' tabs come and go with their items (has_items)
api.nvim_create_autocmd({ "DiagnosticChanged", "QuickFixCmdPost" }, {
  group = group,
  callback = function(args)
    if args.event == "DiagnosticChanged" then
      has_diagnostics = nil
    end
    for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
      if M.is_panel_win(win) then
        api.nvim__redraw { win = win, winbar = true }
      end
    end
  end,
})

-- A shell that exits takes its tab with it.
--
-- Neovim's own `nvim.terminal` TermClose autocmd deletes the buffer of a shell
-- that exits cleanly, and it is registered at startup so it runs before this
-- one -- by the time we get here the buffer is gone and the pane window with
-- it. `state.taken_down_by`, set by the WinClosed below, is what tells `remove`
-- to bring the pane back for the tabs that are still alive.
api.nvim_create_autocmd("TermClose", {
  group = group,
  callback = function(args)
    if index_of(args.buf) then
      vim.schedule(function()
        remove(args.buf)
      end)
    end
  end,
})

api.nvim_create_autocmd("WinClosed", {
  group = group,
  callback = function(args)
    local win = tonumber(args.match)
    if win ~= state.win then
      -- A list closed from inside it (q, :q, ...) loses its tab (Problems
      -- keeps its own while it has items), and the tab next to it takes its
      -- place. Not one put away for another tab, nor closed from elsewhere
      -- (:only, :cclose in the code): that one just goes off screen.
      local mode = win and list_mode(win)
      local inside = win == api.nvim_get_current_win() or vim.w[win].nvterm_close -- (plugins/trouble.lua)
      if mode and not vim.w[win].nvterm_switch and inside then
        local next_tab = neighbour(tabs(mode), mode)
        local i = mode ~= "diagnostics" and index_in(state.lists, mode)
        if i then
          table.remove(state.lists, i)
        end
        if next_tab then
          vim.schedule(function()
            show_tab(next_tab)
          end)
        end
      end
      return
    end

    -- Note which terminal was on screen: if the pane is going down as a side
    -- effect of that buffer being deleted, TermClose is about to follow and
    -- `remove` reopens the pane. A plain `:q` names a buffer no TermClose ever
    -- arrives for, so nothing is reopened.
    local ok, buf = pcall(api.nvim_win_get_buf, win)
    state.taken_down_by = ok and buf or nil
    state.win = nil
  end,
})

-- Only terminals live in the pane. A file opened into it (Telescope or :e from
-- the terminal, a plugin's "open in current window", ...) moves to a code
-- window, and the pane gets its terminal back; otherwise hiding the pane later
-- would close that file's window instead.
api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function(args)
    if api.nvim_get_current_win() ~= state.win or is_term(args.buf) then
      return
    end
    vim.schedule(function()
      -- (a new terminal's buffer isn't one yet when it enters)
      if not (M.is_open() and api.nvim_win_get_buf(state.win) == args.buf) or is_term(args.buf) then
        return
      end
      local cursor = api.nvim_win_get_cursor(state.win)
      local target = pick_code_win() or require("utils.layout").new_editor(args.buf)
      api.nvim_win_set_buf(target, args.buf)
      pcall(api.nvim_win_set_cursor, target, cursor)
      prune()
      if state.active then
        api.nvim_win_set_buf(state.win, state.active)
        configure_win(state.win)
      else
        close_pane()
      end
      api.nvim_set_current_win(target)
    end)
  end,
})

-- The native quickfix / location list window (:copen, :lopen, Telescope's
-- <C-q>, ...) is shown as Trouble's view of that list, like every other list,
-- unless asked for to edit it (M.edit_list); then it's a list tab itself.
-- Neovim re-enters its buffer on every list refresh (:make, :grep, ...) and a
-- few times per open, so only a window not marked yet is new. (A mark, not the
-- winbar: a split copies the winbar of the window it's split from, e.g. :copen
-- from Problems, but not w: variables.)
api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function(args)
    local win = api.nvim_get_current_win()
    if vim.bo[args.buf].buftype == "quickfix" and list_mode(win) then
      vim.schedule(function()
        if not api.nvim_win_is_valid(win) or vim.w[win].nvterm_list then
          return
        end
        vim.w[win].nvterm_list = true
        if editing then
          editing = false
          return M.adopt(win)
        end
        local mode = list_mode(win)
        -- (Trouble's location list is the one of the window it's opened from)
        local owner = mode == "loclist" and vim.fn.getloclist(win, { filewinid = 0 }).filewinid
        put_away(win)
        if owner and api.nvim_win_is_valid(owner) then
          api.nvim_set_current_win(owner)
        end
        vim.cmd(("Trouble %s open focus=true"):format(mode))
      end)
    end
  end,
})

-- Remember the bottom panel's height when it's resized (mouse drag, :resize),
-- for the next terminal or list shown there -- the only place it's recorded.
-- Not when it grew or shrank because a window opened or closed beside it (a
-- tab switch opens the new tab's window first, so the old one is briefly
-- taller), the screen changed size or the command line grew: a resize by
-- hand leaves all of those as they were. (Floats -- hovers, notifications,
-- completion menus -- reflow nothing, so they don't count.)
local layouts = {} ---@type table<integer, string> tab page -> its splits and the screen at the last resize
api.nvim_create_autocmd("WinResized", {
  group = group,
  callback = function()
    local tab = api.nvim_get_current_tabpage()
    local splits = vim.tbl_filter(function(win)
      return api.nvim_win_get_config(win).relative == ""
    end, api.nvim_tabpage_list_wins(tab))
    local layout = ("%s %dx%d %d"):format(table.concat(splits, " "), vim.o.lines, vim.o.columns, vim.o.cmdheight)
    local by_hand = layouts[tab] == layout
    layouts[tab] = layout
    if not by_hand or state.maximized then
      return
    end
    for _, win in ipairs(vim.v.event.windows or {}) do
      if api.nvim_win_is_valid(win) and M.is_panel_win(win) then
        local height = api.nvim_win_get_height(win)
        if height >= 3 then
          vim.g.PANEL_HEIGHT = height
        end
      end
    end
  end,
})

-- The pane's size only changes when you resize it or a window opens / closes
-- beside it: every resize reaches the program as SIGWINCH and full-screen apps
-- (Claude Code, htop, lazygit, ...) redraw on it, glitching or leaving stale
-- lines. (A winbar off/on "resync" used to run here on every Terminal mode
-- enter / leave to clean up after focus.nvim's resize-and-restore of the pane
-- on each window switch; both are gone.)
--
-- Unfocused, keep showing the live screen as the program goes on: Neovim
-- follows the output while the cursor is on the last line.
api.nvim_create_autocmd("TermLeave", {
  group = group,
  callback = function(args)
    vim.schedule(function()
      local win = state.win
      if M.is_showing(args.buf) and win ~= api.nvim_get_current_win() then
        api.nvim_win_set_cursor(win, { api.nvim_buf_line_count(args.buf), 0 })
      end
    end)
  end,
})

M.sync_highlights()

return M
