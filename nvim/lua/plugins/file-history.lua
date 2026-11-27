-- Browses the local history that utils/local_history.lua records on every
-- save: per file (<leader>fH), across files, or by date.
local call = require "utils.call"

return {
  "dawsers/file-history.nvim",
  cmd = "FileHistory",
  keys = {
    { "<leader>fH", call("file_history", "history"), desc = "File History (local snapshots)" },
    { "<leader>fV", call("file_history", "files"), desc = "File History: All Files" },
    { "<leader>fQ", call("file_history", "query"), desc = "File History: By Date" },
    { "<leader>fB", call("file_history", "backup"), desc = "File History: Tagged Snapshot" },
  },
  opts = function()
    return { backup_dir = require("utils.local_history").dir }
  end,
  config = function(_, opts)
    require("file_history").setup(opts)
    -- its blocking save hook; utils/local_history.lua does this
    vim.api.nvim_del_augroup_by_name "file_history_group"
  end,
}
