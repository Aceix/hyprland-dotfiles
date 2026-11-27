return {
  "stevearc/conform.nvim",
  -- Manual (<leader>cf) unless <leader>uF turns format-on-save on
  -- (configs/toggles.lua). A function, so the formatter table is only built
  -- when conform is first used.
  opts = function()
    return require "configs.conform"
  end,
}
