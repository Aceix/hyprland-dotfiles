-- Manual formatting only (<leader>cf in mappings.lua). Filetypes not listed
-- here (java, xml, wat, ...) fall back to their LSP via `lsp_fallback`.
local prettier = { "prettierd", "prettier", stop_after_first = true }

local options = {
  formatters_by_ft = {
    lua = { "stylua" },
    go = { "goimports", "gofumpt" },
    sh = { "shfmt" },
    bash = { "shfmt" },
    python = { "ruff_fix", "ruff_organize_imports", "ruff_format" },
  },
}

for _, ft in ipairs {
  "javascript",
  "javascriptreact",
  "typescript",
  "typescriptreact",
  "vue",
  "svelte",
  "html",
  "htmlangular",
  "css",
  "scss",
  "less",
  "json",
  "jsonc",
  "yaml",
  "markdown",
  "graphql",
} do
  options.formatters_by_ft[ft] = prettier
end

return options
