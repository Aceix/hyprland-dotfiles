-- Module overrides for NvChad's built-in statusline, wired up via
-- `M.ui.statusline.modules` in chadrc.lua.
--
-- Two constraints shape everything in here:
--
-- 1. No top-level `require`s. This file is pulled in by chadrc.lua, which is
--    itself loaded by nvconfig -- which nvchad.stl.* requires. Requiring a
--    statusline module at the top level is a cycle.
-- 2. Optional plugins are probed with `package.loaded[...]`, never
--    `pcall(require, ...)` (nvim-web-devicons excepted). These functions run on nearly every redraw, and a
--    require would drag lazy-loaded plugins (dap, neotest, conform) in at
--    startup.
--
-- Anything that touches the filesystem or spawns a process is cached; a
-- statusline module must stay a cheap table lookup.

local sep_r = ""
local sep_l = ""

-- Filetypes where hard tabs are the convention, so the anomaly module stays
-- quiet instead of crying wolf on every Go/Makefile buffer.
local tab_native = { go = true, gomod = true, make = true, gitconfig = true, gitcommit = true }

-- root -> " ↑2 ↓1", filled in asynchronously by refresh_upstream below
local upstream = {}
local upstream_pending = {}

local M = {}

local function stbufnr()
  return vim.api.nvim_win_get_buf(vim.g.statusline_winid or 0)
end

-- vim.fs.root walks up the filesystem, so the answer is memoised per buffer.
-- "" is the cached "no repo here" answer; nil means not looked up yet.
local function git_root(bufnr)
  local cached = vim.b[bufnr].stl_git_root
  if cached then
    return cached ~= "" and cached or nil
  end

  local root = vim.api.nvim_buf_get_name(bufnr) ~= "" and vim.fs.root(bufnr, ".git") or nil
  vim.b[bufnr].stl_git_root = root or ""
  return root
end

local function refresh_upstream(root)
  if not root or upstream_pending[root] then
    return
  end

  upstream_pending[root] = true

  vim.system(
    { "git", "rev-list", "--left-right", "--count", "@{u}...HEAD" },
    { cwd = root, text = true },
    function(out)
      upstream_pending[root] = nil

      -- A non-zero exit just means there's no upstream configured.
      local behind, ahead = "0", "0"
      if out.code == 0 then
        behind, ahead = (out.stdout or ""):match "(%d+)%s+(%d+)"
      end

      local str = ""
      if ahead and ahead ~= "0" then
        str = str .. " ↑" .. ahead
      end
      if behind and behind ~= "0" then
        str = str .. " ↓" .. behind
      end

      if upstream[root] ~= str then
        upstream[root] = str
        vim.schedule(function()
          vim.cmd.redrawstatus()
        end)
      end
    end
  )
end

M.refresh_upstream = function(bufnr)
  refresh_upstream(git_root(bufnr or vim.api.nvim_get_current_buf()))
end

-- Shared with utils/git_sidebar.lua and utils/git_panel.lua
M.git_root = git_root

M.file = function()
  local bufnr = stbufnr()
  local path = vim.api.nvim_buf_get_name(bufnr)

  if path == "" then
    return "%#St_file# 󰈚 Empty%#St_file_sep#" .. sep_r
  end

  local tail = path:match "([^/\\]+)[/\\]*$"

  local icon = "󰈚"
  local has_devicons, devicons = pcall(require, "nvim-web-devicons")
  if has_devicons then
    icon = devicons.get_icon(tail) or icon
  end

  local name = tail
  if vim.o.columns >= 120 then
    local root = git_root(bufnr)
    if root and path:sub(1, #root + 1) == root .. "/" then
      name = path:sub(#root + 2)
    end
  end

  local flags = ""
  if vim.bo[bufnr].modified then
    flags = flags .. "%#St_FileModified# ●"
  end
  if vim.bo[bufnr].readonly or not vim.bo[bufnr].modifiable then
    flags = flags .. "%#St_FileModified# "
  end
  -- gone from disk, buffer kept (utils/autoreload.lua)
  if vim.b[bufnr].file_deleted then
    flags = flags .. "%#St_FileModified# deleted"
  end

  return "%#St_file# " .. icon .. " " .. name .. flags .. "%#St_file_sep#" .. sep_r
end

M.git = function()
  local base = require("nvchad.stl.utils").git()
  if base == "" then
    return ""
  end

  local root = git_root(stbufnr())
  return "%#St_gitIcons#" .. base .. (root and upstream[root] or "") .. " "
end

M.diagnostics = function()
  if not rawget(vim, "lsp") then
    return ""
  end

  local severity = vim.diagnostic.severity
  local count = vim.diagnostic.count(stbufnr())

  local parts = {
    count[severity.ERROR] and "%#St_lspError# " .. count[severity.ERROR] .. " " or "",
    count[severity.WARN] and "%#St_lspWarning# " .. count[severity.WARN] .. " " or "",
    count[severity.INFO] and "%#St_LspInfo#󰋼 " .. count[severity.INFO] .. " " or "",
    count[severity.HINT] and "%#St_LspHints#󰛩 " .. count[severity.HINT] .. " " or "",
  }

  local str = table.concat(parts)
  return str == "" and "" or " " .. str
end

-- conform's list_formatters_to_run resolves availability with vim.fn.executable
-- per formatter, which is far too costly per redraw -- hence the buffer cache,
-- invalidated by the autocmds in lua/autocmds.lua.
local function formatters(bufnr)
  local cached = vim.b[bufnr].stl_formatters
  if cached then
    return cached
  end

  local names = ""
  if package.loaded["conform"] then
    local list = package.loaded["conform"].list_formatters_to_run(bufnr)
    names = table.concat(
      vim.tbl_map(function(f)
        return f.name
      end, list),
      ", "
    )
  end

  vim.b[bufnr].stl_formatters = names
  return names
end

M.lsp = function()
  if not rawget(vim, "lsp") then
    return ""
  end

  local bufnr = stbufnr()
  local names = {}
  for _, client in ipairs(vim.lsp.get_clients { bufnr = bufnr }) do
    names[#names + 1] = client.name
  end

  if #names == 0 then
    return ""
  end

  if vim.o.columns <= 100 then
    return "%#St_Lsp#   LSP "
  end

  local str = "   " .. table.concat(names, ", ")

  local fmt = formatters(bufnr)
  if fmt ~= "" then
    str = str .. " 󰉼 " .. fmt
  end

  return "%#St_Lsp#" .. str .. " "
end

M.cwd = function()
  if vim.o.columns <= 85 then
    return ""
  end

  local root = git_root(stbufnr()) or vim.uv.cwd()
  local name = root:match "([^/\\]+)[/\\]*$" or root

  return "%#St_cwd_sep#" .. sep_l .. "%#St_cwd_icon#󰉋 %#St_cwd_text# " .. name .. " "
end

-- VS Code's remote indicator: only shows when this nvim is a remote-nvim
-- server. utils.remote has no requires of its own, so it's safe here.
M.remote = function()
  local label = require("utils.remote").label()
  return label == "" and "" or "%#St_Remote# 󰒍 " .. label .. " "
end

M.recording = function()
  local reg = vim.fn.reg_recording()
  if reg == "" then
    return ""
  end

  return "%#St_Recording#  REC @" .. reg .. " "
end

M.search = function()
  if vim.v.hlsearch == 0 then
    return ""
  end

  -- The timeout matters: searchcount runs on every redraw and will happily
  -- scan a huge buffer without one.
  local ok, res = pcall(vim.fn.searchcount, { maxcount = 999, timeout = 250 })
  if not ok or not res.total or res.total == 0 then
    return ""
  end

  local current = res.incomplete == 1 and "?" or res.current
  return "%#St_Search#  " .. current .. "/" .. res.total .. " "
end

M.dap = function()
  local dap = package.loaded["dap"]
  if not dap then
    return ""
  end

  local status = dap.status()
  return status == "" and "" or "%#St_Dap#  " .. status .. " "
end

M.neotest = function()
  local neotest = package.loaded["neotest"]
  if not neotest or not neotest.state then
    return ""
  end

  local bufnr = stbufnr()
  local passed, failed, running = 0, 0, 0

  for _, id in ipairs(neotest.state.adapter_ids()) do
    local counts = neotest.state.status_counts(id, { buffer = bufnr })
    if counts then
      passed = passed + counts.passed
      failed = failed + counts.failed
      running = running + counts.running
    end
  end

  if running == 0 and failed == 0 then
    return ""
  end

  local str = ""
  if running > 0 then
    str = str .. "%#St_TestRun#󰑮 " .. running .. " "
  end
  if passed > 0 then
    str = str .. "%#St_TestPass# " .. passed .. " "
  end
  if failed > 0 then
    str = str .. "%#St_TestFail# " .. failed .. " "
  end

  return " " .. str
end

M.flutter = function()
  local decorations = vim.g.flutter_tools_decorations
  if not decorations then
    return ""
  end

  local parts = {}
  if decorations.device and decorations.device.name then
    parts[#parts + 1] = decorations.device.name
  end
  if decorations.app_version then
    parts[#parts + 1] = decorations.app_version
  end

  if #parts == 0 then
    return ""
  end

  return "%#St_Flutter#  " .. table.concat(parts, " ") .. " "
end

M.anomaly = function()
  local bufnr = stbufnr()
  local bo = vim.bo[bufnr]
  local parts = {}

  if bo.fileencoding ~= "" and bo.fileencoding ~= "utf-8" then
    parts[#parts + 1] = bo.fileencoding
  end

  if bo.fileformat == "dos" then
    parts[#parts + 1] = "CRLF"
  elseif bo.fileformat == "mac" then
    parts[#parts + 1] = "CR"
  end

  if not bo.expandtab and not tab_native[bo.filetype] then
    parts[#parts + 1] = "tabs:" .. bo.tabstop
  end

  if #parts == 0 then
    return ""
  end

  return "%#St_Anomaly#  " .. table.concat(parts, " ") .. " "
end

return M
