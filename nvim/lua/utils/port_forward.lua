-- VS Code's port forwarding for remote-nvim sessions: :RemoteForward 3000
-- makes the remote host's port 3000 reachable at http://localhost:3000 here,
-- e.g. to open a dev server in the local browser.
--
-- You type the command in the remote session, which runs on the remote
-- server, but the tunnel has to start on this machine. So the Neovim you
-- connected from keeps a plain socket to each server it opened (through the
-- session's own tunnel) and registers it there; the server sends requests
-- back over it. They are read as data only: a port number, checked, then
-- `ssh -N -L` with the session's own ssh binary and options. Nothing the
-- remote sends is ever run here, so a remote host still can't execute
-- anything on this machine.
local M = {}

local uv = vim.uv
local MAX_FORWARDS = 32

-- === Local side: the Neovim running remote-nvim ===============================

-- One per server this Neovim opened: { session, tcp }, by local tunnel port
local links = {}
-- Running tunnels: "<host>:<port>" -> { host, port, job, link }
local forwards = {}

local function valid_port(p)
  return type(p) == "number" and p == math.floor(p) and p >= 1 and p <= 65535
end

-- Runs `code` on the linked server (this side may already run code there)
local function send(link, code, ...)
  if link.tcp and not link.tcp:is_closing() then
    link.tcp:write(vim.mpack.encode { 2, "nvim_exec_lua", { code, { ... } } })
  end
end

-- Shows `msg` in the remote session, and here too when asked from here
local function tell(link, msg, level, here)
  level = level or vim.log.levels.INFO
  send(link, "local msg, level = ...; vim.notify(msg, level)", msg, level)
  if here then
    vim.notify(msg, level)
  end
end

-- The ports this server's host has forwarded, for :RemoteForward's list
local function push_state(link)
  local ports = {}
  for _, f in pairs(forwards) do
    if f.host == link.session.host then
      ports[#ports + 1] = f.port
    end
  end
  table.sort(ports)
  send(link, "require('utils.port_forward').set_state(...)", ports, link.session.host)
end

local function refresh_all(host)
  for _, link in pairs(links) do
    if link.session.host == host then
      push_state(link)
    end
  end
end

local function stop(key)
  local f = forwards[key]
  if f then
    forwards[key] = nil
    pcall(function()
      f.job:kill "sigterm"
    end)
  end
end

local function open(link, port, here)
  local s = link.session
  local key = s.host .. ":" .. port
  if forwards[key] then
    return tell(link, ("Port %d is already forwarded: http://localhost:%d"):format(port, port), nil, here)
  end
  if vim.tbl_count(forwards) >= MAX_FORWARDS then
    return tell(link, "Too many forwarded ports; stop some with :RemoteForwardStop", vim.log.levels.WARN, here)
  end

  local ex = s.executor or {}
  -- Same binary and options as the session's own connection (keys, jump
  -- hosts, ports); BatchMode since nobody here can answer a prompt
  -- exec: stopping the job then stops ssh itself, not just the shell
  local cmd = ("exec %s %s -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "
    .. "-o ConnectTimeout=10 -N -L 127.0.0.1:%d:localhost:%d %s"):format(
    ex.ssh_binary or "ssh",
    ex.ssh_conn_opts or "",
    port,
    port,
    vim.fn.shellescape(s.host)
  )
  local f = { host = s.host, port = port, link = link, here = here }
  local ok, job = pcall(vim.system, { "sh", "-c", cmd }, { text = true, stdin = false }, function(out)
    vim.schedule(function()
      local was = forwards[key] == f
      if was then
        forwards[key] = nil
      end
      if f.up and was then
        tell(f.link, ("Stopped forwarding port %d (ssh exited)"):format(port), vim.log.levels.WARN, f.here)
      elseif not f.up then
        local err = vim.trim(out.stderr or "")
        tell(f.link, ("Couldn't forward port %d%s"):format(port, err ~= "" and (":\n" .. err) or ""), vim.log.levels.ERROR, f.here)
      end
      refresh_all(s.host)
    end)
  end)
  if not ok then
    return tell(link, "Couldn't run ssh: " .. tostring(job), vim.log.levels.ERROR, here)
  end
  f.job = job
  forwards[key] = f

  -- ssh -N never says it's ready; a bind or auth failure exits well within this
  vim.defer_fn(function()
    if forwards[key] == f then
      f.up = true
      tell(f.link, ("Forwarding http://localhost:%d → %s:%d"):format(port, s.host, port), nil, f.here)
      refresh_all(s.host)
    end
  end, 1500)
end

-- What a server may ask for. Anything else is ignored.
local function on_request(link, action, port, here)
  if action == "open" and valid_port(port) then
    open(link, port, here)
  elseif action == "close" and valid_port(port) then
    if forwards[link.session.host .. ":" .. port] then
      stop(link.session.host .. ":" .. port)
      tell(link, ("Stopped forwarding port %d"):format(port), nil, here)
    else
      tell(link, ("Port %d isn't forwarded"):format(port), vim.log.levels.WARN, here)
    end
    refresh_all(link.session.host)
  elseif action == "close_all" then
    for key, f in pairs(forwards) do
      if f.host == link.session.host then
        stop(key)
      end
    end
    tell(link, "Stopped all forwarded ports", nil, here)
    refresh_all(link.session.host)
  end
end

--- Links the server at localhost:`port` (a remote-nvim SSH session) to this
--- Neovim, so :RemoteForward typed there can open tunnels here. Called on
--- every connect and reconnect (utils/remote.lua).
function M.link(session, port)
  port = tonumber(port)
  if not session or not session.host or not valid_port(port) then
    return
  end
  local old = links[port]
  if old and old.tcp and not old.tcp:is_closing() then
    old.tcp:close()
  end
  local link = { session = session }
  links[port] = link

  local tcp = assert(uv.new_tcp())
  link.tcp = tcp
  tcp:connect("127.0.0.1", port, function(err)
    if err then
      tcp:close()
      return
    end
    local unpack = vim.mpack.Unpacker()
    tcp:read_start(function(rerr, chunk)
      if rerr or not chunk then
        if not tcp:is_closing() then
          tcp:close()
        end
        return
      end
      local pos = 1
      while pos <= #chunk do
        local ok, msg, next_pos = pcall(unpack, chunk, pos)
        if not ok then -- not msgpack: drop the link rather than guess
          tcp:close()
          return
        end
        pos = next_pos
        if msg == nil then
          break
        end
        -- The answer to nvim_get_api_info below: { 1, 1, nil, { channel id, ... } }
        if type(msg) == "table" and msg[1] == 1 and msg[2] == 1 and type(msg[4]) == "table" then
          local chan = msg[4][1]
          if type(chan) == "number" then
            vim.schedule(function()
              send(link, "require('utils.port_forward').register(...)", chan, session.host)
              push_state(link)
            end)
          end
        -- Only notifications named port_forward: { 2, "port_forward", { action, port } }
        elseif type(msg) == "table" and msg[1] == 2 and msg[2] == "port_forward" and type(msg[3]) == "table" then
          local action, p = msg[3][1], msg[3][2]
          if type(action) == "string" then
            vim.schedule(function()
              on_request(link, action, p)
            end)
          end
        end
      end
    end)
    -- The server's id for this connection, so it knows where to send requests
    -- (Lua there can't tell which channel called it)
    tcp:write(vim.mpack.encode { 0, 1, "nvim_get_api_info", {} })
  end)
end

-- === Remote side: the server you type in ======================================

local launcher -- channel id of the Neovim that opened this server
local state = { ports = {}, host = nil }

--- Run by the connecting Neovim over its link (see M.link), with the id of
--- that link's channel here.
function M.register(chan, host)
  launcher = chan
  state.host = host
end

--- The connecting Neovim reports the forwarded ports after every change.
function M.set_state(ports, host)
  state.ports, state.host = ports, host
end

local function request(action, port)
  if not launcher or not pcall(vim.rpcnotify, launcher, "port_forward", action, port) then
    launcher = nil
    vim.notify(
      "Not linked to the Neovim this session was opened from. Reconnect the session (or reopen it from there) and try again.",
      vim.log.levels.WARN
    )
    return false
  end
  return true
end

-- In the Neovim running remote-nvim itself, act on a linked session directly
local function local_request(action, port)
  local list = vim.tbl_filter(function(l)
    return l.tcp and not l.tcp:is_closing()
  end, vim.tbl_values(links))
  if #list == 0 then
    return vim.notify("No connected remote session to forward ports from", vim.log.levels.WARN)
  end
  local function go(link)
    on_request(link, action, port, true)
  end
  if #list == 1 then
    return go(list[1])
  end
  vim.ui.select(list, {
    prompt = "Forward from which session?",
    format_item = function(l)
      return l.session.unique_host_id or l.session.host
    end,
  }, function(l)
    if l then
      go(l)
    end
  end)
end

local function dispatch(action, port)
  if require("utils.remote").is_remote then
    request(action, port)
  else
    local_request(action, port)
  end
end

-- Forwarded ports: as reported by the connecting Neovim on the remote side,
-- straight from the running tunnels here
local function ports()
  if require("utils.remote").is_remote then
    return state.ports, state.host
  end
  local out, host = {}, nil
  for _, f in pairs(forwards) do
    out[#out + 1], host = f.port, f.host
  end
  table.sort(out)
  return out, host
end

local function list()
  local open_ports, host = ports()
  if #open_ports == 0 then
    return vim.notify("No forwarded ports. :RemoteForward <port> forwards one.", vim.log.levels.INFO)
  end
  local lines = vim.tbl_map(function(p)
    return ("  http://localhost:%d → %s:%d"):format(p, host or "host", p)
  end, open_ports)
  vim.notify("Forwarded ports:\n" .. table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.setup()
  vim.api.nvim_create_user_command("RemoteForward", function(cmd)
    if cmd.args == "" then
      return list()
    end
    local port = tonumber(cmd.args)
    if not valid_port(port) then
      return vim.notify("Usage: :RemoteForward <port> (1-65535)", vim.log.levels.ERROR)
    end
    dispatch("open", port)
  end, { nargs = "?", desc = "Forward a remote port to localhost (no argument: list)" })

  vim.api.nvim_create_user_command("RemoteForwardStop", function(cmd)
    if cmd.args == "" then
      return dispatch("close_all")
    end
    local port = tonumber(cmd.args)
    if not valid_port(port) then
      return vim.notify("Usage: :RemoteForwardStop [port]", vim.log.levels.ERROR)
    end
    dispatch("close", port)
  end, {
    nargs = "?",
    desc = "Stop forwarding a port (no argument: all)",
    complete = function()
      return vim.tbl_map(tostring, (ports()))
    end,
  })

  vim.keymap.set("n", "<leader>rf", ":RemoteForward ", { desc = "Forward a remote port to local machine" })

  -- Don't leave tunnels running after Neovim exits
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("RemotePortForward", { clear = true }),
    callback = function()
      for key in pairs(forwards) do
        stop(key)
      end
    end,
  })
end

return M
