return {
  "folke/todo-comments.nvim",
  event = { "BufReadPost", "BufNewFile" },
  cmd = { "TodoTrouble", "TodoTelescope", "TodoQuickFix", "TodoLocList" },
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {},
}
