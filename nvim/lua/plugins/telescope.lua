return {
  "nvim-telescope/telescope.nvim",
  -- NvChad's base spec lazy-loads on `cmd = "Telescope"`, which every mapping
  -- in mappings.lua goes through; utils/project_picker.lua require()s it. In
  -- practice it loads at startup anyway, as a dependency of opencode.nvim.
  opts = require "configs.telescope",
}
