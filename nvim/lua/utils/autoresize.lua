-- Golden-ratio auto-resize of the focused code split (<leader>uf toggles it).
-- Replaces focus.nvim, whose opt-out flags let any panel that hadn't set one
-- get squashed, and whose ratio was of the whole screen. Here:
--   * only code windows (a listed file buffer) ever grow or shrink; every
--     other window -- the side bar, terminal pane, Trouble, Outline, neotest,
--     chats, dap-ui, Diffview's file list -- keeps its size, no flag needed
--   * the ratio is of the space the code splits share in that row / column,
--     so the side bar and panels don't skew it
--   * window hops within one tick (plugins jumping around and back) coalesce
--     into a single resize of wherever the cursor ends up
local M = {}

local api = vim.api
local RATIO = 1.618

M.enabled = true

-- Code buffers that still shouldn't be resized like an editor split
local exclude_ft = { gitcommit = true }

-- "nowrite" is image.nvim's buftype for image files it displays
local function is_code_win(win)
  if api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  local buf = api.nvim_win_get_buf(win)
  local bt = vim.bo[buf].buftype
  return (bt == "" or bt == "nowrite") and vim.bo[buf].buflisted and not exclude_ft[vim.bo[buf].filetype]
end

--- Window ids under a winlayout() node.
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

local function has_code(node)
  return vim.iter(leaves(node)):any(is_code_win)
end

--- Innermost `kind` ("row" | "col") node holding `win`, and its child that does.
local function find(node, win, kind)
  if node[1] == "leaf" then
    return nil
  end
  for _, child in ipairs(node[2]) do
    if vim.tbl_contains(leaves(child), win) then
      local parent, mine = find(child, win, kind)
      if parent then
        return parent, mine
      end
      if node[1] == kind then
        return node, child
      end
      return nil
    end
  end
end

--- Screen cells a node spans along `axis` (1 = rows, 2 = columns).
local function extent(node, axis)
  local lo, hi = math.huge, 0
  for _, win in ipairs(leaves(node)) do
    local pos = api.nvim_win_get_position(win)[axis]
    local size = axis == 2 and api.nvim_win_get_width(win) or api.nvim_win_get_height(win)
    lo, hi = math.min(lo, pos), math.max(hi, pos + size)
  end
  return hi - lo
end

--- Pin every window in a subtree without code splits, so Neovim only trades
--- space between code splits. Returns the function that unpins them.
local function pin(layout)
  local saved = {}
  local function walk(node)
    if not has_code(node) then
      for _, win in ipairs(leaves(node)) do
        local o = { win = win, scope = "local" }
        saved[win] = { api.nvim_get_option_value("winfixwidth", o), api.nvim_get_option_value("winfixheight", o) }
        api.nvim_set_option_value("winfixwidth", true, o)
        api.nvim_set_option_value("winfixheight", true, o)
      end
    elseif node[1] ~= "leaf" then
      vim.iter(node[2]):each(walk)
    end
  end
  walk(layout)

  return function()
    for win, s in pairs(saved) do
      if api.nvim_win_is_valid(win) then
        local o = { win = win, scope = "local" }
        api.nvim_set_option_value("winfixwidth", s[1], o)
        api.nvim_set_option_value("winfixheight", s[2], o)
      end
    end
  end
end

--- Give `win` the golden share of the code splits beside it (kind "row") or
--- above / below it (kind "col"). No-op when it has no code sibling there.
local function fit(layout, win, kind)
  local parent = find(layout, win, kind)
  if not parent then
    return
  end
  local axis = kind == "row" and 2 or 1
  local free, count = -1, 0 -- -1: n code splits have n - 1 separators
  for _, child in ipairs(parent[2]) do
    if has_code(child) then
      free, count = free + extent(child, axis) + 1, count + 1
    end
  end
  if count < 2 then
    return
  end
  local size = math.floor(free / RATIO)
  if kind == "row" then
    api.nvim_win_set_width(win, size)
  else
    api.nvim_win_set_height(win, size)
  end
end

--- Run `fn` with the non-code windows pinned, keeping 'cmdheight' intact.
local function pinned(fn)
  local unpin = pin(vim.fn.winlayout())
  local cmdheight = vim.o.cmdheight
  pcall(fn)
  unpin()
  vim.o.cmdheight = cmdheight
end

function M.resize()
  local win = api.nvim_get_current_win()
  -- Diff splits stay side by side at equal width
  if not (M.enabled and is_code_win(win)) or vim.wo[win].diff then
    return
  end
  pinned(function()
    local layout = vim.fn.winlayout()
    fit(layout, win, "row")
    fit(layout, win, "col")
  end)
end

--- Share the space evenly between the code splits, panels untouched.
function M.equalise()
  pinned(function()
    vim.cmd "wincmd ="
  end)
end

function M.toggle()
  M.enabled = not M.enabled
  if M.enabled then
    M.resize()
  else
    M.equalise()
  end
  vim.notify("Auto-resize " .. (M.enabled and "on" or "off"))
end

function M.setup()
  local pending = false
  local function schedule()
    if pending then
      return
    end
    pending = true
    vim.schedule(function()
      pending = false
      M.resize()
    end)
  end

  local group = api.nvim_create_augroup("AutoResize", { clear = true })
  api.nvim_create_autocmd({ "WinEnter", "VimResized" }, { group = group, callback = schedule })
end

return M
