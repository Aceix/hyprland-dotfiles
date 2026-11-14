-- Dev Containers, VS Code style, on remote-nvim + DevPod:
--   :Devcontainer [sub] [id]   no argument: the Dev Containers list (menu.lua)
--   <leader>rD list · <leader>rR rebuild and reopen · <leader>rq detach
-- plus the "Reopen in Container" hint for folders with a devcontainer.json.
--
-- watch() runs at startup (plugins/remote-nvim.lua `init`) and loads nothing
-- heavy; setup() runs once remote-nvim loads, and inside a container's server
-- (init.lua), where only the in-container actions apply.
local core = require "devcontainer.core"
local project = require "devcontainer.project"

local M = { did_setup = false }

-- Folders you asked not to be reminded about: { dismissed = { [root] = true } }
local state_file = vim.fn.stdpath "data" .. "/devcontainer.json"
local state

local function load_state()
  if not state then
    local ok, data = pcall(function()
      return vim.json.decode(table.concat(vim.fn.readfile(state_file), "\n"))
    end)
    state = ok and type(data) == "table" and data or {}
    state.dismissed = state.dismissed or {}
  end
  return state
end

function M.dismissed(root)
  return load_state().dismissed[root] == true
end

function M.dismiss(root)
  load_state().dismissed[root] = true
  pcall(vim.fn.writefile, { vim.json.encode(state) }, state_file)
  core.notify(("Won't suggest a container for %s again"):format(vim.fn.fnamemodify(root, ":~")))
end

-- Once per folder per session, like VS Code's toast
local suggested = {}
local function suggest()
  local root = project.root()
  if not root or suggested[root] or M.dismissed(root) then
    return
  end
  suggested[root] = true
  core.notify(
    ("%s has a Dev Container configuration.\n<leader>rD → Reopen in Container"):format(vim.fs.basename(root))
  )
end

-- After a config is saved: a container running from it needs a rebuild
local function on_config_saved(path)
  project.forget()
  if not package.loaded["remote-nvim"] then
    return -- nothing of ours is running
  end
  local runtime = require "devcontainer.runtime"
  for _, t in ipairs(runtime.targets()) do
    local cfg = t.session and t.session:is_remote_server_running() and runtime.config_of(t.session)
    if cfg and vim.fs.normalize(cfg.path) == vim.fs.normalize(path) then
      return core.notify(("%s changed.\n<leader>rR → Rebuild and Reopen %s"):format(cfg.rel, t.id))
    end
  end
end

function M.watch()
  if require("utils.remote").is_remote then
    return
  end
  local group = vim.api.nvim_create_augroup("DevcontainerWatch", { clear = true })
  vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
    group = group,
    callback = function()
      vim.schedule(suggest)
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = { "*/.devcontainer/devcontainer.json", "*/.devcontainer/*/devcontainer.json", "*/.devcontainer.json" },
    callback = function(args)
      on_config_saved(args.match)
    end,
  })
  if vim.v.vim_did_enter == 1 then
    vim.schedule(suggest)
  end
end

-- Inside a container: leaving hands the UI back to the Neovim it came from
-- (vim.g.devcontainer_return, set by client.lua), which then stops it.
-- Without one (opened some other way), it just quits.
function M.leave()
  local addr = vim.g.devcontainer_return
  if addr and #vim.api.nvim_list_uis() > 0 and pcall(vim.cmd.connect, addr) then
    return
  end
  vim.cmd "confirm qall"
end

-- (:q / :qa here end the whole Neovim, terminal included: the Neovim this
-- came from notices and stops the container; client.lua)
function M.in_container_setup()
  -- The last UI left (terminal closed): tell the Neovim this came from.
  -- Polled (in memory, every 2s): a UI dropping over the tunnel doesn't
  -- fire UILeave here.
  local had_ui = false
  local timer = assert(vim.uv.new_timer())
  timer:start(2000, 2000, vim.schedule_wrap(function()
    if #vim.api.nvim_list_uis() > 0 then
      had_ui = true
    elseif had_ui then
      had_ui = false
      require("utils.port_forward").request("ui_gone", nil, true)
    end
  end))
end

local function complete(lead, line)
  local words = vim.split(line, "%s+", { trimempty = true })
  local typing_sub = #words == 1 or (#words == 2 and lead ~= "")
  local list = typing_sub and require("devcontainer.menu").commands()
    or (package.loaded["remote-nvim"] and require("devcontainer.runtime").ids() or {})
  return vim.tbl_filter(function(s)
    return s:find(lead, 1, true) == 1
  end, list)
end

function M.setup(opts)
  core.configure(opts)
  if M.did_setup then
    return
  end
  M.did_setup = true

  local remote = require "utils.remote"
  local menu = require "devcontainer.menu"
  vim.api.nvim_create_user_command("Devcontainer", function(cmd)
    if #cmd.fargs == 0 then
      return menu.open { scope = "container" }
    end
    menu.run(cmd.fargs[1], cmd.fargs[2])
  end, { nargs = "*", complete = complete, desc = "Dev Containers (no argument: the list of actions)" })

  if remote.is_remote then
    if remote.in_container() then
      M.in_container_setup()
      local function map(lhs, fn, desc)
        vim.keymap.set("n", lhs, fn, { desc = "Dev Container: " .. desc })
      end
      map("<leader>rD", function() menu.open { scope = "container" } end, "Actions")
      map("<leader>rR", function() menu.run "rebuild" end, "Rebuild container")
      map("<leader>rq", function() menu.run "detach" end, "Reopen folder locally (stop)")
    end
    return
  end

  require("devcontainer.runtime").patch()
  -- :RemoteStart (no host) opens the launcher instead of the plugin's list
  require("telescope").extensions["remote-nvim"].connect = function()
    menu.open()
  end
end

return M
