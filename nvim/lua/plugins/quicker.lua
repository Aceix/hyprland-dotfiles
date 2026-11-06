return {
  "stevearc/quicker.nvim",
  ft = "qf",
  ---@module "quicker"
  ---@type quicker.SetupOptions
  opts = {
    -- Closes the tab, like q in the other bottom lists (utils/term.lua)
    keys = { { "q", "<cmd>close<cr>", desc = "Close" } },
  },
}
