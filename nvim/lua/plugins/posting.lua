return {
  "YarikYar/posting.nvim",

  dependencies = { "akinsho/toggleterm.nvim" },
  config = function()
    require("posting").setup({
      border = "curved", -- valid options are "single" | "double" | "shadow" | "curved"
    })
  end,
  keys = {
    {
      "<leader>Tp",
      function()
        require("posting").open()
      end,
      desc = "Posting HTTP Client",
    },
  },
}

