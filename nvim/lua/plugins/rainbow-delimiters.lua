-- Matching brackets in matching colors, by nesting depth. <leader>ur toggles
-- (vim.g.rainbow_brackets, configs/toggles.lua).
return {
  "HiPhish/rainbow-delimiters.nvim",
  event = "User FilePost",
  submodules = false, -- test fixtures only
  main = "rainbow-delimiters.setup",
  opts = {
    condition = function(buf)
      return vim.g.rainbow_brackets ~= false and not vim.b[buf].bigfile
    end,
  },
}
