-- CSV / TSV shown as an aligned table (the file is untouched), with
-- field-wise motions. <leader>uv toggles (vim.g.csv_view, configs/toggles.lua).
return {
  "hat0uma/csvview.nvim",
  ft = { "csv", "tsv" },
  cmd = { "CsvViewEnable", "CsvViewDisable", "CsvViewToggle" },
  opts = {
    view = { display_mode = "border" },
  },
  config = function(_, opts)
    local csvview = require "csvview"
    csvview.setup(opts)
    local function enable(buf)
      if vim.g.csv_view ~= false and not vim.b[buf].bigfile and not csvview.is_enabled(buf) then
        csvview.enable(buf)
      end
    end
    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("CsvView", { clear = true }),
      pattern = { "csv", "tsv" },
      callback = function(ev)
        enable(ev.buf)
      end,
    })
    enable(vim.api.nvim_get_current_buf()) -- the file that loaded this
  end,
}
