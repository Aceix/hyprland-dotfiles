-- Side-by-side diffs, file/branch history and the 3-way merge editor: the
-- diff side of VS Code's Source Control and GitLens. Neogit, gitgraph and
-- utils/git_panel.lua all open their diffs here.
return {
  "sindrets/diffview.nvim",
  cmd = {
    "DiffviewOpen",
    "DiffviewClose",
    "DiffviewFileHistory",
    "DiffviewToggleFiles",
    "DiffviewFocusFiles",
    "DiffviewRefresh",
  },
  opts = {
    enhanced_diff_hl = true, -- VS Code-like word-level highlights in changed lines
    hooks = {
      -- the old side red, as in the sidebar's diffs (utils/diff.lua)
      diff_buf_win_enter = function(_, win, ctx)
        if ctx.symbol == "a" and ctx.layout_name:match "^diff2" then
          vim.wo[win].winhighlight = require("utils.diff").OLD_WINHL
        end
      end,
    },
    view = {
      merge_tool = {
        -- ours | base | theirs on top, the result below, like VS Code's merge editor
        layout = "diff3_mixed",
        disable_diagnostics = true,
      },
    },
    keymaps = {
      view = { { "n", "q", "<Cmd>DiffviewClose<CR>", { desc = "Close diffview" } } },
      file_panel = { { "n", "q", "<Cmd>DiffviewClose<CR>", { desc = "Close diffview" } } },
      file_history_panel = { { "n", "q", "<Cmd>DiffviewClose<CR>", { desc = "Close diffview" } } },
    },
  },
}
