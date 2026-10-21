return {
  "neovim/nvim-lspconfig",
  -- data-only: JSON/YAML schemas for jsonls/yamlls
  dependencies = { "b0o/SchemaStore.nvim" },
  config = function()
    require "configs.lspconfig"
  end,
}
