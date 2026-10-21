-- GitHub PRs, reviews and issues (VS Code's GitHub Pull Requests extension).
-- Needs the gh CLI, so it stays off on hosts without it (remote-nvim servers
-- included). utils/git_host.lua routes <leader>gP / <leader>gI here.
return {
  "pwntester/octo.nvim",
  cond = vim.fn.executable "gh" == 1,
  cmd = "Octo",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
    "nvim-tree/nvim-web-devicons",
  },
  opts = {
    picker = "telescope",
    enable_builtin = true,
  },
}
