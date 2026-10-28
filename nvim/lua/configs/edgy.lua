-- edgy.nvim layout: VS Code's side bar. The left area holds either the
-- Explorer (nvim-tree, with the symbol outline below it when docked there)
-- or Source Control (Neogit status + the GitLens-style
-- panel); utils/git_sidebar.lua keeps the two mutually exclusive and draws
-- the clickable "Explorer | Source Control" tab strip in the top winbar.

-- edgy only sets a string winbar verbatim; the tabs are rendered per redraw
local tabs = "%!v:lua.require'utils.git_sidebar'.winbar()"

return {
  animate = { enabled = false },
  exit_when_last = false,
  close_when_all_hidden = true,

  -- Resizable (mouse or keys below), kept across view switches and restarts
  options = {
    left = {
      size = function()
        return require("utils.git_sidebar").width()
      end,
    },
  },

  wo = {
    winbar = true,
    winfixwidth = true,
    winfixheight = false,
    -- a heavy accent right edge, like the terminal pane's top rule
    winhighlight = "WinBar:EdgyWinBar,WinBarNC:EdgyWinBarNC,WinSeparator:NvimTreeWinSeparator",
    fillchars = "vert:┃,vertleft:┨,vertright:┠,verthoriz:╂,eob: ",
    spell = false,
    signcolumn = "no",
  },

  -- edgy's default q/<c-q>/Q would shadow Neogit's own keys
  keys = {
    ["q"] = false,
    ["<c-q>"] = false,
    ["Q"] = false,
    -- edgy's own width keys only size the current window, lost on the next
    -- view switch; resize the shared side bar width instead
    ["<c-w>>"] = function()
      local sidebar = require "utils.git_sidebar"
      sidebar.set_width(sidebar.width() + 2)
    end,
    ["<c-w><lt>"] = function()
      local sidebar = require "utils.git_sidebar"
      sidebar.set_width(sidebar.width() - 2)
    end,
  },

  left = {
    {
      ft = "NvimTree",
      title = "Explorer",
      -- takes whatever the outline below leaves
      wo = { winbar = tabs },
    },
    {
      -- utils/outline_dock.lua: only when docked in the side bar, where it
      -- comes and goes with the Explorer (height resizable, kept across restarts)
      ft = "Outline",
      title = "Outline",
      size = {
        height = function()
          return require("utils.outline_dock").height()
        end,
      },
      filter = function()
        return require("utils.outline_dock").dock() == "left"
      end,
    },
    {
      ft = "NeogitStatus",
      title = "Source Control",
      size = { height = 0.55 },
      wo = { winbar = tabs },
    },
    {
      ft = "gitpanel",
      title = function()
        return require("utils.git_panel").title()
      end,
      size = { height = 0.45 },
    },
  },
}
