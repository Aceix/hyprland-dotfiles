-- Up-front dependency checks for test and debug runs. Toolchains are installed
-- by hand on each machine (this config gets copied to remote hosts that may
-- lack some), so a run whose tools are missing stops with one warning saying
-- what to install, instead of a stack trace from deep inside an adapter.
local M = {}

local data = vim.fn.stdpath "data"

-- A check is { test = fn() -> bool, what = string, hint = string }, built by
-- exe() / file() / mason(); `hint` says how to get it.
local function exe(name, hint)
  return { test = function() return vim.fn.executable(name) == 1 end, what = "`" .. name .. "`", hint = hint }
end

local function file(glob, what, hint)
  return { test = function() return vim.fn.glob(glob) ~= "" end, what = what, hint = hint }
end

local function mason(bin, pkg)
  return exe(bin, ("Mason package %s (:MasonInstall %s, then restart Neovim)"):format(pkg, pkg))
end

local node = exe("node", "install Node.js")
local go = exe("go", "install the Go toolchain")
local flutter = exe("flutter", "install the Flutter SDK")
local java = exe("java", "install a JDK")
-- Filetypes debugged and tested through Node (also used by configs/dap.lua)
M.js_fts = { "javascript", "javascriptreact", "typescript", "typescriptreact", "vue", "svelte" }

-- Test runs, by the filetype of the file under test (configs/neotest.lua)
M.test = {
  go = { label = "Go tests", go },
  dart = { label = "Flutter tests", flutter },
  java = {
    label = "Java tests",
    java,
    file(
      data .. "/neotest-java/junit-platform-console-standalone-*.jar",
      "the JUnit console jar",
      ":NeotestJava setup"
    ),
  },
  python = {
    label = "Python tests",
    {
      test = function() return require("utils.python").path() ~= "" end,
      what = "a Python interpreter",
      hint = "install python3 or create the project's .venv",
    },
  },
}
for _, ft in ipairs(M.js_fts) do
  M.test[ft] = { label = "JS/TS tests", node }
end

-- Debug sessions, by dap configuration type (configs/dap.lua)
M.debug = {
  delve = { label = "Go debugging", go, mason("dlv", "delve") },
  python = { label = "Python debugging", mason("debugpy-adapter", "debugpy") },
  ["pwa-node"] = { label = "JS/TS debugging", node, mason("js-debug-adapter", "js-debug-adapter") },
  ["pwa-chrome"] = { label = "Browser debugging", mason("js-debug-adapter", "js-debug-adapter") },
  dart = { label = "Flutter debugging", flutter },
  java = {
    label = "Java debugging",
    java,
    file(
      data .. "/mason/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar",
      "the java-debug bundle",
      ":MasonInstall java-debug-adapter, then restart Neovim"
    ),
  },
}
M.debug.go = M.debug.delve

-- Debugger a neotest `strategy = "dap"` run uses, by filetype
local debug_type = { go = "delve", python = "python", java = "java", dart = "dart" }
for _, ft in ipairs(M.js_fts) do
  debug_type[ft] = "pwa-node"
end

-- Returns true when everything `key` needs in `kind` (M.test / M.debug) is
-- there, or nothing is known about it. Otherwise warns and returns false.
function M.ok(kind, key)
  local spec = key and kind[key]
  if not spec then
    return true
  end
  local missing = {}
  for _, check in ipairs(spec) do
    if not check.test() then
      missing[#missing + 1] = ("  • %s: %s"):format(check.what, check.hint)
    end
  end
  if #missing == 0 then
    return true
  end
  vim.notify(
    ("Can't start %s, missing on %s:\n%s"):format(spec.label, vim.uv.os_gethostname(), table.concat(missing, "\n")),
    vim.log.levels.WARN
  )
  return false
end

-- Filetype of what a neotest.run.run() call targets: a position id
-- ("path::Test"), a path, or nothing (the cursor, so the current buffer).
-- A directory (whole suite) has no single filetype; use the current buffer's.
local function target_ft(args)
  local target = type(args) == "table" and args[1] or args
  if type(target) == "string" then
    local path = target:gsub("::.*$", "")
    if vim.fn.isdirectory(path) == 0 then
      return vim.filetype.match { filename = path }
    end
  end
  return vim.bo.filetype
end

-- Wraps neotest.run.run (keymaps and gutter buttons all go through it). A
-- `strategy = "dap"` run also needs that language's debugger.
function M.guard_neotest()
  local run = require("neotest").run
  local original = run.run
  run.run = function(args)
    local ft = target_ft(args)
    if not M.ok(M.test, ft) then
      return
    end
    if type(args) == "table" and args.strategy == "dap" and not M.ok(M.debug, debug_type[ft]) then
      return
    end
    return original(args)
  end
end

-- Wraps dap.run, which continue, run_last, neotest's dap strategy, nvim-jdtls
-- and flutter-tools all end up calling.
function M.guard_dap()
  local dap = require "dap"
  local original = dap.run
  dap.run = function(config, ...)
    if type(config) == "table" and not M.ok(M.debug, config.type) then
      return
    end
    return original(config, ...)
  end
end

return M
