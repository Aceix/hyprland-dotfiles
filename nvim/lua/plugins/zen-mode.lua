return {
  "folke/zen-mode.nvim",
  cmd = "ZenMode",
  opts = {
    -- <Esc><Esc> only exists while Zen Mode is open, so plain <Esc> (clear
    -- search highlight) isn't held back by 'timeoutlen' the rest of the time.
    on_open = function()
      vim.keymap.set("n", "<Esc><Esc>", "<cmd>ZenMode<cr>", { desc = "Exit Zen Mode" })
    end,
    on_close = function()
      pcall(vim.keymap.del, "n", "<Esc><Esc>")
    end,
  },
}
