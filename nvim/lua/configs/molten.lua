-- molten-nvim is a Python remote plugin, and this config starts with both the
-- Python provider (NvChad) and the remote-plugin loader (configs/lazy.lua)
-- switched off. Both are switched on here, the first time a notebook key or
-- :Molten* command is used, against a venv of molten's own
-- (:MoltenSetup creates it), so nothing depends on the system Python.
local M = {}

M.venv = vim.fn.stdpath "data" .. "/molten-venv"
local python = M.venv .. "/bin/python"
local ready = M.venv .. "/.ready" -- written once its packages are installed
local manifest = vim.fn.stdpath "data" .. "/rplugin.vim"

local function has_venv()
  return vim.uv.fs_stat(ready) ~= nil
end

-- Whether :UpdateRemotePlugins has recorded molten's commands
local function registered()
  local f = io.open(manifest)
  local text = f and f:read "*a" or ""
  if f then
    f:close()
  end
  return text:find("molten", 1, true) ~= nil
end

local function enable_host()
  vim.g.python3_host_prog = python
  if vim.g.loaded_python3_provider ~= 2 then
    vim.g.loaded_python3_provider = nil -- NvChad's "disabled"
  end
  if vim.fn.exists ":UpdateRemotePlugins" == 0 then
    -- defines :UpdateRemotePlugins and reads the manifest of registered plugins
    vim.cmd.source(vim.env.VIMRUNTIME .. "/plugin/rplugin.vim")
  end
end

-- Registers molten's commands in the remote-plugin manifest; needed once
-- after installing or updating it
function M.update()
  if not has_venv() then
    return
  end
  enable_host()
  require("lazy").load { plugins = { "molten-nvim" } } -- its rplugin/ dir on the runtimepath
  vim.cmd "silent UpdateRemotePlugins" -- (also registers them for this session)
end

-- The plugin spec's `config`
function M.enable()
  if not has_venv() then
    return vim.notify("Jupyter: run :MoltenSetup once first", vim.log.levels.WARN)
  end
  enable_host()
  if not registered() then
    M.update()
  end
end

-- :MoltenSetup -- the venv, with a Python kernel of its own so a notebook
-- works before any project has ipykernel
function M.setup_venv()
  if vim.fn.executable "python3" == 0 then
    return vim.notify("Jupyter: python3 not found", vim.log.levels.ERROR)
  end
  vim.notify "Jupyter: creating the molten venv…"
  local function fail(what, result)
    vim.notify(("Jupyter: %s failed\n%s"):format(what, result.stderr or ""), vim.log.levels.ERROR)
  end
  vim.system({ "python3", "-m", "venv", M.venv }, { text = true }, function(venv)
    if venv.code ~= 0 then
      return vim.schedule_wrap(fail)("python3 -m venv", venv)
    end
    local pip = { python, "-m", "pip", "install", "--quiet", "pynvim", "jupyter_client", "ipykernel" }
    vim.system(
      pip,
      { text = true },
      vim.schedule_wrap(function(install)
        if install.code ~= 0 then
          return fail("pip install", install)
        end
        vim.fn.writefile({}, ready)
        M.update()
        vim.notify "Jupyter: ready. <leader>Ni starts a kernel."
      end)
    )
  end)
end

return M
