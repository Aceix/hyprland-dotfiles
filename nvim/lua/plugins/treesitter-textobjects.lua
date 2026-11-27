-- Jump between functions / arguments and swap arguments. Also the
-- `textobjects` queries that mini.ai's af / ac / ao read (plugins/mini-ai.lua).
local function move(fn, query)
  return function()
    require("nvim-treesitter-textobjects.move")[fn](query, "textobjects")
  end
end

local function swap(fn)
  return function()
    require("nvim-treesitter-textobjects.swap")[fn] "@parameter.inner"
  end
end

local nxo = { "n", "x", "o" }

return {
  "nvim-treesitter/nvim-treesitter-textobjects",
  branch = "main",
  init = function()
    -- its ftplugin-style default maps; the ones wanted are below
    vim.g.no_plugin_maps = true
  end,
  keys = {
    { "]f", move("goto_next_start", "@function.outer"), mode = nxo, desc = "Next Function" },
    { "[f", move("goto_previous_start", "@function.outer"), mode = nxo, desc = "Previous Function" },
    { "]a", move("goto_next_start", "@parameter.inner"), mode = nxo, desc = "Next Argument" },
    { "[a", move("goto_previous_start", "@parameter.inner"), mode = nxo, desc = "Previous Argument" },
    { "<leader>cn", swap "swap_next", desc = "Swap Argument with Next" },
    { "<leader>cN", swap "swap_previous", desc = "Swap Argument with Previous" },
  },
  opts = { move = { set_jumps = true } },
  config = function(_, opts)
    require("nvim-treesitter-textobjects").setup(opts)
  end,
}
