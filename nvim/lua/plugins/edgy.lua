-- Docks the left sidebar like VS Code's side bar: one resizable area that
-- shows either the Explorer (nvim-tree) or Source Control (Neogit status on
-- top, the GitLens-style panel from utils/git_panel.lua below).
-- utils/git_sidebar.lua does the Explorer <-> Source Control switching.
return {
  "folke/edgy.nvim",
  event = "VeryLazy",
  opts = require "configs.edgy",
}
