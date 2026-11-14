-- Shared by the Dev Containers layer (and configs/remote-nvim.lua): the
-- remote-nvim handle, notifications, the DevPod binary, the container engine
-- and the dependency check that runs before anything needs them.
local M = {}

-- configs/devcontainer.lua, with any setup() overrides
M.config = vim.deepcopy(require "configs.devcontainer")

function M.configure(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(require "configs.devcontainer"), opts or {})
end

function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Dev Container" })
end

-- nil on the remote side, where the plugin is off
function M.rn()
  local ok, rn = pcall(require, "remote-nvim")
  return ok and rn or nil
end

local PRIVATE = vim.fn.stdpath "data" .. "/devpod/bin/devpod"

-- Where DevPod should be: the isolated CLI under data/, then PATH, then
-- DevPod.app's bundled CLI on macOS
function M.devpod_path()
  if vim.fn.executable(PRIVATE) == 1 then
    return PRIVATE
  end
  return require("utils.remote").bin("devpod", "/Applications/DevPod.app/Contents/MacOS/devpod-cli")
end

-- The DevPod binary to run now, or nil. Looked up again when the configured
-- one is missing, so a CLI installed after startup is picked up.
function M.devpod()
  local rn = M.rn()
  local bin = rn and rn.config.devpod.binary
  if bin and vim.fn.executable(bin) == 1 then
    return bin
  end
  bin = M.devpod_path()
  if vim.fn.executable(bin) ~= 1 then
    return nil
  end
  if rn then
    rn.config.devpod.binary = bin
  end
  return bin
end

-- The binary a session was started with, for commands about that session
function M.devpod_for(session)
  return session and session.binary or M.devpod() or "devpod"
end

-- { bin, ..., "--log-output=raw" } for `devpod <verb> <id>`-style calls
function M.devpod_cmd(session, ...)
  local cmd = { M.devpod_for(session), ... }
  cmd[#cmd + 1] = "--log-output=raw"
  return cmd
end

local ENGINES = { "docker", "podman" }

local function answers(bin)
  local ok, proc = pcall(vim.system, { bin, "info", "--format", "{{.ServerVersion}}" }, { text = true })
  local out = ok and proc:wait(1500)
  return out and out.code == 0
end

-- Installed engines and the first that answers. Synchronous (up to 1.5s per
-- engine): only call this when the user has picked something.
local function engines()
  local installed, running = {}, nil
  for _, name in ipairs(ENGINES) do
    local bin = vim.fn.exepath(name)
    if bin ~= "" then
      installed[#installed + 1] = name
      if not running and answers(bin) then
        running = bin
      end
    end
  end
  return installed, running
end

-- "pacman" | "dnf" | "apt" | "brew"
local function package_manager()
  if vim.fn.has "mac" == 1 then
    return "brew"
  end
  local ok, lines = pcall(vim.fn.readfile, "/etc/os-release")
  local text = "\n" .. (ok and table.concat(lines, "\n") or "")
  -- ID plus ID_LIKE, so derivatives (EndeavourOS, Rocky, ...) match their base
  local ids = (text:match '\nID="?([^"\n]*)' or "") .. " " .. (text:match '\nID_LIKE="?([^"\n]*)' or "")
  if ids:find("arch", 1, true) or ids:find("manjaro", 1, true) then
    return "pacman"
  elseif ids:find("fedora", 1, true) or ids:find("rhel", 1, true) then
    return "dnf"
  end
  return "apt"
end

local INSTALL = {
  pacman = { docker = "sudo pacman -S --needed docker", podman = "sudo pacman -S --needed podman" },
  dnf = { docker = "sudo dnf install docker", podman = "sudo dnf install podman" },
  apt = { docker = "sudo apt install docker.io", podman = "sudo apt install podman" },
  brew = { docker = "brew install --cask docker", podman = "brew install podman" },
}

local START = {
  docker = vim.fn.has "mac" == 1 and "open -a Docker" or "sudo systemctl enable --now docker",
  podman = vim.fn.has "mac" == 1 and "podman machine init; podman machine start"
    or "systemctl --user enable --now podman.socket",
}

local function devpod_install()
  local machine = vim.uv.os_uname().machine or ""
  local asset = ("devpod-%s-%s"):format(
    vim.fn.has "mac" == 1 and "darwin" or "linux",
    (machine == "aarch64" or machine == "arm64") and "arm64" or "amd64"
  )
  local bin = vim.fn.shellescape(PRIVATE)
  return {
    "mkdir -p " .. vim.fn.shellescape(vim.fs.dirname(PRIVATE)),
    ("curl -fL https://github.com/loft-sh/devpod/releases/latest/download/%s -o %s"):format(asset, bin),
    "chmod +x " .. bin,
  }
end

-- What's missing for a DevPod action: { devpod = true, engine = true, daemon = "docker" }.
-- On success the running engine becomes remote-nvim's docker_binary.
function M.missing(needs_engine)
  local what = {}
  if not M.devpod() then
    what.devpod = true
  end
  if needs_engine then
    local installed, running = engines()
    if running then
      local rn = M.rn()
      if rn then
        rn.config.devpod.docker_binary = running
      end
    elseif #installed == 0 then
      what.engine = true
    else
      what.daemon = installed[1]
    end
  end
  return what
end

function M.install_text(what)
  local lines = {}
  local function section(title, cmds)
    vim.list_extend(lines, { title })
    vim.list_extend(lines, cmds)
    lines[#lines + 1] = ""
  end
  if what.devpod then
    section("DevPod CLI", devpod_install())
  end
  if what.engine then
    local pm = INSTALL[package_manager()]
    section("Docker (or Podman: " .. pm.podman .. ")", { pm.docker, START.docker })
  elseif what.daemon then
    section(("%s isn't running (or isn't accessible)"):format(what.daemon), { START[what.daemon] })
  end
  return table.concat(lines, "\n")
end

local function show_missing(what)
  local text = M.install_text(what)
  if pcall(vim.fn.setreg, "+", text) then
    text = text .. "\nCommands copied to the clipboard."
  end
  vim.notify(text, vim.log.levels.WARN, { title = "Remote: missing dependencies" })
end

-- DevPod's docker provider runs whichever engine answered (DOCKER_PATH), so
-- Podman works too. Done once per engine per Neovim; remote-nvim then finds
-- the provider and doesn't add its own.
local provider_ready = {}

local function run(cmd, cb)
  local ok = pcall(vim.system, cmd, { text = true }, function(out)
    vim.schedule(function()
      cb(out)
    end)
  end)
  if not ok then
    vim.schedule(function()
      cb { code = -1, stderr = "couldn't run " .. cmd[1] }
    end)
  end
end
M.run = run

function M.error_text(out)
  local text = vim.trim((out.stderr or "") .. "\n" .. (out.stdout or ""))
  return text ~= "" and text or ("exit code " .. tostring(out.code))
end

function M.ensure_provider(cb)
  local rn = M.rn()
  local engine = rn and rn.config.devpod.docker_binary
  if not engine or provider_ready[engine] then
    return cb(true)
  end
  local bin = M.devpod()
  run({ bin, "provider", "list", "--output", "json" }, function(list)
    local ok, providers = pcall(vim.json.decode, list.stdout or "")
    local verb = ok and type(providers) == "table" and providers.docker and { "provider", "set-options" }
      or { "provider", "add" }
    run(vim.list_extend({ bin }, vim.list_extend(verb, { "docker", "-o", "DOCKER_PATH=" .. engine })), function(out)
      if out.code ~= 0 then
        M.notify("Couldn't set up DevPod's docker provider: " .. M.error_text(out), vim.log.levels.ERROR)
        return cb(false)
      end
      provider_ready[engine] = true
      cb(true)
    end)
  end)
end

-- Wraps `action` so it only runs once DevPod (and, when `needs_engine`, a
-- running Docker/Podman with DevPod's provider set up) are there; otherwise
-- shows copyable install/start commands.
function M.guard(needs_engine, action)
  return function(...)
    local args = { n = select("#", ...), ... }
    local what = M.missing(needs_engine)
    if next(what) then
      return show_missing(what)
    end
    if not needs_engine then
      return action(unpack(args, 1, args.n))
    end
    M.ensure_provider(function(ok)
      if ok then
        action(unpack(args, 1, args.n))
      end
    end)
  end
end

return M
