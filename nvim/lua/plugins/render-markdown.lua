return {
  "MeanderingProgrammer/render-markdown.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.icons" },
  -- Also render-markdown's default file_types (it reads this list)
  ft = { "markdown", "Avante", "copilot-chat", "opencode_output" },
  opts = {
    -- Keep the cursor line rendered in normal mode, so tables (and the rest)
    -- don't reflow to raw markdown as the cursor moves; insert mode shows raw
    anti_conceal = { disabled_modes = { "n" } },
    win_options = { concealcursor = { rendered = "n" } },
  },
}
