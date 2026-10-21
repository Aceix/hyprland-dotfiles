return {
  -- Everything the LSP/format/debug configs expect, so a fresh machine
  -- reproduces this one instead of relying on ~/.local/share/nvim/mason.
  ensure_installed = {
    -- Go
    "gopls",
    "golangci-lint",
    "golangci-lint-langserver",
    "gofumpt",
    "goimports",
    "delve",
    "go-debug-adapter",
    -- TS/JS, Vue/Nuxt, React/Next, Svelte, Angular
    "vtsls",
    "vue-language-server", -- also provides @vue/typescript-plugin for vtsls
    "svelte-language-server",
    "angular-language-server",
    "eslint-lsp",
    "js-debug-adapter",
    -- Web
    "html-lsp",
    "css-lsp",
    "tailwindcss-language-server",
    "emmet-language-server",
    "prettierd",
    "prettier",
    -- Data / config / markup
    "json-lsp",
    "yaml-language-server",
    "lemminx",
    "dockerfile-language-server",
    "docker-compose-language-service",
    "bash-language-server",
    "shfmt",
    "stylua",
    "lua-language-server", -- NvChad enables lua_ls for this config
    -- WebAssembly text
    "wasm-language-tools",
    -- Java: the LSP plus the debug/test bundles configs/jdtls.lua loads
    "jdtls",
    "java-debug-adapter",
    "java-test",
    -- Python: types/IntelliSense, plus lint + format + import sorting
    "basedpyright",
    "ruff",
    -- Python / Dart debuggers
    "debugpy",
    "dart-debug-adapter",
  },
  -- don't compete with first paint
  start_delay = 3000,
}
