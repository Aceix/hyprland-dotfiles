-- :checkhealth utils -- this config's own modules and what they expect to
-- find on the machine. Nothing here loads a plugin or installs anything.
local M = {}

local h = vim.health
local config = vim.fn.stdpath "config"
local data = vim.fn.stdpath "data"

-- { binary, what stops working without it, required? }
local tools = {
  { "git", "everything git, plugin installs, local history", true },
  { "rg", "live grep, search & replace", true },
  { "fd", "file finder (falls back to find)" },
  { "cc", "building treesitter parsers" },
  { "tree-sitter", "building treesitter parsers" },
  { "node", "JS-based language servers and debuggers" },
  { "magick", "image.nvim previews" },
  { "gh", "GitHub pull requests / issues (octo)" },
  { "ast-grep", "structural search (<leader>sa)" },
  { "copilot-language-server", "Copilot ghost text and next-edit suggestions" },
  { "claude", "Claude Code (<leader>al)" },
  { "claude-agent-acp", "CodeCompanion's Claude agent (<leader>aA)" },
  { "codex-acp", "CodeCompanion's Codex agent (<leader>aA)" },
  { "gemini", "CodeCompanion's Gemini agent (<leader>aA)" },
}

local function report(ok, required, msg, advice)
  if ok then
    h.ok(msg)
  elseif required then
    h.error(msg, advice)
  else
    h.warn(msg, advice)
  end
end

local function check_neovim()
  h.start "Neovim"
  local v = vim.version()
  local have = ("%d.%d.%d"):format(v.major, v.minor, v.patch)
  if vim.fn.has "nvim-0.12" == 0 then
    h.error(have .. ": this config needs 0.12+")
  elseif vim.fn.has "nvim-0.12.5" == 0 then
    h.warn(have .. ": refactoring.nvim (<leader>cx) needs 0.12.5+")
  else
    h.ok(have)
  end
end

-- Compiled, not run: require()ing a module can start watchers and timers
local function check_modules()
  h.start "Config modules"
  local bad = 0
  for _, path in ipairs(vim.fn.globpath(config .. "/lua", "**/*.lua", false, true)) do
    local _, err = loadfile(path)
    if err then
      bad = bad + 1
      h.error(err)
    end
  end
  if bad == 0 then
    h.ok "every file under lua/ compiles"
  end
end

local function check_tools()
  h.start "Tools"
  for _, tool in ipairs(tools) do
    local name, why, required = tool[1], tool[2], tool[3]
    local found = vim.fn.executable(name) == 1
    report(found, required, found and name or ("%s not found: %s"):format(name, why))
  end
end

-- utils/deps.lua's tables: what each language's test and debug runs need
local function check_deps()
  local deps = require "utils.deps"
  for title, kind in pairs { ["Test runs"] = deps.test, ["Debug sessions"] = deps.debug } do
    h.start(title)
    local seen = {} -- several filetypes share one entry (JS/TS)
    for _, spec in pairs(kind) do
      if not seen[spec.label] then
        seen[spec.label] = true
        local missing = {}
        for _, check in ipairs(spec) do
          if not check.test() then
            missing[#missing + 1] = ("%s: %s"):format(check.what, check.hint)
          end
        end
        report(#missing == 0, false, spec.label, missing)
      end
    end
  end
end

-- lua/langs: tooling that installs itself the first time a file of that
-- language is opened, so "not installed yet" is information, not a problem
local function check_langs()
  local ok, langs = pcall(require, "langs")
  if not ok then
    return
  end
  h.start "Languages set up on first use (lua/langs)"
  for name in pairs(langs.index) do
    local spec = langs.spec(name)
    local missing = {}
    for _, pkg in ipairs(spec.mason or {}) do
      pkg = type(pkg) == "table" and pkg[1] or pkg
      if not vim.uv.fs_stat(data .. "/mason/packages/" .. pkg) then
        missing[#missing + 1] = pkg
      end
    end
    if #missing == 0 then
      h.ok(name)
    else
      h.info(("%s: installs %s when first opened"):format(name, table.concat(missing, ", ")))
    end
  end
end

local function check_state()
  h.start "State"
  if vim.uv.fs_stat(data .. "/molten-venv/.ready") then
    h.ok "Jupyter (molten) venv"
  else
    h.info "Jupyter (molten) venv not created: run :MoltenSetup before <leader>Ni"
  end
  local history = require("utils.local_history").dir
  if vim.uv.fs_stat(history .. "/.git") then
    h.ok("local history repo: " .. history)
  else
    h.info "local history repo is created on the first save"
  end
end

function M.check()
  check_neovim()
  check_modules()
  check_tools()
  check_deps()
  check_langs()
  check_state()
end

return M
