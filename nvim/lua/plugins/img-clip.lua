return {
  "HakonHarnes/img-clip.nvim",
  cmd = "PasteImage",
  -- nvim-tree's `p` (configs/nvim-tree.lua) require()s it on demand
  opts = {
    default = {
      dir_path = "assets/img",
      extension = "png",
    },
    filetypes = {
      codecompanion = {
        prompt_for_file_name = false,
        template = "[Image]($FILE_PATH)",
        use_absolute_path = true,
      },
    },
  },
}
