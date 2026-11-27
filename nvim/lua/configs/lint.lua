-- Runs the buffer's linters (lint.linters_by_ft, filled in by lua/langs) on
-- open, on save and on leaving Insert mode
return function()
  local lint = require "lint"
  -- (replacing its defaults, which assume tools this config doesn't install)
  lint.linters_by_ft = require("langs").linters()

  local timer = assert(vim.uv.new_timer())
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave" }, {
    group = vim.api.nvim_create_augroup("Lint", { clear = true }),
    callback = function(ev)
      if not lint.linters_by_ft[vim.bo[ev.buf].filetype] or vim.b[ev.buf].bigfile then
        return
      end
      timer:start(
        150,
        0,
        vim.schedule_wrap(function()
          if vim.api.nvim_get_current_buf() == ev.buf then
            lint.try_lint()
          end
        end)
      )
    end,
  })
end
