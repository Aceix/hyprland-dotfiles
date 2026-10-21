-- VS Code's side bar: one left slot (docked by edgy.nvim, configs/edgy.lua)
-- that shows either the Explorer (nvim-tree) or Source Control (Neogit status
-- on top, utils/git_panel.lua's History/Worktrees/Branches/... below).
--
-- The two are kept mutually exclusive by FileType autocmds rather than by the
-- open functions, so every way in -- <C-S-g>, <leader>gg, :Neogit, NvChad's
-- <C-n>/<leader>e -- behaves like clicking an activity-bar icon.

local M = {}

local scm_fts = { NeogitStatus = true, gitcommit = true, gitpanel = true }

-- "explorer" | "scm": what <C-b> brings back after the sidebar is hidden
M.mode = "explorer"

local function ft_of(win)
  return vim.bo[vim.api.nvim_win_get_buf(win)].filetype
end

local function is_sidebar_ft(ft)
  return ft == "NvimTree" or scm_fts[ft] == true
end

function M.is_sidebar_win(win)
  return is_sidebar_ft(ft_of(win))
end

local function find_wins(pred)
  local wins = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == "" and pred(ft_of(win)) then
      wins[#wins + 1] = win
    end
  end
  return wins
end

-- The repo the user is "in": the last edited file's, else the cwd's. (The
-- current buffer is often the sidebar itself, which has no path.)
function M.root()
  local buf = require("utils.git_panel").file_buf()
  local root = buf and require("configs.statusline").git_root(buf)
  return root or vim.fs.root(vim.uv.cwd(), ".git")
end

local function close_explorer()
  if package.loaded["nvim-tree"] then
    require("nvim-tree.api").tree.close()
  end
end

local function close_scm()
  -- Neogit's own close keeps fold/cursor state for the next open
  local status = package.loaded["neogit"] and require("neogit.buffers.status").instance()
  if status then
    status:close()
  end
  for _, win in ipairs(find_wins(function(ft)
    return ft == "NeogitStatus" or ft == "gitpanel"
  end)) do
    pcall(vim.api.nvim_win_close, win, false)
  end
end

local function open_explorer()
  require("nvim-tree.api").tree.open { find_file = true }
end

local function open_scm()
  local root = M.root()
  if not root then
    vim.notify("Source Control: not inside a git repository", vim.log.levels.WARN)
    return false
  end
  require("neogit").open { cwd = root, kind = "vsplit_left" }
  return true
end

-- === Width ===================================================================

-- One width shared by both views, so it survives Explorer <-> Source Control
-- switches and <C-b>. Upper-case g: var so shada ('!') keeps it across
-- restarts. edgy reads it via configs/edgy.lua's options.left.size.
local MIN_WIDTH = 15

function M.width()
  return vim.g.SIDEBAR_WIDTH or 40
end

function M.set_width(w)
  vim.g.SIDEBAR_WIDTH = math.max(MIN_WIDTH, math.min(w, vim.o.columns - 20))
  require("edgy.layout").update()
end

function M.is_open()
  return #find_wins(is_sidebar_ft) > 0
end

---@param mode "explorer"|"scm"
function M.show(mode)
  if mode == "scm" then
    if open_scm() then
      M.mode = "scm"
    end
  else
    open_explorer()
    M.mode = "explorer"
  end
end

-- <C-b>: hide the sidebar, or bring back whichever view was last shown
function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.show(M.mode)
  end
end

function M.close()
  close_explorer()
  close_scm()
end

-- === Opening files from the sidebar =========================================

-- A window in the editor area to open files in: the previous window if it is
-- one, else the first ordinary file window, else a fresh split.
local function editor_win()
  local function usable(win)
    if win == 0 or not vim.api.nvim_win_is_valid(win) then
      return false
    end
    if vim.api.nvim_win_get_config(win).relative ~= "" or M.is_sidebar_win(win) then
      return false
    end
    local buf = vim.api.nvim_win_get_buf(win)
    return vim.bo[buf].buftype == "" or vim.bo[buf].filetype == "nvdash"
  end

  local prev = vim.fn.win_getid(vim.fn.winnr "#")
  if usable(prev) then
    return prev
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if usable(win) then
      return win
    end
  end
end

-- Open a file in the editor area, leaving the sidebar where it is (VS Code
-- style), instead of Neogit's default of closing its status buffer.
function M.open_in_editor(path, lnum)
  local win = editor_win()
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd "botright vsplit"
  end
  vim.cmd.edit(vim.fn.fnameescape(path))
  if lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
    vim.cmd "normal! zz"
  end
end

local function neogit_item()
  local status = require("neogit.buffers.status").instance()
  local item = status and status.buffer and status.buffer.ui:get_item_under_cursor()
  return status, item
end

-- === Diff beside the sidebar ===================================================
--
-- VS Code's "click a changed file": a side-by-side diff in the editor area
-- (old version | new version) with the sidebar still showing. The old side,
-- and the new side for staged files, are read-only scratch buffers holding
-- `git show` output; for unstaged files the new side is the real file, so it
-- stays editable. One diff at a time: opening another replaces it.

-- { wins, bufs, specs, path, root, prev_buf, file_buf? } for the open diff
local diff_state

local function git_show(root, spec)
  local out = vim.system({ "git", "--no-pager", "show", spec }, { cwd = root, text = false }):wait()
  if out.code ~= 0 then
    return nil
  end
  local lines = vim.split(out.stdout or "", "\n", { plain = true })
  if lines[#lines] == "" then
    lines[#lines] = nil
  end
  return lines
end

-- Read-only buffer with a git object's content, highlighted like the file.
-- Treesitter is started directly instead of setting 'filetype', so LSP,
-- linters and the like don't attach to it.
local function scratch(name, lines, path)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or {})
  vim.bo[buf].modifiable = false
  pcall(vim.api.nvim_buf_set_name, buf, name)
  local ft = vim.filetype.match { filename = path }
  local lang = ft and vim.treesitter.language.get_lang(ft)
  if not (lang and pcall(vim.treesitter.start, buf, lang)) and ft then
    vim.bo[buf].syntax = ft
  end
  return buf
end

local function diff_winbar(label, open_button)
  local bar = "%#WinBar# " .. label:gsub("%%", "%%%%") .. "%="
  if open_button then
    bar = bar .. "%@v:lua.require'utils.git_sidebar'.open_file@%#GitSidebarTabActive#  Open File %X%#WinBar# "
  end
  return bar
end

-- Undo the diff: the old side's window closes, the new side's window stays
-- in the editor (back to the buffer it showed before, if it held a scratch
-- buffer), diff mode goes off and breadcrumbs get the winbar back.
function M.close_diff()
  local s = diff_state
  diff_state = nil
  if not s then
    return
  end
  pcall(vim.api.nvim_del_augroup_by_name, "GitSidebarDiff")
  local left, right = s.wins[1], s.wins[2]

  if vim.api.nvim_win_is_valid(left) and vim.list_contains(s.bufs, vim.api.nvim_win_get_buf(left)) then
    pcall(vim.api.nvim_win_close, left, true)
  end
  if vim.api.nvim_win_is_valid(right) then
    if vim.list_contains(s.bufs, vim.api.nvim_win_get_buf(right)) then
      local prev = s.prev_buf
      if prev and vim.api.nvim_buf_is_valid(prev) and vim.bo[prev].buflisted then
        vim.api.nvim_win_set_buf(right, prev)
      else
        vim.api.nvim_win_call(right, function()
          vim.cmd "enew"
        end)
      end
    end
    vim.api.nvim_win_call(right, function()
      vim.cmd "diffoff"
    end)
    vim.w[right].git_diff = nil
    vim.wo[right].winbar = ""
  end

  if s.file_buf and vim.api.nvim_buf_is_valid(s.file_buf) then
    pcall(vim.keymap.del, "n", "gf", { buffer = s.file_buf })
  end
  for _, buf in ipairs(s.bufs) do
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  if package.loaded["utils.breadcrumbs"] then
    pcall(require("utils.breadcrumbs").update)
  end
end

-- Re-read the git side(s) of the open diff after a git operation (the
-- working-tree side is a real buffer: utils/autoreload.lua reloads it)
function M.refresh_diff()
  local s = diff_state
  if not s then
    return
  end
  for buf, spec in pairs(s.specs) do
    if vim.api.nvim_buf_is_valid(buf) then
      local lines = git_show(s.root, spec) or {}
      if not vim.deep_equal(lines, vim.api.nvim_buf_get_lines(buf, 0, -1, false)) then
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.bo[buf].modifiable = false
      end
    end
  end
  for _, win in ipairs(s.wins) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_call(win, function()
        vim.cmd "diffupdate"
      end)
    end
  end
end

-- Leave the diff for the working-tree file, at the line the cursor is on
function M.open_file()
  local s = diff_state
  if not s then
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local right = s.wins[2]
  if vim.api.nvim_win_is_valid(right) then
    vim.api.nvim_set_current_win(right)
    -- Show the file first, so close_diff keeps this window rather than
    -- swapping the scratch buffer out for the previous one
    vim.cmd.edit(vim.fn.fnameescape(s.path))
    M.close_diff()
    pcall(vim.api.nvim_win_set_cursor, right, { lnum, 0 })
    vim.cmd "normal! zz"
  else
    M.close_diff()
    M.open_in_editor(s.path, lnum)
  end
end

---@param path string absolute path of the changed file
---@param kind "staged"|"unstaged" which change to show
---@param opts? { lnum?: integer, original?: string } original: pre-rename path
function M.open_diff(path, kind, opts)
  opts = opts or {}
  local root = vim.fs.root(path, ".git")
  if not root then
    return M.open_in_editor(path, opts.lnum)
  end
  local rel = path:sub(#root + 2)
  local old_rel = opts.original and opts.original ~= "" and opts.original or rel

  M.close_diff()

  -- unstaged: index -> working tree;  staged: HEAD -> index
  local left_label, left_spec, right_label
  if kind == "staged" then
    left_label, left_spec, right_label = "HEAD", "HEAD:" .. old_rel, "Index"
  else
    left_label, left_spec, right_label = "Index", ":" .. old_rel, "Working Tree"
  end
  local name = vim.fn.fnamemodify(rel, ":t")

  local editor = editor_win()
  if editor then
    vim.api.nvim_set_current_win(editor)
  else
    vim.cmd "botright vsplit"
  end

  local right_win = vim.api.nvim_get_current_win()
  local s = { path = path, root = root, bufs = {}, specs = {}, wins = {}, prev_buf = vim.api.nvim_win_get_buf(right_win) }
  if kind == "unstaged" and vim.uv.fs_stat(path) then
    vim.cmd.edit(vim.fn.fnameescape(path))
    s.file_buf = vim.api.nvim_get_current_buf()
    vim.keymap.set("n", "gf", M.open_file, { buffer = s.file_buf, desc = "Open file (leave diff)" })
  else
    -- Staged side, or a file deleted from the working tree
    local spec = kind == "staged" and ":" .. rel or nil
    local buf = scratch(("git://%s/%s (%s)"):format(root, rel, right_label), spec and git_show(root, spec), path)
    vim.api.nvim_win_set_buf(right_win, buf)
    s.bufs[#s.bufs + 1] = buf
    s.specs[buf] = spec
  end

  local left_buf = scratch(("git://%s/%s (%s)"):format(root, old_rel, left_label), git_show(root, left_spec), path)
  s.bufs[#s.bufs + 1] = left_buf
  s.specs[left_buf] = left_spec
  vim.cmd "leftabove vsplit"
  local left_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(left_win, left_buf)
  s.wins = { left_win, right_win }

  for _, buf in ipairs(s.bufs) do
    vim.keymap.set("n", "gf", M.open_file, { buffer = buf, desc = "Open file (leave diff)" })
    vim.keymap.set("n", "q", M.close_diff, { buffer = buf, desc = "Close diff" })
  end
  for _, win in ipairs(s.wins) do
    vim.w[win].git_diff = true
    vim.api.nvim_win_call(win, function()
      vim.cmd "diffthis"
    end)
  end
  vim.wo[left_win].winhighlight = require("utils.diff").OLD_WINHL
  vim.wo[left_win].winbar = diff_winbar(name .. " (" .. left_label .. ")", false)
  vim.wo[right_win].winbar = diff_winbar(name .. " (" .. right_label .. ")", true)
  diff_state = s

  -- The diff ends when either side's window closes or shows something else
  local group = vim.api.nvim_create_augroup("GitSidebarDiff", { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      if vim.list_contains(s.wins, tonumber(ev.match)) then
        vim.schedule(M.close_diff)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(ev)
      local win = vim.api.nvim_get_current_win()
      if vim.list_contains(s.wins, win) and ev.buf ~= s.file_buf and not vim.list_contains(s.bufs, ev.buf) then
        vim.schedule(M.close_diff)
      end
    end,
  })

  vim.api.nvim_set_current_win(right_win)
  if opts.lnum then
    pcall(vim.api.nvim_win_set_cursor, right_win, { opts.lnum, 0 })
  else
    vim.cmd "normal! gg"
    pcall(vim.cmd, "normal! ]c")
  end
  vim.cmd "normal! zz"
end

-- Neogit status <CR>: a changed file opens as a diff beside the sidebar,
-- at the hunk under the cursor (new files, untracked or added, just open).
-- Anything else (commits, stashes, ...) keeps Neogit's behaviour.
function M.neogit_open()
  local status, item = neogit_item()
  if not (item and item.absolute_path) or vim.fn.isdirectory(item.absolute_path) == 1 then
    if status then
      status:_action("n_goto_file")()
    end
    return
  end

  -- Same translation Neogit's own GoToFile does; rawget because indexing
  -- item.diff would load the diff of a folded file just to find no hunk
  local lnum
  local diff = rawget(item, "diff")
  if diff then
    local line = vim.api.nvim_win_get_cursor(0)[1]
    for _, hunk in ipairs(diff.hunks) do
      if line >= hunk.first and line <= hunk.last then
        lnum = require("neogit.lib.jump").adjust_row(hunk.disk_from, line - hunk.first, hunk.lines, "-")
        break
      end
    end
  end

  local section = status.buffer.ui:get_current_section()
  local kind = section and section.options.section
  -- N: staged new file, A: intent-to-add; neither has an old side to diff
  if (kind == "staged" or kind == "unstaged") and item.mode ~= "N" and item.mode ~= "A" then
    M.open_diff(item.absolute_path, kind, { lnum = lnum, original = item.original_name })
  else
    M.open_in_editor(item.absolute_path, lnum)
  end
end

-- Neogit status click, VS Code style: a file opens as <CR> does, a section
-- header folds. On release, after the click moved the cursor; a drag ends in
-- Visual mode, where this normal-mode mapping doesn't fire.
function M.neogit_click()
  local status, item = neogit_item()
  local pos = vim.fn.getmousepos()
  if not status or pos.winid ~= vim.api.nvim_get_current_win() or pos.line ~= vim.fn.line "." then
    return
  end
  local section = status.buffer.ui:get_current_section()
  if item and item.absolute_path then
    M.neogit_open()
  elseif section and section:row_range_abs() == pos.line then
    status:_action("n_toggle")()
  end
end

-- Neogit status D: the file's working-tree / index changes in diffview
function M.neogit_diff()
  local _, item = neogit_item()
  if item and item.absolute_path then
    local rel = vim.fn.fnamemodify(item.absolute_path, ":.")
    vim.cmd("DiffviewOpen --selected-file=" .. vim.fn.fnameescape(item.absolute_path) .. " -- " .. vim.fn.fnameescape(rel))
  else
    vim.cmd "DiffviewOpen"
  end
end

-- === Winbar tab strip ========================================================

function M.click_explorer()
  M.show "explorer"
end

function M.click_scm()
  M.show "scm"
end

function M.winbar()
  local win = vim.g.statusline_winid or 0
  local scm = ft_of(win) ~= "NvimTree"

  local count = require("utils.git_panel").change_count()
  local scm_label = "󰊢 Source Control" .. (count > 0 and (" (" .. count .. ")") or "")

  local function tab(label, active, fn)
    return ("%%@v:lua.require'utils.git_sidebar'.%s@%%#%s# %s %%X"):format(
      fn,
      active and "GitSidebarTabActive" or "GitSidebarTab",
      label
    )
  end

  return tab(" Explorer", not scm, "click_explorer")
    .. "%#GitSidebarTab#│"
    .. tab(scm_label, scm, "click_scm")
    .. "%#GitSidebarTab#%="
end

-- === Wiring ==================================================================

function M.setup()
  local group = vim.api.nvim_create_augroup("GitSidebar", { clear = true })

  -- BufWinEnter as well as FileType: a hidden buffer shown again doesn't
  -- re-fire FileType. The handler is idempotent, so both firing is fine.
  vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
    group = group,
    callback = function(ev)
      local ft = vim.bo[ev.buf].filetype
      if ft ~= "NvimTree" and ft ~= "NeogitStatus" then
        return
      end

      vim.schedule(function()
        if ft == "NvimTree" then
          M.mode = "explorer"
          close_scm()
        else
          M.mode = "scm"
          -- Neogit's window has its own highlight namespace, which overrides
          -- 'winhighlight': give it the side bar's edge there (configs/edgy.lua)
          local ns = vim.api.nvim_get_hl_ns { winid = vim.fn.bufwinid(ev.buf) }
          if ns > 0 then
            vim.api.nvim_set_hl(ns, "WinSeparator", { link = "NvimTreeWinSeparator" })
          end
          close_explorer()
          require("utils.git_panel").open(M.root())
        end
      end)
    end,
  })

  -- Windows split or tab-opened from the sidebar (DiffviewOpen, Neogit's
  -- log / commit views, gitgraph, Octo, ...) inherit its window-local
  -- options: fixed 40-col width, the tab-strip winbar, edgy's highlights.
  -- Put those back to normal on any window that isn't part of the sidebar.
  local function scrub(win)
    if M.is_sidebar_win(win) or vim.api.nvim_win_get_config(win).relative ~= "" then
      return false
    end
    local wo = vim.wo[win]
    if not wo.winhighlight:find("EdgyWinBar", 1, true) then
      return false
    end
    wo.winfixwidth = false
    wo.winfixheight = false
    wo.winbar = vim.go.winbar
    wo.winhighlight = ""
    wo.signcolumn = vim.go.signcolumn
    wo.scrolloff = -1
    wo.spell = vim.go.spell
    return true
  end

  vim.api.nvim_create_autocmd({ "WinNew", "BufWinEnter", "TabEnter" }, {
    group = group,
    callback = function()
      vim.schedule(function()
        local fixed, has_sidebar = false, false
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          if vim.api.nvim_win_is_valid(win) then
            fixed = scrub(win) or fixed
            has_sidebar = has_sidebar or M.is_sidebar_win(win)
          end
        end
        -- The inherited width already skewed this tab's layout
        if fixed and not has_sidebar then
          -- 'winfixwidth' keeps panels out of the equalise; "autoresize"
          -- (not focus.nvim's equalise goal, which sticks) regrows the split
          vim.cmd "wincmd ="
          if package.loaded.focus then
            require("focus").resize "autoresize"
          end
        end
      end)
    end,
  })

  -- Mouse drags / :vertical resize on the side bar: edgy snaps any width it
  -- didn't set back to options.left.size on WinResized, so record the new
  -- width first. This is registered before edgy's handler (edgy loads on
  -- VeryLazy), so edgy's layout pass already sees it. Only windows edgy has
  -- settled count -- a freshly opened one (not yet at the shared width)
  -- or a terminal resize would otherwise overwrite the saved width.
  local settled = {} ---@type table<integer, boolean>
  local columns = vim.o.columns
  local function settle()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if M.is_sidebar_win(win) and vim.api.nvim_win_get_width(win) == M.width() then
        settled[win] = true
      end
    end
  end

  vim.api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function()
      if vim.o.columns ~= columns then
        columns = vim.o.columns
      else
        for _, win in ipairs(vim.v.event.windows or {}) do
          if settled[win] and vim.api.nvim_win_is_valid(win) and M.is_sidebar_win(win) then
            local w = vim.api.nvim_win_get_width(win)
            if w ~= M.width() then
              vim.g.SIDEBAR_WIDTH = math.max(MIN_WIDTH, w)
            end
            break
          end
        end
      end
      vim.schedule(settle)
    end,
  })
  vim.api.nvim_create_autocmd({ "WinNew", "BufWinEnter" }, {
    group = group,
    callback = function()
      vim.schedule(settle)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      settled[tonumber(ev.match)] = nil
    end,
  })

  -- Sessions: the PersistenceSavePre handler in lua/autocmds.lua already
  -- closes every non-file window, the sidebar's included.
end

return M
