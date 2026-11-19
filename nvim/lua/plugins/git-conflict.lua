-- VS Code's inline merge-conflict actions: co / ct / cb / c0 accept
-- ours / theirs / both / none, ]x / [x jump between conflicts.
return {
  "akinsho/git-conflict.nvim",
  version = "*",
  event = "BufReadPre",
  opts = {
    default_mappings = true,
    -- Its own switch calls vim.diagnostic.disable(), gone in Neovim 0.12, so
    -- every conflicted file errored; done below with the current API instead
    disable_diagnostics = false,
  },
  config = function(_, opts)
    require("git-conflict").setup(opts)

    -- LSP errors inside conflict markers are just noise: hide them in the
    -- buffer until its conflicts are resolved
    local group = vim.api.nvim_create_augroup("GitConflictDiagnostics", { clear = true })
    for pattern, show in pairs { GitConflictDetected = false, GitConflictResolved = true } do
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = pattern,
        callback = function()
          vim.diagnostic.enable(show, { bufnr = vim.api.nvim_get_current_buf() })
        end,
      })
    end
  end,
}
