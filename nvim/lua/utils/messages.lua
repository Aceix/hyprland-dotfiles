-- All messages in one centered box: the notifications (fidget's history,
-- since it takes over vim.notify) and the command-line messages (:messages:
-- errors, echoes, print). Oldest first, cursor on the newest; q or <Esc>
-- closes it (utils/float_focus.lua).
local M = {}

local function notifications()
  local ok, fidget = pcall(require, "fidget.notification")
  if not ok then
    return {}
  end
  local history = fidget.get_history()
  table.sort(history, function(a, b)
    return a.last_updated < b.last_updated
  end)
  local lines = {}
  for _, item in ipairs(history) do
    local head = os.date("%H:%M:%S ", math.floor(item.last_updated))
      -- the group, unless it's the plain vim.notify one
      .. (item.group_name and item.group_name ~= "Notifications" and ("[" .. item.group_name .. "] ") or "")
      .. (item.annote and item.annote ~= "" and (item.annote .. ": ") or "")
    for i, line in ipairs(vim.split(vim.trim(item.message), "\n")) do
      lines[#lines + 1] = (i == 1 and head or (" "):rep(#head)) .. line
    end
  end
  return lines
end

function M.show()
  local lines, titles = {}, {}
  local function section(title, body)
    if #body > 0 then
      vim.list_extend(lines, #lines > 0 and { "" } or {})
      titles[#titles + 1] = #lines
      lines[#lines + 1] = title
      vim.list_extend(lines, body)
    end
  end
  section("Notifications", notifications())
  section("Messages", vim.split(vim.api.nvim_exec2("messages", { output = true }).output, "\n", { trimempty = true }))
  if #lines == 0 then
    return vim.notify "No messages"
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  for _, row in ipairs(titles) do
    vim.hl.range(buf, vim.api.nvim_create_namespace "messages_box", "Title", { row, 0 }, { row, -1 })
  end
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.min(#lines, math.floor(vim.o.lines * 0.8))
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = " Messages ",
    title_pos = "center",
  })
  vim.wo[win].wrap = true
  require("utils.float_focus").enter(win)
  vim.api.nvim_win_set_cursor(win, { #lines, 0 })
end

return M
