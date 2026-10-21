-- nvim-treesitter is pinned to the `main` branch (see lazy-lock.json), which
-- dropped the old setup() options. Only `ensure_installed` below is still read,
-- and only by NvChad's `:TSInstallAll` command -- nothing installs parsers
-- automatically, so **run `:TSInstallAll` after adding a language here**.
-- Building parsers on `main` needs the `tree-sitter` CLI on $PATH, not just cc.
--
-- `highlight` / `indent` / `auto_install` are inert: NvChad starts highlighting
-- from a FileType autocmd (`pcall(vim.treesitter.start)`), and `main` has no
-- auto-install. They are kept only so this list stays portable.
return {
  ensure_installed = {
    "bash",
    "angular",
    "css",
    "scss",
    "dart",
    "dockerfile",
    "go",
    "gomod",
    "gowork",
    "gosum",
    "gotmpl",
    "graphql",
    "html",
    "java",
    "javascript",
    "jsdoc",
    "json",
    "jsonc",
    "lua",
    "markdown",
    "markdown_inline",
    "python",
    "regex",
    "rust",
    "svelte",
    "toml",
    "tsx",
    "typescript",
    "vue",
    "yaml",
    "xml",
    "vim",
    "vimdoc",
    "astro",
  },
  highlight = {
    enable = true,
  },
  indent = {
    enable = true,
  },
  auto_install = true,
}
