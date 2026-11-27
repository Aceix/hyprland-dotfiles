-- Claude Code as an IDE integration (<leader>al): it sees the open file and
-- selection, and its edits arrive as diffs to accept or reject. The CLI runs
-- in the bottom panel (utils/claude_term.lua).
return {
  "coder/claudecode.nvim",
  cond = vim.fn.executable "claude" == 1,
  cmd = {
    "ClaudeCode",
    "ClaudeCodeFocus",
    "ClaudeCodeSelectModel",
    "ClaudeCodeAdd",
    "ClaudeCodeSend",
    "ClaudeCodeTreeAdd",
    "ClaudeCodeDiffAccept",
    "ClaudeCodeDiffDeny",
  },
  keys = {
    { "<leader>al", "", mode = { "n", "v" }, desc = "+claude code" },
    { "<leader>alc", "<cmd>ClaudeCode<cr>", desc = "Claude Code Toggle" },
    { "<leader>alf", "<cmd>ClaudeCodeFocus<cr>", desc = "Claude Code Focus" },
    { "<leader>alr", "<cmd>ClaudeCode --resume<cr>", desc = "Claude Code Resume a Session" },
    { "<leader>alC", "<cmd>ClaudeCode --continue<cr>", desc = "Claude Code Continue Last Session" },
    { "<leader>alm", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Claude Code Model" },
    { "<leader>alb", "<cmd>ClaudeCodeAdd %<cr>", desc = "Claude Code: Add This File" },
    { "<leader>als", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Claude Code: Send Selection" },
    { "<leader>als", "<cmd>ClaudeCodeTreeAdd<cr>", ft = "NvimTree", desc = "Claude Code: Add File" },
    { "<leader>aly", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Claude Code: Accept Diff" },
    { "<leader>aln", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Claude Code: Reject Diff" },
  },
  opts = function()
    return {
      terminal = { provider = require "utils.claude_term" },
      -- Away from the sidebar and panel layout
      diff_opts = { open_in_new_tab = true },
    }
  end,
}
