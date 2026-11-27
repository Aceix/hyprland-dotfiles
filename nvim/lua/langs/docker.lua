-- Dockerfiles (dockerls is always on, configs/lspconfig.lua; hadolint adds
-- best-practice lints) and Compose files, which options.lua gives the
-- `yaml.docker-compose` filetype.
return {
  mason = { "docker-compose-language-service", "hadolint" },
  lsp = { docker_compose_language_service = {} },
  parsers = { "dockerfile", "yaml" },
  lint = { dockerfile = { "hadolint" } },
}
