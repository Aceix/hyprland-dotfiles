-- Test runner framework with per-language adapters, see
-- https://github.com/nvim-neotest/neotest
return {
  "nvim-neotest/neotest",
  dependencies = {
    -- Required by neotest core
    "nvim-neotest/nvim-nio",
    "nvim-lua/plenary.nvim",
    "antoinemadec/FixCursorHold.nvim",
    "nvim-treesitter/nvim-treesitter",

    -- Language adapters, wired up in configs/neotest.lua
    "fredrikaverpil/neotest-golang",
    -- neotest-golang's debug strategy (<leader>cTd) runs delve through it.
    -- It sets itself up per debug run, taking over dap's "go" adapter and
    -- Go launch configs from mason-nvim-dap (same delve, more test configs).
    "leoluz/nvim-dap-go",
    "sidlatau/neotest-dart",
    "nvim-neotest/neotest-jest",
    "marilari88/neotest-vitest",
    -- neotest-java drives jdtls, which is set up in plugins/jdtls.lua
    "rcasia/neotest-java",
    "nvim-neotest/neotest-python",
  },
  cmd = "Neotest",
  -- Load as soon as a test file opens so its run buttons are already in the
  -- gutter (utils/test_gutter.lua), not only after the first test key.
  event = {
    {
      event = { "BufReadPost", "BufNewFile" },
      pattern = {
        "*_test.go",
        "*.test.{js,jsx,ts,tsx,mjs,cjs,mts,cts}",
        "*.spec.{js,jsx,ts,tsx,mjs,cjs,mts,cts}",
        "*/__tests__/*",
        "*_test.dart",
        "*Test.java",
        "*Tests.java",
        "*IT.java",
        "test_*.py",
        "*_test.py",
      },
    },
  },
  keys = {
    {
      "<leader>cTt",
      function()
        require("neotest").run.run()
      end,
      desc = "Test Nearest",
    },
    {
      "<leader>cTf",
      function()
        require("neotest").run.run(vim.fn.expand "%")
      end,
      desc = "Test Current File",
    },
    {
      "<leader>cTA",
      function()
        require("neotest").run.run(vim.uv.cwd())
      end,
      desc = "Test Whole Suite",
    },
    {
      "<leader>cTl",
      function()
        require("neotest").run.run_last()
      end,
      desc = "Test Rerun Last",
    },
    {
      "<leader>cTd",
      function()
        require("neotest").run.run { strategy = "dap" }
      end,
      desc = "Test Debug Nearest",
    },
    {
      "<leader>cTx",
      function()
        require("neotest").run.stop()
      end,
      desc = "Test Stop",
    },
    {
      "<leader>cTa",
      function()
        require("neotest").run.attach()
      end,
      desc = "Test Attach To Running",
    },
    {
      "<leader>cTs",
      function()
        require("neotest").summary.toggle()
      end,
      desc = "Test Summary Toggle",
    },
    {
      "<leader>cTo",
      function()
        require("neotest").output.open { enter = true, auto_close = true }
      end,
      desc = "Test Output Float",
    },
    {
      "<leader>cTO",
      function()
        require("utils.test_results").toggle()
      end,
      desc = "Test Results Panel",
    },
    {
      "<leader>cTw",
      function()
        require("neotest").watch.toggle(vim.fn.expand "%")
      end,
      desc = "Test Watch File",
    },
  },
  config = require "configs.neotest",
}
