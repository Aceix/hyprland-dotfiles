-- LSP progress and notifications in the corner
return {
  "j-hui/fidget.nvim",
  -- at startup, so notifications before any LSP attaches go there too
  event = "VeryLazy",
  opts = {
    notification = { override_vim_notify = true },
  },
}
