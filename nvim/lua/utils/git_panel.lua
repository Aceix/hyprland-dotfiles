-- The GitLens-style half of the Source Control sidebar (below Neogit status,
-- see utils/git_sidebar.lua): foldable File History / Worktrees / Branches /
-- Tags / Stashes / Remotes sections, each with VS Code / GitLens actions.
--
-- Everything is fetched with async `git` calls and rendered in one pass once
-- they all return, so the panel never blocks the editor. Press ? in the panel
-- for its keys.

local M = {}

local ns = vim.api.nvim_create_namespace "git_panel"

local state = {
  buf = nil, ---@type integer?
  root = nil, ---@type string?
  file_buf = nil, ---@type integer? last ordinary file buffer, for File History
  data = {}, -- section id -> items, from the last refresh
  changes = {}, -- root -> number of changed files (for the winbar badge)
  folded = { tags = true, worktrees = true },
  nodes = {}, -- line (1-based) -> node
  generation = 0, -- drops results of a refresh that was superseded
}

local sections = {
  { id = "history", title = "FILE HISTORY" },
  { id = "worktrees", title = "WORKTREES" },
  { id = "branches", title = "BRANCHES" },
  { id = "tags", title = "TAGS" },
  { id = "stashes", title = "STASHES" },
  { id = "remotes", title = "REMOTES" },
}

-- === Helpers ==================================================================

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Git" })
end

-- Never let a credential prompt hang a background git call
local git_env = { GIT_TERMINAL_PROMPT = "0", GIT_OPTIONAL_LOCKS = "0" }

---@param args string[]
---@param cb fun(out: vim.SystemCompleted)
local function git(args, cb)
  local cmd = { "git", "--no-pager" }
  vim.list_extend(cmd, args)
  vim.system(cmd, { cwd = state.root, text = true, env = git_env }, function(out)
    vim.schedule(function()
      cb(out)
    end)
  end)
end

local function lines_of(out)
  if out.code ~= 0 or not out.stdout then
    return {}
  end
  return vim.split(vim.trim(out.stdout), "\n", { trimempty = true })
end

local function split0(line)
  return vim.split(line, "\0", { plain = true })
end

-- Run a state-changing git command from a panel action, then refresh
-- everything that shows repo state.
local function run(args, ok_msg)
  git(args, function(out)
    if out.code ~= 0 then
      notify(vim.trim((out.stderr ~= "" and out.stderr or out.stdout) or "git failed"), vim.log.levels.ERROR)
    elseif ok_msg then
      notify(ok_msg)
    end
    M.refresh()
    if package.loaded["gitsigns"] then
      require("gitsigns").refresh()
    end
    require("configs.statusline").refresh_upstream()
  end)
end

local function confirm(prompt, fn)
  vim.ui.select({ "Yes", "No" }, { prompt = prompt }, function(choice)
    if choice == "Yes" then
      fn()
    end
  end)
end

local function input(prompt, default, fn)
  vim.ui.input({ prompt = prompt, default = default }, function(value)
    if value and vim.trim(value) ~= "" then
      fn(vim.trim(value))
    end
  end)
end

local function diffview(args)
  vim.cmd("DiffviewOpen " .. args)
end

-- === Data =====================================================================

local fetchers = {}

function fetchers.branches(done)
  git({
    "for-each-ref",
    "--sort=-committerdate",
    "--format=%(HEAD)%00%(refname:short)%00%(upstream:short)%00%(upstream:track,nobracket)%00%(committerdate:relative)",
    "refs/heads",
  }, function(out)
    local items = {}
    for _, line in ipairs(lines_of(out)) do
      local head, name, upstream, track, date = unpack(split0(line))
      items[#items + 1] = {
        kind = "branch",
        name = name,
        current = head == "*",
        upstream = upstream ~= "" and upstream or nil,
        ahead = track:match "ahead (%d+)",
        behind = track:match "behind (%d+)",
        gone = track == "gone",
        date = date,
      }
    end
    done(items)
  end)
end

function fetchers.remotes(done)
  git({ "for-each-ref", "--sort=refname", "--format=%(refname:short)%00%(committerdate:relative)", "refs/remotes" }, function(out)
    local items, seen = {}, {}
    for _, line in ipairs(lines_of(out)) do
      local ref, date = unpack(split0(line))
      local remote, branch = ref:match "^([^/]+)/(.+)$"
      -- refs/remotes/<r>/HEAD shortens to just "<r>"
      if remote and branch ~= "HEAD" then
        if not seen[remote] then
          seen[remote] = true
          items[#items + 1] = { kind = "remote", name = remote }
        end
        items[#items + 1] = { kind = "remote_branch", name = ref, remote = remote, branch = branch, date = date, depth = 2 }
      end
    end
    done(items)
  end)
end

function fetchers.tags(done)
  git({ "for-each-ref", "--sort=-creatordate", "--count=50", "--format=%(refname:short)%00%(creatordate:relative)", "refs/tags" }, function(out)
    local items = {}
    for _, line in ipairs(lines_of(out)) do
      local name, date = unpack(split0(line))
      items[#items + 1] = { kind = "tag", name = name, date = date }
    end
    done(items)
  end)
end

function fetchers.stashes(done)
  git({ "stash", "list", "--format=%gd%x00%s%x00%cr" }, function(out)
    local items = {}
    for _, line in ipairs(lines_of(out)) do
      local ref, msg, date = unpack(split0(line))
      items[#items + 1] = { kind = "stash", name = ref, msg = msg, date = date }
    end
    done(items)
  end)
end

function fetchers.worktrees(done)
  git({ "worktree", "list", "--porcelain" }, function(out)
    local items, cur = {}, nil
    for _, line in ipairs(lines_of(out)) do
      local path = line:match "^worktree (.+)$"
      if path then
        cur = { kind = "worktree", path = path, name = vim.fn.fnamemodify(path, ":t") }
        items[#items + 1] = cur
      elseif cur then
        cur.branch = line:match "^branch refs/heads/(.+)$" or cur.branch
        if line == "detached" then
          cur.branch = "(detached)"
        end
      end
    end
    -- Only worth a section when there's more than the main checkout
    done(#items > 1 and items or {})
  end)
end

function fetchers.history(done)
  local buf = M.file_buf()
  local path = buf and vim.api.nvim_buf_get_name(buf) or ""
  if path == "" or not state.root or path:sub(1, #state.root + 1) ~= state.root .. "/" then
    return done {}
  end
  local rel = path:sub(#state.root + 2)
  git({ "log", "--follow", "-n", "50", "--format=%h%x00%an%x00%ar%x00%s", "--", rel }, function(out)
    local items = {}
    for _, line in ipairs(lines_of(out)) do
      local sha, author, date, subject = unpack(split0(line))
      items[#items + 1] = { kind = "commit", sha = sha, author = author, date = date, name = subject, file = rel }
    end
    state.history_file = rel
    done(items)
  end)
end

local function fetch_change_count(root)
  vim.system({ "git", "status", "--porcelain" }, { cwd = root, text = true, env = git_env }, function(out)
    if out.code == 0 then
      local n = #lines_of(out)
      if state.changes[root] ~= n then
        state.changes[root] = n
        vim.schedule(function()
          vim.cmd.redrawstatus { bang = true } -- winbars too
        end)
      end
    end
  end)
end

-- === Rendering ================================================================

local function item_line(item)
  local depth = item.depth or 1
  local pad = string.rep("  ", depth)
  if item.kind == "branch" then
    local track = ""
    if item.gone then
      track = " ⊘"
    else
      track = (item.ahead and (" ↑" .. item.ahead) or "") .. (item.behind and (" ↓" .. item.behind) or "")
    end
    return pad .. (item.current and " " or " ") .. item.name .. track, item.date
  elseif item.kind == "remote" then
    return pad .. "󰒍 " .. item.name, nil
  elseif item.kind == "remote_branch" then
    return pad .. " " .. item.branch, item.date
  elseif item.kind == "tag" then
    return pad .. " " .. item.name, item.date
  elseif item.kind == "stash" then
    return pad .. " " .. item.name .. " " .. item.msg, item.date
  elseif item.kind == "worktree" then
    return pad .. "󰙅 " .. item.name .. " [" .. (item.branch or "?") .. "]", nil
  elseif item.kind == "commit" then
    return pad .. item.sha .. " " .. item.name, item.author .. ", " .. item.date
  end
end

local item_hl = {
  branch = "GitPanelBranch",
  remote = "GitPanelRemote",
  remote_branch = "GitPanelBranch",
  tag = "GitPanelTag",
  stash = "GitPanelStash",
  worktree = "GitPanelBranch",
  commit = "Normal",
}

function M.render()
  local buf = state.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end

  local lines, hls, virt, nodes = {}, {}, {}, {}
  local function add(text, node, hl, right)
    lines[#lines + 1] = text
    nodes[#lines] = node
    if hl then
      hls[#hls + 1] = { #lines - 1, hl }
    end
    if right then
      virt[#virt + 1] = { #lines - 1, right }
    end
  end

  for _, section in ipairs(sections) do
    local items = state.data[section.id]
    -- Empty sections stay out of the way, like GitLens hides them
    if items and #items > 0 then
      local folded = state.folded[section.id]
      local title = section.title
      if section.id == "history" and state.history_file then
        title = title .. " · " .. vim.fn.fnamemodify(state.history_file, ":t")
      end
      add((folded and " " or " ") .. title .. " (" .. #items .. ")", { kind = "section", id = section.id }, "GitPanelSection")
      if not folded then
        for _, item in ipairs(items) do
          local text, right = item_line(item)
          add(text, item, item.current and "GitPanelCurrent" or item_hl[item.kind], right)
        end
      end
    end
  end

  if #lines == 0 then
    add("  (nothing to show)", nil, "Comment")
  end

  state.nodes = nodes
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(buf, ns, h[1], 0, { end_row = h[1] + 1, hl_group = h[2], hl_eol = false })
  end
  for _, v in ipairs(virt) do
    vim.api.nvim_buf_set_extmark(buf, ns, v[1], 0, { virt_text = { { v[2], "GitPanelDim" } }, virt_text_pos = "right_align" })
  end
end

-- === Refresh ==================================================================

local refresh_timer = vim.uv.new_timer()

-- Debounced: BufEnter, GitSignsUpdate and Neogit refreshes come in bursts
function M.refresh()
  refresh_timer:stop()
  refresh_timer:start(150, 0, vim.schedule_wrap(M.refresh_now))
end

function M.refresh_now()
  if state.root then
    fetch_change_count(state.root)
  end
  if not M.is_visible() then
    return
  end

  state.generation = state.generation + 1
  local gen, pending, data = state.generation, #sections, {}
  for _, section in ipairs(sections) do
    fetchers[section.id](function(items)
      if gen ~= state.generation then
        return
      end
      data[section.id] = items
      pending = pending - 1
      if pending == 0 then
        state.data = data
        M.render()
      end
    end)
  end
end

-- === Actions ==================================================================

local function current_branch()
  for _, b in ipairs(state.data.branches or {}) do
    if b.current then
      return b
    end
  end
end

local function upstream_remote(branch)
  return branch and branch.upstream and branch.upstream:match "^([^/]+)/" or "origin"
end

local actions = {}

actions.branch = {
  ["<CR>"] = { "Checkout", function(b)
    run({ "switch", b.name }, "Switched to " .. b.name)
  end },
  c = { "Compare with HEAD", function(b)
    diffview("HEAD..." .. b.name)
  end },
  l = { "Branch history", function(b)
    vim.cmd("DiffviewFileHistory --range=" .. b.name)
  end },
  m = { "Merge into current branch", function(b)
    confirm("Merge " .. b.name .. " into the current branch?", function()
      run({ "merge", b.name }, "Merged " .. b.name)
    end)
  end },
  n = { "New branch from here", function(b)
    input("New branch from " .. b.name .. ": ", "", function(name)
      run({ "switch", "-c", name, b.name }, "Created " .. name)
    end)
  end },
  r = { "Rename", function(b)
    input("Rename branch: ", b.name, function(name)
      run({ "branch", "-m", b.name, name })
    end)
  end },
  p = { "Push (sets upstream)", function(b)
    local remote = upstream_remote(b)
    run({ "push", "-u", remote, b.name }, "Pushed " .. b.name .. " to " .. remote)
  end },
  d = { "Delete", function(b)
    vim.ui.select({ "Delete", "Force delete (unmerged)" }, { prompt = "Delete branch " .. b.name .. "?" }, function(choice)
      if choice then
        run({ "branch", choice == "Delete" and "-d" or "-D", b.name }, "Deleted " .. b.name)
      end
    end)
  end },
  o = { "Open on remote", function(b)
    require("utils.git_host").browse { what = "branch", branch = b.name }
  end },
}

actions.remote = {
  f = { "Fetch", function(r)
    run({ "fetch", "--prune", r.name }, "Fetched " .. r.name)
  end },
  o = { "Open on remote", function()
    require("utils.git_host").browse { what = "repo" }
  end },
}

actions.remote_branch = {
  ["<CR>"] = { "Checkout (tracking)", function(r)
    for _, b in ipairs(state.data.branches or {}) do
      if b.name == r.branch then
        return run({ "switch", r.branch }, "Switched to " .. r.branch)
      end
    end
    run({ "switch", "--track", r.name }, "Switched to new branch " .. r.branch)
  end },
  c = { "Compare with HEAD", function(r)
    diffview("HEAD..." .. r.name)
  end },
  l = { "Branch history", function(r)
    vim.cmd("DiffviewFileHistory --range=" .. r.name)
  end },
  m = { "Merge into current branch", function(r)
    confirm("Merge " .. r.name .. " into the current branch?", function()
      run({ "merge", r.name }, "Merged " .. r.name)
    end)
  end },
  d = { "Delete on remote", function(r)
    confirm("Delete " .. r.branch .. " on " .. r.remote .. "?", function()
      run({ "push", r.remote, "--delete", r.branch }, "Deleted " .. r.name)
    end)
  end },
  o = { "Open on remote", function(r)
    require("utils.git_host").browse { what = "branch", branch = r.branch }
  end },
}

actions.tag = {
  ["<CR>"] = { "Checkout (detached)", function(t)
    run({ "switch", "--detach", t.name }, "Checked out " .. t.name)
  end },
  c = { "Compare with HEAD", function(t)
    diffview(t.name .. "..HEAD")
  end },
  p = { "Push tag", function(t)
    run({ "push", upstream_remote(current_branch()), t.name }, "Pushed " .. t.name)
  end },
  d = { "Delete (local)", function(t)
    confirm("Delete tag " .. t.name .. "?", function()
      run({ "tag", "-d", t.name })
    end)
  end },
}

actions.stash = {
  ["<CR>"] = { "Show changes", function(s)
    diffview(s.name .. "^!")
  end },
  a = { "Apply", function(s)
    run({ "stash", "apply", s.name }, "Applied " .. s.name)
  end },
  P = { "Pop", function(s)
    run({ "stash", "pop", s.name }, "Popped " .. s.name)
  end },
  d = { "Drop", function(s)
    confirm("Drop " .. s.name .. "?", function()
      run({ "stash", "drop", s.name })
    end)
  end },
}

actions.worktree = {
  ["<CR>"] = { "Switch to (tab-local cwd)", function(w)
    vim.cmd.tcd(vim.fn.fnameescape(w.path))
    notify("cwd → " .. w.path)
    M.refresh()
  end },
}

actions.commit = {
  ["<CR>"] = { "Show commit (this file)", function(c)
    diffview(c.sha .. "^! -- " .. vim.fn.fnameescape(c.file))
  end },
  C = { "Show commit (all files)", function(c)
    diffview(c.sha .. "^!")
  end },
  l = { "Full file history", function(c)
    vim.cmd("DiffviewFileHistory " .. vim.fn.fnameescape(c.file))
  end },
  y = { "Copy SHA", function(c)
    vim.fn.setreg("+", c.sha)
    notify("Copied " .. c.sha)
  end },
  o = { "Open commit on remote", function(c)
    require("utils.git_host").browse { what = "commit", commit = c.sha }
  end },
}

actions.section = {
  ["<CR>"] = { "Fold / unfold", function(s)
    state.folded[s.id] = not state.folded[s.id]
    M.render()
  end },
  n = { "New branch (branches)", function(s)
    if s.id == "branches" then
      input("New branch from HEAD: ", "", function(name)
        run({ "switch", "-c", name }, "Created " .. name)
      end)
    end
  end },
  f = { "Fetch all (remotes)", function(s)
    if s.id == "remotes" then
      run({ "fetch", "--all", "--prune" }, "Fetched all remotes")
    end
  end },
  s = { "Stash changes (stashes)", function(s)
    if s.id == "stashes" then
      input("Stash message: ", "", function(msg)
        run({ "stash", "push", "--include-untracked", "-m", msg }, "Stashed")
      end)
    end
  end },
}
actions.section["<Tab>"] = actions.section["<CR>"]

local function node_at_cursor()
  return state.nodes[vim.api.nvim_win_get_cursor(0)[1]]
end

local function dispatch(key)
  local node = node_at_cursor()
  local action = node and actions[node.kind] and actions[node.kind][key]
  if action then
    action[2](node)
  end
end

local function help()
  local node = node_at_cursor()
  local lines = { "Git panel keys:", "  R  refresh    ?  this help    q  hide panel" }
  if node and actions[node.kind] then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "On this " .. node.kind:gsub("_", " ") .. ":"
    for key, action in vim.spairs(actions[node.kind]) do
      lines[#lines + 1] = ("  %-5s %s"):format(key, action[1])
    end
  end
  notify(table.concat(lines, "\n"))
end

-- === Buffer / window ==========================================================

local function create_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "gitpanel"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, "gitpanel://" .. buf)

  local keys = {}
  for _, set in pairs(actions) do
    for key in pairs(set) do
      keys[key] = true
    end
  end
  for key in pairs(keys) do
    vim.keymap.set("n", key, function()
      dispatch(key)
    end, { buffer = buf, nowait = true })
  end
  vim.keymap.set("n", "R", M.refresh_now, { buffer = buf, desc = "Refresh" })
  vim.keymap.set("n", "?", help, { buffer = buf, desc = "Help" })
  vim.keymap.set("n", "q", M.close, { buffer = buf, desc = "Hide panel" })
  return buf
end

function M.is_visible()
  return state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf) and vim.fn.bufwinid(state.buf) ~= -1
end

---@param root string?
function M.open(root)
  if not root then
    return
  end
  if root ~= state.root then
    state.root = root
    state.data = {}
  end
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    state.buf = create_buf()
  end
  if not M.is_visible() then
    -- edgy picks it up by filetype and docks it under Neogit's status
    local win = vim.api.nvim_open_win(state.buf, false, { split = "left", win = -1 })
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].cursorline = true
    vim.wo[win].wrap = false
    vim.wo[win].foldcolumn = "0"
  end
  M.refresh_now()
end

function M.close()
  local win = state.buf and vim.fn.bufwinid(state.buf) or -1
  if win ~= -1 then
    pcall(vim.api.nvim_win_close, win, false)
  end
end

function M.title()
  return "GitLens · " .. (state.root and vim.fn.fnamemodify(state.root, ":t") or "")
end

-- Changed-file count for the sidebar tab badge, kept fresh even while the
-- panel is hidden (refresh_now always updates it).
function M.change_count()
  local root = state.root or vim.fs.root(vim.uv.cwd(), ".git")
  return root and state.changes[root] or 0
end

function M.file_buf()
  local buf = state.file_buf
  return buf and vim.api.nvim_buf_is_valid(buf) and buf or nil
end

-- === Wiring ===================================================================

function M.setup()
  local group = vim.api.nvim_create_augroup("GitPanel", { clear = true })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      if vim.bo[ev.buf].buftype ~= "" or vim.api.nvim_buf_get_name(ev.buf) == "" then
        return
      end
      if state.file_buf == ev.buf then
        return
      end
      state.file_buf = ev.buf
      -- File History follows the editor; switching repos re-roots the panel
      local root = require("configs.statusline").git_root(ev.buf)
      if root and root ~= state.root then
        state.root = root
        state.data = {}
      end
      M.refresh()
    end,
  })

  vim.api.nvim_create_autocmd({ "FocusGained", "DirChanged" }, {
    group = group,
    callback = function()
      M.refresh()
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "NeogitStatusRefreshed", "GitSignsUpdate", "GitAutoFetch", "GitChanged" },
    callback = function()
      M.refresh()
    end,
  })
end

return M
