-- Dependency/tooling folders: the file finder and grep never walk them, and
-- the Explorer never auto-reveals a file inside one (or outside the cwd)
local M = {}

M.dirs = {
  ".git",
  "node_modules",
  ".venv",
  "venv",
  "vendor",
  "target",
  ".dart_tool",
  "__pycache__",
  ".gradle",
  "Pods",
  ".next",
}

local skip = {}
-- rg flags: include hidden and git-ignored files, but never descend into M.dirs
M.rg_args = { "--hidden", "--no-ignore" }
for _, dir in ipairs(M.dirs) do
  skip[dir] = true
  M.rg_args[#M.rg_args + 1] = "--glob=!" .. dir
end

-- Same rules for fd, and for find (prune M.dirs, list files) and grep (skip
-- binary files and M.dirs) when rg isn't installed, as on a bare remote host
M.fd_args = { "--type=f", "--hidden", "--no-ignore", "--color=never" }
M.find_args = { ".", "(" }
M.grep_args = { "-rnIE", "--color=never" }
for i, dir in ipairs(M.dirs) do
  M.fd_args[#M.fd_args + 1] = "--exclude=" .. dir
  M.grep_args[#M.grep_args + 1] = "--exclude-dir=" .. dir
  vim.list_extend(M.find_args, i == 1 and { "-name", dir } or { "-o", "-name", dir })
end
vim.list_extend(M.find_args, { ")", "-prune", "-o", "-type", "f", "-print" })

---@param path string absolute path
function M.is_external(path)
  local rel = vim.fs.relpath(vim.uv.cwd(), path)
  if not rel then
    return true
  end
  return vim.iter(vim.split(rel, "/")):any(function(seg)
    return skip[seg]
  end)
end

return M
