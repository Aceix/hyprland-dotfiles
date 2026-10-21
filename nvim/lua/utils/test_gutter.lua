-- VS Code-style "Run Test" gutter buttons on top of neotest.
--
-- neotest's own status consumer already draws a sign on every discovered test
-- and namespace (the ▶ icons set in configs/neotest.lua) and swaps it for
-- ✓/✗ once results come in. This module only adds the two missing pieces:
--   * a consumer that starts the neotest client as soon as neotest loads, so
--     the signs show up on open instead of after the first `<leader>cT` key;
--   * mouse handling: left-click on a sign runs that test, right-click opens
--     a Run / Debug / Output / Watch menu. Clicks anywhere else fall through
--     to the normal <LeftMouse>/<RightMouse> behaviour.
local M = {}

local sign_group = "neotest-status" -- neotest/consumers/status.lua

---@type table? neotest client handed to the consumer
local client

-- Width of the number column, which sits to the right of the sign column
local function number_width(win)
  local wo = vim.wo[win]
  if not (wo.number or wo.relativenumber) then
    return 0
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local digits = #tostring(vim.api.nvim_buf_line_count(buf))
  return math.max(wo.numberwidth, digits + 1)
end

-- The buffer line under a click on a neotest sign, or nil when the click
-- landed anywhere else.
local function clicked_test()
  local m = vim.fn.getmousepos()
  if m.winid == 0 or m.line == 0 or not vim.api.nvim_win_is_valid(m.winid) then
    return
  end
  local info = vim.fn.getwininfo(m.winid)[1]
  if
    not info
    or m.wincol > info.textoff - number_width(m.winid)
    or m.wincol <= require("utils.fold_gutter").width(m.winid)
  then
    return -- text area, line numbers or fold chevrons
  end
  local buf = vim.api.nvim_win_get_buf(m.winid)
  local placed = vim.fn.sign_getplaced(buf, { group = sign_group, lnum = m.line })[1]
  if not placed or #placed.signs == 0 then
    return
  end
  return { buf = buf, win = m.winid, line = m.line }
end

-- Resolves the test/namespace declared on `hit.line` and calls `fn(pos)` with
-- its neotest position data. Runs inside nio since client lookups are async.
local function with_position(hit, fn)
  if not client then
    return
  end
  local path = vim.api.nvim_buf_get_name(hit.buf)
  require("nio").run(function()
    local adapter = client:get_adapter(path)
    local tree = adapter and client:get_position(path, { adapter = adapter })
    if not tree then
      return
    end
    for _, node in tree:iter_nodes() do
      local pos = node:data()
      if pos.type ~= "file" and pos.range and pos.range[1] == hit.line - 1 then
        vim.schedule(function()
          fn(pos)
        end)
        return
      end
    end
  end)
end

local actions = {
  {
    label = "Run Test",
    fn = function(pos)
      require("neotest").run.run(pos.id)
    end,
  },
  {
    label = "Debug Test",
    fn = function(pos)
      require("neotest").run.run { pos.id, strategy = "dap" }
    end,
  },
  {
    label = "Show Output",
    fn = function(pos)
      require("neotest").output.open { position_id = pos.id, enter = true, auto_close = true }
    end,
  },
  {
    label = "Watch Test (rerun on save)",
    fn = function(pos)
      require("neotest").watch.toggle(pos.id)
    end,
  },
  {
    label = "Run All Tests in File",
    fn = function(pos)
      require("neotest").run.run(pos.path)
    end,
  },
  {
    label = "Stop Running Tests",
    fn = function()
      require("neotest").run.stop()
    end,
  },
}

local function on_left()
  local hit = clicked_test()
  if hit then
    vim.schedule(function()
      with_position(hit, actions[1].fn)
    end)
  end
  return "<LeftMouse>" -- still move the cursor there
end

local function on_right()
  local hit = clicked_test()
  if not hit then
    return require("utils.tree_menu").right_click()
  end
  vim.schedule(function()
    with_position(hit, function(pos)
      vim.ui.select(actions, {
        prompt = pos.name,
        format_item = function(a)
          return a.label
        end,
      }, function(choice)
        if choice then
          choice.fn(pos)
        end
      end)
    end)
  end)
  return "<LeftMouse>"
end

--- neotest consumer (registered as `consumers.test_gutter` in
--- configs/neotest.lua). Starting the client here makes it discover the
--- buffers already open, which is what draws the signs.
function M.consumer(c)
  client = c
  require("nio").run(function()
    client:get_adapters()
  end)

  for _, mode in ipairs { "n", "i" } do
    vim.keymap.set(mode, "<LeftMouse>", on_left, { expr = true, desc = "Run test from gutter" })
    vim.keymap.set(mode, "<RightMouse>", on_right, { expr = true, desc = "Test actions menu from gutter" })
  end
  return {}
end

return M
