-- Smooth scrolling. With settings.vscode_keys, <C-b>/<C-f>/<C-d> belong to the
-- VS Code layer (sidebar / find / multi-cursor); PageUp/PageDown and <C-u>
-- still scroll.
local mappings = { "<C-u>", "<C-y>", "<C-e>", "zt", "zz", "zb" }
if not require("settings").vscode_keys then
  vim.list_extend(mappings, { "<C-d>", "<C-b>", "<C-f>" })
end

local keys = {
  { "<PageUp>", mode = { "n", "i", "v" }, desc = "Smooth scroll half page up" },
  { "<PageDown>", mode = { "n", "i", "v" }, desc = "Smooth scroll half page down" },
}
for _, k in ipairs(mappings) do
  keys[#keys + 1] = { k, mode = { "n", "v" } } -- neoscroll's own modes ("v" = visual + select)
end

return {
  "karb94/neoscroll.nvim",
  keys = keys,
  cmd = {
    "NeoscrollEnablePM", "NeoscrollDisablePM", "NeoscrollEnableBufferPM", "NeoscrollDisableBufferPM",
    "NeoscrollEnableGlobalPM", "NeoscrollDisableGlobalePM",
  },
  opts = { mappings = mappings },
  config = require "configs.neoscroll",
}
