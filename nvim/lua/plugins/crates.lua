-- Cargo.toml: latest versions inline, completion and hover for crate names,
-- versions and features, code actions to upgrade
return {
  "saecki/crates.nvim",
  event = "BufRead Cargo.toml",
  opts = {
    lsp = { enabled = true, actions = true, completion = true, hover = true },
  },
}
