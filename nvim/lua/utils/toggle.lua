-- On/off switches under <leader>u, one row each (the list is in mappings.lua):
--   { key, name, get = fn() -> bool, set = fn(bool), persist = bool, default = bool }
-- Snacks.toggle supplies the keymap, its which-key label and icon, and the
-- notification. `persist` rows are remembered across restarts (and need
-- `default`: the state the feature is in when nothing was saved).
--
-- which-key calls `get` each time <leader>u opens, and saved states are
-- re-applied at startup: neither may require() a lazy-loaded plugin. Read a
-- vim.g flag or check package.loaded instead.
local M = {}

local path = vim.fn.stdpath "state" .. "/toggles.json"
local saved

local function load()
  if not saved then
    local f = io.open(path)
    local ok, data = pcall(vim.json.decode, f and f:read "*a" or "")
    if f then
      f:close()
    end
    saved = ok and type(data) == "table" and data or {}
  end
  return saved
end

local function save()
  local f = io.open(path, "w")
  if f then
    f:write(vim.json.encode(saved))
    f:close()
  end
end

function M.setup(rows)
  for _, row in ipairs(rows) do
    local key, name = row[1], row[2]
    local id = vim.trim(name:lower():gsub("%W+", " ")):gsub(" ", "_")
    local set = row.set
    if row.persist then
      set = function(on)
        row.set(on)
        load()[id] = on
        save()
      end
      local state = load()[id]
      if state ~= nil and state ~= row.default then
        row.set(state)
      end
    end
    Snacks.toggle.new({ id = id, name = name, get = row.get, set = set }):map("<leader>u" .. key)
  end
end

--- Row for a boolean vim.g flag that plugins read when they act
function M.flag(key, name, var, default)
  return {
    key,
    name,
    persist = true,
    default = default,
    get = function()
      local v = vim.g[var]
      if v == nil then
        return default
      end
      return v
    end,
    set = function(on)
      vim.g[var] = on
    end,
  }
end

return M
