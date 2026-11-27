return {
  "MagicDuck/grug-far.nvim",
  cmd = "GrugFar",
  keys = {
    {
      -- Structural search & replace: matches syntax, not text
      -- (`console.log($A)`, `if ($COND) { $$$BODY }`)
      "<leader>sa",
      function()
        require("utils.mason_ensure").ensure({ "ast-grep" }, function()
          require("grug-far").open { engine = "astgrep" }
        end)
      end,
      desc = "Structural Search & Replace (ast-grep)",
    },
  },
  opts = { headerMaxWidth = 80 },
}
