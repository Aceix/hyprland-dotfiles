-- Sticky scroll: the enclosing function / class / block headers stay pinned
-- at the top of the window. <leader>uc toggles, [u jumps to the header.
return {
  "nvim-treesitter/nvim-treesitter-context",
  event = "User FilePost",
  keys = {
    { "[u", require "utils.call"("treesitter-context", "go_to_context"), desc = "Up to Enclosing Scope" },
  },
  opts = {
    max_lines = 3,
    -- Context of the first visible line, like VS Code (default follows the cursor)
    mode = "topline",
    multiwindow = false,
    -- File buffers only (not the panels), and never a big file
    on_attach = function(buf)
      return vim.bo[buf].buftype == "" and not vim.b[buf].bigfile
    end,
  },
}
