-- The Remote menu (<leader>rs, :RemoteStart) and the Dev Containers menu
-- (<leader>rD, :Devcontainer): small NvChad popups (nvzone/menu, like the
-- nvim-tree right-click menu) with submenus, laid out like VS Code's remote
-- indicator menu:
--
--   󰡨  Reopen proj in Container          o   what this folder can do, first
--   ─────────────────────────────────
--   ● 󰒍  prod-api · ~/srv/api   running  1   recent: ⏎ opens, l / → its actions
--     󰡨  my-project · ~/proj    2h ago   2
--   ─────────────────────────────────
--   󰒍  Connect to Host…                  s   long lists open in Telescope
--   󰡨  Dev Containers                  ▸ d
--     More                            ▸ m
--
-- Every action is defined once (A); the popups, the Telescope lists and
-- :Devcontainer's subcommands all call it. Building a menu only reads memory
-- and the cached project root, so it opens instantly; dependency checks run
-- when something is picked (core.guard).
local core = require "devcontainer.core"
local project = require "devcontainer.project"
local remote = require "utils.remote"

local M = {}

local api = vim.api
local SSH, BOX = "󰒍", "󰡨"
local SEP = { name = "separator" }
local RECENT = 5
-- Telescope lists and the popup: key → row action (see ROW)
local ROW_KEYS = { ["<C-s>"] = "s", ["<C-x>"] = "x", ["<C-r>"] = "r", ["<C-l>"] = "v" }
local LIST_HINT = "⏎ open  ^s stop  ^x forget/delete  ^r rebuild  ^l log"

local function runtime()
  return require "devcontainer.runtime"
end

-- remote-nvim's own flow for `mod` (telescope/_extensions/choices/<mod>.lua),
-- dependency-checked when it needs DevPod (needs_engine ~= nil)
local function plugin(mod, needs_engine)
  local run = function()
    require("telescope._extensions.choices." .. mod).action {}
  end
  return needs_engine == nil and run or core.guard(needs_engine, run)
end

local function ago(t)
  if not t or t == 0 then
    return ""
  end
  local s = os.time() - t
  if s < 60 then
    return "just now"
  elseif s < 3600 then
    return ("%dm ago"):format(s / 60)
  elseif s < 86400 then
    return ("%dh ago"):format(s / 3600)
  end
  return ("%dd ago"):format(s / 86400)
end

-- === Saved sessions ==========================================================

-- Name and detail of a saved workspace, as a person would call it
local function describe(id, cfg)
  local src = cfg.devpod_source_opts
  if not src then
    -- a host's own entry opens in its home folder
    return cfg.parent or id, cfg.folder and vim.fn.fnamemodify(cfg.folder, ":~") or "~"
  end
  if src.type == "devcontainer" then
    local name = vim.fs.basename(src.id)
    for _, c in ipairs(project.configs(src.id)) do
      if c.name and project.id(src.id, c) == id then
        name = name .. " · " .. c.name
      end
    end
    return name, vim.fn.fnamemodify(src.id, ":~")
  end
  local uri = tostring(src.name or src.id or id)
  local what = src.type == "repo" and "" or (" (%s %s)"):format(src.type, src.id)
  local short = vim.fs.basename(uri):gsub("%.git$", "")
  return src.type == "container" and (src.name or id) or short, uri .. what
end

-- Saved sessions, last used first; kind: "ssh" | "devpod" | nil for both.
-- running() is asked live (in-memory, no shell), for the popup's status.
function M.sessions(kind)
  local rn = core.rn()
  if not rn then
    return {}
  end
  local live = rn.session_provider:get_all_sessions()
  local out = {}
  for id, cfg in pairs(rn.session_provider:get_config_provider():get_workspace_config()) do
    local devpod = cfg.provider == "devpod"
    if not kind or kind == (devpod and "devpod" or "ssh") then
      local name, detail = describe(id, cfg)
      out[#out + 1] = {
        id = id, devpod = devpod, name = name, detail = detail, last_used = cfg.last_used or 0,
        running = function()
          local s = live[id]
          return s ~= nil and s:is_remote_server_running()
        end,
      }
    end
  end
  table.sort(out, function(a, b)
    if a.last_used ~= b.last_used then
      return a.last_used > b.last_used
    end
    return a.name < b.name
  end)
  return out
end

local function target(s)
  return runtime().target(s.id) or { id = s.id }
end

-- What can be done to a saved session: its submenu, and the list keys
local ROW = {
  { key = "o", name = "Open", run = function(s)
    if s.devpod then
      return core.guard(true, runtime().attach)(target(s))
    end
    remote.connect(s.id)
  end },
  { key = "r", name = "Rebuild Container", devpod = true, run = function(s)
    core.guard(true, runtime().rebuild)(target(s))
  end },
  { key = "s", name = "Stop", run = function(s)
    if s.devpod then
      return runtime().stop(target(s))
    end
    vim.cmd.RemoteStop(s.id)
  end },
  { key = "v", name = "Show Log", run = function(s)
    if s.devpod then
      return runtime().log(target(s))
    end
    vim.cmd "RemoteLog"
  end },
  { key = "x", name = "Forget…", devpod_name = "Delete Container…", hl = "ExRed", run = function(s)
    if s.devpod then
      return runtime().delete(target(s))
    end
    if vim.fn.confirm(("Forget %s?"):format(s.id), "&Forget\n&Cancel", 2) == 1 then
      vim.cmd.RemoteConfigDel(s.id)
    end
  end },
}

local function row_action(key, s)
  for _, a in ipairs(ROW) do
    if a.key == key and (s.devpod or not a.devpod) then
      return function()
        a.run(s)
      end
    end
  end
end

local function row_items(s)
  local items = {}
  for _, a in ipairs(ROW) do
    if s.devpod or not a.devpod then
      local run = row_action(a.key, s)
      items[#items + 1] = {
        name = (s.devpod and a.devpod_name or a.name), rtxt = a.key, hl = a.hl,
        cmd = function()
          vim.schedule(run)
        end,
      }
    end
  end
  return items
end

-- === Telescope lists (hosts, workspaces) =====================================

-- rows: { icon, label, detail, status, running, help, run, session }
function M.list(title, rows)
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local conf = require("telescope.config").values
  local actions = require "telescope.actions"
  local state = require "telescope.actions.state"
  local displayer = require("telescope.pickers.entry_display").create {
    separator = " ",
    items = { { width = 2 }, { width = 30 }, { remaining = true } },
  }
  pickers
    .new({}, {
      prompt_title = title,
      results_title = LIST_HINT,
      layout_strategy = "horizontal",
      layout_config = { width = 0.8, height = 0.7, preview_width = 0.4 },
      finder = finders.new_table {
        results = rows,
        entry_maker = function(r)
          local tail = vim.trim((r.detail or "") .. "  " .. (r.status or ""))
          return {
            value = r,
            ordinal = r.label .. " " .. (r.detail or ""),
            display = function()
              local hl = r.running and "DiagnosticOk" or "Comment"
              return displayer { { r.icon, r.running and "DiagnosticOk" or "Special" }, r.label, { tail, hl } }
            end,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = require("telescope.previewers").new_buffer_previewer {
        title = "About",
        define_preview = function(self, entry)
          vim.bo[self.state.bufnr].filetype = "markdown"
          vim.wo[self.state.winid].wrap = true
          vim.wo[self.state.winid].linebreak = true
          api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(entry.value.help or "", "\n"))
        end,
      },
      attach_mappings = function(bufnr, map)
        local function take(fn)
          return function()
            local entry = state.get_selected_entry()
            actions.close(bufnr)
            if entry then
              vim.schedule(function()
                fn(entry.value)
              end)
            end
          end
        end
        actions.select_default:replace(take(function(r)
          r.run()
        end))
        for lhs, key in pairs(ROW_KEYS) do
          map({ "i", "n" }, lhs, take(function(r)
            local run = r.session and row_action(key, r.session)
            if run then
              run()
            end
          end))
        end
        return true
      end,
    })
    :find()
end

local function session_row(s)
  local running = s.running()
  return {
    icon = s.devpod and BOX or SSH, label = s.name, detail = s.detail,
    status = running and "● running" or ago(s.last_used), running = running, session = s,
    run = row_action("o", s),
    help = table.concat({
      ("**%s** — %s"):format(s.name, s.devpod and "Dev Container" or "SSH"),
      "",
      ("`%s`"):format(s.detail),
      ("Workspace id: `%s`"):format(s.id),
      running and "Running now." or ("Last used: %s"):format(s.last_used > 0 and os.date("%c", s.last_used) or "never"),
    }, "\n"),
  }
end

local SSH_CONFIG = vim.fn.expand "~/.ssh/config"

-- Hosts in the SSH config files remote-nvim reads, by name
local function config_hosts()
  local rn = core.rn()
  local ok, hosts = pcall(function()
    local parser = require("remote-nvim.providers.ssh.ssh_config_parser")()
    for _, path in ipairs(rn.config.ssh_config.ssh_config_file_paths) do
      parser = parser:parse_config_file(path)
    end
    return parser:get_config()
  end)
  return ok and hosts or {}
end

local function connect_host(name)
  core.rn().session_provider:get_or_initialize_session({ host = name, provider_type = "ssh" }):launch_neovim()
end

-- VS Code's "Add New SSH Host…": an ssh command line as a Host block.
-- Returns host, lines or nil.
function M.host_block(cmd)
  local args = vim.split((vim.trim(cmd or ""):gsub("^ssh%s+", "")), "%s+", { trimempty = true })
  local KEYS = { p = "Port", i = "IdentityFile", J = "ProxyJump", l = "User" }
  local TAKES_ARG = "bcDEeFIiJLlmOoPpQRSWw" -- ssh flags with a value
  local opts, dest, i = {}, nil, 1
  while i <= #args do
    local flag = args[i]:match "^%-(%a)$"
    if flag and TAKES_ARG:find(flag, 1, true) then
      if KEYS[flag] then
        opts[KEYS[flag]] = args[i + 1]
      end
      i = i + 2
    elseif args[i]:sub(1, 1) == "-" then
      i = i + 1
    else
      dest = dest or args[i]
      i = i + 1
    end
  end
  if not dest then
    return nil
  end
  local user, host = dest:match "^(.-)@(.+)$"
  host = host or dest
  opts.User = opts.User or (user ~= "" and user or nil)
  local lines = { "Host " .. host, "  HostName " .. host }
  for _, k in ipairs { "User", "Port", "IdentityFile", "ProxyJump" } do
    if opts[k] then
      lines[#lines + 1] = ("  %s %s"):format(k, opts[k])
    end
  end
  return host, lines
end

-- === Actions (each defined once) =============================================

local A = {}

function A.open(ctx)
  core.guard(true, runtime().open)(ctx.proj)
end

function A.rebuild(ctx)
  if ctx.inside then
    return require("utils.port_forward").request "rebuild"
  end
  core.guard(true, runtime().open)(ctx.proj, { rebuild = true })
end

function A.reset(ctx)
  core.guard(true, runtime().open)(ctx.proj, { reset = true })
end

function A.config(ctx)
  local proj = ctx.proj or project.current()
  if not proj then
    return core.notify("No devcontainer.json in this folder or above it", vim.log.levels.WARN)
  end
  local function edit(c)
    vim.cmd.edit(vim.fn.fnameescape(c.path))
  end
  if #proj.configs == 1 then
    return edit(proj.configs[1])
  end
  vim.ui.select(proj.configs, {
    prompt = "Open configuration",
    format_item = function(c)
      return c.rel
    end,
  }, function(c)
    if c then
      edit(c)
    end
  end)
end

function A.new()
  require("devcontainer.wizard").run()
end

function A.detach(ctx)
  if ctx.inside then
    return require("devcontainer").leave()
  end
  require("devcontainer.client").detach()
end

function A.dismiss(ctx)
  require("devcontainer").dismiss(ctx.proj.root)
end

-- :RemoteCleanup takes exactly one host id, so ask which first
function A.cleanup()
  vim.ui.select(M.sessions(), {
    prompt = "Clean up which host?",
    format_item = function(s)
      return ("%s  %s  %s"):format(s.devpod and BOX or SSH, s.name, s.detail)
    end,
  }, function(s)
    if s then
      vim.cmd.RemoteCleanup(s.id)
    end
  end)
end

function A.forward()
  vim.ui.input({ prompt = "Forward port: " }, function(p)
    if p and vim.trim(p) ~= "" then
      vim.cmd("RemoteForward " .. vim.trim(p))
    end
  end)
end

local CLONE = {
  { key = "r", name = "Repository (default branch)…", mod = "devpod.repo" },
  { key = "b", name = "Branch…", mod = "devpod.branch" },
  { key = "p", name = "Pull Request…", mod = "devpod.pr" },
  { key = "c", name = "Commit…", mod = "devpod.commit" },
}

function A.clone()
  vim.ui.select(CLONE, {
    prompt = "Clone into a container",
    format_item = function(k)
      return k.name
    end,
  }, function(k)
    if k then
      plugin(k.mod, true)()
    end
  end)
end

function A.workspaces()
  local rows = vim.tbl_map(session_row, M.sessions "devpod")
  rows[#rows + 1] = {
    icon = BOX, label = "Existing DevPod Workspace…", run = plugin("devpod.existing_workspace", false),
    help = "Open a workspace DevPod knows that isn't listed here (e.g. created from DevPod's own UI).",
  }
  M.list("Dev Container Workspaces", rows)
end

function A.configure_hosts()
  vim.cmd.edit(vim.fn.fnameescape(SSH_CONFIG))
end

function A.add_host()
  vim.ui.input({ prompt = "ssh " }, function(cmd)
    local host, lines = M.host_block(cmd)
    if not host then
      return
    end
    if config_hosts()[host] then
      core.notify(("%s is already in your SSH config"):format(host), vim.log.levels.WARN)
      return connect_host(host)
    end
    local msg = ("Add to %s?\n\n%s"):format(vim.fn.fnamemodify(SSH_CONFIG, ":~"), table.concat(lines, "\n"))
    if vim.fn.confirm(msg, "&Add\n&Cancel", 1) ~= 1 then
      return
    end
    vim.fn.mkdir(vim.fs.dirname(SSH_CONFIG), "p", tonumber("700", 8))
    local existed = vim.uv.fs_stat(SSH_CONFIG) ~= nil
    local f = assert(io.open(SSH_CONFIG, "a"))
    f:write("\n" .. table.concat(lines, "\n") .. "\n")
    f:close()
    if not existed then
      vim.uv.fs_chmod(SSH_CONFIG, tonumber("600", 8))
    end
    if vim.fn.confirm(("Added %s. Connect now?"):format(host), "&Connect\n&Later", 1) == 1 then
      connect_host(host)
    end
  end)
end

function A.hosts()
  local rows, saved = {}, {}
  for _, s in ipairs(M.sessions "ssh") do
    rows[#rows + 1] = session_row(s)
    saved[s.id] = true
  end
  local names = vim.tbl_filter(function(n)
    return not saved[n]
  end, vim.tbl_keys(config_hosts()))
  table.sort(names)
  for _, n in ipairs(names) do
    rows[#rows + 1] = {
      icon = SSH, label = n, detail = "~/.ssh/config",
      run = function()
        connect_host(n)
      end,
      help = ("Connect to **%s** from your SSH config."):format(n),
    }
  end
  vim.list_extend(rows, {
    { icon = "", label = "Add New SSH Host…", run = A.add_host,
      help = "Type an ssh command (`user@host -p 2222 -i ~/.ssh/key`); the Host entry is shown before it's added "
        .. "to ~/.ssh/config." },
    { icon = "", label = "Configure SSH Hosts…", run = A.configure_hosts, help = "Open ~/.ssh/config." },
    { icon = "", label = "Connect with an ssh Command…", run = plugin "ssh.manual_input",
      help = "Connect once without saving a Host entry." },
  })
  M.list("Connect to Host", rows)
end

-- :Devcontainer <sub> [id]
local function with_target(fn)
  return function(_, arg)
    runtime().resolve(arg, function(t)
      if t then
        fn(t)
      else
        core.notify("No Dev Container workspace found", vim.log.levels.WARN)
      end
    end)
  end
end

local COMMANDS = {
  open = A.open, rebuild = A.rebuild, reset = A.reset, config = A.config, new = A.new, clone = A.clone,
  detach = A.detach, workspaces = A.workspaces,
  attach = with_target(function(t) runtime().attach(t) end),
  stop = with_target(function(t) runtime().stop(t) end),
  delete = with_target(function(t) runtime().delete(t) end),
  log = with_target(function(t) runtime().log(t) end),
}

-- === Popups ==================================================================

local function context()
  local here = not remote.is_remote
  return { here = here, inside = remote.is_remote and remote.in_container(), proj = here and project.current() or nil }
end

-- A popup item running action `fn` with ctx, once the popup has closed
local function item(icon, name, key, fn, ctx, hl)
  return {
    name = icon .. "  " .. name, rtxt = key, hl = hl,
    cmd = function()
      vim.schedule(function()
        fn(ctx)
      end)
    end,
  }
end

-- Submenu lists built here, so keys() is added when nvzone opens one (not a
-- field on the list: nvzone walks it with pairs)
local OURS = setmetatable({}, { __mode = "k" })

local function sub(icon, name, key, items)
  OURS[items] = true
  return { name = icon .. "  " .. name .. "  ▸", keybind = key, items = items }
end

-- A recent session: "● 󰒍  name · detail   status"; render() refreshes it
local LABEL = 36
local function session_item(s, i)
  local label = vim.fn.strcharpart(s.name .. (s.detail ~= "" and (" · " .. s.detail) or ""), 0, LABEL)
  label = label .. string.rep(" ", LABEL - vim.fn.strdisplaywidth(label))
  local open = row_action("o", s)
  local it = { rtxt = tostring(i), session = s, cmd = function() vim.schedule(open) end }
  function it.render()
    local running = s.running()
    it.name = ("%s %s  %s %8s"):format(running and "●" or " ", s.devpod and BOX or SSH, label,
      running and "running" or ago(s.last_used))
    it.hl = running and "ExGreen" or nil
  end
  it.render()
  return it
end

local function recent(kind)
  local items = {}
  for i, s in ipairs(M.sessions(kind)) do
    if i > RECENT then
      break
    end
    items[#items + 1] = session_item(s, i)
  end
  return items
end

local function folder_items(ctx)
  local p = ctx.proj
  if not p then
    return { item("", "Add Dev Container Configuration…", "a", A.new, ctx) }
  end
  return {
    item(BOX, ("Reopen %s in Container"):format(vim.fs.basename(p.root)), "o", A.open, ctx),
    item(BOX, "Rebuild and Reopen in Container", "r", A.rebuild, ctx),
    item(BOX, "Rebuild from Scratch…", "R", A.reset, ctx),
    item("", "Open Configuration File", "c", A.config, ctx),
    item("", "Add Another Configuration…", "a", A.new, ctx),
  }
end

local function source_items(ctx)
  local clone = vim.tbl_map(function(k)
    return item("", k.name, k.key, plugin(k.mod, true), ctx)
  end, CLONE)
  local items = {
    sub(BOX, "Clone Repository in Container", "g", clone),
    item(BOX, "Docker Image…", "i", plugin("docker.image", true), ctx),
    item(BOX, "Running Docker Container…", "u", plugin("docker.container", true), ctx),
    item(BOX, "All Workspaces…", "w", A.workspaces, ctx),
  }
  if ctx.proj and not require("devcontainer").dismissed(ctx.proj.root) then
    vim.list_extend(items, { SEP, item("", "Don't Suggest for This Folder", nil, A.dismiss, ctx, "ExLightGrey") })
  end
  return items
end

local function cmd(name)
  return function()
    vim.cmd(name)
  end
end

local function more_items(ctx)
  return {
    item("", "Remote Log", "v", cmd "RemoteLog", ctx),
    item("", "Session Info", "i", cmd "RemoteInfo", ctx),
    item("󰛳", "Forwarded Ports", "p", cmd "RemoteForward", ctx),
    item("", "Re-copy Config to a Host…", "c", cmd "RemoteRefresh", ctx),
    item("", "Clean Up a Host…", "u", A.cleanup, ctx),
  }
end

-- Joins groups with separators, skipping empty ones
local function groups(...)
  local out = {}
  for _, g in ipairs { ... } do
    if #g > 0 then
      if #out > 0 then
        out[#out + 1] = SEP
      end
      vim.list_extend(out, g)
    end
  end
  return out
end

-- The popup's items for `scope` (nil = Remote, "container" = Dev Containers)
function M.tree(scope, ctx)
  ctx = ctx or context()
  if ctx.inside then
    return {
      item("", "Reopen Folder Locally", "o", A.detach, ctx),
      item(BOX, "Rebuild Container", "r", A.rebuild, ctx),
      item("", "Open Configuration File", "c", A.config, ctx),
      item("󰛳", "Forward a Port…", "p", A.forward, ctx),
    }
  end
  if scope == "container" then
    return groups(folder_items(ctx), recent "devpod", source_items(ctx))
  end
  return groups(ctx.proj and { folder_items(ctx)[1] } or {}, recent(), {
    item(SSH, "Connect to Host…", "s", A.hosts, ctx),
    sub(BOX, "Dev Containers", "d", groups(folder_items(ctx), source_items(ctx))),
    sub("", "More", "m", more_items(ctx)),
  })
end

-- Keys nvzone/menu doesn't do (right): submenu hotkeys (its own look the
-- row up with vim.fn.index, which can't compare items holding functions);
-- l / → on a recent row opens its actions like a submenu (again: goes in);
-- the list keys act on recent rows directly
local function keys(buf, items)
  local utils = require "menu.utils"
  local state = require "menu.state"
  local function current()
    return items[api.nvim_win_get_cursor(0)[1]]
  end
  for i, it in ipairs(items) do
    if it.keybind then
      vim.keymap.set("n", it.keybind, function()
        api.nvim_win_set_cursor(0, { i, 0 })
        utils.toggle_nested_menu(it.name, it.items)
      end, { buffer = buf })
    end
  end
  for _, lhs in ipairs { "l", "<Right>" } do
    vim.keymap.set("n", lhs, function()
      local it = current()
      if it and it.session and state.nested_menu ~= it.session.id then
        return utils.toggle_nested_menu(it.session.id, row_items(it.session))
      end
      utils.switch_win(1)
    end, { buffer = buf })
  end
  for lhs, key in pairs(ROW_KEYS) do
    vim.keymap.set("n", lhs, function()
      local it = current()
      local run = it and it.session and row_action(key, it.session)
      if run then
        require("volt").close()
        vim.schedule(run)
      end
    end, { buffer = buf })
  end
end

-- Submenus opened any way (hotkey, ⏎, l) get keys() too
local function patch_nested()
  local utils = require "menu.utils"
  if utils._remote_keys then
    return
  end
  utils._remote_keys = true
  local toggle = utils.toggle_nested_menu
  function utils.toggle_nested_menu(name, items)
    toggle(name, items)
    local state = require "menu.state"
    local buf = state.bufids[#state.bufids]
    if OURS[items] and buf and state.bufs[buf] and state.bufs[buf].items == items then
      keys(buf, items)
    end
  end
end

-- Running dots and "2h ago" kept current while the popup is open
local function keep_live(buf, items)
  if not vim.iter(items):any(function(it) return it.render end) then
    return
  end
  local timer = assert(vim.uv.new_timer())
  timer:start(1000, 1000, vim.schedule_wrap(function()
    if timer:is_closing() then
      return
    end
    if not api.nvim_buf_is_valid(buf) then
      timer:stop()
      return timer:close()
    end
    local changed = false
    for _, it in ipairs(items) do
      if it.render then
        local before = it.name
        it.render()
        changed = changed or it.name ~= before
      end
    end
    if changed then
      require("volt").redraw(buf, "items")
    end
  end))
end

function M.open(opts)
  opts = opts or {}
  local items = M.tree(opts.scope)
  patch_nested()
  require("menu.utils").delete_old_menus()
  require("menu").open(items, {})
  local buf = require("menu.state").bufids[1]
  local win = buf and vim.fn.bufwinid(buf) or -1
  if win == -1 then
    return
  end
  -- centred like a launcher, not at the cursor like a context menu
  local cfg = api.nvim_win_get_config(win)
  api.nvim_win_set_config(win, {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - cfg.height) / 2) - 2),
    col = math.floor((vim.o.columns - cfg.width) / 2),
    title = opts.scope == "container" and " Dev Containers " or " Remote ",
    title_pos = "center",
  })
  keys(buf, items)
  keep_live(buf, items)
end

-- === :Devcontainer =========================================================

function M.commands()
  local out = vim.tbl_keys(COMMANDS)
  table.sort(out)
  return out
end

function M.run(name, arg)
  local fn = COMMANDS[name]
  if not fn then
    return core.notify(("Unknown :Devcontainer %s"):format(name), vim.log.levels.WARN)
  end
  fn(context(), arg)
end

return M
