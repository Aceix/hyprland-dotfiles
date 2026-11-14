-- DevPod workspaces: open (Reopen in Container), rebuild, attach, stop,
-- delete, log. remote-nvim still drives every launch; this picks the project,
-- config and workspace id, and adds the one-shot `devpod up` flags rebuilds need.
local core = require "devcontainer.core"
local client = require "devcontainer.client"
local project = require "devcontainer.project"

local M = {}

local function sessions()
  local rn = core.rn()
  return rn and rn.session_provider:get_all_sessions() or {}
end

-- Active DevPod sessions plus saved DevPod workspaces, by id
function M.targets()
  local rn = core.rn()
  if not rn then
    return {}
  end
  local out, seen = {}, {}
  for _, session in pairs(sessions()) do
    local id = session.unique_host_id
    if session.provider_type == "devpod" and id then
      seen[id] = true
      out[#out + 1] = { id = id, host = session.host, session = session }
    end
  end
  local saved = rn.session_provider:get_config_provider():get_workspace_config(nil, "devpod") or {}
  for id, entry in pairs(saved) do
    if not seen[id] then
      out[#out + 1] = { id = id, host = entry.host, config = entry }
    end
  end
  table.sort(out, function(a, b)
    return a.id < b.id
  end)
  return out
end

function M.ids()
  return vim.tbl_map(function(t)
    return t.id
  end, M.targets())
end

function M.target(id)
  for _, t in ipairs(M.targets()) do
    if t.id == id then
      return t
    end
  end
end

-- `id` if given, else the only workspace, else ask
function M.resolve(id, cb)
  id = vim.trim(id or "")
  if id ~= "" then
    return cb(M.target(id))
  end
  local targets = M.targets()
  if #targets <= 1 then
    return cb(targets[1])
  end
  vim.ui.select(targets, {
    prompt = "Dev Container workspace",
    format_item = function(t)
      return ("%s (%s)"):format(t.id, t.session and t.session:is_remote_server_running() and "running" or "saved")
    end,
  }, cb)
end

-- Two fixes to remote-nvim's DevPod provider (v0.3.12):
-- * it runs devpod in a pty, where DevPod queries the terminal (OSC 11, cursor
--   position) and those escape codes land in the JSON it then parses; with
--   TERM=dumb DevPod doesn't ask
-- * its launch knows no `--recreate`/`--reset`, so a rebuild sets
--   session._dc_up_once and this adds it to that one `devpod up`
function M.patch()
  local Devpod = require "remote-nvim.providers.devpod.devpod_provider"
  if Devpod._dc_patched then
    return
  end
  Devpod._dc_patched = true

  local init = Devpod.init
  function Devpod:init(...)
    init(self, ...)
    local ex = self.local_provider.local_executor
    local run = ex.run_executor_job
    function ex:run_executor_job(command, ...)
      return run(self, "env TERM=dumb " .. command, ...)
    end
  end

  local launch = Devpod._launch_devpod_workspace
  function Devpod:_launch_devpod_workspace(...)
    local once, opts = self._dc_up_once, self.launch_opts
    if not once then
      return launch(self, ...)
    end
    self._dc_up_once = nil
    self.launch_opts = vim.list_extend(vim.deepcopy(opts), once)
    local ok, err = pcall(launch, self, ...)
    self.launch_opts = opts
    assert(ok, err)
  end
end

-- (Re)starts `session`'s workspace; `flag` ("--recreate"/"--reset") rebuilds
-- its container. The server dies with the container, so a running one is
-- just disconnected first (DevPod sessions aren't kept alive like SSH ones).
local function relaunch(session, flag)
  if client.session() == session then
    client.close { stop = false }
  end
  client.cancel_idle(session)
  local job = session._remote_server_process_id
  if job and session:is_remote_server_running() then
    pcall(vim.fn.jobstop, job)
    vim.fn.jobwait({ job }, 3000)
  end
  if flag then
    session._devpod_workspace_active = false
    session._dc_up_once = { flag }
  end
  session:launch_neovim()
end

-- The session for a project config, created the way remote-nvim's own
-- "Launch current project" does, plus our id and --devcontainer-path
local function project_session(root, cfg)
  return core.rn().session_provider:get_or_initialize_session {
    host = root,
    provider_type = "devpod",
    unique_host_id = project.id(root, cfg),
    conn_opts = { "--devcontainer-path=" .. cfg.rel },
    devpod_opts = { provider = "docker", source_opts = { type = "devcontainer", id = root } },
  }
end

-- Asks which config when there are several
local function pick_config(proj, cb)
  if #proj.configs == 1 then
    return cb(proj.configs[1])
  end
  vim.ui.select(proj.configs, {
    prompt = "Dev Container configuration",
    format_item = function(c)
      return c.name and ("%s  (%s)"):format(c.name, c.rel) or ("default  (%s)"):format(c.rel)
    end,
  }, function(c)
    if c then
      cb(c)
    end
  end)
end

local function confirm_reset(id)
  return vim.fn.confirm(
    ("Rebuild %s from scratch?\nThe container and its workspace sources are removed and set up again;\n"
      .. "uncommitted changes in a cloned repository are lost."):format(id),
    "&Rebuild\n&Cancel",
    2,
    "Warning"
  ) == 1
end

-- Reopen in Container (flags.rebuild / flags.reset to rebuild first)
function M.open(proj, flags)
  flags = flags or {}
  proj = proj or project.current()
  if not proj then
    return core.notify("No devcontainer.json in this folder or above it", vim.log.levels.WARN)
  end
  pick_config(proj, function(cfg)
    local session = project_session(proj.root, cfg)
    if flags.reset and not confirm_reset(session.unique_host_id) then
      return
    end
    local flag = flags.reset and "--reset" or flags.rebuild and "--recreate" or nil
    if not flag and session:is_remote_server_running() then
      local port = session:get_local_neovim_server_port()
      if port then
        return client.open(port, { provider = "devpod", host = session.host }, session)
      end
    end
    relaunch(session, flag)
  end)
end

-- A target's session, starting one from its saved workspace when needed
local function session_of(target)
  if target.session then
    return target.session
  end
  return require("utils.remote").session_for(target.id)
end

function M.rebuild(target, flags)
  flags = flags or {}
  if not target then
    return M.open(nil, { rebuild = true, reset = flags.reset })
  end
  if flags.reset and not confirm_reset(target.id) then
    return
  end
  local session = session_of(target)
  if session then
    relaunch(session, flags.reset and "--reset" or "--recreate")
  end
end

function M.attach(target)
  local session = target and target.session
  local port = session and session:is_remote_server_running() and session:get_local_neovim_server_port()
  if not port then
    if session then
      return session:launch_neovim()
    end
    return require("utils.remote").connect(target.id)
  end
  client.cancel_idle(session)
  client.open(port, { provider = "devpod", host = target.host }, session)
end

local function forget_session(session)
  local all = sessions()
  for id, value in pairs(all) do
    if value == session then
      all[id] = nil
    end
  end
end

function M.stop(target)
  if not target then
    return
  end
  local session = target.session
  if session and client.session() == session then
    client.close { stop = false }
  end
  client.cancel_idle(session)

  if session then
    if session._dc_stopping then
      return
    end
    session._dc_stopping = true
    -- DevpodProvider stops the workspace too, if it started it
    local active = session._devpod_workspace_active
    pcall(session.stop_neovim, session)
    vim.defer_fn(function()
      session._dc_stopping = nil
    end, 5000)
    if active then
      return core.notify(("Stopping Dev Container %s…"):format(target.id))
    end
  end
  core.run(core.devpod_cmd(session, "stop", target.id), function(out)
    if out.code == 0 then
      core.notify(("Stopped Dev Container %s"):format(target.id))
    else
      core.notify(("Couldn't stop %s: %s"):format(target.id, core.error_text(out)), vim.log.levels.ERROR)
    end
  end)
end

function M.delete(target)
  if not target then
    return
  end
  if core.config.confirm_delete then
    local choice = vim.fn.confirm(
      ("Delete Dev Container %s?\nThe container and its workspace data will be removed."):format(target.id),
      "&Delete\n&Cancel",
      2,
      "Warning"
    )
    if choice ~= 1 then
      return
    end
  end

  local session = target.session
  if session and client.session() == session then
    client.close { stop = false }
  end
  client.cancel_idle(session)
  if session then
    session._dc_stopping = true
    pcall(session.stop_neovim, session)
  end

  core.notify(("Deleting Dev Container %s…"):format(target.id))
  -- `delete` stops a running container itself; a workspace already gone
  -- from DevPod still has its saved entry removed
  core.run(core.devpod_cmd(session, "delete", "--ignore-not-found", target.id), function(out)
    if out.code ~= 0 then
      return core.notify(("Couldn't delete %s: %s"):format(target.id, core.error_text(out)), vim.log.levels.ERROR)
    end
    local rn = core.rn()
    if rn then
      rn.session_provider:get_config_provider():remove_workspace_config(target.id)
    end
    forget_session(session)
    core.notify(("Deleted Dev Container %s"):format(target.id))
  end)
end

-- The project config a DevPod session runs (the one whose id is the
-- session's), or nil for repo/image/... workspaces
function M.config_of(session)
  local src = session and session._devpod_source_opts
  if not (src and src.type == "devcontainer") then
    return nil
  end
  for _, cfg in ipairs(project.configs(src.id)) do
    if project.id(src.id, cfg) == session.unique_host_id then
      return cfg
    end
  end
end

-- The config's forwardPorts (plain numbers; "service:port" ones are Compose's)
-- reachable on localhost, as VS Code does on open
function M.forward_ports(session, server_port)
  local cfg = M.config_of(session)
  local data = cfg and project.read(cfg.path)
  for _, port in ipairs(data and data.forwardPorts or {}) do
    if type(port) == "number" then
      require("utils.port_forward").forward(server_port, port)
    end
  end
end

-- The workspace's DevPod log in a bottom split; q closes it
function M.log(target)
  if not target then
    return
  end
  vim.cmd "botright 15new"
  local buf = vim.api.nvim_get_current_buf()
  vim.fn.jobstart(core.devpod_cmd(target.session, "logs", target.id), { term = true })
  vim.bo[buf].bufhidden = "wipe"
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true })
end

return M
