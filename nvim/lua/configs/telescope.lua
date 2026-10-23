-- Files and grep include hidden and git-ignored files, minus dependency
-- folders (utils/dep_dirs.lua); rg skips those itself, so it never walks them.
local rg_args = require("utils.dep_dirs").rg_args

return {
  defaults = {
    vimgrep_arguments = {
      "rg",
      "--color=never",
      "--no-heading",
      "--with-filename",
      "--line-number",
      "--column",
      "--smart-case",
      unpack(rg_args),
    },
  },
  pickers = {
    find_files = {
      -- A function: find_files appends to the table it gets back
      find_command = function()
        return { "rg", "--files", "--color=never", unpack(rg_args) }
      end,
    },
  },
}
