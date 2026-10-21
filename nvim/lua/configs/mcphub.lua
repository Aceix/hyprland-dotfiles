return {
  auto_approve = false,
  auto_toggle_mcp_servers = true,
  workspace = {
    enabled = true,
    look_for = { ".mcphub/servers.json", ".vscode/mcp.json", ".cursor/mcp.json" },
    reload_on_dir_changed = true,
  },
}
