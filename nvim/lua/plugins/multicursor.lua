-- VS Code multi-cursor (Ctrl+D & co.). Only with settings.vscode_keys; loads on
-- the first key press.
local function mc(fn, ...)
  return require "utils.call"("multicursor-nvim", fn, ...)
end

return {
  "jake-stewart/multicursor.nvim",
  branch = "1.0",
  enabled = require("settings").vscode_keys,
  keys = {
    { "<C-d>", mc("matchAddCursor", 1), mode = { "n", "x" }, desc = "Add cursor at next match" },
    { "<C-S-l>", mc "matchAllAddCursors", mode = { "n", "x" }, desc = "Add cursors at all matches" },
    { "<C-S-Up>", mc("lineAddCursor", -1), mode = { "n", "x" }, desc = "Add cursor above" },
    { "<C-S-Down>", mc("lineAddCursor", 1), mode = { "n", "x" }, desc = "Add cursor below" },
    { "<C-LeftMouse>", mc "handleMouse", mode = "n", desc = "Add cursor at click" },
    { "<C-LeftDrag>", mc "handleMouseDrag", mode = "n" },
    { "<C-LeftRelease>", mc "handleMouseRelease", mode = "n" },
  },
  config = function()
    local m = require "multicursor-nvim"
    m.setup()

    -- only exists while cursors are active, so plain <Esc> keeps doing :noh
    m.addKeymapLayer(function(layer)
      layer({ "n", "x" }, "<Esc>", function()
        if not m.cursorsEnabled() then
          m.enableCursors()
        else
          m.clearCursors()
        end
      end)
      layer({ "n", "x" }, "<C-S-d>", function()
        m.matchSkipCursor(1)
      end, { desc = "Skip match" })
    end)
  end,
}
