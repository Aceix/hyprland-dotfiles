-- VS Code's empty editor: an editor window showing a blank, unnamed buffer
-- (the last file closed, :enew, the editor utils/layout.lua reopens) gets a
-- few shortcut hints drawn in its middle as virtual lines, the gutter hidden.
-- The buffer stays an ordinary empty buffer: typing, :e or a filetype in it
-- clears the hints and puts the gutter back.
local M = {}

local api = vim.api
local ns = api.nvim_create_namespace "EmptyState"

local function hints()
  if require("settings").vscode_keys then
    return {
      { "Show All Commands", { "Ctrl", "Shift", "P" } },
      { "Go to File", { "Ctrl", "P" } },
      { "Find in Files", { "Ctrl", "Shift", "F" } },
      { "Open Recent", { "Space", "f", "o" } },
      { "Toggle Explorer", { "Ctrl", "B" } },
      { "Toggle Terminal", { "Ctrl", "`" } },
    }
  end
  return {
    { "Find File", { "Space", "f", "f" } },
    { "Find in Files", { "Space", "f", "w" } },
    { "Open Recent", { "Space", "f", "o" } },
    { "Toggle Explorer", { "Ctrl", "N" } },
    { "Mappings", { "Space", "c", "h" } },
  }
end

local function is_empty(buf)
  local bo = vim.bo[buf]
  return api.nvim_buf_is_valid(buf)
    and bo.buflisted
    and bo.buftype == ""
    and bo.filetype == ""
    and not bo.modified
    and api.nvim_buf_get_name(buf) == ""
    and api.nvim_buf_line_count(buf) == 1
    and api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

local width_of = vim.fn.strdisplaywidth

-- Display width of a virtual line's chunks
local function chunks_width(chunks)
  local w = 0
  for _, chunk in ipairs(chunks) do
    w = w + width_of(chunk[1])
  end
  return w
end

-- One row: the label right-aligned to `label_w`, then the keys as keycaps
local function row(label, keys, label_w)
  local chunks = { { (" "):rep(label_w - width_of(label)) .. label, "EmptyStateLabel" }, { "   " } }
  for i, key in ipairs(keys) do
    if i > 1 then
      chunks[#chunks + 1] = { " + ", "EmptyStateDim" }
    end
    chunks[#chunks + 1] = { " " .. key .. " ", "EmptyStateKey" }
  end
  return chunks
end

local function draw(buf, win)
  local list = hints()
  local label_w = 0
  for _, h in ipairs(list) do
    label_w = math.max(label_w, width_of(h[1]))
  end
  local rows, block_w = {}, 0
  for i, h in ipairs(list) do
    rows[i] = row(h[1], h[2], label_w)
    block_w = math.max(block_w, chunks_width(rows[i]))
  end

  local width = api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if width < block_w then
    return -- too narrow: no hints rather than cut-off ones
  end

  local lines = {}
  -- Adds a line indented so a block `w` wide sits in the middle
  local function add(chunks, w)
    table.insert(chunks, 1, { (" "):rep(math.max(0, math.floor((width - (w or chunks_width(chunks))) / 2))) })
    lines[#lines + 1] = chunks
  end

  add { { vim.fn.fnamemodify(vim.fn.getcwd(), ":t"), "EmptyStateTitle" } }
  add { { "No file open", "EmptyStateDim" } }
  for _, chunks in ipairs(rows) do
    lines[#lines + 1] = { { "" } }
    add(chunks, block_w) -- the rows share one indent so their columns line up
  end

  -- Line 1 (the buffer's only line) takes the first row
  local top = math.max(0, math.floor((api.nvim_win_get_height(win) - #lines) / 2) - 1)
  for _ = 1, top do
    table.insert(lines, 1, { { "" } })
  end

  api.nvim_buf_set_extmark(buf, ns, 0, 0, { virt_lines = lines })
end

local function set_gutter(win, hide)
  if hide then
    if not vim.w[win].empty_state then
      vim.w[win].empty_state = true
      vim.wo[win][0].number = false
      vim.wo[win][0].relativenumber = false
      vim.wo[win][0].statuscolumn = ""
    end
  elseif vim.w[win].empty_state then
    vim.w[win].empty_state = nil
    vim.wo[win][0].number = vim.go.number
    vim.wo[win][0].relativenumber = vim.go.relativenumber
    vim.wo[win][0].statuscolumn = vim.go.statuscolumn
  end
end

local function refresh()
  local drawn = {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_config(win).relative == "" then
      local buf = api.nvim_win_get_buf(win)
      local empty = is_empty(buf)
      set_gutter(win, empty)
      if empty then
        -- A buffer shown twice is centred in its first window
        if not drawn[buf] then
          drawn[buf] = true
          draw(buf, win)
        end
      else
        api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      end
    end
  end
end

function M.setup()
  api.nvim_set_hl(0, "EmptyStateTitle", { link = "Title", default = true })
  api.nvim_set_hl(0, "EmptyStateLabel", { link = "Comment", default = true })
  api.nvim_set_hl(0, "EmptyStateDim", { link = "NonText", default = true })
  api.nvim_set_hl(0, "EmptyStateKey", { link = "Special", default = true })

  local group = api.nvim_create_augroup("EmptyState", { clear = true })
  local pending = false
  api.nvim_create_autocmd({
    "BufEnter",
    "BufWinEnter",
    "BufReadPost",
    "FileType",
    "TextChanged",
    "TextChangedI",
    "WinResized",
    "VimResized",
    "DirChanged",
  }, {
    group = group,
    callback = function()
      if pending then
        return
      end
      pending = true
      vim.schedule(function()
        pending = false
        refresh()
      end)
    end,
  })
end

return M
