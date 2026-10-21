return {
  "sudo-tee/opencode.nvim",
  lazy = false,
  opts = { keymap_prefix = "<leader>ao" },
  dependencies = {
    "MeanderingProgrammer/render-markdown.nvim",
    "saghen/blink.cmp", -- file mentions and command completion
    "nvim-telescope/telescope.nvim", -- file mentions picker
    "folke/snacks.nvim",
  },
}
