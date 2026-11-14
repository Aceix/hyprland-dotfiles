-- vim.ui.input / vim.ui.select as floating windows. Input boxes open in the
-- middle of the screen, like the pickers and menus. The exception is LSP
-- rename (<leader>cr / F2), which stays at the symbol like VS Code's inline
-- rename: Neovim marks that prompt with scope = "cursor".
return {
  "stevearc/dressing.nvim",
  lazy = false,
  opts = {
    input = {
      relative = "editor",
      title_pos = "center",
      get_config = function(opts)
        if opts.scope == "cursor" then
          return { relative = "cursor", title_pos = "left" }
        end
      end,
    },
  },
}
