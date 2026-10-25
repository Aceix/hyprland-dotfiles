-- Sessions. persistence.nvim only takes `dir` / `need` / `branch`; what a
-- session holds is 'sessionoptions' (lua/options.lua), and lua/autocmds.lua
-- restores on startup and strips non-file windows before saving.
return {
  "folke/persistence.nvim",
  -- Every session has to save on exit, so load once startup is done (that
  -- covers `nvim`, `nvim file`, `nvim newfile` and `nvim -` alike)
  event = "VimEnter",
  opts = {
    -- Save even with no file open. The default (1) skipped the save after
    -- the last file was closed, so the previous session -- files and all --
    -- came back on the next launch.
    need = 0,
  },
}
