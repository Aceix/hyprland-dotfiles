-- Bookmarks, per project: <leader>j the pinned files (then 1-9 to jump, s to
-- pin / unpin the current one), <leader>k the marked lines of this file
return {
  "otavioschwanck/arrow.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  keys = {
    { "<leader>j", desc = "Bookmarked Files" },
    { "<leader>k", desc = "Bookmarked Lines (this file)" },
  },
  opts = {
    show_icons = true,
    leader_key = "<leader>j",
    buffer_leader_key = "<leader>k",
  },
}
