-- Local history: every save is snapshotted into a private git repo, off the
-- main loop. file-history.nvim (plugins/file-history.lua) browses the same
-- repo -- its own save hook runs three blocking git commands per write, so
-- this replaces it and the plugin only loads when the history is opened.
-- Secrets, temp files and big files stay out.
local M = {}

M.dir = vim.fn.stdpath "data" .. "/file-history"

local queue, busy = {}, false

local function git(args, on_exit)
  local cmd = { "git", "--work-tree", M.dir, "--git-dir", M.dir .. "/.git" }
  vim.system(vim.list_extend(cmd, args), { text = true }, on_exit)
end

local function init()
  if vim.uv.fs_stat(M.dir .. "/.git") then
    return
  end
  vim.fn.mkdir(M.dir, "p")
  for _, args in ipairs {
    { "init", "-q" },
    { "config", "--local", "user.email", "file-history@noemail.com" },
    { "config", "--local", "user.name", "file-history" },
    { "config", "--local", "commit.gpgSign", "false" },
  } do
    vim.system(vim.list_extend({ "git", "-C", M.dir }, args)):wait()
  end
end

-- One snapshot at a time: concurrent commits fight over git's index lock
local function drain()
  local path = table.remove(queue, 1)
  if not path then
    busy = false
    return
  end
  busy = true
  -- file-history.nvim's layout: <repo>/<hostname>/<absolute path>, commit
  -- message = the path
  local copy = M.dir .. "/" .. vim.fn.hostname() .. path
  vim.fn.mkdir(vim.fs.dirname(copy), "p")
  local next = vim.schedule_wrap(drain)
  vim.uv.fs_copyfile(path, copy, function(err)
    if err then
      return next()
    end
    git({ "add", copy }, function()
      -- exits 1 when the file didn't change, which is fine
      git({ "commit", "-q", "-m", path, "--", copy }, next)
    end)
  end)
end

local function skip(buf, path)
  return vim.bo[buf].buftype ~= ""
    or vim.b[buf].bigfile
    or path == ""
    or require("utils.sensitive").is(path)
    or require("utils.sensitive").is_temp(path)
end

function M.setup()
  if vim.fn.executable "git" == 0 then
    return
  end
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("LocalHistory", { clear = true }),
    callback = function(ev)
      local path = vim.api.nvim_buf_get_name(ev.buf)
      if skip(ev.buf, path) then
        return
      end
      init()
      queue[#queue + 1] = path
      if not busy then
        drain()
      end
    end,
  })
end

return M
