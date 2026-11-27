-- Tasks (<leader>o): .vscode/tasks.json, package.json scripts, Makefile
-- targets, cargo, ... or any shell command (<leader>os)
return {
  task_list = { direction = "right" },
  component_aliases = {
    -- overseer's defaults plus the panel tab
    default = {
      "on_exit_set_status",
      "on_complete_notify",
      { "on_complete_dispose", require_view = { "SUCCESS", "FAILURE" } },
      "panel_tab",
    },
  },
}
