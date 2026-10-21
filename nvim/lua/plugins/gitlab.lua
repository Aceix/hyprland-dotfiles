-- GitLab MRs: review, discussions, pipelines. Builds a small Go server on
-- install, and needs a token (GITLAB_TOKEN, or a .gitlab.nvim file in the
-- repo), so it stays off when either is missing. utils/git_host.lua routes
-- <leader>gP / <leader>gI here for GitLab remotes.
return {
  "harrisoncramer/gitlab.nvim",
  cond = vim.fn.executable "go" == 1,
  dependencies = {
    "MunifTanjim/nui.nvim",
    "nvim-lua/plenary.nvim",
    "sindrets/diffview.nvim",
  },
  build = function()
    require("gitlab.server").build(true)
  end,
  opts = {},
}
