-- VS Code's Ctrl+Tab: a popup listing this tab page's tabs, most recently
-- used first.
--
-- VS Code commits when Ctrl is released, but a terminal never reports a key
-- release, so the popup is modal instead: Ctrl+Tab opens it on the previous
-- tab (Ctrl+Shift+Tab on the oldest), further presses / Tab / j / k / arrows
-- move the highlight, Enter or 1-9 open, Esc / q cancel. Nothing switches
-- until you confirm, so the order can't shift under you mid-walk.
local M = {}

local api = vim.api
local mru = {} -- bufnrs, most recent first
local ns = api.nvim_create_namespace "BufMru"

-- "nowrite" is image.nvim's buftype for image files it displays
local function is_code_buf(buf)
  if not (api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted) then
    return false
  end
  local bt = vim.bo[buf].buftype
  return bt == "" or bt == "nowrite"
end

local function forget(buf)
  for i, b in ipairs(mru) do
    if b == buf then
      table.remove(mru, i)
      return
    end
  end
end

local function touch(buf)
  if not is_code_buf(buf) then
    return
  end
  forget(buf)
  table.insert(mru, 1, buf)
end

local group = api.nvim_create_augroup("BufMru", { clear = true })

api.nvim_create_autocmd("BufEnter", {
  group = group,
  callback = function(ev)
    touch(ev.buf)
  end,
})

-- Closed tabs leave the list, so it only ever holds open buffers
api.nvim_create_autocmd("BufDelete", {
  group = group,
  callback = function(ev)
    forget(ev.buf)
  end,
})

-- Seed with buffers entered before this module loaded (NvChad requires
-- mappings in a vim.schedule), oldest first so the newest ends up in front.
local seen = vim.fn.getbufinfo { buflisted = 1 }
table.sort(seen, function(a, b)
  return a.lastused < b.lastused
end)
for _, info in ipairs(seen) do
  if info.lastused > 0 then
    touch(info.bufnr)
  end
end
touch(api.nvim_get_current_buf())

-- This tab page's tabs (tabufline's vim.t.bufs), most recent first; ones
-- never entered (e.g. opened from the command line) follow in tabline order.
local function snapshot()
  local tab_bufs, list, seen = vim.t.bufs or {}, {}, {}
  local in_tab = {}
  for _, b in ipairs(tab_bufs) do
    in_tab[b] = true
  end
  for _, b in ipairs(mru) do
    if in_tab[b] and is_code_buf(b) then
      list[#list + 1], seen[b] = b, true
    end
  end
  for _, b in ipairs(tab_bufs) do
    if not seen[b] and is_code_buf(b) then
      list[#list + 1] = b
    end
  end
  return list
end

-- One row per tab: icon, name, modified dot, then its directory dimmed (so
-- same-named files can be told apart).
local function render(list)
  local ok, devicons = pcall(require, "nvim-web-devicons")
  local lines, marks, width = {}, {}, 0
  for i, b in ipairs(list) do
    local path = api.nvim_buf_get_name(b)
    local name = path == "" and "[No Name]" or vim.fn.fnamemodify(path, ":t")
    local dir = path == "" and "" or vim.fn.fnamemodify(path, ":~:.:h")
    dir = dir == "." and "" or dir
    local icon, icon_hl = "󰈙", "Normal"
    if ok then
      local ic, hl = devicons.get_icon(name, nil, { default = true })
      icon, icon_hl = ic or icon, hl or icon_hl
    end
    local key = i <= 9 and tostring(i) or " "
    local mod = vim.bo[b].modified and " ●" or ""
    local head = (" %s  %s %s%s"):format(key, icon, name, mod)
    local line = dir == "" and head or head .. "  " .. dir
    lines[i] = line
    width = math.max(width, api.nvim_strwidth(line) + 1)
    local icon_col = #(" " .. key .. "  ")
    marks[i] = {
      { 1, 1 + #key, "Comment" },
      { icon_col, icon_col + #icon, icon_hl },
      { #head - #mod, #head, "DiagnosticWarn" },
      { #head, #line, "Comment" },
    }
  end
  return lines, marks, width
end

local popup -- { win, origin, list } while open

local function close()
  local p = popup
  popup = nil
  if p and api.nvim_win_is_valid(p.win) then
    api.nvim_win_close(p.win, true)
  end
  if p and api.nvim_win_is_valid(p.origin) then
    api.nvim_set_current_win(p.origin)
  end
end

local function open(idx)
  local p = popup
  if not p then
    return
  end
  local target = p.list[idx or api.nvim_win_get_cursor(p.win)[1]]
  close()
  if target and api.nvim_buf_is_valid(target) and target ~= api.nvim_get_current_buf() then
    require("nvchad.tabufline").goto_buf(target)
  end
end

local function move(dir)
  local p = popup
  local n = #p.list
  local row = api.nvim_win_get_cursor(p.win)[1]
  api.nvim_win_set_cursor(p.win, { (row - 1 + dir) % n + 1, 0 })
end

--- Open the switcher: 1 = start on the previous tab, -1 = on the oldest.
function M.cycle(dir)
  if popup then
    return move(dir)
  end

  local cur = api.nvim_get_current_buf()
  touch(cur)
  local list = snapshot()
  if #list < 2 then
    return
  end

  -- Leave Insert/Visual so we come back in Normal mode, as VS Code would
  local mode = api.nvim_get_mode().mode
  if mode:match "^[vV\22sS\19]" then
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  elseif mode:match "^i" then
    vim.cmd.stopinsert()
  end

  local lines, marks, width = render(list)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for i, row in ipairs(marks) do
    for _, m in ipairs(row) do
      if m[2] > m[1] then
        api.nvim_buf_set_extmark(buf, ns, i - 1, m[1], { end_col = m[2], hl_group = m[3] })
      end
    end
  end
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  width = math.min(math.max(width, 40), vim.o.columns - 4)
  local height = math.min(#list, math.max(vim.o.lines - 6, 1))
  local origin = api.nvim_get_current_win()
  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 5),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Open Tabs ",
    title_pos = "center",
    footer = " ⏎ open  esc cancel ",
    footer_pos = "center",
  })
  vim.wo[win].cursorline = true
  vim.wo[win].winhighlight = "CursorLine:PmenuSel,FloatBorder:FloatBorder"

  popup = { win = win, origin = origin, list = list }
  local start = dir == 1 and 2 or #list
  api.nvim_win_set_cursor(win, { start, 0 })

  local function bmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true })
  end
  for _, k in ipairs { "<C-Tab>", "<Tab>", "j", "<Down>", "<C-n>" } do
    bmap(k, function() move(1) end)
  end
  for _, k in ipairs { "<C-S-Tab>", "<S-Tab>", "k", "<Up>", "<C-p>" } do
    bmap(k, function() move(-1) end)
  end
  for _, k in ipairs { "<CR>", "<Space>", "l", "<2-LeftMouse>" } do
    bmap(k, function() open() end)
  end
  for _, k in ipairs { "<Esc>", "q", "<C-c>", "h" } do
    bmap(k, close)
  end
  for i = 1, math.min(#list, 9) do
    bmap(tostring(i), function() open(i) end)
  end

  -- Clicking or jumping elsewhere cancels, like VS Code losing focus
  api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      if popup and popup.win == win then
        popup = nil
        vim.schedule(function()
          if api.nvim_win_is_valid(win) then
            api.nvim_win_close(win, true)
          end
        end)
      end
    end,
  })
end

return M
