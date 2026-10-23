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
