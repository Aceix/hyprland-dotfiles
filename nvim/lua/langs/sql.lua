-- SQL. The Postgres server only starts in projects with a
-- postgres-language-server.jsonc (it needs the connection in there); the
-- formatter works everywhere. Running queries: <leader>Td (plugins/dadbod.lua).
local formatter = { "sql_formatter" }

return {
  mason = { "postgres-language-server", { "sql-formatter", needs = "node" } },
  lsp = { postgres_lsp = {} },
  parsers = { "sql" },
  format = { sql = formatter, mysql = formatter, plsql = formatter },
}
