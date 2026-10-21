return {
  "3rd/image.nvim",
  build = false,
  -- Its integrations' filetypes, plus image files opened directly (its
  -- hijack_file_patterns); utils/svg_preview.lua require()s it on demand
  ft = { "markdown", "vimwiki", "norg", "asciidoc", "adoc", "typst", "syslang" },
  event = {
    { event = "BufReadPre", pattern = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif" } },
  },
  cmd = "ImageReport",
  opts = require "configs.image",
}
