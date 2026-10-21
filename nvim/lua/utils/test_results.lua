-- VS Code's "Test Results" panel: a tab in the bottom terminal pane
-- (utils/term.lua) that streams test output live while a run is going.
--
-- neotest's own output panel only gets output once a run has *finished*, so
-- this taps the process instead: neotest's "integrated" strategy (the one
-- every non-debug run uses) is wrapped so each test process it starts also
-- feeds its output_stream into our terminal buffer. A new run (one starting
-- while nothing else is running) gets a fresh, empty buffer in the same tab.
-- The tab comes to the front on every run; the cursor stays in the code.
-- Debug runs (strategy = "dap") aren't captured: dap-ui's REPL/Console
-- already show their output.
local api = vim.api

local M = {}

local buf ---@type integer? the Test Results terminal buffer
local chan ---@type integer? its nvim_open_term channel
local running = 0 -- test processes still streaming

local function valid()
  return buf ~= nil and api.nvim_buf_is_valid(buf) and chan ~= nil
end

-- nvim_open_term truncates lines to the width of the window it's created in,
-- so create it inside a throwaway editor-sized float (same trick as neotest's
-- lib.ui.open_term).
local function new_buffer()
  local b = api.nvim_create_buf(false, true)
  local float = api.nvim_open_win(b, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = vim.o.columns,
    height = math.max(vim.o.lines - 2, 1),
    style = "minimal",
    noautocmd = true,
  })
  local c = api.nvim_open_term(b, {})
  api.nvim_win_close(float, true)

  vim.bo[b].bufhidden = "hide" -- survive the pane being toggled shut
  vim.b[b].nvterm_label = "Test Results"
  -- q hides the pane (other tabs and these results stay for next time),
  -- <C-l> or the tab bar's Clear button empties it
  vim.keymap.set("n", "q", function()
    require("utils.term").hide()
  end, { buffer = b, nowait = true, desc = "Close Test Results" })
  vim.keymap.set("n", "<C-l>", function()
    M.clear()
  end, { buffer = b, desc = "Clear Test Results" })
  vim.b[b].nvterm_buttons = {
    { text = " " .. vim.fn.nr2char(0xeabf) .. " Clear ", click = "v:lua.require'utils.test_results'.clear" },
  }
  return b, c
end

--- Tailing ------------------------------------------------------------------

-- Like VS Code's output panels: every window showing the results follows new
-- output, until you scroll up (or move the cursor up in it) to read; getting
-- back to the bottom resumes following.
local paused = {} ---@type table<integer, boolean> window -> stopped following

-- Last non-blank line: a terminal buffer pads its screen with empty rows.
local function last_line()
  local n = api.nvim_buf_line_count(buf)
  local from = math.max(n - 300, 0)
  local lines = api.nvim_buf_get_lines(buf, from, n, false)
  for i = #lines, 1, -1 do
    if lines[i] ~= "" then
      return from + i
    end
  end
  return 1
end

local function at_bottom(win)
  local last = last_line()
  if vim.fn.line("w$", win) < last then
    return false
  end
  -- reading with the cursor inside the results window counts as scrolled up
  return win ~= api.nvim_get_current_win() or api.nvim_win_get_cursor(win)[1] >= last
end

local function tail()
  if not (buf and api.nvim_buf_is_valid(buf)) then
    return
  end
  local last = last_line()
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if not paused[win] then
      pcall(api.nvim_win_set_cursor, win, { last, 0 })
      pcall(api.nvim_win_call, win, function()
        vim.cmd "normal! zb" -- newest line at the bottom, no blank rows below
      end)
    end
  end
end

-- The terminal updates its buffer a moment after nvim_chan_send, so tail on
-- its own redraw schedule; bursts of output collapse into one tail.
local tail_pending = false
local function tail_soon()
  if tail_pending then
    return
  end
  tail_pending = true
  vim.defer_fn(function()
    tail_pending = false
    tail()
  end, 30)
end

-- Only re-judge the windows that moved: new output alone leaves a window
-- short of the bottom until tail() runs, which mustn't count as scrolling up.
local function judge(win)
  if buf and api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf then
    paused[win] = not at_bottom(win)
  end
end

local tail_group = api.nvim_create_augroup("TestResultsTail", { clear = true })
api.nvim_create_autocmd("WinScrolled", {
  group = tail_group,
  callback = function()
    for id in pairs(vim.v.event) do
      if id ~= "all" then
        judge(tonumber(id))
      end
    end
  end,
})
api.nvim_create_autocmd("CursorMoved", {
  group = tail_group,
  callback = function()
    judge(api.nvim_get_current_win())
  end,
})
api.nvim_create_autocmd("WinClosed", {
  group = tail_group,
  callback = function(ev)
    paused[tonumber(ev.match)] = nil
  end,
})

local function send(data)
  if valid() then
    pcall(api.nvim_chan_send, chan, data)
    tail_soon()
  end
end

-- Swap in a fresh, empty buffer: it takes the old one's tab slot and windows
-- (a terminal's scrollback can't be wiped in place), then the old one goes.
local function fresh_buffer(opts)
  local old = buf
  buf, chan = new_buffer()
  paused = {} -- starts out following
  if old and api.nvim_buf_is_valid(old) then
    -- deleting a buffer closes the windows showing it, so move them over first
    for _, win in ipairs(vim.fn.win_findbuf(old)) do
      pcall(api.nvim_win_set_buf, win, buf)
    end
  end
  require("utils.term").show(buf, { replace = old, enter = opts and opts.enter })
  if old and api.nvim_buf_is_valid(old) then
    pcall(api.nvim_buf_delete, old, { force = true })
  end
end

-- The command, on one line: some are huge (neotest-java's carries the whole
-- classpath) and would otherwise push the actual output out of the pane.
local function command_line(command)
  local cmd = tostring(command or "")
  if type(command) == "table" then -- a string one (neotest-dart) is shown as is
    local parts = vim.deepcopy(command)
    parts[1] = parts[1] and vim.fn.fnamemodify(parts[1], ":t")
    cmd = table.concat(parts, " ")
  end
  local max = math.max(vim.o.columns - 6, 40)
  if vim.fn.strchars(cmd) > max then
    cmd = vim.fn.strcharpart(cmd, 0, max - 1) .. "…"
  end
  return cmd
end

local function header(spec, context)
  local pos = context and context.position
  local cmd = command_line(spec.command)
  local lines = {}
  if pos then
    lines[#lines + 1] = ("\27[1m▶ %s\27[0m"):format(pos.name)
  end
  if cmd ~= "" then
    lines[#lines + 1] = ("\27[2m$ %s\27[0m"):format(cmd)
  end
  return table.concat(lines, "\r\n") .. "\r\n\r\n"
end

local function crlf(text)
  return (text:gsub("\r?\n", "\r\n"))
end

-- Some runners stream JSON events instead of plain output, one per line:
--   * `go test -json` (neotest-golang): test2json events; show their "Output"
--     text, which is what `go test -v` would print;
--   * `flutter test --reporter json` (neotest-dart): the program's print()s,
--     errors with stack traces, and a ✓/✗ line per finished test.
-- Returns a filter that turns raw chunks into what to display. Only a line
-- that starts with "{" is held back until it's complete, so ordinary output
-- (progress bars, prompts without a newline) still shows the moment it arrives.
local function json_unwrapper()
  local pending = ""
  local dart_names = {} ---@type table<integer, string> testID -> name

  local function dart_event(ev)
    if ev.type == "testStart" and type(ev.test) == "table" then
      dart_names[ev.test.id] = ev.test.name
    elseif ev.type == "print" and type(ev.message) == "string" then
      return crlf(ev.message .. "\n")
    elseif ev.type == "error" then
      return crlf(("\27[31m%s\27[0m\n%s\n"):format(tostring(ev.error), tostring(ev.stackTrace or "")))
    elseif ev.type == "testDone" and not ev.hidden then
      local name = dart_names[ev.testID] or "?"
      if ev.skipped then
        return ("\27[33m- %s (skipped)\27[0m\r\n"):format(name)
      elseif ev.result == "success" then
        return ("\27[32m✓ %s\27[0m\r\n"):format(name)
      end
      return ("\27[31m✗ %s\27[0m\r\n"):format(name)
    elseif ev.type == "done" then
      return ev.success and "\r\n\27[32mAll tests passed\27[0m\r\n" or "\r\n\27[31mSome tests failed\27[0m\r\n"
    end
    return ""
  end

  local function line_out(line)
    if line:sub(1, 1) == "{" then
      local ok, ev = pcall(vim.json.decode, (line:gsub("\r$", "")))
      if ok and type(ev) == "table" then
        if ev.Action then
          return type(ev.Output) == "string" and crlf(ev.Output) or ""
        elseif type(ev.type) == "string" then
          return dart_event(ev)
        end
      end
    end
    return line .. "\n"
  end
  return function(chunk)
    local text = pending .. chunk
    pending = ""
    local out = {}
    local start = 1
    while true do
      local nl = text:find("\n", start, true)
      if not nl then
        break
      end
      out[#out + 1] = line_out(text:sub(start, nl - 1))
      start = nl + 1
    end
    local rest = text:sub(start)
    if rest:sub(1, 1) == "{" then
      pending = rest
    else
      out[#out + 1] = rest
    end
    return table.concat(out)
  end
end

---@param process neotest.Process
local function stream(process, spec, context)
  local nio = require "nio"
  running = running + 1
  local first = running == 1
  local head = header(spec, context)
  vim.schedule(function()
    if first or not valid() then
      fresh_buffer()
    end
    send(head)
  end)

  -- The integrated strategy's output_stream() can wait forever once the
  -- process is gone (it only ends if the pty reported EOF), so stop reading
  -- half a second after the process completes.
  local done_at
  local function finished()
    while true do
      if process.is_complete() then
        done_at = done_at or vim.uv.now()
        if vim.uv.now() - done_at > 500 then
          return false
        end
      end
      nio.sleep(100)
    end
  end

  nio.run(function()
    local unwrap = json_unwrapper()
    local ok, err = pcall(function()
      local next_chunk = process.output_stream()
      while true do
        local data = nio.first { next_chunk, finished }
        if not data then
          break
        end
        data = unwrap(data)
        if data ~= "" then
          vim.schedule(function()
            send(data)
          end)
        end
      end
    end)
    vim.schedule(function()
      if not ok then
        send(("\r\n\27[31m[test output stream failed: %s]\27[0m\r\n"):format(err))
      end
      send "\r\n"
      running = math.max(running - 1, 0)
    end)
  end)
end

--- Wrap neotest's integrated strategy. Done through package.loaded so the
--- strategy keeps its name -- neotest still merges `strategies.integrated`
--- (pty width/height) from config, and `run.run_last` still matches.
function M.setup()
  local name = "neotest.client.strategies.integrated"
  local integrated = require(name)
  package.loaded[name] = function(spec, context)
    local process = integrated(spec, context)
    if process then
      stream(process, spec, context)
    end
    return process
  end
end

--- Empty the Test Results. A run that's still going keeps writing into the
--- new buffer.
function M.clear()
  if valid() then
    fresh_buffer { enter = api.nvim_get_current_buf() == buf }
  end
end

--- <leader>cTO: show the Test Results tab (and jump into it), or hide the
--- pane when it's already showing.
function M.toggle()
  local term = require "utils.term"
  if valid() and term.is_showing(buf) then
    term.hide()
    return
  end
  if not valid() then
    buf, chan = new_buffer()
    send "\27[2mNo test run yet.\27[0m\r\n"
  end
  term.show(buf, { enter = true })
end

return M
