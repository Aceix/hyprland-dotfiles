-- VS Code's git.autofetch: fetch the current repo in the background every few
-- minutes so the statusline's ↑/↓ counts and the sidebar stay current.
-- Switched on/off by settings.git_autofetch. Fires `User GitAutoFetch` after
-- every successful fetch.

local M = {}

local INTERVAL_MS = 180 * 1000

local timer
local running = {}

local function fetch()
  local root = require("utils.git_sidebar").root()
  if not root or running[root] then
    return
  end

  running[root] = true
  vim.system(
    { "git", "fetch", "--all", "--prune", "--quiet", "--no-write-fetch-head" },
    -- A missing credential must fail, not wait on a prompt nobody can see
    -- (ssh can't prompt either: vim.system gives it no tty)
    { cwd = root, text = true, env = { GIT_TERMINAL_PROMPT = "0" } },
    function(out)
      running[root] = nil
      if out.code == 0 then
        vim.schedule(function()
          require("configs.statusline").refresh_upstream()
          vim.api.nvim_exec_autocmds("User", { pattern = "GitAutoFetch", modeline = false })
        end)
      end
    end
  )
end

function M.start()
  if timer then
    return
  end
  timer = vim.uv.new_timer()
  -- First run shortly after startup, off the startup path
  timer:start(10 * 1000, INTERVAL_MS, vim.schedule_wrap(fetch))
end

M.fetch = fetch

return M
