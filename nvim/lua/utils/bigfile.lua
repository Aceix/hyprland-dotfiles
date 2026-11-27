-- Big-file guard: files over 1.5 MB, or with very long lines (minified
-- bundles, generated JSON, logs), open without treesitter, LSP, completion,
-- indent guides, the minimap and the rest, so they stay instant. Everything
-- else that should stay out of them checks `vim.b[buf].bigfile`
-- (utils/breadcrumbs.lua, plugins/treesitter-context.lua, ...).
local M = {}

local max_size = 1.5 * 1024 * 1024
local max_line_length = 1000 -- average, in bytes

local function mark(buf)
  if vim.b[buf].bigfile then
    return
  end
  local b = vim.b[buf]
  b.bigfile = true
  b.completion = false -- blink.cmp
  b.snacks_indent = false
  b.minimap_disable = true -- mini.map
  b.sidekick_nes = false
  vim.bo[buf].swapfile = false
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    -- NvChad starts treesitter from its own FileType autocmd; stop it after
    pcall(vim.treesitter.stop, buf)
    for _, client in ipairs(vim.lsp.get_clients { bufnr = buf }) do
      vim.lsp.buf_detach_client(buf, client.id)
    end
    if package.loaded.gitsigns then
      pcall(require("gitsigns").detach, buf)
    end
  end)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("BigFile", { clear = true })

  vim.api.nvim_create_autocmd("BufReadPre", {
    group = group,
    callback = function(args)
      local stat = vim.uv.fs_stat(args.match)
      if stat and stat.size > max_size then
        mark(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    callback = function(args)
      local lines = vim.api.nvim_buf_line_count(args.buf)
      local bytes = vim.api.nvim_buf_get_offset(args.buf, lines)
      if bytes / lines > max_line_length then
        mark(args.buf)
      end
    end,
  })

  -- Later filetype changes and late-starting servers
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(args)
      if vim.b[args.buf].bigfile then
        vim.schedule(function()
          pcall(vim.treesitter.stop, args.buf)
        end)
      end
    end,
  })

  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
      if vim.b[args.buf].bigfile then
        vim.schedule(function()
          vim.lsp.buf_detach_client(args.buf, args.data.client_id)
        end)
      end
    end,
  })

  -- The treesitter foldexpr (options.lua) is window-local
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(args)
      if vim.b[args.buf].bigfile then
        vim.wo[0][0].foldmethod = "manual"
      end
    end,
  })
end

return M
