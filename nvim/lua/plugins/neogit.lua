-- Neogit is the Source Control view: its status buffer is the top half of
-- the git sidebar (utils/git_sidebar.lua, docked by edgy.nvim). Stage /
-- unstage / discard are s / u / x, commit is c c, push / pull / fetch are
-- P / p / f; ? lists everything.
return {
  "NeogitOrg/neogit",
  dependencies = {
    "sindrets/diffview.nvim",
    "m00qek/baleia.nvim", -- for a custom log pager
    "nvim-telescope/telescope.nvim",
  },
  cmd = "Neogit",
  opts = function()
    local sidebar = require "utils.git_sidebar"
    return {
      kind = "vsplit_left", -- edgy then docks it in the left sidebar
      graph_style = "unicode",
      disable_hint = false,
      -- utils/autoreload.lua refreshes it on any change made outside it (its
      -- own watcher misses staging, commits and work-tree edits)
      filewatcher = { enabled = false },
      integrations = { diffview = true, telescope = true },

      -- The commit message opens in a centered float rather than squeezed
      -- into the sidebar. The staged diff is skipped: the status in the
      -- sidebar already shows it.
      commit_editor = { kind = "floating", show_staged_diff = false },
      -- Only the commit editor uses "floating" here, so size it for a message
      floating = { width = 0.5, height = 0.4, border = "rounded" },
      -- Everything else opens in the editor area, not inside the sidebar
      commit_view = { kind = "tab" },
      log_view = { kind = "tab" },
      reflog_view = { kind = "tab" },
      refs_view = { kind = "tab" },
      stash = { kind = "tab" },
      commit_select_view = { kind = "tab" },
      rebase_editor = { kind = "tab" },
      merge_editor = { kind = "tab" },

      sections = {
        untracked = { folded = false },
        unstaged = { folded = false },
        staged = { folded = false },
        stashes = { folded = true },
        unpulled_upstream = { folded = true },
        unmerged_upstream = { folded = false },
        recent = { folded = true },
      },

      mappings = {
        status = {
          -- Changed files open as a diff beside the sidebar (gf / "Open File"
          -- in the diff goes to the file itself)
          ["<cr>"] = sidebar.neogit_open,
          ["<2-LeftMouse>"] = sidebar.neogit_click,
          -- Full-tab diffview for the file under the cursor
          ["D"] = sidebar.neogit_diff,
        },
        -- <C-CR> commits, q / <Esc> (normal mode) cancel. <C-CR> needs a
        -- terminal that reports it (kitty keyboard protocol / modifyOtherKeys).
        commit_editor = {
          ["q"] = "Abort",
          ["<esc>"] = "Abort",
          ["<c-cr>"] = "Submit",
        },
        commit_editor_I = {
          ["<c-cr>"] = "Submit",
        },
      },
    }
  end,
  config = function(_, opts)
    require("neogit").setup(opts)
    -- Untracked folders list each new file (VS Code style) rather than one
    -- "dir/" line, for Neogit's git status only: not the shell's or the repo's
    local process = require "neogit.process"
    local new = process.new
    process.new = function(p)
      if p.cmd and vim.list_contains(p.cmd, "status") then
        p.env = vim.tbl_extend("force", p.env or {}, {
          GIT_CONFIG_COUNT = "1",
          GIT_CONFIG_KEY_0 = "status.showUntrackedFiles",
          GIT_CONFIG_VALUE_0 = "all",
        })
      end
      return new(p)
    end
  end,
}
