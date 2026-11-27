-- Database client (<leader>Td): connections and saved queries in a side
-- drawer, results in a split. Table / column completion in SQL buffers comes
-- through blink (plugins/blink.lua).
return {
  "kristijanhusak/vim-dadbod-ui",
  dependencies = {
    { "tpope/vim-dadbod", cmd = "DB" },
    { "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" } },
  },
  cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
  keys = {
    { "<leader>Td", "<cmd>DBUIToggle<cr>", desc = "Database" },
  },
  init = function()
    vim.g.db_ui_use_nerd_fonts = 1
    vim.g.db_ui_show_database_icon = 1
    -- connections and saved queries, outside any project
    vim.g.db_ui_save_location = vim.fn.stdpath "data" .. "/db_ui"
    -- run with <leader>cf-style explicit keys, not on every save
    vim.g.db_ui_execute_on_save = 0
  end,
}
