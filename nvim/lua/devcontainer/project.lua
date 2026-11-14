-- The devcontainer project around a folder: its root, its configs (VS Code's
-- default, single-file and named `.devcontainer/<name>/` variants), the
-- DevPod workspace id for each, and reading a config (JSON with comments).
-- No requires at load time: the statusline calls root() on every redraw.
local M = {}

-- dir -> root, or false when there's none. Cleared by M.forget() whenever a
-- config is added or removed.
local roots = {}

function M.forget()
  roots = {}
end

-- `.devcontainer/devcontainer.json` wins over `.devcontainer.json`, as in
-- the spec; named configs are listed after it.
function M.configs(root)
  local out = {}
  local function add(rel, name)
    if vim.uv.fs_stat(root .. "/" .. rel) then
      out[#out + 1] = { name = name, rel = rel, path = root .. "/" .. rel }
      return true
    end
  end
  if not add(".devcontainer/devcontainer.json") then
    add ".devcontainer.json"
  end
  for name, kind in vim.fs.dir(root .. "/.devcontainer") do
    if kind == "directory" then
      add((".devcontainer/%s/devcontainer.json"):format(name), name)
    end
  end
  return out
end

-- The devcontainer project folder `dir` (default: cwd) is in, or nil. A
-- `.devcontainer` in $HOME would claim every folder under it, so it's skipped.
function M.root(dir)
  dir = dir or vim.uv.cwd()
  if roots[dir] == nil then
    local root = vim.fs.root(dir, { ".devcontainer", ".devcontainer.json" })
    roots[dir] = root and root ~= vim.uv.os_homedir() and #M.configs(root) > 0 and root or false
  end
  return roots[dir] or nil
end

-- What remote-nvim's DevPod provider makes of an id: lowercase, runs of
-- other characters as "-", at most 48 long, no trailing "-". Kept identical
-- so ids worked out here match the sessions' and saved workspaces'.
local function sanitize(id)
  id = id:lower():gsub("[^a-z0-9]+", "-"):sub(1, 48)
  return (id:gsub("%-$", ""))
end

-- The DevPod workspace id for `cfg` in `root`. The default config keeps
-- remote-nvim's id (existing workspaces stay), named ones get "-<name>" so
-- each config has its own container, as in VS Code.
function M.id(root, cfg)
  local base = require("remote-nvim.providers.devpod.devpod_utils").get_devcontainer_unique_host(root)
  if cfg and cfg.name then
    base = base:sub(-math.max(1, 47 - #cfg.name)) .. "-" .. cfg.name
  end
  return sanitize(base)
end

-- Comments out of JSONC (strings kept intact, so "https://..." survives) and
-- trailing commas, which vim.json.decode rejects
function M.strip(text)
  local out, i, n = {}, 1, #text
  while i <= n do
    local c, two = text:sub(i, i), text:sub(i, i + 1)
    if c == '"' then
      local j = i + 1
      while j <= n and text:sub(j, j) ~= '"' do
        j = j + (text:sub(j, j) == "\\" and 2 or 1)
      end
      out[#out + 1] = text:sub(i, j)
      i = j + 1
    elseif two == "//" then
      i = (text:find("\n", i, true) or n + 1)
    elseif two == "/*" then
      i = (select(2, text:find("*/", i + 2, true)) or n) + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return (table.concat(out):gsub(",(%s*[}%]])", "%1"))
end

function M.decode(text)
  local ok, value = pcall(vim.json.decode, M.strip(text), { luanil = { object = true, array = true } })
  if ok and type(value) == "table" then
    return value
  end
  return nil, ok and "not a JSON object" or value
end

-- A config file as a table, or nil, err
function M.read(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, lines
  end
  return M.decode(table.concat(lines, "\n"))
end

-- { root, configs } for `dir`, or nil
function M.current(dir)
  local root = M.root(dir)
  return root and { root = root, configs = M.configs(root) } or nil
end

return M
