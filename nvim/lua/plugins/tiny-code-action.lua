-- Code actions (<leader>ca / <C-.>) in a picker that previews each one's diff
return {
  "rachartier/tiny-code-action.nvim",
  dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope.nvim" },
  opts = { picker = "telescope" },
}
