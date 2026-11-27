-- VS Code's Peek Definition / References: an inline preview with the list of
-- locations beside it, without leaving the file
return {
  "DNLHC/glance.nvim",
  cmd = "Glance",
  keys = {
    { "<leader>cP", "<cmd>Glance definitions<cr>", desc = "Peek Definition" },
    { "<leader>cu", "<cmd>Glance references<cr>", desc = "Peek References (usages)" },
  },
  opts = {},
}
