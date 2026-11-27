-- Extract / inline function and variable (<leader>cx), for languages whose
-- server has no such code actions. Operators: in Normal mode they take a
-- motion or text object (<leader>cxe + af), in Visual the selection.
local function op(fn)
  return function()
    return require("refactoring")[fn]()
  end
end

return {
  "ThePrimeagen/refactoring.nvim",
  dependencies = { "lewis6991/async.nvim" }, -- until Neovim 0.13
  cond = vim.fn.has "nvim-0.12.5" == 1,
  cmd = "Refactor",
  keys = {
    { "<leader>cx", "", mode = { "n", "x" }, desc = "+refactor" },
    { "<leader>cxx", op "select_refactor", mode = { "n", "x" }, desc = "Pick a Refactor" },
    { "<leader>cxe", op "extract_func", mode = { "n", "x" }, expr = true, desc = "Extract Function" },
    { "<leader>cxv", op "extract_var", mode = { "n", "x" }, expr = true, desc = "Extract Variable" },
    { "<leader>cxi", op "inline_var", mode = { "n", "x" }, expr = true, desc = "Inline Variable" },
    { "<leader>cxf", op "inline_func", mode = { "n", "x" }, expr = true, desc = "Inline Function" },
  },
}
