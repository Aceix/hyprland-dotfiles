return {
  "ahmedkhalf/project.nvim",
  -- manual_mode (configs/project.lua): roots only change on :ProjectRoot, and
  -- utils/project_picker.lua require()s it on <C-o>, which lazy autoloads
  cmd = "ProjectRoot",
  opts = require "configs.project",
  config = function(_, opts)
    require("project_nvim").setup(opts)
    if package.loaded.telescope then
      pcall(require("telescope").load_extension, "projects")
    end
  end,
}
