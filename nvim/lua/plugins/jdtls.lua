-- Java LSP. jdtls needs a launcher that lspconfig can't express (per-project
-- data dir, extension bundles), so nvim-jdtls starts it manually instead of it
-- going through the `servers` list in configs/lspconfig.lua.
return {
  "mfussenegger/nvim-jdtls",
  ft = "java",
  dependencies = { "mfussenegger/nvim-dap" },
  config = require "configs.jdtls",
}
