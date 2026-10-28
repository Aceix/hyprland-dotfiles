-- Docked in the side bar under the Explorer or in its own right pane;
-- utils/outline_dock.lua does the placing and switching.
return {
  "hedyhli/outline.nvim",
  cmd = { "Outline", "OutlineOpen" },
  keys = {
    {
      "<leader>co",
      function()
        require("utils.outline_dock").toggle()
      end,
      desc = "Toggle Symbol Outline",
    },
    {
      "<leader>cO",
      function()
        require("utils.outline_dock").switch()
      end,
      desc = "Outline: Side Bar <-> Right Pane",
    },
  },
  opts = function()
    return { outline_window = { position = require("utils.outline_dock").dock() } }
  end,
}
