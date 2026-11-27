-- Test coverage in the gutter (<leader>cTc), read from the report the test
-- run wrote: coverage.out (go test -coverprofile=coverage.out), .coverage
-- (pytest --cov), coverage/lcov.info (jest / vitest --coverage, flutter
-- test --coverage). Reloads when the report changes.
local loaded = false

return {
  "andythigpen/nvim-coverage",
  pin = true, -- unmaintained upstream; this commit works
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = { "Coverage", "CoverageLoad", "CoverageShow", "CoverageHide", "CoverageToggle", "CoverageSummary" },
  keys = {
    {
      "<leader>cTc",
      function()
        -- the first press loads the report, later ones show / hide the marks
        vim.cmd(loaded and "CoverageToggle" or "Coverage")
        loaded = true
      end,
      desc = "Test Coverage in Gutter",
    },
    { "<leader>cTC", "<cmd>CoverageLoad<cr><cmd>CoverageSummary<cr>", desc = "Test Coverage Summary" },
  },
  opts = { auto_reload = true },
}
