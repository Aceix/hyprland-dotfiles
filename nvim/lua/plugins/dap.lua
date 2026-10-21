local call = require "utils.call"

local function dap(fn)
  return call("dap", fn)
end

-- Breakpoint edits go through persistent-breakpoints so they survive restarts
local function bp(fn)
  return call("persistent-breakpoints.api", fn)
end

local spec = {
  "mfussenegger/nvim-dap",
  -- Loads with the first file so persistent-breakpoints can restore that
  -- buffer's breakpoints on BufReadPost.
  event = { "BufReadPre", "BufNewFile" },
  dependencies = {
    -- Provides a nice graphical user interface for debugging
    "rcarriga/nvim-dap-ui",
    -- Required dependency for nvim-dap-ui
    "nvim-neotest/nvim-nio",
    -- Bridges mason.nvim with nvim-dap to easily install debuggers
    "jay-babu/mason-nvim-dap.nvim",
    -- Variable values inline while stepping, <leader>dv toggles
    "theHamsta/nvim-dap-virtual-text",
    -- Saves breakpoints per file across restarts
    "Weissle/persistent-breakpoints.nvim",
  },
  keys = {
    -- Breakpoints
    { "<leader>db", bp "toggle_breakpoint", desc = "Toggle Breakpoint" },
    { "<leader>dB", bp "set_conditional_breakpoint", desc = "Conditional Breakpoint" },
    { "<leader>dL", bp "set_log_point", desc = "Log Point" },
    { "<leader>dX", bp "clear_all_breakpoints", desc = "Clear All Breakpoints" },

    -- Session
    { "<leader>dc", dap "continue", desc = "Continue/Start Debugging" },
    { "<leader>dl", dap "run_last", desc = "Run Last" },
    { "<leader>dR", dap "restart", desc = "Restart" },
    { "<leader>dp", dap "pause", desc = "Pause" },
    { "<leader>dx", dap "terminate", desc = "Terminate" },

    -- Stepping
    { "<leader>do", dap "step_over", desc = "Step Over" },
    { "<leader>di", dap "step_into", desc = "Step Into" },
    { "<leader>dO", dap "step_out", desc = "Step Out" },
    { "<leader>dC", dap "run_to_cursor", desc = "Run to Cursor" },
    { "<leader>dk", dap "up", desc = "Stack Frame Up" },
    { "<leader>dj", dap "down", desc = "Stack Frame Down" },

    -- Inspecting
    { "<leader>de", call("dapui", "eval"), mode = { "n", "v" }, desc = "Eval Expression" },
    {
      "<leader>dw",
      function()
        require("dapui").elements.watches.add(vim.fn.expand "<cexpr>")
      end,
      desc = "Watch Expression",
    },
    { "<leader>dv", "<cmd>DapVirtualTextToggle<cr>", desc = "Toggle Inline Values" },
    {
      "<leader>dr",
      function()
        require("dap").repl.open()
      end,
      desc = "Open REPL",
    },
    { "<leader>dt", call("utils.dap_ui", "toggle"), desc = "Toggle Debugger UI" },
  },
  config = require "configs.dap",
}

-- VS Code debug keys, only with settings.vscode_keys (lazy-load dap on press)
if require("settings").vscode_keys then
  vim.list_extend(spec.keys, {
    { "<F5>", dap "continue", desc = "Debug: Start/Continue" },
    { "<S-F5>", dap "terminate", desc = "Debug: Stop" },
    { "<C-S-F5>", dap "restart", desc = "Debug: Restart" },
    { "<F6>", dap "pause", desc = "Debug: Pause" },
    { "<F9>", bp "toggle_breakpoint", desc = "Debug: Toggle Breakpoint" },
    { "<F10>", dap "step_over", desc = "Debug: Step Over" },
    { "<F11>", dap "step_into", desc = "Debug: Step Into" },
    { "<S-F11>", dap "step_out", desc = "Debug: Step Out" },
  })
end

return spec
