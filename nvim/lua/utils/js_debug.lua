-- JS/TS debugging through vscode-js-debug: Node, and web apps (Vue/Nuxt,
-- React/Next, Angular, Svelte, Astro, ...) in a Chromium browser.
--
-- The debug menu gets its entries from the project, not the buffer's filetype:
-- any buffer under a package.json (css, html, json too) offers
--   * "Web: dev server + browser": runs the dev script under the debugger
--     (server-side breakpoints bind), reads the URL it prints and opens a
--     browser session on it. Stopping the server closes that browser.
--   * "Web: browser on running dev server": for a server you started yourself.
-- The browser is picked per session (last choice first) and runs with its own
-- persistent profile, so it never clashes with your open browser and keeps
-- the DevTools extensions and logins you add to it.
local M = {}

local APP = "Web: dev server + browser"
local skip = { "<node_internals>/**", "**/node_modules/**" }

-- First listed dependency found decides the dev server's default port
local frameworks = {
  { "@angular/core", 4200 },
  { "nuxt", 3000 },
  { "next", 3000 },
  { "astro", 4321 },
  { "gatsby", 8000 },
  { "react-scripts", 3000 },
  { "@vue/cli-service", 8080 },
  { "vite", 5173 }, -- Vue, React, Svelte(Kit), Solid, Remix, ...
}

local lockfiles = {
  ["pnpm-lock.yaml"] = "pnpm",
  ["yarn.lock"] = "yarn",
  ["bun.lock"] = "bun",
  ["bun.lockb"] = "bun",
  ["package-lock.json"] = "npm",
}

-- Chromium-based, so js-debug drives them all; only installed ones are offered
local browsers = {
  { "Chrome", "google-chrome-stable", "google-chrome" },
  { "Chromium", "chromium" },
  { "Brave", "brave", "brave-browser" },
  { "Edge", "microsoft-edge-stable" },
}

local last_browser -- label picked last time
local last_url = {} -- project root -> URL its dev server printed

-- What the project under `bufnr` is: { root, pm, script, port }. `script` is
-- nil without a dev/start/serve script, `port` nil when it's not a web app.
local function project(bufnr)
  local root = vim.fs.root(bufnr, "package.json")
  if not root then
    return nil
  end
  local ok, pkg = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(root .. "/package.json"), "\n"))
  end)
  pkg = ok and type(pkg) == "table" and pkg or {}
  local deps = vim.tbl_extend("force", pkg.dependencies or {}, pkg.devDependencies or {})
  local scripts = pkg.scripts or {}

  local p = { root = root, pm = "npm" }
  -- Lockfiles sit at the workspace root in monorepos, so look upwards
  local lock = vim.fs.find(vim.tbl_keys(lockfiles), { upward = true, path = root })[1]
  if lock then
    p.pm = lockfiles[vim.fs.basename(lock)]
  end
  for _, name in ipairs { "dev", "start", "serve" } do
    if scripts[name] then
      p.script = name
      break
    end
  end
  for _, f in ipairs(frameworks) do
    if deps[f[1]] then
      p.port = f[2]
      break
    end
  end
  return p
end

-- Asks which installed browser to use (nil: none or cancelled); must run
-- inside a coroutine
local function pick_browser()
  local installed = {}
  for _, b in ipairs(browsers) do
    for i = 2, #b do
      local exe = vim.fn.exepath(b[i])
      if exe ~= "" then
        table.insert(installed, b[1] == last_browser and 1 or #installed + 1, { label = b[1], exe = exe })
        break
      end
    end
  end
  if #installed == 0 then
    vim.notify("No Chromium-based browser found (Chrome, Chromium, Brave, Edge)", vim.log.levels.ERROR)
  end
  if #installed <= 1 then
    return installed[1]
  end
  local co = coroutine.running()
  vim.ui.select(installed, {
    prompt = "Browser",
    format_item = function(b)
      return b.label
    end,
  }, function(choice)
    vim.schedule(function()
      coroutine.resume(co, choice)
    end)
  end)
  return coroutine.yield()
end

-- A browser session on `url`. Callable, so nvim-dap only builds it (and asks
-- for the browser) when it runs; run_last asks again.
local function browser(url, root)
  return setmetatable({ type = "pwa-chrome", request = "launch", name = "Browser: " .. url, url = url }, {
    __call = function(stub)
      local b = pick_browser()
      if not b then
        return vim.tbl_extend("force", stub, { url = require("dap").ABORT })
      end
      last_browser = b.label
      return vim.tbl_extend("force", stub, {
        runtimeExecutable = b.exe,
        userDataDir = vim.fn.stdpath "data" .. "/dap-browser/" .. b.label:lower(),
        webRoot = root,
        sourceMaps = true,
        skipFiles = skip,
      })
    end,
  })
end

-- `<pm> run <script>` under the debugger. js-debug follows the processes it
-- spawns, so Next/Nuxt/SvelteKit SSR and API route breakpoints bind. Output
-- comes through the adapter (not a terminal) so the URL can be read from it.
local function server(p, name)
  return {
    type = "pwa-node",
    request = "launch",
    name = name,
    runtimeExecutable = p.pm,
    runtimeArgs = { "run", p.script },
    cwd = p.root,
    autoAttachChildProcesses = true,
    outputCapture = "std",
    sourceMaps = true,
    skipFiles = skip,
  }
end

local node_file = {
  type = "pwa-node",
  request = "launch",
  name = "Node: launch current file",
  program = "${file}",
  cwd = "${workspaceFolder}",
  sourceMaps = true,
  skipFiles = skip,
  console = "integratedTerminal",
}

local node_attach = {
  type = "pwa-node",
  request = "attach",
  name = "Node: attach to process (--inspect)",
  processId = "${command:pickProcess}",
  cwd = "${workspaceFolder}",
  sourceMaps = true,
  skipFiles = skip,
}

local function configs(bufnr)
  local list = {}
  local p = project(bufnr)
  if p and p.port then
    if p.script then
      table.insert(list, server(p, APP))
    end
    table.insert(list, browser(last_url[p.root] or ("http://localhost:" .. p.port), p.root))
  elseif p and p.script then
    table.insert(list, server(p, ("Node: %s run %s"):format(p.pm, p.script)))
  end
  if vim.tbl_contains(require("utils.deps").js_fts, vim.bo[bufnr].filetype) then
    table.insert(list, node_file)
  end
  if p or #list > 0 then
    table.insert(list, node_attach)
  end
  return list
end

local function root_session(session)
  while session.parent do
    session = session.parent
  end
  return session
end

function M.setup(js_debug)
  local dap = require "dap"
  for _, adapter in ipairs { "pwa-node", "pwa-chrome" } do
    dap.adapters[adapter] = {
      type = "server",
      host = "localhost",
      port = "${port}",
      executable = { command = js_debug, args = { "${port}" } },
    }
  end

  -- Providers are listed in name order: after dap.global and launch.json
  dap.providers.configs.js = configs

  -- The first local URL the dev server prints opens the browser session
  dap.listeners.after.event_output.js_debug = function(session, body)
    local app = root_session(session)
    if app.config.name ~= APP or app.web_url or not body.output then
      return
    end
    local url = body.output:gsub("\27%[[%d;]*m", ""):match "https?://[%w%.%-]+:%d+/?"
    if url and (url:find "localhost" or url:find "127%.0%.0%.1") then
      app.web_url = url
      last_url[app.config.cwd] = url
      dap.run(browser(url, app.config.cwd))
      -- Stopping the server (any way it ends) closes its browser. on_close
      -- may run inside the luv loop, hence the schedule.
      app.on_close.js_debug = function()
        vim.schedule(function()
          for _, s in pairs(dap.sessions()) do
            if s.config.type == "pwa-chrome" and s.config.url == url then
              s:disconnect { terminateDebuggee = true }
            end
          end
        end)
      end
    end
  end
end

return M
