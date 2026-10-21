-- One front door for "the remote side" of git, whatever hosts the repo:
-- open/copy links (snacks.gitbrowse, works for GitHub, GitLab and Bitbucket)
-- and Pull Requests / Issues, routed to octo.nvim (GitHub, needs gh),
-- gitlab.nvim (GitLab, needs go + a token) or the host's web UI otherwise.
--
-- In a remote-nvim session there's no browser on that host, so URLs are
-- copied (and shown) instead of opened.

local M = {}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Git" })
end

-- snacks only knows github.com / gitlab.com / bitbucket.org by name; these
-- also cover self-hosted GitLab, GitHub Enterprise and Bitbucket hosts.
-- (Bitbucket line anchors are #lines-A:B; snacks' built-in one is off.)
local url_patterns = {
  ["github"] = {
    branch = "/tree/{branch}",
    file = "/blob/{branch}/{file}#L{line_start}-L{line_end}",
    permalink = "/blob/{commit}/{file}#L{line_start}-L{line_end}",
    commit = "/commit/{commit}",
  },
  ["gitlab"] = {
    branch = "/-/tree/{branch}",
    file = "/-/blob/{branch}/{file}#L{line_start}-{line_end}",
    permalink = "/-/blob/{commit}/{file}#L{line_start}-{line_end}",
    commit = "/-/commit/{commit}",
  },
  ["bitbucket"] = {
    branch = "/src/{branch}",
    file = "/src/{branch}/{file}#lines-{line_start}:{line_end}",
    permalink = "/src/{commit}/{file}#lines-{line_start}:{line_end}",
    commit = "/commits/{commit}",
  },
}
url_patterns["bitbucket%.org"] = url_patterns.bitbucket

-- Per-host paths for the Pull Requests / Issues fallbacks
local web = {
  github = { prs = "/pulls", issues = "/issues", new_pr = "/compare/%s?expand=1" },
  gitlab = { prs = "/-/merge_requests", issues = "/-/issues", new_pr = "/-/merge_requests/new?merge_request[source_branch]=%s" },
  bitbucket = { prs = "/pull-requests", issues = "/issues", new_pr = "/pull-requests/new?source=%s" },
}

local function root()
  return require("utils.git_sidebar").root()
end

local function git_out(args)
  local cmd = { "git", "-C", root() or vim.uv.cwd() }
  vim.list_extend(cmd, args)
  local out = vim.system(cmd, { text = true }):wait()
  return out.code == 0 and vim.trim(out.stdout or "") or nil
end

-- The repo's web URL from its push/fetch remote (origin, else the first one)
function M.repo_url()
  local remote = git_out { "remote", "get-url", "origin" }
  if not remote then
    local first = (git_out { "remote" } or ""):match "^(%S+)"
    remote = first and git_out { "remote", "get-url", first }
  end
  return remote and require("snacks.gitbrowse").get_repo(remote) or nil
end

---@return "github"|"gitlab"|"bitbucket"|"other", string? url
function M.kind()
  local url = M.repo_url()
  local host = url and url:match "^https?://([^/]+)" or ""
  for _, kind in ipairs { "github", "gitlab", "bitbucket" } do
    if host:find(kind, 1, true) then
      return kind, url
    end
  end
  return "other", url
end

function M.open_url(url, copy)
  if copy or require("utils.remote").is_remote then
    pcall(vim.fn.setreg, "+", url)
    notify("Copied: " .. url)
  else
    vim.ui.open(url)
  end
end

-- snacks.gitbrowse with our patterns and opener. opts.what: "file" (default,
-- or the selected line range in visual mode), "permalink", "branch",
-- "commit", "repo". opts.copy: copy instead of open.
function M.browse(opts)
  opts = vim.deepcopy(opts or {}) -- keymaps share one opts table
  local copy = opts.copy
  opts.copy = nil
  require("snacks.gitbrowse").open(vim.tbl_extend("force", {
    what = "file",
    notify = false,
    url_patterns = url_patterns,
    open = function(url)
      M.open_url(url, copy)
    end,
  }, opts))
end

local function token_for_gitlab()
  return vim.env.GITLAB_TOKEN or vim.uv.fs_stat((root() or ".") .. "/.gitlab.nvim")
end

local function web_fallback(page)
  local kind, url = M.kind()
  if not url then
    return notify("No git remote configured", vim.log.levels.WARN)
  end
  local paths = web[kind]
  if not paths then
    return M.open_url(url)
  end
  if page == "new_pr" then
    local branch = git_out { "rev-parse", "--abbrev-ref", "HEAD" } or ""
    M.open_url(url .. paths.new_pr:format(branch))
  else
    M.open_url(url .. paths[page])
  end
end

-- VS Code's Sync Changes button: pull (rebase, autostash), then push
function M.sync()
  local cwd = root()
  if not cwd then
    return notify("Not inside a git repository", vim.log.levels.WARN)
  end
  local env = { GIT_TERMINAL_PROMPT = "0" }
  local function after(step, out, next_step)
    vim.schedule(function()
      if out.code ~= 0 then
        notify(step .. " failed:\n" .. vim.trim(out.stderr ~= "" and out.stderr or out.stdout or ""), vim.log.levels.ERROR)
      elseif next_step then
        next_step()
      else
        notify "Synced with remote"
        require("configs.statusline").refresh_upstream()
        vim.api.nvim_exec_autocmds("User", { pattern = "GitAutoFetch", modeline = false })
      end
    end)
  end

  notify "Syncing…"
  vim.system({ "git", "pull", "--rebase", "--autostash" }, { cwd = cwd, text = true, env = env }, function(pull)
    after("Pull", pull, function()
      vim.system({ "git", "push" }, { cwd = cwd, text = true, env = env }, function(push)
        after("Push", push)
      end)
    end)
  end)
end

-- Hosts with an in-editor UI: GitHub through octo.nvim (needs gh), GitLab
-- through gitlab.nvim (needs go and a token)
local function octo(kind)
  return kind == "github" and vim.fn.executable "gh" == 1
end

local function gitlab_nvim(kind)
  return kind == "gitlab" and vim.fn.executable "go" == 1 and token_for_gitlab()
end

-- VS Code's "Pull Requests" view, per host
function M.pull_requests()
  local kind = M.kind()
  if octo(kind) then
    vim.cmd "Octo pr list"
  elseif gitlab_nvim(kind) then
    require("gitlab").choose_merge_request()
  else
    web_fallback "prs"
  end
end

function M.issues()
  local kind = M.kind()
  if octo(kind) then
    vim.cmd "Octo issue list"
  else
    web_fallback "issues"
  end
end

function M.create_pr()
  local kind = M.kind()
  if octo(kind) then
    vim.cmd "Octo pr create"
  elseif gitlab_nvim(kind) then
    require("gitlab").create_mr()
  else
    web_fallback "new_pr"
  end
end

-- Review the PR/MR for the current branch (GitHub: checked-out PR; GitLab:
-- the branch's MR). Falls back to the PR list.
function M.review()
  local kind = M.kind()
  if octo(kind) then
    vim.cmd "Octo review"
  elseif gitlab_nvim(kind) then
    require("gitlab").review()
  else
    web_fallback "prs"
  end
end

return M
