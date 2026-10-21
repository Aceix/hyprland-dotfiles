-- Sessions. persistence.nvim only takes `dir` / `need` / `branch`; what a
-- session holds is 'sessionoptions' (lua/options.lua), and lua/autocmds.lua
-- restores on startup and strips non-file windows before saving.
return {
  "folke/persistence.nvim",
  -- Every session has to save on exit, so load once startup is done (that
  -- covers `nvim`, `nvim file`, `nvim newfile` and `nvim -` alike)
  event = "VimEnter",
  opts = {},
}
