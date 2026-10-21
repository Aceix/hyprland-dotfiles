-- Reflect changes made outside Neovim (git checkout / pull / stash / reset,
-- another editor, a formatter, rm, ...) as they happen. libuv's fs_event is
-- FSEvents on macOS and inotify on Linux, so this works the same locally and
-- on a remote host (remote-nvim runs this config there).
--   * The directories of open files are watched. A changed file reloads; one
--     with unsaved edits asks first (keep / load / compare); a deleted one
--     stays open, marked "deleted" in the statusline (:w writes it back).
--   * Each repo's git dir (HEAD, index, refs) is watched. Any git operation
--     fires `User GitChanged` (data.root), which refreshes nvim-tree, the git
--     panel, the statusline, diffview, Source Control and the sidebar diff.
--   * While Source Control (Neogit's status) shows, its repo's work tree is
--     watched too, so edits, new and deleted files show there. Recursively on
--     macOS (FSEvents); inotify can't, so on Linux only the top directory is
--     and the focus / terminal checks below catch the rest.
--   * A directory that can't be watched (gone after a branch switch, or the
--     watch failed, e.g. inotify's limit) is polled every 2s until it can.
--   * :checktime on focus / leaving a terminal / entering a buffer stays as
--     a safety net.
local M = {}
local uv = vim.uv

local POLL_MS = 2000
local DEBOUNCE_MS = 150

-- dir -> { files?, root?, refs?, handle?, ino?, recheck?, broken?, sig? }
--   files: open buffers live here; root: a git dir of that repo; refs: the
--   refs/heads dir (any entry counts, not just the names below)
local watched = {}
local pending = { dirs = {}, roots = {}, tree = false }
local flush_timer = assert(uv.new_timer())
local sync_timer = assert(uv.new_timer())
local poll_timer

-- Files in a git dir whose change means "the repo changed"
local git_names = {
  HEAD = true,
  ORIG_HEAD = true,
  FETCH_HEAD = true,
  MERGE_HEAD = true,
  REBASE_HEAD = true,
  CHERRY_PICK_HEAD = true,
  REVERT_HEAD = true,
  index = true,
  ["packed-refs"] = true,
  ["rebase-merge"] = true,
  ["rebase-apply"] = true,
}

--- buf -> absolute path, for every loaded buffer backed by a real file
local function file_bufs()
  local out = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and not name:match "^%a[%w+.-]*://" then
        out[buf] = name
      end
    end
  end
  return out
end

local function checktime(buf)
  pcall(vim.cmd, buf and ("checktime " .. buf) or "checktime")
end

-- root -> { dirs to watch } | false (not a repo / git failed)
local git_dir_cache = {}
local function git_dirs(root)
  if git_dir_cache[root] == nil then
    -- (not --path-format=absolute: that needs git 2.31+)
    local out = vim
      .system({ "git", "-C", root, "rev-parse", "--absolute-git-dir", "--git-common-dir" }, { text = true })
      :wait()
    local dirs = false
    if out.code == 0 then
      local gitdir, common = unpack(vim.split(vim.trim(out.stdout):gsub("\r", ""), "\n"))
      if common and not (common:match "^/" or common:match "^%a:") then
        common = root .. "/" .. common -- relative to -C's directory
      end
      common = common and vim.fs.normalize(uv.fs_realpath(common) or common)
      gitdir = vim.fs.normalize(uv.fs_realpath(gitdir) or gitdir)
      dirs = { gitdir }
      if common and common ~= gitdir then
        dirs[#dirs + 1] = common -- a linked worktree shares refs with the main one
      end
      dirs[#dirs + 1] = (common or gitdir) .. "/refs/heads"
    end
    git_dir_cache[root] = dirs
  end
  return git_dir_cache[root] or {}
end

-- Polling fallback for a git dir: change in this signature = repo changed
local function git_sig(dir)
  local parts = {}
  for _, name in ipairs { "HEAD", "index", "packed-refs", "FETCH_HEAD", "ORIG_HEAD", "." } do
    local st = uv.fs_stat(dir .. "/" .. name)
    parts[#parts + 1] = st and (st.mtime.sec .. "." .. st.mtime.nsec) or "-"
  end
  return table.concat(parts, ",")
end

local schedule_flush

local function on_event(dir, err, fname)
  local info = watched[dir]
  if not info then
    return
  end
  -- Re-arm on the next flush if the directory itself went away or was
  -- replaced (inotify keeps watching the old inode)
  info.recheck = true
  if err then
    info.broken = true
  end
  if info.root then
    local base = fname and fname:match "[^/]*$"
    if not base or (info.refs or git_names[base]) and not base:match "%.lock$" then
      pending.roots[info.root] = true
    end
  end
  if info.files then
    pending.dirs[dir] = true
  end
  schedule_flush()
end

local function stop(info)
  if info.handle then
    info.handle:stop()
    if not info.handle:is_closing() then
      info.handle:close()
    end
    info.handle = nil
  end
end

---@return boolean started
local function start(dir, info)
  stop(info)
  info.broken = nil
  local st = uv.fs_stat(dir)
  if not st or st.type ~= "directory" then
    return false
  end
  local handle = uv.new_fs_event()
  if not handle then
    return false
  end
  local ok = handle:start(dir, {}, function(err, fname)
    on_event(dir, err, fname)
  end)
  if ok ~= 0 then
    handle:close()
    return false
  end
  info.handle, info.ino = handle, st.ino
  return true
end

local function poll()
  local again = false
  for dir, info in pairs(watched) do
    if not info.handle then
      -- back or still missing, whatever is in it may have changed
      if info.files then
        pending.dirs[dir] = true
      end
      if start(dir, info) then
        if info.root then
          pending.roots[info.root] = true
        end
      else
        again = true
        if info.root then
          local sig = git_sig(dir)
          if info.sig and sig ~= info.sig then
            pending.roots[info.root] = true
          end
          info.sig = sig
        end
      end
    end
  end
  if next(pending.dirs) or next(pending.roots) then
    schedule_flush()
  end
  if not again and poll_timer then
    poll_timer:stop()
  end
end

local function update_poll()
  for _, info in pairs(watched) do
    if not info.handle then
      poll_timer = poll_timer or assert(uv.new_timer())
      if not poll_timer:is_active() then
        poll_timer:start(POLL_MS, POLL_MS, vim.schedule_wrap(poll))
      end
      return
    end
  end
  if poll_timer then
    poll_timer:stop()
  end
end

-- Source Control; the git panel follows (NeogitStatusRefreshed)
local function refresh_scm()
  local neogit = package.loaded["neogit"]
  if neogit and neogit.dispatch_refresh then
    pcall(neogit.dispatch_refresh)
  end
end

--- Everything that shows git state, brought up to date
local function refresh_git_views()
  if package.loaded["nvim-tree"] then
    pcall(function()
      require("nvim-tree.api").tree.reload()
    end)
  end
  if package.loaded["configs.statusline"] then
    pcall(require("configs.statusline").refresh_upstream)
  end
  if package.loaded["diffview.lib"] then
    for _, view in ipairs(require("diffview.lib").views) do
      if view.update_files then
        pcall(view.update_files, view)
      end
    end
  end
  if package.loaded["utils.git_sidebar"] then
    pcall(require("utils.git_sidebar").refresh_diff)
  end
  refresh_scm()
  vim.cmd.redrawstatus { bang = true }
end

local function flush()
  -- :checktime isn't allowed from the command-line window
  if vim.fn.getcmdwintype() ~= "" then
    return flush_timer:start(500, 0, vim.schedule_wrap(flush))
  end
  local dirs, roots, tree_changed = pending.dirs, pending.roots, pending.tree
  pending.dirs, pending.roots, pending.tree = {}, {}, false

  for dir, info in pairs(watched) do
    if info.recheck then
      info.recheck = nil
      local st = uv.fs_stat(dir)
      if info.broken or not st or st.ino ~= info.ino then
        start(dir, info)
      end
    end
  end
  update_poll()

  if next(roots) then
    checktime() -- a checkout / reset / stash can touch any file
    for root in pairs(roots) do
      vim.api.nvim_exec_autocmds("User", { pattern = "GitChanged", data = { root = root }, modeline = false })
    end
    refresh_git_views()
  else
    if next(dirs) then
      for buf, name in pairs(file_bufs()) do
        if dirs[vim.fs.dirname(name)] then
          checktime(buf)
        end
      end
    end
    if tree_changed then
      refresh_scm()
    end
  end
end

-- Callable from libuv callbacks (fast context): only touches a timer
schedule_flush = function()
  flush_timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(flush))
end

--- Watch exactly the directories of the open files and their repos' git dirs
function M.sync()
  local want = {}
  local roots = {}
  for _, name in pairs(file_bufs()) do
    local dir = vim.fs.dirname(name)
    want[dir] = want[dir] or {}
    want[dir].files = true
    local root = vim.fs.root(name, ".git")
    if root then
      roots[root] = true
    end
  end
  local cwd_root = vim.fs.root(uv.cwd(), ".git")
  if cwd_root then
    roots[cwd_root] = true
  end
  for root in pairs(roots) do
    for i, dir in ipairs(git_dirs(root)) do
      want[dir] = want[dir] or {}
      want[dir].root = root
      want[dir].refs = dir:sub(-11) == "/refs/heads" or nil
      if i == 1 then
        want[dir].sig = git_sig(dir)
      end
    end
  end

  for dir, info in pairs(watched) do
    if not want[dir] then
      stop(info)
      watched[dir] = nil
    end
  end
  for dir, w in pairs(want) do
    local info = watched[dir]
    if info then
      info.files, info.root, info.refs = w.files, w.root, w.refs
    else
      watched[dir] = w
      start(dir, w)
    end
  end
  update_poll()
end

-- The work tree Source Control shows: { root, handle }
local tree = {}
local function watch_tree()
  local status = package.loaded["neogit"] and require("neogit.buffers.status").instance()
  local root = status and status.buffer and vim.fn.bufwinid(status.buffer.handle) ~= -1 and status.root or nil
  if tree.root == root then
    return
  end
  stop(tree)
  tree = { root = root }
  if not root then
    return
  end
  local handle = assert(uv.new_fs_event())
  local ok = handle:start(root, { recursive = true }, function(err, fname)
    -- the git dir has its own watch
    if not err and fname and fname ~= ".git" and not vim.startswith(fname, ".git/") then
      pending.tree = true
      schedule_flush()
    end
  end)
  if ok == 0 then
    tree.handle = handle
  else
    handle:close()
  end
end

local function schedule_sync()
  sync_timer:start(200, 0, vim.schedule_wrap(M.sync))
end

-- Deleted files, reported in one message per batch
local deleted, deleted_timer = {}, assert(uv.new_timer())
local function report_deleted(buf)
  deleted[#deleted + 1] = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":~:.")
  deleted_timer:start(
    300,
    0,
    vim.schedule_wrap(function()
      local names = table.concat(deleted, ", ")
      deleted = {}
      vim.notify("Deleted on disk, kept open (:w writes it back): " .. names, vim.log.levels.WARN)
    end)
  )
end

-- The file as it is on disk beside the buffer, as a diff. `do` / `dp` move
-- hunks across; q closes it.
local function compare(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    vim.api.nvim_set_current_buf(buf)
    win = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_set_current_win(win)

  local ok, lines = pcall(vim.fn.readfile, path)
  local disk = vim.api.nvim_create_buf(false, true)
  vim.bo[disk].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(disk, 0, -1, false, ok and lines or {})
  vim.bo[disk].modifiable = false
  pcall(vim.api.nvim_buf_set_name, disk, path .. " (on disk)")
  local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
  if not (lang and pcall(vim.treesitter.start, disk, lang)) then
    vim.bo[disk].syntax = vim.bo[buf].filetype
  end

  vim.cmd "rightbelow vsplit"
  local disk_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(disk_win, disk)
  vim.wo[disk_win].winbar = "%#WinBar# On disk   do/dp: move a hunk   q: close   :e! in your buffer takes this version"
  for _, w in ipairs { win, disk_win } do
    vim.api.nvim_win_call(w, function()
      vim.cmd "diffthis"
    end)
  end
  vim.keymap.set("n", "q", "<Cmd>close<CR>", { buffer = disk, desc = "Close the on-disk version" })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = disk,
    once = true,
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_call(win, function()
            vim.cmd "diffoff"
          end)
        end
      end)
    end,
  })
end

local asking = {}
local function resolve_conflict(buf)
  if asking[buf] or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  asking[buf] = true
  local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":~:.")
  vim.ui.select(
    { "Keep my edits", "Load from disk (discard my edits)", "Compare with the version on disk" },
    { prompt = name .. " changed on disk, but has unsaved edits here" },
    function(_, idx)
      asking[buf] = nil
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      if idx == 2 then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd "edit!"
        end)
      elseif idx == 3 then
        compare(buf)
      end
    end
  )
end

function M.setup()
  vim.o.autoread = true
  local group = vim.api.nvim_create_augroup("AutoReload", { clear = true })

  -- Decides what a :checktime that found a change does (instead of Vim's
  -- W11 / W12 prompts)
  vim.api.nvim_create_autocmd("FileChangedShell", {
    group = group,
    callback = function(ev)
      local buf, reason = ev.buf, vim.v.fcs_reason
      if reason == "deleted" then
        vim.v.fcs_choice = ""
        if not vim.b[buf].file_deleted then
          vim.b[buf].file_deleted = true
          vim.schedule(function()
            report_deleted(buf)
          end)
        end
      elseif reason == "conflict" or vim.bo[buf].modified then
        vim.v.fcs_choice = ""
        vim.schedule(function()
          resolve_conflict(buf)
        end)
      else -- changed / mode / time, no unsaved edits
        vim.b[buf].file_deleted = nil
        vim.v.fcs_choice = "reload"
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWritePost", "FileChangedShellPost" }, {
    group = group,
    callback = function(ev)
      vim.b[ev.buf].file_deleted = nil
    end,
  })

  -- Safety net: focus back, a terminal split done (git ran there), a buffer
  -- entered
  vim.api.nvim_create_autocmd({ "FocusGained", "TermLeave", "TermClose" }, {
    group = group,
    callback = function()
      checktime()
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      if vim.bo[ev.buf].buftype == "" and vim.fn.getcmdwintype() == "" then
        checktime(ev.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd(
    { "BufReadPost", "BufNewFile", "BufFilePost", "BufWritePost", "BufUnload", "BufWipeout", "DirChanged" },
    { group = group, callback = schedule_sync }
  )
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinClosed", "TabEnter" }, {
    group = group,
    callback = function()
      vim.schedule(watch_tree)
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for _, info in pairs(watched) do
        stop(info)
      end
      watched = {}
      stop(tree)
    end,
  })
  schedule_sync()
end

return M
