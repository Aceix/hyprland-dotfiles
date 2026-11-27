-- Habit trainer: hints when a motion is repeated where a better one exists
-- (jjjj -> 4j, }), like Key Promoter X. Off, and not even loaded, until
-- <leader>uH turns it on (configs/toggles.lua).
return {
  "m4xshen/hardtime.nvim",
  dependencies = { "MunifTanjim/nui.nvim" },
  cmd = "Hardtime",
  -- a function: read when it loads, after the saved <leader>uH state
  opts = function()
    return {
      -- (configs/toggles.lua loads it on <leader>uH; this switches it on then)
      enabled = vim.g.hardtime == true,
      -- hint only: never swallow the keys (arrows and the mouse stay usable)
      restriction_mode = "hint",
      disable_mouse = false,
      -- its defaults disable the arrows; `false` per key switches that off
      -- (`{}` would just merge into the defaults)
      disabled_keys = {
        ["<Up>"] = false,
        ["<Down>"] = false,
        ["<Left>"] = false,
        ["<Right>"] = false,
      },
    }
  end,
}
