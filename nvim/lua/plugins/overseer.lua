-- Task runner, like VS Code's Tasks: output goes to a tab in the bottom panel
-- (lua/overseer/component/panel_tab.lua)
local function rerun_last()
  local overseer = require "overseer"
  local task = overseer.list_tasks()[1] -- most recent first
  if task then
    overseer.run_action(task, "restart")
  else
    vim.cmd "OverseerRun"
  end
end

return {
  "stevearc/overseer.nvim",
  cmd = { "OverseerRun", "OverseerToggle", "OverseerOpen", "OverseerClose", "OverseerShell", "OverseerTaskAction" },
  keys = {
    { "<leader>o", "", desc = "+tasks" },
    { "<leader>or", "<cmd>OverseerRun<cr>", desc = "Run Task…" },
    { "<leader>ol", rerun_last, desc = "Rerun Last Task" },
    { "<leader>os", "<cmd>OverseerShell<cr>", desc = "Run Shell Command as Task" },
    { "<leader>ot", "<cmd>OverseerToggle<cr>", desc = "Task List" },
    { "<leader>oa", "<cmd>OverseerTaskAction<cr>", desc = "Task Action (stop, restart, …)" },
  },
  opts = require "configs.overseer",
}
