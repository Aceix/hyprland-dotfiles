return function()
  local dap = require "dap"
  local dapui = require "dapui"
  local dap_ui = require "utils.dap_ui"

  -- Gutter signs (Nerd Font codepoints), colors come from hl_add in chadrc.lua
  local icon = vim.fn.nr2char
  local signs = {
    DapBreakpoint = { icon(0xf111), "DapBreakpoint" }, -- circle
    DapBreakpointCondition = { icon(0xf059), "DapBreakpoint" }, -- question circle
    DapLogPoint = { icon(0xf05a), "DapLogPoint" }, -- info circle
    DapBreakpointRejected = { icon(0xf057), "DapBreakpointRejected" }, -- x circle
    DapStopped = { icon(0xf0055), "DapStopped", "DapStoppedLine" }, -- arrow right
  }
  for name, s in pairs(signs) do
    vim.fn.sign_define(name, { text = s[1], texthl = s[2], linehl = s[3], numhl = "" })
  end

  -- Let python find a project venv without activating it first
  local function python_path()
    return require("utils.python").path()
  end

  -- A handler list (rather than `handlers = {}`) still registers the default
  -- adapter + configurations for every installed adapter it knows (delve for
  -- Go, debugpy), with two exceptions: Dart is left to flutter-tools, which
  -- knows the selected device, and python gets a venv-aware interpreter.
  -- Java goes through nvim-jdtls instead.
  local mason_dap = require "mason-nvim-dap"
  mason_dap.setup {
    ensure_installed = { "delve", "python" },
    automatic_installation = false, -- mason-tool-installer owns installs
    handlers = {
      mason_dap.default_setup,
      dart = function() end,
      python = function(config)
        for _, c in ipairs(config.configurations or {}) do
          c.pythonPath = python_path
        end
        mason_dap.default_setup(config)
      end,
    },
  }

  -- JS/TS: Node, and web apps in a browser, offered by project (utils/js_debug.lua)
  local js_debug = vim.fn.exepath "js-debug-adapter"
  if js_debug ~= "" then
    require("utils.js_debug").setup(js_debug)
  end

  -- .vscode/launch.json is read by nvim-dap on its own; these make the
  -- VS Code type names resolve to the adapters registered above.
  local function alias(name, target)
    dap.adapters[name] = function(callback, config)
      -- js-debug only answers to its own pwa-* type names
      if target:match "^pwa%-" then
        config.type = target
      end
      local adapter = dap.adapters[target]
      if type(adapter) == "function" then
        adapter(callback, config)
      elseif adapter then
        callback(adapter)
      else
        vim.notify("dap: no '" .. target .. "' adapter for type '" .. name .. "'", vim.log.levels.ERROR)
      end
    end
  end
  alias("node", "pwa-node")
  alias("chrome", "pwa-chrome")
  alias("go", "delve")

  -- NASM through gdb's built-in DAP mode (gdb 14+). Assemble with
  -- `nasm -f elf64 -g -F dwarf` so line breakpoints have something to bind to.
  dap.adapters.gdb = {
    type = "executable",
    command = "gdb",
    args = { "--interpreter=dap", "--eval-command", "set print pretty on" },
  }
  local asm_configs = {
    {
      type = "gdb",
      request = "launch",
      name = "gdb: launch executable",
      program = function()
        return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
      end,
      cwd = "${workspaceFolder}",
      stopAtBeginningOfMainSubprogram = false,
    },
  }
  dap.configurations.asm = asm_configs
  dap.configurations.nasm = asm_configs

  require("nvim-dap-virtual-text").setup {
    enabled = true,
    commented = false,
    virt_text_pos = "eol",
  }

  require("persistent-breakpoints").setup {
    load_breakpoints_event = { "BufReadPost" },
  }

  -- VS Code-like: Variables/Watch/Call Stack/Breakpoints on the left,
  -- REPL (with the toolbar) and program output at the bottom.
  dapui.setup {
    layouts = {
      {
        position = "left",
        size = 45,
        elements = {
          { id = "scopes", size = 0.40 },
          { id = "watches", size = 0.20 },
          { id = "stacks", size = 0.25 },
          { id = "breakpoints", size = 0.15 },
        },
      },
      {
        position = "bottom",
        size = 12,
        elements = {
          { id = "repl", size = 0.60 },
          { id = "console", size = 0.40 },
        },
      },
    },
    controls = { enabled = true, element = "repl" },
  }

  -- Open the UI when debugging starts. It stays open after the session ends
  -- so the final output is still readable; <leader>dt closes it.
  dap.listeners.before.attach.dapui_config = dap_ui.open
  dap.listeners.before.launch.dapui_config = dap_ui.open

  -- Warn and stop when a session's debugger is missing (utils/deps.lua)
  require("utils.deps").guard_dap()
end
