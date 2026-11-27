-- Change a word's case: crc camelCase, crs snake_case, crp PascalCase,
-- crk kebab-case, cru UPPER_CASE, crd dot.case, ... (renames through the
-- language server when the word is a symbol); <leader>cv on a selection.
-- Its `co` (no-LSP variant) is left unmapped: that's git-conflict's "ours".
return {
  "gregorias/coerce.nvim",
  keys = {
    { "cr", "<Plug>(coerce-normal)", desc = "Coerce Case of Word" },
    { "<leader>cv", "<Plug>(coerce-visual)", mode = "x", desc = "Coerce Case of Selection" },
  },
  opts = {},
}
