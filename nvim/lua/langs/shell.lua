-- Shell scripts. bash-language-server runs shellcheck by itself when it's on
-- $PATH; shfmt is in configs/conform.lua.
return {
  mason = { "bash-language-server", "shellcheck" },
  lsp = { bashls = {} },
  parsers = { "bash" },
}
