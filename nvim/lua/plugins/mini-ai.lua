-- Text objects: af/if function, ac/ic class, ao/io block (loop, conditional),
-- aa/ia argument, plus smarter quotes and brackets (works from before the
-- object, and with a count)
return {
  "nvim-mini/mini.ai",
  dependencies = { "nvim-treesitter/nvim-treesitter-textobjects" }, -- the queries
  keys = {
    { "a", mode = { "x", "o" } },
    { "i", mode = { "x", "o" } },
  },
  opts = function()
    local ts = require("mini.ai").gen_spec.treesitter
    return {
      n_lines = 500,
      custom_textobjects = {
        f = ts { a = "@function.outer", i = "@function.inner" },
        c = ts { a = "@class.outer", i = "@class.inner" },
        o = ts {
          a = { "@block.outer", "@conditional.outer", "@loop.outer" },
          i = { "@block.inner", "@conditional.inner", "@loop.inner" },
        },
      },
      -- an / in stay Neovim 0.12's own: grow / shrink the selection by syntax node
      mappings = { around_next = "", inside_next = "", around_last = "", inside_last = "" },
    }
  end,
}
