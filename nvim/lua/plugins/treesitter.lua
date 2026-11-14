return {
  "nvim-treesitter/nvim-treesitter",
  lazy = false,
  -- :TSUpdate, after fetching the tree-sitter CLI where it's missing
  build = function()
    require("utils.ts_parsers").update()
  end,
  -- still exposed as `opts` so NvChad's :TSInstallAll can read ensure_installed
  -- off the lazy spec
  opts = require "configs.treesitter",

  config = function(_, opts)
    require("nvim-treesitter").setup {} -- `main` only accepts { install_dir }
    -- `main` dropped auto_install: build what's declared but missing (async;
    -- a no-op once all are there). On remotes this also fixes up parsers
    -- copied from here and fetches the tree-sitter CLI if needed.
    require("utils.ts_parsers").ensure(opts.ensure_installed)
  end,
}
