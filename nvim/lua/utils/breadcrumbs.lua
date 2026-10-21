-- VS Code-style breadcrumbs in the winbar: `dir › file › Class › method`,
-- built from LSP document symbols (no plugin). Symbols are fetched on attach
-- and after edits (debounced), then the path is re-walked on CursorHold.
local M = {}

local sep = "%#Comment# › %*"
local cache = {} ---@type table<integer, table[]> bufnr -> flattened symbols
local timers = {} ---@type table<integer, uv.uv_timer_t>

local skip_ft = {
  NvimTree = true,
  trouble = true,
  codecompanion = true,
  qf = true,
  help = true,
  lazy = true,
  mason = true,
  ["grug-far"] = true,
  Outline = true,
  minimap = true,
}

local function wants_winbar(win, buf)
  return vim.api.nvim_win_get_config(win).relative == ""
    and vim.bo[buf].buftype == ""
    and not skip_ft[vim.bo[buf].filetype]
    and not vim.bo[buf].filetype:match "^dap"
    and not vim.b[buf].bigfile
    and vim.api.nvim_buf_get_name(buf) ~= ""
    and not vim.w[win].git_diff -- the sidebar's diff owns this winbar
end

local function icon(kind)
  local ok, icons = pcall(require, "mini.icons")
  if not ok then
    return ""
  end
  local glyph, hl = icons.get("lsp", vim.lsp.protocol.SymbolKind[kind] or "")
  return ("%%#%s#%s %%*"):format(hl, glyph)
end

-- DocumentSymbol[] (nested) or SymbolInformation[] (flat) -> flat list of
-- { name, kind, range, depth }
local function flatten(symbols, depth, out)
  for _, s in ipairs(symbols or {}) do
    local range = s.range or (s.location and s.location.range)
    if range then
      out[#out + 1] = { name = s.name, kind = s.kind, range = range, depth = depth }
    end
    flatten(s.children, depth + 1, out)
  end
  return out
end

local function request(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local client = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/documentSymbol" })[1]
  if not client then
    return
  end
  local params = { textDocument = vim.lsp.util.make_text_document_params(buf) }
  client:request("textDocument/documentSymbol", params, function(err, result)
    if err or not result or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    cache[buf] = flatten(result, 0, {})
    M.update()
  end, buf)
end

local function request_debounced(buf)
  local t = timers[buf] or vim.uv.new_timer()
  timers[buf] = t
  t:stop()
  t:start(300, 0, vim.schedule_wrap(function()
    request(buf)
  end))
end

local function contains(range, line, col)
  local s, e = range.start, range["end"]
  if line < s.line or line > e.line then
    return false
  end
  if line == s.line and col < s.character then
    return false
  end
  if line == e.line and col > e.character then
    return false
  end
  return true
end

function M.update()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  if not wants_winbar(win, buf) then
    return
  end

  local parts = {}
  local rel = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":~:.")
  for piece in rel:gmatch "[^/]+" do
    parts[#parts + 1] = "%#Comment#" .. piece:gsub("%%", "%%%%") .. "%*"
  end

  local pos = vim.api.nvim_win_get_cursor(win)
  local line, col = pos[1] - 1, pos[2]
  local chain = {}
  for _, s in ipairs(cache[buf] or {}) do
    if contains(s.range, line, col) then
      chain[#chain + 1] = s
    end
  end
  -- outermost first: shallower depth, then wider range (flat SymbolInformation)
  table.sort(chain, function(a, b)
    if a.depth ~= b.depth then
      return a.depth < b.depth
    end
    return a.range.start.line < b.range.start.line
      or (a.range.start.line == b.range.start.line and a.range["end"].line > b.range["end"].line)
  end)
  for _, s in ipairs(chain) do
    parts[#parts + 1] = icon(s.kind) .. s.name:gsub("%%", "%%%%")
  end

  vim.wo[win].winbar = " " .. table.concat(parts, sep)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("Breadcrumbs", { clear = true })

  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client:supports_method "textDocument/documentSymbol" then
        request_debounced(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave", "TextChanged" }, {
    group = group,
    callback = function(args)
      if cache[args.buf] then
        request_debounced(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWinEnter", "CursorHold", "WinEnter" }, {
    group = group,
    callback = function()
      M.update()
    end,
  })

  -- BufDelete too: tabufline closes with :bdelete, which never wipes, and
  -- each entry holds a libuv timer handle
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(args)
      cache[args.buf] = nil
      if timers[args.buf] then
        timers[args.buf]:close()
        timers[args.buf] = nil
      end
    end,
  })
end

return M
