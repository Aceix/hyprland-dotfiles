require "nvchad.autocmds"

-- `nvim .` puts the project directory in the arglist and in a listed buffer.
-- :mksession always writes the arglist (`$argadd .`), so it came back on every
-- restore as a blank tab named after the project that opened nvim-tree full
-- screen when entered. Called before saving and after restoring (the latter
-- also cleans sessions saved before this existed).
local function drop_directory_args()
  pcall(vim.cmd, "%argdelete")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.bo[buf].buflisted and name ~= "" and vim.fn.isdirectory(name) == 1 then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

-- Automate session restoration on Neovim startup via persistence.nvim
local session_restore_group = vim.api.nvim_create_augroup("PersistenceAutoRestore", { clear = true })

vim.api.nvim_create_autocmd("VimEnter", {
  group = session_restore_group,
  nested = true, -- Ensures syntax loading and other plugins kick in after files load
  callback = function()
    local argc = vim.fn.argc()
    local should_restore = argc == 0 or (argc == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1)

    if should_restore and not vim.g.started_by_firenvim then
      local ok, persistence = pcall(require, "persistence")
      if ok then
        persistence.load()
        drop_directory_args()
      end
    end
  end,
})

-- Only ordinary file buffers belong in a saved session. Terminals, the file
-- tree, quickfix/help, and plugin scratch buffers either restore as empty
-- panes or land in the wrong window on restore, so they get closed and wiped
-- right before persistence.nvim runs :mksession. PersistenceSavePre only fires
-- from persistence.nvim's own VimLeavePre handler, so nothing is destroyed
-- mid-session.
local session_ignored_filetypes = {
  ["NvimTree"] = true,
  ["Outline"] = true,
  ["trouble"] = true,
  ["codecompanion"] = true,
  ["dapui_scopes"] = true,
  ["dapui_breakpoints"] = true,
  ["dapui_stacks"] = true,
  ["dapui_watches"] = true,
  ["dapui_console"] = true,
  ["dap-repl"] = true,
  ["minimap"] = true,
  ["gitcommit"] = true,
  ["gitrebase"] = true,
}

-- A buffer is worth saving only if it maps to a real file on disk.
local function is_session_worthy(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  -- Anything other than "" is special: terminal, nofile, help, quickfix,
  -- prompt, acwrite (oil, fugitive, ...).
  if vim.bo[buf].buftype ~= "" then
    return false
  end
  if not vim.bo[buf].buflisted then
    return false
  end
  if session_ignored_filetypes[vim.bo[buf].filetype] then
    return false
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return false
  end
  -- URI-style names (term://, oil://, fugitive://, octo://, ...) aren't files.
  if name:match "^%a[%w+.%-]*://" then
    return false
  end
  if vim.fn.isdirectory(name) == 1 then
    return false
  end
  return true
end

vim.api.nvim_create_autocmd("User", {
  pattern = "PersistenceSavePre",
  group = session_restore_group,
  callback = function()
    drop_directory_args()

    -- Close nvim-tree through its own API so it tears down cleanly.
    local ok, api = pcall(require, "nvim-tree.api")
    if ok then
      pcall(api.tree.close)
    end

    -- Drop windows showing special buffers, so :mksession doesn't record them
    -- as blank panes in the layout.
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) and not is_session_worthy(vim.api.nvim_win_get_buf(win)) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end

    -- Then wipe the buffers themselves so they're not written as `badd` lines.
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if not is_session_worthy(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end,
})

-- mini.map's setup() only registers the module, it never opens the map window,
-- so open it automatically for real file buffers. <leader>uM (see
-- lua/mappings.lua) flips vim.g.minimap_auto_open, so an explicit close stays
-- closed for the rest of the session instead of popping back on the next
-- BufEnter.
local minimap_group = vim.api.nvim_create_augroup("MiniMapAutoOpen", { clear = true })

vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  group = minimap_group,
  callback = function(args)
    if vim.g.minimap_auto_open == false then
      return
    end
    -- Real file buffers only: skip terminals, the file tree, quickfix, help,
    -- and other plugin scratch buffers. Images (image.nvim's "nowrite"
    -- buffers) carry on so the map gets closed over them, see below.
    local bt = vim.bo[args.buf].buftype
    if (bt ~= "" and bt ~= "nowrite") or vim.api.nvim_buf_get_name(args.buf) == "" then
      return
    end
    -- Don't trigger from inside floating windows (telescope previews, lazy, ...).
    if vim.api.nvim_win_get_config(0).relative ~= "" then
      return
    end

    vim.schedule(function()
      if vim.api.nvim_get_current_buf() ~= args.buf then
        return
      end
      local ok, minimap = pcall(require, "mini.map")
      if not ok then
        return
      end
      -- image.nvim turns image files into blank buffers (by now, so this check
      -- is deferred) and hides an image any float overlaps, so the map would
      -- just blank it out. Close it; the next file buffer reopens it.
      if vim.bo[args.buf].filetype == "image_nvim" then
        pcall(minimap.close)
        return
      end
      if vim.bo[args.buf].buftype ~= "" then
        return
      end
      -- Already open in this tabpage: mini.map refreshes its own contents.
      local win = minimap.current.win_data[vim.api.nvim_get_current_tabpage()]
      if win and vim.api.nvim_win_is_valid(win) then
        return
      end
      pcall(minimap.open)
    end)
  end,
})

-- Turn relativenumber back on (e.g. after <leader>rn switched it off) whenever
-- outside Insert mode
local number_group = vim.api.nvim_create_augroup("NumberToggle", { clear = true })

vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained", "InsertLeave", "CmdlineLeave" }, {
  group = number_group,
  callback = function()
    if vim.o.number and vim.api.nvim_get_mode().mode ~= "i" then
      vim.opt.relativenumber = true
    end
  end,
})

-- CodeCompanion "AI thinking" spinner in the statusline's lsp_msg slot. A
-- single timer: overlapping requests used to start one redraw loop each.
local stl_group = vim.api.nvim_create_augroup("CodeCompanionStatusline", { clear = true })
local spinners = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner = { timer = nil, frame = 1 }

local function set_lsp_msg(msg)
  local ok, stl_utils = pcall(require, "nvchad.stl.utils")
  if ok then
    stl_utils.state.lsp_msg = msg
    vim.cmd.redrawstatus()
  end
end

vim.api.nvim_create_autocmd("User", {
  pattern = "CodeCompanionRequestStarted",
  group = stl_group,
  callback = function()
    if spinner.timer then
      return
    end
    spinner.timer = vim.uv.new_timer()
    spinner.timer:start(0, 100, vim.schedule_wrap(function()
      if not spinner.timer then
        return -- a tick queued just before the stop
      end
      set_lsp_msg(spinners[spinner.frame] .. " AI thinking...")
      spinner.frame = spinner.frame % #spinners + 1
    end))
  end,
})

vim.api.nvim_create_autocmd("User", {
  pattern = "CodeCompanionRequestFinished",
  group = stl_group,
  callback = function()
    if not spinner.timer then
      return
    end
    spinner.timer:stop()
    spinner.timer:close()
    spinner.timer = nil
    set_lsp_msg ""
  end,
})

-- Desktop/system notifications for CodeCompanion actions that need user attention
local notify_group = vim.api.nvim_create_augroup("CodeCompanionNotifications", { clear = true })

vim.api.nvim_create_autocmd("User", {
  pattern = "CodeCompanionToolApprovalRequested",
  group = notify_group,
  callback = function(args)
    local name = args.data and args.data.name or "a tool"
    vim.schedule(function()
      vim.notify(("CodeCompanion needs your approval for %s"):format(name), vim.log.levels.WARN, {
        title = "CodeCompanion",
      })
    end)
  end,
})

vim.api.nvim_create_autocmd("User", {
  pattern = "CodeCompanionToolApprovalFinished",
  group = notify_group,
  callback = function(args)
    local name = args.data and args.data.name or "the request"
    vim.schedule(function()
      vim.notify(("CodeCompanion approval resolved for %s"):format(name), vim.log.levels.INFO, {
        title = "CodeCompanion",
      })
    end)
  end,
})

-- Statusline refresh hooks for the custom modules in lua/configs/statusline.lua
local statusline_group = vim.api.nvim_create_augroup("CustomStatusline", { clear = true })

-- Nothing redraws the statusline on its own when a macro starts or stops, so
-- the REC indicator would otherwise only appear on the next unrelated redraw.
vim.api.nvim_create_autocmd({ "RecordingEnter", "RecordingLeave" }, {
  group = statusline_group,
  callback = function()
    vim.cmd.redrawstatus()
  end,
})

-- Refresh the (async, cached) ahead/behind counts and drop the cached conform
-- formatter list, which is keyed off filetype and executable lookups.
vim.api.nvim_create_autocmd({ "BufWritePost", "BufEnter", "FocusGained" }, {
  group = statusline_group,
  callback = function(args)
    vim.b[args.buf].stl_formatters = nil
    require("configs.statusline").refresh_upstream(args.buf)
  end,
})

vim.api.nvim_create_autocmd("User", {
  pattern = "GitSignsUpdate",
  group = statusline_group,
  callback = function()
    require("configs.statusline").refresh_upstream()
  end,
})

-- VS Code-style Source Control sidebar, GitLens panel and background fetch
-- (utils/git_sidebar.lua, utils/git_panel.lua, utils/git_autofetch.lua)
require("utils.git_sidebar").setup()
-- Always an editor area beside the sidebar and above the bottom panel
require("utils.layout").setup()
require("utils.git_panel").setup()
if require("settings").git_autofetch then
  require("utils.git_autofetch").start()
end


-- auto (un)set kitty opacity
local kitty_group = vim.api.nvim_create_augroup("SecureKittyTransparency", { clear = true })
local transparency = require "configs.transparency"

-- Only execute if Neovim detects it is running inside a socket-enabled Kitty window
if vim.env.KITTY_LISTEN_ON then
  -- Lower background opacity when entering Neovim
  vim.api.nvim_create_autocmd("VimEnter", {
    group = kitty_group,
    callback = function()
      transparency.set_kitty_opacity(transparency.kitty_opacity)
    end,
  })

  -- Restore fully opaque background when leaving Neovim
  vim.api.nvim_create_autocmd("VimLeave", {
    group = kitty_group,
    callback = function()
      transparency.set_kitty_opacity(1.0)
    end,
  })
end


-- Big-file guard: skip treesitter and LSP for files over 1.5 MB (minified
-- bundles, generated JSON, logs) so opening them stays instant.
local bigfile_group = vim.api.nvim_create_augroup("BigFile", { clear = true })

vim.api.nvim_create_autocmd("BufReadPre", {
  group = bigfile_group,
  callback = function(args)
    local stat = vim.uv.fs_stat(args.match)
    if stat and stat.size > 1.5 * 1024 * 1024 then
      vim.b[args.buf].bigfile = true
    end
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  group = bigfile_group,
  callback = function(args)
    if vim.b[args.buf].bigfile then
      -- NvChad starts treesitter from its own FileType autocmd; stop it after
      vim.schedule(function()
        pcall(vim.treesitter.stop, args.buf)
      end)
    end
  end,
})

vim.api.nvim_create_autocmd("LspAttach", {
  group = bigfile_group,
  callback = function(args)
    if vim.b[args.buf].bigfile then
      vim.schedule(function()
        vim.lsp.buf_detach_client(args.buf, args.data.client_id)
      end)
    end
  end,
})

-- VS Code-style breadcrumbs (path › symbol › symbol) in the winbar
require("utils.breadcrumbs").setup()

-- Fresh remote-nvim host: mason's data dir isn't copied over (configs/remote-nvim.lua),
-- so no LSPs/formatters exist yet. Remind on attach until something's installed.
if require("utils.remote").is_remote then
  vim.api.nvim_create_autocmd("UIEnter", {
    once = true,
    callback = function()
      local bin = vim.fn.stdpath "data" .. "/mason/bin"
      if vim.fn.empty(vim.fn.glob(bin .. "/*")) == 1 then
        vim.notify(
          "New remote host: no Mason tools installed yet.\nRun :MasonToolsInstallSync (needs node/npm for the JS-based LSPs).",
          vim.log.levels.WARN
        )
      end
    end,
  })
end


-- Golden-ratio resize of the focused code split, panels never touched
-- (utils/autoresize.lua)
require("utils.autoresize").setup()

-- Diff panes split 50/50 and scroll together under the mouse (utils/diff.lua)
require("utils.diff").setup()

-- Reload files and refresh git views when something changes outside Neovim
-- (utils/autoreload.lua)
require("utils.autoreload").setup()

-- VS Code fold chevrons in the gutter, clickable (utils/fold_gutter.lua)
require("utils.fold_gutter").setup()
