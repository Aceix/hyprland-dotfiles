-- Closes HTML / JSX tags as they're typed and renames the matching tag
return {
  "windwp/nvim-ts-autotag",
  ft = {
    "html", "xml", "vue", "svelte", "astro", "htmlangular",
    "javascriptreact", "typescriptreact", "blade", "php", "markdown",
  },
  opts = {},
}
