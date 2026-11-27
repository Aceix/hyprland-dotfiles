return {
  "sudo-tee/opencode.nvim",
  -- Needs the `opencode` CLI; without it setup() errors at startup
  cond = vim.fn.executable "opencode" == 1,
  cmd = "Opencode",
  keys = { { "<leader>ao", mode = { "n", "v" }, desc = "OpenCode" } },
  opts = { keymap_prefix = "<leader>ao" },
  dependencies = {
    "MeanderingProgrammer/render-markdown.nvim",
    "saghen/blink.cmp", -- file mentions and command completion
    "nvim-telescope/telescope.nvim", -- file mentions picker
    "folke/snacks.nvim",
  },
}
