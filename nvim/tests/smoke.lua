-- Headless smoke test, run by tests/smoke.sh. Checks that the config starts
-- clean, that nothing beyond `startup` below loads before a file is opened,
-- and that each language's tooling switches on for its files and only then.
local failures, passed = {}, 0

local function check(ok, what)
  if ok then
    passed = passed + 1
  else
    failures[#failures + 1] = what
  end
end

local function loaded_plugins()
  local names = {}
  for _, plugin in pairs(require("lazy").plugins()) do
    if plugin._.loaded then
      names[#names + 1] = plugin.name
    end
  end
  table.sort(names)
  return names
end

local function plugin_loaded(name)
  local plugin = require("lazy.core.config").plugins[name]
  return plugin ~= nil and plugin._.loaded ~= nil
end

-- Plugins allowed to be loaded once startup (including VeryLazy) is done and
-- no file is open. Adding to this list is a decision, not a fix.
local startup = {
  "NvChad",
  "base46",
  "camouflage.nvim",
  "edgy.nvim",
  "fidget.nvim",
  "flash.nvim",
  "lazy.nvim",
  "mason-nvim-dap.nvim",
  "mason-tool-installer.nvim",
  "mason.nvim",
  "nvim-treesitter",
  "nvim-web-devicons",
  "outline.nvim",
  "persistence.nvim",
  "plenary.nvim",
  "projectmgr.nvim",
  "snacks.nvim",
  "telescope.nvim",
  "ts-comments.nvim",
  "ui",
  "which-key.nvim",
}

-- Never before a matching file, key or command
local on_demand = {
  "arrow.nvim",
  "blink.cmp",
  "claudecode.nvim",
  "codecompanion.nvim",
  "coerce.nvim",
  "conform.nvim",
  "crates.nvim",
  "csvview.nvim",
  "file-history.nvim",
  "flutter-tools.nvim",
  "glance.nvim",
  "hardtime.nvim",
  "image.nvim",
  "inc-rename.nvim",
  "mini.ai",
  "mini.map",
  "mini.surround",
  "molten-nvim",
  "neotest",
  "neotest-pest",
  "neotest-phpunit",
  "nvim-coverage",
  "nvim-dap",
  "nvim-lint",
  "nvim-lspconfig",
  "nvim-treesitter-context",
  "nvim-treesitter-textobjects",
  "nvim-ts-autotag",
  "overseer.nvim",
  "rainbow-delimiters.nvim",
  "refactoring.nvim",
  "rustaceanvim",
  "sidekick.nvim",
  "tiny-code-action.nvim",
  "tiny-inline-diagnostic.nvim",
  "vim-dadbod",
  "vim-dadbod-completion",
  "vim-dadbod-ui",
  "zen-mode.nvim",
}

local dir = vim.env.SMOKE_DIR

-- v:errmsg holds the last error, including ones raised under `silent!`
local benign = {
  "Couldn't find a watcher matching key and callback", -- mini.map's setup, by design
  "E31: No such mapping", -- ftplugins undoing their maps (`silent! nunmap`) when FileType re-fires
}
local function no_error(stage)
  local msg = vim.v.errmsg
  vim.v.errmsg = ""
  for _, known in ipairs(benign) do
    if msg:find(known, 1, true) then
      return
    end
  end
  check(msg == "", ("error %s: %s"):format(stage, msg))
end

local function write(name, lines)
  local path = dir .. "/" .. name
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
  return path
end

local function open(name, lines)
  vim.cmd.edit(vim.fn.fnameescape(write(name, lines)))
  return vim.api.nvim_get_current_buf()
end

local function attaches(buf, client, timeout)
  return vim.wait(timeout or 15000, function()
    return #vim.lsp.get_clients { bufnr = buf, name = client } > 0
  end, 100)
end

local function run()
  -- 1. Startup
  no_error "at startup"
  for _, note in ipairs(Smoke.notes) do
    check(false, "startup warning: " .. note)
  end

  -- Headless has no UI, so lazy.nvim never fires this itself
  vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
  vim.wait(200)
  no_error "on VeryLazy"

  -- 2. Every spec file returns a table, every plugin is installed
  for _, path in ipairs(vim.fn.globpath(vim.fn.stdpath "config" .. "/lua/plugins", "*.lua", false, true)) do
    local ok, spec = pcall(dofile, path)
    check(ok and type(spec) == "table", "bad spec file " .. path .. (ok and "" or ": " .. tostring(spec)))
  end
  for _, plugin in pairs(require("lazy").plugins()) do
    check(plugin._.installed, "not installed: " .. plugin.name .. " (run :Lazy install)")
  end

  -- 3. Nothing extra at startup
  local allowed = {}
  for _, name in ipairs(startup) do
    allowed[name] = true
  end
  for _, name in ipairs(loaded_plugins()) do
    check(allowed[name], "loaded at startup, not in tests/smoke.lua's `startup` list: " .. name)
  end
  for _, name in ipairs(on_demand) do
    check(not plugin_loaded(name), "loaded before it was needed: " .. name)
  end
  for mod in pairs(package.loaded) do
    check(not mod:match "^langs%.", "language spec read at startup: " .. mod)
  end
  check(vim.g.loaded_python3_provider == 0, "the Python provider is enabled at startup")

  -- 4. Built-ins this config relies on
  check(pcall(vim.cmd.packadd, "nvim.undotree") and vim.fn.exists ":Undotree" == 2, "built-in :Undotree missing")

  -- 5. Languages
  write("go.mod", { "module smoke", "", "go 1.22" })
  local go = open("main.go", { "package main", "", "func main() {}" })
  if vim.fn.executable "gopls" == 1 then
    check(attaches(go, "gopls"), "gopls did not attach to a .go file")
  end

  -- Languages set up on first use (lua/langs): nothing of theirs before
  -- their first file, their server after it. Mason is in dry-run mode here
  -- (smoke_pre.lua), so a server not installed on this machine yet counts
  -- as passed when it was queued for install.
  local mason = require "utils.mason_ensure"
  local function starts(buf, client, pkg)
    if vim.tbl_contains(mason.dry, pkg) then
      return true
    end
    return attaches(buf, client)
  end

  check(not vim.lsp.is_enabled "phpantom_lsp", "PHP server enabled before a PHP file was opened")
  write("php/composer.json", { '{ "name": "smoke/smoke" }' })
  local php = open("php/index.php", { "<?php", "", "echo 1;" })
  check(package.loaded["langs.php"] ~= nil, "lua/langs/php.lua not read for a .php file")
  check(starts(php, "phpantom_lsp", "phpantom_lsp"), "phpantom_lsp did not attach to a .php file")
  check(not plugin_loaded "rustaceanvim", "Rust tooling loaded by a PHP file")
  check(vim.filetype.match { filename = "view.blade.php" } == "blade", "*.blade.php is not filetype `blade`")

  write("Cargo.toml", { "[package]", 'name = "smoke"', 'version = "0.1.0"', 'edition = "2021"' })
  local rust = open("src/main.rs", { "fn main() {}" })
  check(plugin_loaded "rustaceanvim", "rustaceanvim not loaded for a .rs file")
  check(not vim.lsp.is_enabled "rust_analyzer", "lspconfig's rust_analyzer enabled next to rustaceanvim")
  check(starts(rust, "rust-analyzer", "rust-analyzer"), "rust-analyzer did not attach to a .rs file")

  local sh = open("run.sh", { "#!/bin/sh", "echo hi" })
  check(starts(sh, "bashls", "shellcheck"), "bashls did not attach to a .sh file")

  open("compose.yaml", { "services: {}" })
  check(vim.bo.filetype == "yaml.docker-compose", "compose.yaml is not filetype yaml.docker-compose")
  check(
    vim.lsp.is_enabled "docker_compose_language_service" or vim.tbl_contains(mason.dry, "hadolint"),
    "Compose language server not enabled for compose.yaml"
  )

  local sql = open("query.sql", { "select 1;" })
  vim.wait(500)
  check(
    #vim.lsp.get_clients { bufnr = sql, name = "postgres_lsp" } == 0,
    "postgres_lsp started without its config file"
  )

  -- Jupyter: a Python file alone must not switch the Python provider on
  open("script.py", { "print(1)" })
  check(not plugin_loaded "molten-nvim", "molten-nvim loaded by opening a .py file")
  check(vim.g.loaded_python3_provider == 0, "the Python provider was enabled by opening a .py file")

  -- On/off switches registered (configs/toggles.lua)
  for _, key in ipairs { "F", "d", "l", "c", "h", "s", "N", "g", "r", "v", "C", "H" } do
    check(vim.fn.maparg("<leader>u" .. key, "n") ~= "", "toggle <leader>u" .. key .. " is not mapped")
  end

  -- A big file: flagged, no treesitter
  local long = open("bundle.min.js", { ("x=1;"):rep(2000) })
  vim.wait(200)
  check(vim.b[long].bigfile == true, "minified file not flagged as a big file")
  check(vim.treesitter.highlighter.active[long] == nil, "treesitter still running in a big file")

  no_error "after opening files"
end

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.schedule(function()
      local ok, err = xpcall(run, debug.traceback)
      if not ok then
        failures[#failures + 1] = "smoke test crashed: " .. err
      end
      local out = { ("smoke: %d passed, %d failed"):format(passed, #failures) }
      for _, failure in ipairs(failures) do
        out[#out + 1] = "  FAIL " .. failure
      end
      io.stdout:write(table.concat(out, "\n") .. "\n")
      vim.cmd(#failures == 0 and "qall!" or "cquit 1")
    end)
  end,
})
