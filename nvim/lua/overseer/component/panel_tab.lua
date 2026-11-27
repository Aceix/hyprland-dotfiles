-- Overseer component (configs/overseer.lua adds it to every task): the
-- task's output becomes a tab of the bottom panel, next to the shells and
-- Test Results (utils/term.lua), and stays there after the task ends.
return {
  desc = "Show the task's output as a tab in the bottom panel",
  constructor = function()
    return {
      on_start = function(self, task)
        local buf = task:get_bufnr()
        if not buf or vim.bo[buf].buftype ~= "terminal" then
          return
        end
        vim.b[buf].nvterm_label = vim.fn.strcharpart(task.name, 0, 24)
        vim.b[buf].nvterm_keep = true -- not dropped when the job exits
        vim.bo[buf].buflisted = false
        -- a restarted task gets a new buffer: same tab
        require("utils.term").show(buf, { replace = self.buf })
        self.buf = buf
      end,
    }
  end,
}
