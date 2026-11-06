-- Folds from the language server where there's no Treesitter parser (e.g.
-- .wat files), rather than no folds at all. Treesitter stays the source
-- wherever it has a parser (options.lua): it's instant and works without a
-- server.
local M = {}

local function has_parser(buf)
  local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
  return lang ~= nil and vim.treesitter.language.add(lang) == true
end

--- Every window showing `buf` folds by its server's folding ranges
local function lsp_folds(buf)
  if has_parser(buf) or #vim.lsp.get_clients { bufnr = buf, method = "textDocument/foldingRange" } == 0 then
    return
  end
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    vim.wo[win][0].foldexpr = "v:lua.vim.lsp.foldexpr()"
  end
end

function M.setup()
  vim.api.nvim_create_autocmd({ "LspAttach", "BufWinEnter" }, {
    group = vim.api.nvim_create_augroup("LspFolds", { clear = true }),
    callback = function(ev)
      lsp_folds(ev.buf)
    end,
  })
end

return M
