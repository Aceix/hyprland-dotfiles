-- Helpers for remote-nvim.nvim (plugins/remote-nvim.lua).
--
-- Two sides to this:
-- * Server side: remote-nvim copies this config to the remote host and runs
--   it there. `is_remote` lets the statusline badge and configs/lazy.lua (which
--   switches off local-only plugins) know they're running on that remote.
-- * Client side: `open_client` opens the local `nvim --remote-ui` in a new tab
--   of the terminal running this nvim, like VS Code's new remote window.

local M = {}

-- remote-nvim starts the server with
-- XDG_CONFIG_HOME=~/.remote-nvim/workspaces/<id>/.config
M.is_remote = (vim.env.XDG_CONFIG_HOME or ""):find("/.remote-nvim/", 1, true) ~= nil

-- remote-nvim starts the server with `--listen 0.0.0.0:<port>`, so anyone who
-- can reach the remote host could connect to it, and an nvim server runs any
-- command it's sent. The SSH tunnel only needs loopback, so rebind there.
local function listen_local_only()
  local addr = vim.v.servername
  local port = M.is_remote and addr:match "^0%.0%.0%.0:(%d+)$"
  if port and vim.fn.serverstop(addr) == 1 then
    vim.fn.serverstart("127.0.0.1:" .. port)
  end
end

-- A server with no client for this long shuts itself down, so ones nobody
-- comes back to don't pile up on the host (see keep_alive below).
M.idle_shutdown_hours = 24

-- "42s", "3m 05s", "2h 14m"
local function duration(ms)
  local s = math.floor(ms / 1000)
  if s < 60 then
    return s .. "s"
  elseif s < 3600 then
    return ("%dm %02ds"):format(math.floor(s / 60), s % 60)
  end
  return ("%dh %02dm"):format(math.floor(s / 3600), math.floor(s % 3600 / 60))
end

-- Timeline of drops and reconnects, to see what happened when one goes wrong:
-- :e ~/.local/state/nvim/remote-reconnect.log (kept under ~256 KB)
local log_path = vim.fn.stdpath "log" .. "/remote-reconnect.log"
local function log(fmt, ...)
  local line = os.date "%Y-%m-%d %H:%M:%S " .. fmt:format(...)
  local stat = vim.uv.fs_stat(log_path)
  if stat and stat.size > 256 * 1024 then
    pcall(vim.uv.fs_rename, log_path, log_path .. ".1")
  end
  pcall(vim.fn.writefile, { line }, log_path, "a")
end

-- Through fidget when it's there (lazy-loads it), else a plain notification
local function notify(msg, level, annote)
  local ok, fidget = pcall(require, "fidget")
  if ok and fidget.notify then
    fidget.notify(msg, level, { annote = annote, key = "remote-nvim" })
  else
    vim.notify(msg, level)
  end
end

-- Servers launched by socket_launch outlive their SSH connection (laptop
-- sleep, network change) so the client can reattach. Such a server records
-- its pid for the launch script, and quits once it has had no client for
-- idle_shutdown_hours: cleanly when nothing is unsaved, otherwise by SIGTERM,
-- which leaves swap files to recover the unsaved changes from.
local function keep_alive(dir)
  vim.fn.writefile({ tostring(vim.fn.getpid()) }, dir .. "/pid")

  local timer = assert(vim.uv.new_timer())
  local function shut_down()
    if #vim.api.nvim_list_uis() > 0 then
      return
    end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].modified then
        pcall(vim.cmd, "silent! preserve")
        vim.uv.kill(vim.fn.getpid(), "sigterm")
        return
      end
    end
    vim.cmd "qa!"
  end
  local function arm()
    timer:stop()
    if #vim.api.nvim_list_uis() == 0 then
      timer:start(M.idle_shutdown_hours * 3600 * 1000, 0, vim.schedule_wrap(shut_down))
    end
  end
  -- Coming back to the session (reconnect after a drop, or a later
  -- :RemoteStart) says how long it ran without you
  local away_since
  local group = vim.api.nvim_create_augroup("RemoteKeepAlive", { clear = true })
  vim.api.nvim_create_autocmd("UIEnter", {
    group = group,
    callback = function()
      arm()
      local away = away_since and vim.uv.now() - away_since
      away_since = nil
      if away and away > 3000 then
        -- once the client has drawn its first screen
        vim.defer_fn(function()
          notify(("Reconnected · the session kept running for %s"):format(duration(away)), vim.log.levels.INFO, M.label())
        end, 800)
      end
    end,
  })
  vim.api.nvim_create_autocmd("UILeave", {
    group = group,
    callback = vim.schedule_wrap(function()
      if #vim.api.nvim_list_uis() == 0 then
        away_since = vim.uv.now()
      end
      arm()
    end),
  })
  arm()
end

-- Called first thing from init.lua, before the plugin's tunnel connects.
-- No-op unless this is a remote-nvim server.
function M.server_init()
  listen_local_only()
  if M.is_remote and vim.env.RNVIM_DIR then
    keep_alive(vim.env.RNVIM_DIR)
  end
end

-- remote-nvim keeps one progress window per host and reuses it on reconnect.
-- If its buffers get deleted in between (:q makes nui unmount the popup;
-- :bd or a buffer-close mapping wipes it outright), the next connect fails
-- with "Invalid buffer id" until Neovim restarts. So unmount only hides, and
-- a run that finds a dead buffer rebuilds the view first. Session info is
-- re-added on every launch, so nothing is lost.
function M.keep_progress_view()
  local ProgressView = require "remote-nvim.ui.progressview"
  local valid = vim.api.nvim_buf_is_valid

  local init = ProgressView.init
  function ProgressView:init(...)
    init(self, ...)
    local pv = self.progress_view
    pv.destroy = pv.unmount -- nui's real teardown, used when rebuilding below
    pv.unmount = pv.hide
  end

  -- Tear the view down fully (windows, border, augroups, any buffer still
  -- alive), so a rebuild doesn't leak the previous one, and build it afresh.
  function ProgressView:rebuild()
    local pv = self.progress_view
    pcall(pv.destroy, pv)
    for _, buf in ipairs { self.help_pane_bufnr, self.session_info_pane_bufnr } do
      if valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    self:init()
  end

  local start_run = ProgressView.start_run
  function ProgressView:start_run(...)
    local pv = self.progress_view
    if not (pv.bufnr and valid(pv.bufnr) and valid(self.help_pane_bufnr) and valid(self.session_info_pane_bufnr)) then
      self:rebuild()
    end
    return start_run(self, ...)
  end
end

-- Runs the server relaunch of a reconnect. In a *fresh* progress view: adding
-- the relaunch's steps to the tree left by the earlier launch corrupts nui's
-- node chain (its render then loops forever and this Neovim hangs, taking the
-- client tab with it). The window stays hidden; :RemoteInfo shows it.
local function relaunch(s, title)
  s.progress_viewer:rebuild()
  s.progress_viewer:start_run(title)
  s:_run_code_in_coroutine(function()
    s:_launch_remote_neovim_server()
  end, "Reconnecting to " .. s.host)
end

-- remote-nvim always starts the remote server on TCP, which has no auth: any
-- user on that host can connect to the port and run commands as you. So on
-- SSH hosts, rewrite the launch to listen on a Unix socket in a 0700 folder
-- of your own and tunnel to that instead; only you (and root) can reach it.
-- Windows hosts, hosts that refuse socket forwarding (remembered in
-- tcp_hosts_file), and launch commands this doesn't recognise keep TCP.
--
-- These socket servers also survive the connection: when SSH drops (laptop
-- sleep, network change) the server keeps running, and the client tab
-- (client_script) reattaches through a fresh tunnel. The folder is fixed per
-- workspace (~/.remote-nvim/run/<id>), which is how a relaunch finds the
-- server that is still running and reuses it instead of starting another.
local tcp_hosts_file = vim.fn.stdpath "data" .. "/remote-nvim-tcp-hosts.json"
local LAUNCH_DESC = "Launching Neovim server on the remote machine"
M.READY = "rnvim-socket-ready"
M.REUSED = "rnvim-reused"

-- Notice a dead connection within ~30s of waking up, and don't hang on a
-- network that isn't back yet
local SSH_OPTS = "-o ServerAliveInterval=10 -o ServerAliveCountMax=3 -o ConnectTimeout=10"

local function read_json(path)
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  end)
  return ok and type(data) == "table" and data or {}
end

-- Rewrites remote-nvim's launch command and ssh options to serve from the
-- socket in `dir` (an absolute path on the remote). Returns nil when the
-- command isn't the shape this expects (e.g. after a plugin update), in which
-- case the caller leaves it alone.
function M.socket_launch(cmd, conn_opts, dir)
  local lport = conn_opts:match "^%-t %-L (%d+):localhost:%d+$"
  if not lport or not cmd:find "%-%-listen 0%.0%.0%.0:%d+ " or dir:find "[^%w/._-]" then
    return nil
  end
  local sock = dir .. "/s"

  local inner = cmd:gsub("%-%-listen 0%.0%.0%.0:%d+ ", "--listen " .. sock .. " ")
  -- The whole thing goes inside sh -c '...', so the only single quotes allowed
  -- are remote-nvim's optional --cmd ':cd <dir>', turned into double quotes.
  inner = inner:gsub("%-%-cmd ':cd ([^'\"$`\\]*)'$", '--cmd ":cd %1"')
  if inner:find("'", 1, true) then
    return nil
  end

  -- sh, not the login shell (which may be fish), runs it:
  --  * the folder must be ours and not a symlink, so nobody can plant it;
  --  * a server already running there (its pid is alive, see keep_alive) is
  --    reused; otherwise one starts in a session of its own (setsid, or perl
  --    where there's none), so the hangup when SSH drops never reaches it;
  --  * READY tells secure_launch the socket is up; then the script stays
  --    until the server exits, keeping the tunnel open, and exits 0 then.
  local script = table.concat({
    "umask 077",
    ("d=%s; s=$d/s"):format(dir),
    'mkdir -p "$d" && chmod 700 "$d" && [ -O "$d" ] && [ ! -L "$d" ] || exit 1',
    'alive() { [ -S "$s" ] && [ -f "$d/pid" ] && kill -0 "$(cat "$d/pid")" 2>/dev/null; }',
    -- After a silent drop sshd may not notice for hours, leaving the previous
    -- launcher and its connection behind, and that connection's tunnel keeps
    -- the dead client attached to the server, which then buffers screen
    -- updates for it. If that pid is still our launcher, end the sshd it runs
    -- under (the per-connection one, ours; this closes its tunnel) and it.
    'o=$(cat "$d/launcher" 2>/dev/null); if [ -n "$o" ] && ps -o args= -p "$o" 2>/dev/null | grep -qF "$d"; then '
      .. 'p=$o; for i in 1 2 3 4; do p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d " "); '
      .. '{ [ -z "$p" ] || [ "$p" -le 1 ]; } && break; '
      .. 'case "$(ps -o comm= -p "$p" 2>/dev/null)" in *sshd*) kill "$p" 2>/dev/null; break;; esac; done; '
      .. 'kill "$o" 2>/dev/null; fi',
    'echo $$ > "$d/launcher"',
    "if command -v setsid >/dev/null 2>&1; then ds() { setsid \"$@\"; }; "
      .. 'else ds() { perl -MPOSIX -e "POSIX::setsid(); exec @ARGV" "$@"; }; fi',
    ("if alive; then echo %s; else "):format(M.REUSED)
      .. 'rm -f "$s" "$d/pid"; '
      .. ('ds env RNVIM_DIR="$d" %s </dev/null >/dev/null 2>&1 & '):format(inner)
      .. "i=0; while ! alive && [ $i -lt 300 ]; do sleep 0.1; i=$((i+1)); done; fi",
    "alive || exit 1",
    "echo " .. M.READY,
    "while alive; do sleep 2; done",
  }, "; ")

  return ("sh -c '%s'"):format(script), ("-t %s -L %s:%s"):format(SSH_OPTS, lport, sock)
end

-- Socket sessions by short id (a hash of the workspace id), for reattach()
local sessions = {}

-- Runs `code` (with `args` as ...) on the server at `addr`, fire-and-forget.
-- Never a request: one through a tunnel that died silently would wait for an
-- answer forever and hang this Neovim. Connecting is instant either way (ssh
-- owns the local port); the channel closes once the message has gone out.
local function rpc_notify(addr, code, args)
  local ok, ch = pcall(vim.fn.sockconnect, "tcp", addr, { rpc = true })
  if not ok or not ch or ch <= 0 then
    return false
  end
  pcall(vim.rpcnotify, ch, "nvim_exec_lua", code, args or {})
  vim.defer_fn(function()
    pcall(vim.fn.chanclose, ch)
  end, 1000)
  return true
end

-- Asks the server on the local end of the tunnel to quit the way the old
-- hangup did (SIGTERM, so unsaved changes stay in swap files).
local function stop_server(port)
  rpc_notify("localhost:" .. port, "vim.schedule(function() vim.uv.kill(vim.fn.getpid(), 'sigterm') end)")
end

-- Reconnection status in this Neovim: a fidget progress item under the host's
-- name ("Reconnecting · 0:42 · attempt 2") that ends as "Reconnected after
-- 42s" or "Session ended". Plain notifications when fidget isn't available.
-- The client tab drives the attempts (reattach), so a tab that stops asking
-- (closed) ends the status instead of leaving it spinning.
local status = {}

function status.finish(s, title, message, level)
  local st = s._rnvim_status
  if not st then
    return
  end
  s._rnvim_status = nil
  st.timer:stop()
  st.timer:close()
  if st.handle then
    st.handle:report { title = title, message = message }
    st.handle:finish()
  else
    vim.notify(("%s: %s %s"):format(s.host, title, message), level or vim.log.levels.INFO)
  end
end

-- A reconnect that needs something typed (password, passphrase, 2FA code)
function status.needs_input(s, what)
  local st = s._rnvim_status
  if st and st.handle then
    st.handle:report { title = "Needs you", message = ("%s; run :RemoteReconnect here"):format(what) }
  else
    vim.notify(("%s asks for %s. Run :RemoteReconnect to answer it."):format(s.host, what), vim.log.levels.WARN)
  end
end

function status.update(s)
  local st = s._rnvim_status
  if not st then
    return
  end
  if vim.uv.now() - st.last_ask > 15000 then
    return status.finish(s, "Not reconnecting", "its tab is closed; :RemoteStart to reattach", vim.log.levels.WARN)
  end
  local r = s._rnvim_reattach
  if st.handle and not (r and r.needs_input) then
    local msg = ("lost %s ago"):format(duration(vim.uv.now() - st.started))
    if st.attempts > 1 then
      msg = msg .. " · attempt " .. st.attempts
    end
    st.handle:report { message = msg }
  end
end

function status.start(s)
  if s._rnvim_status then
    return -- dropped again mid-reconnect: same status carries on
  end
  local st = { started = vim.uv.now(), last_ask = vim.uv.now(), attempts = 0, timer = assert(vim.uv.new_timer()) }
  local ok, progress = pcall(require, "fidget.progress")
  if ok then
    st.handle = progress.handle.create {
      title = "Reconnecting",
      message = "connection lost",
      lsp_client = { name = s.host },
    }
  else
    vim.notify(("Lost the connection to %s; reconnecting. The session is still running there."):format(s.host), vim.log.levels.WARN)
  end
  s._rnvim_status = st
  st.timer:start(1000, 1000, vim.schedule_wrap(function()
    status.update(s)
  end))
end

-- After the laptop wakes, a tunnel the network dropped while it slept only
-- shows as dead once ssh's keepalives run out (~30s), and until then the tab
-- just hangs. This notices the wake (the wall clock jumped between ticks),
-- pings each server through its tunnel, and ends the SSH job of any that
-- doesn't answer within 4s, so the reconnect starts right away.
local watchdog = { timer = nil, last = nil }

local function ping(s)
  local job, port = s._remote_server_process_id, s:get_local_neovim_server_port()
  if s._rnvim_pinging or not job or not port then
    return
  end
  s._rnvim_pinging = true
  local cmd = { vim.v.progpath, "--clean", "--headless", "--server", "localhost:" .. port, "--remote-expr", "1" }
  local ok = pcall(vim.system, cmd, { text = true, timeout = 4000 }, function(out)
    vim.schedule(function()
      s._rnvim_pinging = nil
      local alive = out.code == 0 and vim.trim(out.stdout or "") == "1"
      log("wake: %s tunnel %s", s.host, alive and "still works" or "is dead, dropping it now")
      if not alive and s._remote_server_process_id == job and s:is_remote_server_running() then
        pcall(vim.fn.jobstop, job)
      end
    end)
  end)
  if not ok then
    s._rnvim_pinging = nil
  end
end

local function watchdog_tick()
  local now = os.time()
  local woke = watchdog.last and now - watchdog.last > 20
  watchdog.last = now
  local active = false
  for _, s in pairs(sessions) do
    if s._rnvim_ready and s:is_remote_server_running() then
      active = true
      if woke then
        ping(s)
      end
    end
  end
  if not active then
    watchdog.timer:stop()
    watchdog.timer:close()
    watchdog.timer, watchdog.last = nil, nil
  end
end

local function watchdog_start()
  if not watchdog.timer then
    watchdog.timer = assert(vim.uv.new_timer())
    watchdog.last = os.time()
    watchdog.timer:start(5000, 5000, vim.schedule_wrap(watchdog_tick))
  end
end

function M.secure_launch()
  local Provider = require "remote-nvim.providers.provider"
  local run_command = Provider.run_command

  -- remote-nvim answers ssh prompts with a blocking input() in this Neovim.
  -- On an automatic reconnect nobody is looking at it (you're in the client
  -- tab), and the tab waits on this Neovim, so both would hang. Answers it
  -- already has (prompts are remembered per session) still go through; a
  -- prompt it can't answer stops the attempt and waits for :RemoteReconnect,
  -- which asks right here.
  local SSHExecutor = require "remote-nvim.providers.ssh.ssh_executor"
  local process_prompt = SSHExecutor._process_prompt
  function SSHExecutor:_process_prompt(prompt)
    local s = self._rnvim_owner
    local r = s and s._rnvim_reattach
    local cached = prompt.value_type == "static" and prompt.value ~= nil and prompt.value ~= ""
    if r and not (r.interactive_until and vim.uv.now() < r.interactive_until) and not cached then
      self._job_stdout_processed_idx = #self._job_stdout -- this prompt is handled
      if r.needs_input then
        return
      end
      local what = prompt.type == "secret" and "a password / passphrase" or ("an answer to %q"):format(prompt.match)
      r.needs_input = what
      log("reconnect to %s stopped: ssh asks for %s", s.host, what)
      pcall(vim.fn.jobstop, self._job_id)
      vim.schedule(function()
        status.needs_input(s, what)
      end)
      return
    end
    return process_prompt(self, prompt)
  end

  function Provider:run_command(cmd, desc, extra_opts, exit_cb, ...)
    if self.executor then
      self.executor._rnvim_owner = self
    end
    if self._rnvim_reattach and desc ~= LAUNCH_DESC then
      -- reattach's helper commands give up quickly on a network that's still
      -- down (the launch gets SSH_OPTS from socket_launch)
      extra_opts = extra_opts and (extra_opts .. " " .. SSH_OPTS) or SSH_OPTS
    end
    if desc ~= LAUNCH_DESC or self.provider_type ~= "ssh" or self._remote_is_windows then
      return run_command(self, cmd, desc, extra_opts, exit_cb, ...)
    end

    local host = self.unique_host_id
    if read_json(tcp_hosts_file)[host] then
      return run_command(self, cmd, desc, extra_opts, exit_cb, ...)
    end

    local key = vim.fn.sha256(host):sub(1, 16)
    local new_cmd, new_opts = M.socket_launch(cmd, extra_opts or "", self._remote_neovim_home .. "/run/" .. key)
    if not new_cmd then
      vim.notify(
        "remote-nvim's launch command changed shape; using its default TCP listener.\nCheck utils/remote.lua socket_launch.",
        vim.log.levels.WARN
      )
      return run_command(self, cmd, desc, extra_opts, exit_cb, ...)
    end

    sessions[key] = self
    self._rnvim_key, self._rnvim_ready, self._rnvim_reused = key, false, false
    self._rnvim_gone, self._rnvim_stopping = nil, nil
    -- A launch that isn't a reconnect gets its own client tab; tabs of an
    -- earlier launch close instead of reattaching (see reattach)
    if not self._rnvim_reattach then
      self._rnvim_gen = (self._rnvim_gen or 0) + 1
    end

    -- sshd decides on socket forwarding per connection, not at setup, so a
    -- host that forbids it (AllowStreamLocalForwarding no) only shows up as
    -- "open failed" in the ssh output once the client tries to connect. The
    -- same line appears when the client simply connects before the socket
    -- exists, so only count it after the remote's READY marker. Then remember
    -- the host and say to reconnect.
    local timer = vim.uv.new_timer()
    local ticks = 0
    timer:start(500, 500, vim.schedule_wrap(function()
      ticks = ticks + 1
      local out = table.concat(self.executor:job_stdout(), "\n")
      local ready = out:find(M.READY, 1, true)
      local refused = ready and out:find("open failed", ready, true)
      if ready and not self._rnvim_ready and self:is_remote_server_running() then
        self._rnvim_ready = true
        self._rnvim_reused = out:find(M.REUSED, 1, true) ~= nil
        log("connected %s (port %s, %s)", host, tostring(self:get_local_neovim_server_port()),
          self._rnvim_reused and "server was still running" or "new server")
        watchdog_start()
      end
      -- (the job id is only set once the launch is under way, hence ticks > 10)
      if refused or ticks >= 60 or (ticks > 10 and not self:is_remote_server_running()) then
        timer:stop()
        timer:close()
      end
      if refused then
        local hosts = read_json(tcp_hosts_file)
        hosts[host] = true
        pcall(vim.fn.writefile, { vim.json.encode(hosts) }, tcp_hosts_file)
        self:stop_neovim()
        vim.notify(
          ("%s doesn't allow forwarding to a Unix socket. It'll use TCP from now on; run :RemoteStart again."):format(
            self.host
          ),
          vim.log.levels.WARN
        )
      end
    end))

    -- The SSH job ending is either the server quitting (exit 0, or our own
    -- stop) or the connection dropping while the server lives on. A drop
    -- isn't a failure: no error window, and the client tab reattaches.
    local function on_exit(node)
      local inner = exit_cb and exit_cb(node)
      return function(code)
        local dropped = code ~= 0 and self._rnvim_ready and not self._rnvim_stopping
        log("ssh ended %s: exit %d -> %s", host, code,
          dropped and "connection lost" or self._rnvim_stopping and "stopped" or code == 0 and "session ended"
            or "launch failed")
        self._rnvim_ready = false
        if not dropped then
          self._rnvim_gone = code == 0 or self._rnvim_stopping or nil
          if self._rnvim_gone then
            vim.schedule(function()
              status.finish(self, "Session ended", "")
            end)
          end
        else
          self._provider_stopped_neovim = true
          vim.schedule(function()
            status.start(self)
          end)
        end
        if inner then
          inner(code)
        end
      end
    end

    return run_command(self, new_cmd, desc, new_opts, on_exit, ...)
  end

  -- RemoteStop / RemoteCleanup / RemoteRefresh's restart: with the server no
  -- longer tied to the SSH job, ending the job alone would leave it running
  local stop = Provider.stop_neovim
  function Provider:stop_neovim(...)
    if self._rnvim_key and self:is_remote_server_running() and self:get_local_neovim_server_port() then
      self._rnvim_stopping = true
      log("stopping %s", self.unique_host_id)
      stop_server(self:get_local_neovim_server_port())
    end
    return stop(self, ...)
  end
end

-- Whether the host answers SSH again: one short-lived `ssh <host> true` with
-- the session's own binary and options. An auth refusal (password hosts,
-- with no tty here) still means the host is back; the relaunch then prompts.
local function probe(s, done)
  local ex = s.executor or {}
  local cmd = ("%s %s -o BatchMode=yes -o ConnectTimeout=8 %s true"):format(
    ex.ssh_binary or "ssh",
    ex.ssh_conn_opts or "",
    vim.fn.shellescape(s.host)
  )
  local ok = pcall(vim.system, { "sh", "-c", cmd }, { text = true, stdin = false, timeout = 15000 }, function(out)
    local err = out.stderr or ""
    local reachable = out.code == 0 or err:find("Permission denied", 1, true) ~= nil or err:lower():find("password", 1, true) ~= nil
    vim.schedule(function()
      done(reachable)
    end)
  end)
  if not ok then
    vim.schedule(function()
      done(false)
    end)
  end
end

-- Called by the client tab (client_script) after its connection ended, with
-- the session's id and the launch it belongs to. Answers:
--   "gone"  the session ended, was relaunched in another tab, or the client
--           left on purpose (:detach) while the connection is fine: close
--   "wait"  reconnecting: ask again shortly
--   <port>  the tunnel is back: attach to localhost:<port>
function M.reattach(key, gen)
  local s = sessions[key]
  if not s or s._rnvim_gone or gen ~= s._rnvim_gen then
    if s then
      log("tab for %s closes: %s", s.host, s._rnvim_gone and "session ended" or "replaced by a newer launch")
      status.finish(s, "Session ended", "")
    end
    return "gone"
  end
  local running = s:is_remote_server_running()
  local r = s._rnvim_reattach
  if not r then
    if running then
      return "gone"
    end
    r = { next_try = 0 }
    s._rnvim_reattach = r
    log("tab asks to reconnect to %s", s.host)
  end
  local st = s._rnvim_status
  if st then
    st.last_ask = vim.uv.now()
  end
  if r.needs_input and not running then
    return "input " .. r.needs_input
  end
  if running and s._rnvim_ready then
    s._rnvim_reattach = nil
    log("tab reattached to %s on port %s", s.host, tostring(s:get_local_neovim_server_port()))
    require("utils.port_forward").link(s, s:get_local_neovim_server_port())
    if st then
      status.finish(s, "Reconnected", "after " .. duration(vim.uv.now() - st.started))
    end
    return tostring(s:get_local_neovim_server_port())
  end
  -- While the network is down, only a cheap probe runs (backing off to once a
  -- minute): a full relaunch through remote-nvim adds to its progress window
  -- and log every time, which would grow for as long as the outage lasts.
  if not running and not r.probing and vim.uv.now() >= r.next_try then
    r.probing = true
    if st then
      st.attempts = st.attempts + 1
      status.update(s)
    end
    probe(s, function(reachable)
      r.probing = false
      log("probe %s: %s", s.host, reachable and "reachable, reconnecting" or "unreachable")
      if not reachable then
        r.delay = math.min((r.delay or 2500) * 2, 60000)
        r.next_try = vim.uv.now() + r.delay
        return
      end
      r.delay = nil
      r.next_try = vim.uv.now() + 20000 -- the relaunch's own time to come up
      relaunch(s, ("Reconnect %s"):format(os.date "%H:%M:%S"))
    end)
  end
  -- "wait <attempt> <what's happening>", for the tab's screen
  local what
  if r.probing then
    what = "checking whether the host answers"
  elseif running then
    what = "host is back, reconnecting"
  elseif r.delay then
    what = ("host unreachable, next check in %ds"):format(math.max(math.ceil((r.next_try - vim.uv.now()) / 1000), 1))
  else
    what = "checking whether the host answers"
  end
  return ("wait %d %s"):format(st and st.attempts or 0, what)
end

-- :RemoteReconnect: retry a reconnect that's waiting for you to type
-- something (see SSHExecutor:_process_prompt), with prompts allowed for the
-- next minute, here, where you can see them
function M.reconnect()
  local waiting = {}
  for _, s in pairs(sessions) do
    if s._rnvim_reattach and not s:is_remote_server_running() then
      waiting[#waiting + 1] = s
    end
  end
  local function go(s)
    local r = s._rnvim_reattach
    r.needs_input, r.interactive_until = nil, vim.uv.now() + 60000
    r.next_try = vim.uv.now() + 60000
    log("reconnect to %s retried by hand", s.host)
    local st = s._rnvim_status
    if st and st.handle then
      st.handle:report { title = "Reconnecting", message = "answer ssh's prompt below" }
    end
    relaunch(s, ("Reconnect %s (manual)"):format(os.date "%H:%M:%S"))
  end
  if #waiting == 0 then
    vim.notify("No remote session is waiting to reconnect", vim.log.levels.INFO)
  elseif #waiting == 1 then
    go(waiting[1])
  else
    vim.ui.select(waiting, {
      prompt = "Reconnect which session?",
      format_item = function(s)
        return s.unique_host_id
      end,
    }, function(s)
      if s then
        go(s)
      end
    end)
  end
end

-- The client tab's command: attaches, and when the connection ends asks this
-- Neovim (reattach) whether to wait for a new tunnel or close. While waiting
-- it draws a status screen (spinner, time since the drop, attempt, what's
-- happening); q closes the tab. bash: `read -t` for the key polling.
local function client_script()
  local path = vim.fn.stdpath "cache" .. "/remote-nvim-client.sh"
  vim.fn.writefile({
    "# Remote Neovim client tab (utils/remote.lua): reattaches after a dropped connection",
    'nv=$1 here=$2 port=$3 key=$4 gen=$5 host=$6',
    -- headless with no tty on stdin, or it starts a UI and its escape codes end up in $r
    "ask() { \"$nv\" --clean --headless --server \"$here\" --remote-expr "
      .. "\"v:lua.require'utils.remote'.reattach('$key', $gen)\" </dev/null 2>/dev/null; }",
    'spin="⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏"',
    "esc=$(printf '\\033')",
    'B="$esc[1m" D="$esc[2m" Y="$esc[33m" R="$esc[0m"',
    "trap 'printf \"%s[?25h%s\" \"$esc\" \"$R\"' EXIT",
    "# center <text> on <row>; <width> is its visible width (escape codes don't count)",
    "at() { printf '%s[%d;%dH%s' \"$esc\" \"$1\" $(( (cols - $2) / 2 + 1 )) \"$3\"; }",
    "draw() {",
    '  set -- $(stty size 2>/dev/null); rows=${1:-24}; cols=${2:-80}; [ "$cols" -lt 60 ] && cols=60',
    "  e=$(( $(date +%s) - lost_at ))",
    "  t=$(printf '%d:%02d' $((e / 60)) $((e % 60)))",
    "  f=$(( tick % 10 + 1 )); set -- $spin; eval \"c=\\${$f}\"",
    "  top=$(( rows / 2 - 4 )); [ \"$top\" -lt 1 ] && top=1",
    "  printf '%s[?25l%s[H%s[2J' \"$esc\" \"$esc\" \"$esc\"",
    '  title="Reconnecting to $host"',
    '  at $top $(( ${#title} + 3 )) "$B$c  $title$R"',
    '  line="Connection lost $t ago"; [ "${attempt:-0}" -gt 1 ] && line="$line  ·  attempt $attempt"',
    '  at $(( top + 2 )) ${#line} "$D$line$R"',
    '  if [ -n "$need" ]; then',
    '    l1="The host asks for $need."; l2="Run :RemoteReconnect in the Neovim you connected from."',
    '    at $(( top + 3 )) ${#l1} "$Y$l1$R"; at $(( top + 4 )) ${#l2} "$Y$l2$R"',
    "  else",
    '    at $(( top + 3 )) ${#what} "$what"',
    "  fi",
    '  l="Your session is still running on the host; nothing is lost."',
    '  at $(( top + 6 )) ${#l} "$D$l$R"',
    '  l="q  close this tab"',
    '  at $(( top + 8 )) ${#l} "$D$l$R"',
    "}",
    "while :; do",
    '  "$nv" --server "localhost:$port" --remote-ui',
    "  lost_at=$(date +%s); tick=0; need=; attempt=; what=",
    "  sleep 1",
    "  r=$(ask) || exit 0",
    "  while :; do",
    '    case "$r" in',
    "      gone) exit 0 ;;",
    '      input*) need=${r#input }; what= ;;',
    '      wait*) need=; i=${r#wait}; i=${i# }; attempt=${i%% *}; what=${i#* }; [ "$what" = "$i" ] && what= ;;',
    '      "") ;;',
    '      *) port=$r; break ;;',
    "    esac",
    "    # redraw for the spinner (5fps; bash 3 only has whole-second timeouts: 1fps), ask again every 2s",
    '    if [ "${BASH_VERSINFO[0]:-3}" -ge 4 ]; then dt=0.2 n=10; else dt=1 n=2; fi',
    "    while [ $n -gt 0 ]; do",
    "      draw; tick=$((tick + 1)); n=$((n - 1))",
    '      read -r -s -n 1 -t $dt k 2>/dev/null </dev/tty && [ "$k" = q ] && exit 0',
    "    done",
    "    r=$(ask) || exit 0",
    "  done",
    "  printf '%s[H%s[2J' \"$esc\" \"$esc\"",
    "done",
  }, path)
  return path
end

local function in_container()
  return vim.uv.fs_stat "/.dockerenv" ~= nil or vim.uv.fs_stat "/run/.containerenv" ~= nil
end

-- "SSH: host" / "Dev Container: project", as VS Code's remote indicator reads.
-- Worked out once: the statusline calls this on every redraw.
local label
function M.label()
  if label == nil then
    if not M.is_remote then
      label = ""
    elseif in_container() then
      label = "Dev Container: " .. vim.fs.basename(vim.uv.cwd())
    else
      label = "SSH: " .. vim.uv.os_gethostname()
    end
  end
  return label
end

-- Use the binary on PATH if there is one, otherwise the copy inside the .app
-- bundle (DevPod.app, kitty.app, ... don't put their CLIs on PATH).
function M.bin(name, app_path)
  local path = vim.fn.exepath(name)
  if path ~= "" then
    return path
  end
  return vim.uv.fs_stat(app_path) and app_path or name
end

local function float_client(client)
  require("remote-nvim.ui").float_term(table.concat(client, " "), function(code)
    if code ~= 0 then
      vim.notify(("Remote client exited with code %s"):format(code), vim.log.levels.ERROR)
    end
  end)
end

-- Runs `cmd` and falls back to a floating terminal if it fails, so a session
-- always comes up even when the terminal refuses remote control.
local function launch(term, cmd, client, on_ok)
  -- vim.system throws (rather than calling back) when the CLI isn't on PATH
  local ok, err = pcall(vim.system, cmd, { text = true }, function(out)
    vim.schedule(function()
      if out.code == 0 then
        if on_ok then
          on_ok(out.stdout)
        end
        return
      end

      local err = vim.trim(out.stderr or "")
      if term == "kitty" then
        err = err .. "\nAdd `allow_remote_control socket-only` and `listen_on unix:/tmp/kitty` to kitty.conf"
      end
      vim.notify(
        ("Couldn't open a %s tab for the remote session, using a floating window.\n%s"):format(term, err),
        vim.log.levels.WARN
      )
      float_client(client)
    end)
  end)
  if not ok then
    vim.notify(
      ("Couldn't run %s, using a floating window for the remote session.\n%s"):format(cmd[1], err),
      vim.log.levels.WARN
    )
    float_client(client)
  end
end

local function concat(...)
  local out = {}
  for _, list in ipairs { ... } do
    vim.list_extend(out, list)
  end
  return out
end

-- Last folder opened per SSH host, used to prefill the next "Open folder" prompt
local dirs_file = vim.fn.stdpath "data" .. "/remote-nvim-dirs.json"

-- Evaluates `expr` in the remote server; `cb(out)` runs on the main loop
local function remote_expr(server, expr, cb)
  vim.system({ vim.v.progpath, "--server", server, "--remote-expr", expr }, { text = true }, function(out)
    vim.schedule(function()
      cb(out)
    end)
  end)
end

-- cd the remote server into `dir` before the UI attaches. expand() runs on the
-- remote, so ~ is the remote home.
local function remote_cd(server, dir, done)
  local expr = ("execute('cd ' .. fnameescape(expand('%s')))"):format(dir:gsub("'", "''"))
  remote_expr(server, expr, function(out)
    local err = vim.trim((out.stdout or "") .. (out.stderr or ""))
    if out.code ~= 0 or err ~= "" then
      vim.notify(("Couldn't open %s on the remote: %s"):format(dir, err), vim.log.levels.WARN)
    end
    done()
  end)
end

-- The remote server's working directory, or nil
local function remote_cwd(server, done)
  remote_expr(server, "getcwd()", function(out)
    local dir = out.code == 0 and vim.trim(out.stdout or "") or ""
    done(dir ~= "" and dir or nil)
  end)
end

-- Lists the sub-folders of `dir` on the remote, through the remote server
-- itself, so no extra SSH round trip. Calls back with (absolute path, names).
local function remote_ls(server, dir, done)
  local p = ("fnamemodify(expand('%s'), ':p')"):format(dir:gsub("'", "''"))
  local expr = ("json_encode({'path': %s, 'dirs': map(globpath(%s, '*/', 0, 1) + globpath(%s, '.[^.]*/', 0, 1),"
    .. " {_, d -> fnamemodify(d, ':h:t')})})"):format(p, p, p)
  remote_expr(server, expr, function(out)
    local ok, res = pcall(vim.json.decode, out.stdout or "")
    if out.code ~= 0 or not ok or type(res) ~= "table" or res.path == "" then
      return done(nil, nil, vim.trim((out.stderr or "") .. (out.stdout or "")))
    end
    done(res.path:gsub("(.)/$", "%1"), res.dirs)
  end)
end

local open_tab

-- Env vars (Lua patterns on the name) copied into the remote server, so AI
-- adapters there find the same API keys as here, whichever provider is in use.
M.forward_env = { "_API_KEY$", "^CODECOMPANION_" }

-- Sets the matching env vars in the remote server over its RPC socket: held in
-- memory only, never written to the remote disk or passed in argv.
local function push_env(server)
  local vars = {}
  for name, value in pairs(vim.fn.environ()) do
    for _, pat in ipairs(M.forward_env) do
      if name:find(pat) then
        vars[name] = value
        break
      end
    end
  end
  if next(vars) == nil then
    return
  end

  if not rpc_notify(server, "for k, v in pairs(...) do vim.env[k] = v end", { vars }) then
    vim.notify("Couldn't forward env to the remote", vim.log.levels.WARN)
  end
end

-- VS Code's "Open Folder" for a remote: a picker over the remote filesystem.
-- <CR> on a folder goes into it; the top entry opens the folder you're in.
local function browse(server, host, dir, done)
  remote_ls(server, dir, function(path, subdirs, err)
    if not path then
      vim.notify(("Can't list %s on %s: %s"):format(dir, host, err), vim.log.levels.WARN)
      if dir ~= "~" then
        return browse(server, host, "~", done)
      end
      return done(nil)
    end

    local open = { label = "  Open this folder", action = "open" }
    local items = { open, { label = "  Type a path...", action = "type" } }
    if path ~= "/" then
      items[#items + 1] = { label = "  ..", path = vim.fs.dirname(path) }
    end
    table.sort(subdirs)
    for _, name in ipairs(subdirs) do
      items[#items + 1] = { label = "  " .. name, path = vim.fs.joinpath(path, name) }
    end

    vim.ui.select(items, {
      prompt = ("Open folder on %s: %s"):format(host, path),
      format_item = function(item)
        return item.label
      end,
    }, function(item)
      if not item then
        return done(nil) -- cancelled: stay in the remote home
      elseif item.action == "open" then
        return done(path)
      elseif item.action == "type" then
        vim.ui.input({ prompt = "Remote path: ", default = path .. "/" }, function(typed)
          browse(server, host, vim.trim(typed or "") ~= "" and vim.trim(typed) or path, done)
        end)
      else
        browse(server, host, item.path, done)
      end
    end)
  end)
end

-- remote-nvim's client_callback. SSH servers start in the remote home, so ask
-- which folder to open, like VS Code does after connecting. Devcontainers
-- already start in their workspace folder.
--
-- Each folder gets its own server, like separate VS Code windows. The first
-- folder picked on a fresh connect is served by the host's own server (cd'd
-- there); picking another folder while it runs starts a folder session. Every
-- folder opened is also saved as a "<host>#<folder>" workspace entry, so it
-- shows in the :RemoteStart picker. Folder entries copy the host's workspace
-- id, so they share its remote install, config and plugins.

local function store()
  return require("remote-nvim").session_provider:get_config_provider()
end

local function get(id)
  return store():get_workspace_config(id)
end

function M.folder_id(host_id, dir)
  return host_id .. "#" .. dir
end

-- Host fields a folder entry mirrors so it reuses the host's remote workspace
local SHARED = {
  "provider", "host", "connection_options", "os", "arch", "neovim_version",
  "neovim_install_method", "remote_neovim_home", "workspace_id", "config_copy", "client_auto_start",
}

-- Creates or re-syncs the folder entry for `dir` on `host_id`; returns its id
local function save_folder(host_id, dir)
  local host = get(host_id)
  local entry = { parent = host_id, folder = dir }
  for _, key in ipairs(SHARED) do
    entry[key] = host[key]
  end
  local id = M.folder_id(host_id, dir)
  store():update_workspace_config(id, entry)
  return id
end

-- Folder id -> the session whose server is in that folder, so each folder is
-- only ever served once. Stale entries are dropped on lookup.
local serving = {}

local function server_for(id)
  local session = serving[id]
  if session and session:is_remote_server_running() and session:get_local_neovim_server_port() then
    return session
  end
  serving[id] = nil
end

-- Another client window on a session that's already running
local function attach(session)
  local cfg = get(session.unique_host_id)
  open_tab(session:get_local_neovim_server_port(), cfg, session._rnvim_folder or cfg.folder, session)
end

local function start_folder(id)
  local cfg = get(id)
  require("remote-nvim").session_provider
    :get_or_initialize_session({
      host = cfg.host,
      provider_type = cfg.provider,
      unique_host_id = id,
      conn_opts = { cfg.connection_options },
    })
    :launch_neovim()
end

-- Set by the _launch_local_neovim_client patch (track_sessions) right before
-- the plugin calls client_callback, which only gets the port and the config
local current

function M.open_client(port, workspace)
  workspace = workspace or {}
  local session = current
  current = nil
  local server = "localhost:" .. port
  push_env(server)
  if workspace.provider == "ssh" and session then
    require("utils.port_forward").link(session, port) -- for :RemoteForward
  end
  if workspace.provider ~= "ssh" or not session then
    return open_tab(port, workspace, nil, session)
  end

  -- A folder entry's server was launched in its folder
  if workspace.folder then
    session._rnvim_restart = nil
    serving[session.unique_host_id] = session
    return open_tab(port, workspace, workspace.folder, session)
  end

  -- RemoteRefresh restarted this host server: back to the folder it had
  if session._rnvim_restart ~= nil then
    local dir = session._rnvim_restart
    session._rnvim_restart = nil
    if not dir then
      return open_tab(port, workspace, nil, session)
    end
    return remote_cd(server, dir, function()
      open_tab(port, workspace, dir, session)
    end)
  end

  local host_id = session.unique_host_id
  local host = workspace.host or tostring(port)
  -- Connecting again to a host whose server already has a folder open
  local busy = session._rnvim_reconnect and session._rnvim_folder

  -- The server outlived an earlier connection (secure_launch reused it):
  -- open it where it is rather than asking for a folder and moving it
  if not busy and session._rnvim_reused then
    return remote_cwd(server, function(dir)
      session._rnvim_folder = dir
      if dir then
        serving[M.folder_id(host_id, dir)] = session
      end
      open_tab(port, workspace, dir, session)
    end)
  end
  local dirs = read_json(dirs_file)
  browse(server, host, dirs[host] or "~", function(dir)
    if not dir then
      return open_tab(port, workspace, busy, session)
    end

    dirs[host] = dir
    pcall(vim.fn.writefile, { vim.json.encode(dirs) }, dirs_file)
    local id = save_folder(host_id, dir)

    if busy then
      local running = server_for(id)
      if running then
        return attach(running)
      end
      return start_folder(id)
    end

    remote_cd(server, dir, function()
      session._rnvim_folder = dir
      serving[id] = session
      open_tab(port, workspace, dir, session)
    end)
  end)
end

-- The terminal is detected each time a session opens, not at startup, because
-- the same config runs in kitty, WezTerm and Ghostty. tmux comes first since
-- it runs inside any of them.
open_tab = function(port, workspace, folder, session)
  -- progpath, not "nvim": the new tab's shell may not have Homebrew on PATH yet
  local client = { vim.v.progpath, "--server", "localhost:" .. port, "--remote-ui" }
  if session and session._rnvim_key then
    -- a server that survives dropped connections gets a tab that reattaches
    client = {
      "bash", client_script(), vim.v.progpath, vim.v.servername, tostring(port), session._rnvim_key, tostring(session._rnvim_gen),
      session.host or "the host",
    }
  end

  local title = (workspace.provider == "devpod" and "Container: " or "SSH: ") .. (workspace.host or port)
  if folder then
    title = title .. " · " .. vim.fs.basename(folder)
  end

  if vim.env.TMUX then
    launch("tmux", concat({ "tmux", "new-window", "-n", title }, client), client)
  elseif vim.env.KITTY_WINDOW_ID then
    local kitty = M.bin("kitty", "/Applications/kitty.app/Contents/MacOS/kitty")
    launch("kitty", concat({ kitty, "@", "launch", "--type=tab", "--tab-title", title }, client), client)
  elseif vim.env.WEZTERM_PANE then
    local wezterm = M.bin("wezterm", "/Applications/WezTerm.app/Contents/MacOS/wezterm")
    launch("WezTerm", concat({ wezterm, "cli", "spawn", "--" }, client), client, function(pane)
      vim.system { wezterm, "cli", "set-tab-title", "--pane-id", vim.trim(pane), title }
    end)
  elseif vim.env.TERM_PROGRAM == "ghostty" and vim.fn.has "mac" == 0 then
    -- Linux Ghostty has no tab API, so a new window running the client.
    -- Detached: its exit code is the session's, not whether the launch worked.
    if not pcall(vim.system, concat({ "ghostty", "-e" }, client), { detach = true }) then
      vim.notify("Couldn't run ghostty, using a floating window for the remote session.", vim.log.levels.WARN)
      float_client(client)
    end
  elseif vim.env.TERM_PROGRAM == "ghostty" then
    -- Ghostty >= 1.3 AppleScript; the first run may ask for Automation access
    local script = ([[
      tell application "Ghostty"
        set cfg to new surface configuration
        set command of cfg to "%s"
        new tab in front window with configuration cfg
      end tell]]):format(table.concat(client, " "))
    launch("Ghostty", { "osascript", "-e", script }, client)
  else
    float_client(client)
  end
end

-- Hooks that make folder sessions work (see open_client) and keep the remote
-- config current.
function M.track_sessions()
  local Provider = require "remote-nvim.providers.provider"
  -- Copy the config on every fresh connect. The plugin remembers a per-host
  -- "No (never)", which left hosts running a stale copy indefinitely.
  -- RemoteRefresh restarts skip it, having just done a clean copy.
  function Provider:_get_neovim_config_upload_preference()
    if self._rnvim_skip_copy then
      self._rnvim_skip_copy = nil
      return false
    end
    if self._host_config.config_copy ~= true then
      self._host_config.config_copy = true
      self._config_provider:update_workspace_config(self.unique_host_id, { config_copy = true })
    end
    return true
  end

  -- Folder entries pick up the host's current workspace (it changes after a
  -- RemoteCleanup + reconnect) and launch their server in their folder.
  local setup_vars = Provider._setup_workspace_variables
  function Provider:_setup_workspace_variables(...)
    local cfg = get(self.unique_host_id)
    if cfg.parent and not vim.tbl_isempty(get(cfg.parent)) then
      save_folder(cfg.parent, cfg.folder)
    end
    setup_vars(self, ...)
    if cfg.folder then
      self._remote_working_dir = cfg.folder
    end
  end

  local launch = Provider._launch_neovim
  function Provider:_launch_neovim(...)
    local running = self:is_remote_server_running()
    -- A folder entry the host's own server already has open: add a window
    -- to that server rather than starting a second one in the same folder
    local other = not running and get(self.unique_host_id).folder and server_for(self.unique_host_id)
    if other and other ~= self then
      return attach(other)
    end
    self._rnvim_reconnect = running
    return launch(self, ...)
  end

  local launch_client = Provider._launch_local_neovim_client
  function Provider:_launch_local_neovim_client(...)
    current = self
    return launch_client(self, ...)
  end

  -- RemoteCleanup on a folder entry only forgets it: the remote workspace is
  -- the host's and shared. Cleaning up the host removes that workspace, so
  -- its folder entries go too.
  local cleanup = Provider._cleanup_remote_host
  function Provider:_cleanup_remote_host(...)
    local cfg = get(self.unique_host_id)
    if cfg.parent then
      self:stop_neovim()
      self._config_provider:remove_workspace_config(self.unique_host_id)
      self:hide_progress_view_window()
      vim.notify(("Forgot %s. Its remote install is shared with %s and was kept."):format(cfg.folder, cfg.parent))
      return
    end
    cleanup(self, ...)
    for id, entry in pairs(get()) do
      if entry.parent == self.unique_host_id then
        self._config_provider:remove_workspace_config(id)
      end
    end
  end
end

-- Stops a running session and starts it again once its server has exited,
-- back in the same folder
local function restart(session)
  local folder = session._rnvim_folder
  session:stop_neovim()
  local timer, ticks = vim.uv.new_timer(), 0
  timer:start(200, 200, vim.schedule_wrap(function()
    ticks = ticks + 1
    -- the server job's exit callback clears the process id (Provider:_reset)
    if session._remote_server_process_id ~= nil and ticks < 50 then
      return
    end
    timer:stop()
    timer:close()
    session._rnvim_skip_copy = true
    session._rnvim_restart = folder or false
    session:launch_neovim()
  end))
end

local function offer_restart(host_id)
  local running = {}
  for id, session in pairs(require("remote-nvim").session_provider:get_all_sessions()) do
    local cfg = get(id)
    if (id == host_id or cfg.parent == host_id) and session:is_remote_server_running() then
      running[#running + 1] = session
    end
  end
  if #running == 0 then
    return vim.notify(("Config refreshed on %s. The next connect uses it."):format(host_id))
  end

  vim.ui.select({ "Restart now", "Later" }, {
    prompt = ("Config refreshed. Restart the %d running session(s) on %s?"):format(#running, host_id),
  }, function(choice)
    if choice == "Restart now" then
      for _, session in ipairs(running) do
        restart(session)
      end
    end
  end)
end

-- Saved SSH hosts, without their folder entries
function M.hosts()
  local ids = {}
  for id, cfg in pairs(store():get_workspace_config(nil, "ssh")) do
    if not cfg.parent then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  return ids
end

-- :RemoteRefresh. Replaces the host's remote config with a clean copy of this
-- one (a normal connect only adds/overwrites files, so deleted files linger),
-- syncs plugins to lazy-lock.json, then offers to restart running sessions.
-- Runs on its own provider so it never touches a running session's jobs.
function M.refresh(host_id)
  local cfg = get(host_id)
  if cfg.parent then
    host_id, cfg = cfg.parent, get(cfg.parent)
  end
  if cfg.provider ~= "ssh" or not cfg.workspace_id or not cfg.remote_neovim_home then
    return vim.notify(("%s isn't a saved SSH host that's been connected to"):format(host_id), vim.log.levels.ERROR)
  end

  local remote_nvim = require "remote-nvim"
  local p = require "remote-nvim.providers.ssh.ssh_provider" {
    host = cfg.host,
    provider_type = "ssh",
    unique_host_id = host_id,
    conn_opts = { cfg.connection_options },
    progress_view = require "remote-nvim.ui.progressview"(),
  }

  p:_run_code_in_coroutine(function()
    p:start_progress_view_run "Refresh config"
    p:show_progress_view_window()
    p:_setup_workspace_variables()

    local dir = p._remote_neovim_config_path
    -- Never rm -rf anything but this workspace's config dir
    assert(dir:find("/workspaces/" .. cfg.workspace_id .. "/.config/", 1, true), "Unexpected config path " .. dir)
    p:run_command(("rm -rf %s && mkdir -p %s"):format(dir, dir), "Removing the old config from the remote")
    p:upload(
      p._local_path_to_remote_neovim_config,
      dir,
      "Copying your Neovim configuration onto remote",
      remote_nvim.config.remote.copy_dirs.config.compression
    )

    -- Same environment the server runs in (see _launch_remote_neovim_server)
    local sync = table.concat({
      ("XDG_CONFIG_HOME=%s XDG_DATA_HOME=%s XDG_STATE_HOME=%s XDG_CACHE_HOME=%s NVIM_APPNAME=%s"):format(
        p._remote_xdg_config_path,
        p._remote_xdg_data_path,
        p._remote_xdg_state_path,
        p._remote_xdg_cache_path,
        remote_nvim.config.remote.app_name
      ),
      p:_remote_neovim_binary_path(),
      "--headless",
      '"+Lazy! install"',
      '"+Lazy! restore"',
      '"+Lazy! clean"',
      -- NvChad's theme cache, in case a base46 update changed it
      [["+lua pcall(function() require('base46').load_all_highlights() end)"]],
      "+qa",
    }, " ")
    p:run_command(sync, "Syncing plugins to lazy-lock.json")

    p:hide_progress_view_window()
    vim.schedule(function()
      offer_restart(host_id)
    end)
  end, ("Refreshing config on %s"):format(host_id))
end

return M
