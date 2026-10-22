-- Zen Mode for diffs: zen-mode.nvim floats a single window, so a diff would
-- lose its other half. Here every diff pane of the tab (both sides, or all of
-- diffview's merge editor) is floated over zen's backdrop, in the same
-- arrangement, centered and as wide as zen's width times the panes across.
-- The panes stay in their tab, so diffview's and the sidebar's keymaps still
-- work, and the floats follow along when those swap files or close the diff.
local M = {}

---@class DiffZenState
---@field bg integer backdrop float
---@field floats table<integer, integer> diff pane -> its float
---@field panes table<integer, integer> float -> its diff pane
---@field sig string signature() the floats were built for
---@field group integer
---@field tries integer settle() retries while diffview is busy
---@field force boolean rebuild even if the diff is unchanged (resize)
---@type DiffZenState?
local state
local building = false

local function is_float(win)
  return vim.api.nvim_win_get_config(win).relative ~= ""
end

local function is_ours(win)
  return state ~= nil and (win == state.bg or state.panes[win] ~= nil)
end

-- The tab's window layout with everything but the (non-float) diff panes
-- pruned out, splits left with one child collapsed into it
local function prune(node)
  if node[1] == "leaf" then
    return vim.wo[node[2]].diff and node or nil
  end
  local kids = {}
  for _, child in ipairs(node[2]) do
    table.insert(kids, prune(child))
  end
  if #kids == 0 then
    return nil
  end
  return #kids == 1 and kids[1] or { node[1], kids }
end

local function leaves(node, out)
  out = out or {}
  if node[1] == "leaf" then
    table.insert(out, node[2])
  else
    for _, child in ipairs(node[2]) do
      leaves(child, out)
    end
  end
  return out
end

-- How many panes sit side by side at most
local function across(node)
  if node[1] == "leaf" then
    return 1
  end
  local n = 0
  for _, child in ipairs(node[2]) do
    n = node[1] == "row" and n + across(child) or math.max(n, across(child))
  end
  return n
end

-- Screen extent of a subtree along one axis (true: columns)
local function extent(node, horiz)
  local lo, hi = math.huge, 0
  for _, win in ipairs(leaves(node)) do
    local pos = vim.api.nvim_win_get_position(win)
    local start = horiz and pos[2] or pos[1]
    local size = horiz and vim.api.nvim_win_get_width(win) or vim.api.nvim_win_get_height(win)
    lo, hi = math.min(lo, start), math.max(hi, start + size)
  end
  return hi - lo
end

-- Split rect between the subtree's panes in their original proportions. A
-- pane gets a right/bottom border when another pane follows on that side.
local function place(node, rect, out)
  if node[1] == "leaf" then
    out[node[2]] = rect
    return
  end
  local horiz = node[1] == "row"
  local kids = node[2]
  local sizes, total = {}, 0
  for i, child in ipairs(kids) do
    sizes[i] = extent(child, horiz)
    total = total + sizes[i]
  end
  local avail = horiz and rect.width or rect.height
  local offset = 0
  for i, child in ipairs(kids) do
    local size = i == #kids and avail - offset or math.floor(avail * sizes[i] / total + 0.5)
    local r = vim.deepcopy(rect)
    if horiz then
      r.col, r.width = rect.col + offset, size
      r.right = i < #kids or rect.right
    else
      r.row, r.height = rect.row + offset, size
      r.bottom = i < #kids or rect.bottom
    end
    place(child, r, out)
    offset = offset + size
  end
end

-- zen-mode's sizes: a number <= 1 is a fraction of max
local function resolve(max, value)
  return value <= 1 and math.floor(max * value) or math.min(value, max)
end

local function zen_window()
  local ok, config = pcall(require, "zen-mode.config")
  if not (ok and config.options) then
    return { width = 120, height = 1 }
  end
  config.colors() -- ZenBg: the colorscheme may have changed since setup
  return config.options.window
end

local function screen_height()
  local height = vim.o.lines - vim.o.cmdheight
  return vim.o.laststatus == 3 and height - 1 or height
end

-- Which buffer each diff pane of the tab shows: tells a changed diff from
-- a DiffUpdated after a mere edit
local function signature()
  local panes = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not is_float(win) and vim.wo[win].diff then
      table.insert(panes, win .. ":" .. vim.api.nvim_win_get_buf(win))
    end
  end
  return table.concat(panes, ",")
end

local function close_floats()
  if not state then
    return
  end
  building = true
  for _, float in pairs(state.floats) do
    pcall(vim.api.nvim_win_close, float, true)
  end
  pcall(vim.api.nvim_win_close, state.bg, true)
  building = false
end

---@param focus? integer original window to put the cursor in (default: current)
local function build(focus)
  local tree = prune(vim.fn.winlayout())
  if not tree then
    return false
  end
  focus = focus or vim.api.nvim_get_current_win()
  local window = zen_window()
  local lines = screen_height()
  local width = math.min(vim.o.columns, resolve(vim.o.columns, window.width) * across(tree))
  local height = resolve(lines, window.height)
  local rects = {}
  place(tree, {
    row = math.floor((lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
  }, rects)

  building = true
  local bg_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[bg_buf].bufhidden = "wipe"
  state.bg = vim.api.nvim_open_win(bg_buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = vim.o.columns,
    height = lines,
    focusable = false,
    style = "minimal",
    zindex = 30,
  })
  vim.wo[state.bg].winhighlight = "Normal:ZenBg"
  vim.wo[state.bg].winblend = 0

  state.floats, state.panes = {}, {}
  for win, r in pairs(rects) do
    local right, bottom = r.right and "│" or "", r.bottom and "─" or ""
    local corner = r.right and r.bottom and "┘" or right .. bottom
    local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
    -- opened from win, the float inherits its window options: 'diff', the
    -- binds, folds, winbar and the old side's 'winhighlight'
    local float = vim.api.nvim_win_call(win, function()
      return vim.api.nvim_open_win(vim.api.nvim_win_get_buf(win), false, {
        relative = "editor",
        row = r.row,
        col = r.col,
        width = math.max(1, r.width - (r.right and 1 or 0)),
        height = math.max(1, r.height - (r.bottom and 1 or 0)),
        border = { "", "", "", right, corner, bottom, "", "" },
        zindex = 40,
      })
    end)
    local winhl = vim.wo[win].winhighlight
    vim.wo[float].winhighlight = (winhl ~= "" and winhl .. "," or "")
      .. "NormalFloat:Normal,FloatBorder:WinSeparator"
    vim.wo[float].winblend = 0
    vim.api.nvim_win_call(float, function()
      vim.fn.winrestview(view)
    end)
    state.floats[win], state.panes[float] = float, win
  end
  building = false
  state.sig = signature()

  local _, first = next(state.floats)
  vim.api.nvim_set_current_win(state.floats[focus] or first)
  return true
end

-- The diff changed under the floats (another file, a pane closed, the diff
-- ended): float the new state, or leave zen when there's no diff left.
-- Debounced, and given a while to settle when diffview is in the middle of
-- switching files: it turns 'diff' off and passes through its file panel.
local timer = assert(vim.uv.new_timer())
local DELAY, TRIES = 30, 30

local settle

-- Try settle() again later if diffview may still be switching files
local function retry()
  local lib = package.loaded["diffview.lib"]
  if not (lib and lib.get_current_view() and state.tries < TRIES) then
    return false
  end
  state.tries = state.tries + 1
  timer:start(DELAY, 0, vim.schedule_wrap(settle))
  return true
end

function settle()
  if not state then
    return
  end
  local cur = vim.api.nvim_get_current_win()
  local focus = state.panes[cur]
  if not (focus or cur == state.bg or is_float(cur)) then
    if not vim.wo[cur].diff then
      return retry() or M.close() -- the cursor moved on to a non-diff window
    end
    focus = cur -- e.g. diffview focused a pane of the next file
  end
  local sig = signature()
  if sig == "" and retry() then
    return
  end
  state.tries = 0

  if sig == state.sig and not state.force then
    if state.floats[focus] and cur ~= state.floats[focus] then
      vim.api.nvim_set_current_win(state.floats[focus])
    end
    return
  end
  state.force = false
  close_floats()
  if not build(focus) then
    M.close()
  end
end

---@param resized? boolean rebuild even if the diff is unchanged
local function refresh(resized)
  if not building then
    state.force = state.force or resized == true
    timer:start(DELAY, 0, vim.schedule_wrap(settle))
  end
end

function M.open()
  if state then
    return
  end
  state = { floats = {}, panes = {}, tries = 0, force = false }
  if not build() then
    state = nil
    return vim.notify("No diff in this tab", vim.log.levels.WARN)
  end

  local group = vim.api.nvim_create_augroup("DiffZen", { clear = true })
  state.group = group
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      if not (is_ours(win) or is_float(win)) then -- pickers, notifications, ... are floats too
        refresh()
      end
    end,
  })
  -- :diffoff doesn't trigger OptionSet, but DiffUpdated
  vim.api.nvim_create_autocmd({ "BufWinEnter", "DiffUpdated" }, { group = group, callback = function() refresh() end })
  vim.api.nvim_create_autocmd("OptionSet", { group = group, pattern = "diff", callback = function() refresh() end })
  vim.api.nvim_create_autocmd("VimResized", { group = group, callback = function() refresh(true) end })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      if building then
        return
      end
      local win = tonumber(ev.match)
      if state.floats[win] then
        refresh() -- a diff pane closed: the rebuild drops its float
      elseif is_ours(win) then
        vim.schedule(M.close) -- :q in a float
      end
    end,
  })
  vim.api.nvim_create_autocmd("TabLeave", { group = group, callback = function() M.close() end })

  vim.keymap.set("n", "<Esc><Esc>", M.close, { desc = "Exit Zen Mode" })
end

function M.close()
  if not state then
    return
  end
  local back = state.panes[vim.api.nvim_get_current_win()]
  local view = vim.fn.winsaveview()
  timer:stop()
  pcall(vim.api.nvim_del_augroup_by_id, state.group)
  close_floats()
  state = nil
  pcall(vim.keymap.del, "n", "<Esc><Esc>")
  if back and vim.api.nvim_win_is_valid(back) then
    vim.api.nvim_set_current_win(back)
    vim.fn.winrestview(view)
    pcall(vim.cmd.syncbind)
  end
end

--- <leader>uz: both sides of a diff, otherwise plain Zen Mode
function M.toggle()
  if state then
    M.close()
  elseif vim.wo.diff and not is_float(0) then
    M.open()
  else
    vim.cmd "ZenMode"
  end
end

return M
