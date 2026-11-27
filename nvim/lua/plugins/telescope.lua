return {
  "nvim-telescope/telescope.nvim",
  -- NvChad's base spec lazy-loads on `cmd = "Telescope"`, which every mapping
  -- in mappings.lua goes through; utils/project_picker.lua require()s it.
  opts = require "configs.telescope",
}
