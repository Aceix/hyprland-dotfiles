-- Linters with no language server of their own. Nothing triggers this spec:
-- lua/langs loads it for the languages that declare a `lint` table.
return {
  "mfussenegger/nvim-lint",
  config = require "configs.lint",
}
