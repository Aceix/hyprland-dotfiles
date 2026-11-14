-- The Dev Container UI: this terminal's Neovim UI is handed to the
-- container's server with :connect (Neovim 0.12), and back when you leave.
-- One real TUI, no terminal inside Neovim, so every key (Ctrl+`, kitty's
-- extended keys) reaches the container.
--
--   open      the container's server learns this Neovim's address
--             (vim.g.devcontainer_return), then :connect hands it the UI
--   leave     <leader>rq / "Reopen Folder Locally" connect back
--             (devcontainer/init.lua); UIEnter here stops the container
--   close     :q there, closing the terminal, or the container going away
--             end the whole Neovim: the container reports "ui_gone" over the
--             port-forward link, or its session ends, and with no UI here
--             either this stops the containers and ends (end_here)
--
-- After a round trip this Neovim is no longer tied to the terminal it
-- started in, so it also ends itself when its last UI leaves later.
local api = vim.api
local core = require "devcontainer.core"

local M = {}

local notify = core.notify

-- The handed-off session; gone = the container said its UI left
local state = { session = nil, port = nil, gone = false, timer = nil, group = nil }
local idle = {}

local function ui_attached()
  return #api.nvim_list_uis() > 0
end

local function server(port)
  return "localhost:" .. port
end

-- Sends the UI from the container's server back here
local function call_back(port)
  return require("utils.remote").rpc_notify(
    server(port),
    "local addr = ...; vim.schedule(function() pcall(vim.cmd.connect, addr) end)",
    { vim.v.servername }
  )
end

function M.cancel_idle(session)
  local timer = session and idle[session.unique_host_id]
  if timer then
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
    idle[session.unique_host_id] = nil
  end
end

-- Stops a container left running without a UI after idle_shutdown_hours
function M.arm_idle(session)
  local hours = tonumber(core.config.idle_shutdown_hours) or 0
  if not session or hours <= 0 then
    return
  end
  M.cancel_idle(session)
  local id = session.unique_host_id
  local timer = assert(vim.uv.new_timer())
  idle[id] = timer
  timer:start(hours * 3600 * 1000, 0, vim.schedule_wrap(function()
    if idle[id] == timer then
      idle[id] = nil
    end
    pcall(timer.close, timer)
    notify(("Stopping Dev Container %s after %sh without a UI"):format(id, hours))
    require("devcontainer.runtime").stop { id = id, session = session }
  end))
end

-- Stops watching the handed-off session; returns it
local function finish()
  local session = state.session
  if state.timer and not state.timer:is_closing() then
    state.timer:stop()
    state.timer:close()
  end
  if state.group then
    pcall(api.nvim_del_augroup_by_id, state.group)
  end
  state.session, state.port, state.gone, state.timer, state.group = nil, nil, false, nil, nil
  return session
end

local function stop(session)
  require("devcontainer.runtime").stop { id = session.unique_host_id, session = session }
end

-- The UI came back: you left the container
local function on_return()
  local session = finish()
  if not session then
    return
  end
  if core.config.stop_on_close ~= false then
    stop(session)
  else
    notify(("Left Dev Container %s; it keeps running"):format(session.unique_host_id))
    M.arm_idle(session)
  end
end

-- No UI is here and none is coming back: end, as an embedded Neovim ends
-- with its terminal, leaving nothing running. Containers this Neovim started
-- are stopped first (even with stop_on_close off: nothing would be left to
-- stop them). Unsaved changes stay in swap files: SIGTERM keeps them, as
-- utils/remote.lua's keep_alive does; :qa! would delete them.
local function end_here()
  if ui_attached() then
    return
  end
  local rn = core.rn()
  for _, s in pairs(rn and rn.session_provider:get_all_sessions() or {}) do
    if s._devpod_workspace_active then
      pcall(function()
        vim.system(core.devpod_cmd(s, "stop", s.unique_host_id), { text = true }):wait(15000)
      end)
      s._devpod_workspace_active = false
    end
  end
  local unsaved = vim.iter(api.nvim_list_bufs()):any(function(b)
    return vim.bo[b].modified and vim.bo[b].buftype == ""
  end)
  if unsaved then
    pcall(vim.cmd, "silent! preserve")
    return vim.uv.kill(vim.fn.getpid(), "sigterm")
  end
  vim.cmd "qa!"
end

-- The UI went down with the container side (:q there, terminal closed,
-- container gone)
local function on_lost()
  finish()
  end_here()
end

-- Once this Neovim's UI has been away, closing its terminal later must still
-- end it (see the top); a UI briefly away during a handoff doesn't count
local function own_lifetime()
  if M._own_lifetime then
    return
  end
  M._own_lifetime = true
  api.nvim_create_autocmd("UILeave", {
    group = api.nvim_create_augroup("DevcontainerLifetime", { clear = true }),
    callback = function()
      vim.defer_fn(function()
        if not state.session and not ui_attached() then
          end_here()
        end
      end, 1500)
    end,
  })
end

-- Called over the port-forward link when the container's last UI left
function M.remote_ui_gone(session)
  if state.session == session then
    state.gone = true
  end
end

local function watch(session)
  state.group = api.nvim_create_augroup("DevcontainerHandoff", { clear = true })
  api.nvim_create_autocmd("UIEnter", {
    group = state.group,
    callback = function()
      vim.schedule(on_return)
    end,
  })
  -- The container's UI left without coming here, or its session ended:
  -- give a connect-back a moment before calling it lost
  local timer = assert(vim.uv.new_timer())
  state.timer = timer
  local pending = false
  timer:start(2000, 2000, vim.schedule_wrap(function()
    if state.timer ~= timer or pending or ui_attached() then
      return
    end
    if state.gone or not session:is_remote_server_running() then
      pending = true
      vim.defer_fn(function()
        pending = false
        if state.session == session and not ui_attached() then
          on_lost()
        end
      end, 1500)
    end
  end))
end

-- Stores this Neovim's address in the container's server, and confirms it:
-- a plain notification sent while that server is still starting can be
-- lost, and without it there's no way back. cb(ok); a few tries, 1s apart.
local function tell_return(port, cb, tries)
  tries = tries or 5
  local addr = vim.v.servername
  local expr = ("luaeval('(function(a) vim.g.devcontainer_return = a; return a end)(_A)', '%s')"):format(addr)
  local cmd = { vim.v.progpath, "--clean", "--headless", "--server", server(port), "--remote-expr", expr }
  local ok = pcall(vim.system, cmd, { text = true, timeout = 5000 }, function(out)
    vim.schedule(function()
      if vim.trim(out.stdout or "") == addr then
        return cb(true)
      elseif tries <= 1 then
        return cb(false)
      end
      vim.defer_fn(function()
        tell_return(port, cb, tries - 1)
      end, 1000)
    end)
  end)
  if not ok then
    cb(false)
  end
end

function M.is_open()
  return state.session ~= nil
end

function M.session()
  return state.session
end

-- Hands this Neovim's UI to the container's server at localhost:`port`
function M.open(port, workspace, session)
  if not port or not session then
    notify("Couldn't open the Dev Container UI: missing session or port", vim.log.levels.ERROR)
    return false
  end
  if state.session and state.session ~= session then
    notify(("The UI is already in Dev Container %s"):format(state.session.unique_host_id), vim.log.levels.WARN)
    return false
  end
  if not ui_attached() then
    return false -- headless: nothing to hand over
  end
  M.cancel_idle(session)
  state.session, state.port = session, port
  tell_return(port, function(ok)
    if state.session ~= session then
      return
    end
    if not ok or not ui_attached() then
      finish()
      return ok or notify(
        ("Couldn't reach Dev Container %s to open it"):format(workspace.host or session.unique_host_id),
        vim.log.levels.ERROR
      )
    end
    pcall(session.hide_progress_view_window, session)
    watch(session)
    own_lifetime()
    vim.cmd.connect(server(port))
  end)
  return true
end

-- Brings the UI back from the container (before a rebuild, stop or delete,
-- or it would go down with it); opts.stop also stops the container
function M.close(opts)
  opts = opts or {}
  local port = state.port
  local session = finish()
  if not session then
    return
  end
  if not ui_attached() and port then
    call_back(port)
    vim.wait(3000, ui_attached, 50)
  end
  if opts.stop then
    stop(session)
  end
end

function M.detach()
  if not state.session then
    return notify("No Dev Container is open", vim.log.levels.WARN)
  end
  M.close { stop = core.config.stop_on_close ~= false }
end

return M
