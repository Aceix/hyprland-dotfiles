-- VS Code's inline merge-conflict actions: co / ct / cb / c0 accept
-- ours / theirs / both / none, ]x / [x jump between conflicts.
return {
  "akinsho/git-conflict.nvim",
  version = "*",
  event = "BufReadPre",
  opts = {
    default_mappings = true,
    disable_diagnostics = true, -- LSP errors inside markers are just noise
  },
}
