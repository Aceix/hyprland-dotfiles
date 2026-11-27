-- Error Lens: the diagnostic message at the end of its line, wrapped rather
-- than cut off. Replaces NvChad's virtual text (configs/lspconfig.lua);
-- <leader>ud switches back.
return {
  "rachartier/tiny-inline-diagnostic.nvim",
  event = { "LspAttach", "DiagnosticChanged" },
  opts = {},
  config = function(_, opts)
    local diag = require "tiny-inline-diagnostic"
    diag.setup(opts)
    if vim.g.inline_diagnostics == false then
      diag.disable()
    end
  end,
}
