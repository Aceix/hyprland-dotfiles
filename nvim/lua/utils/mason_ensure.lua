-- Mason packages installed the first time they're needed (a language's first
-- file, a key's first press) rather than on every machine up front:
-- configs/mason-tool-installer.lua stays the list for the always-on set.
local M = {}

local packages = vim.fn.stdpath "data" .. "/mason/packages/"

-- With vim.g.mason_ensure_dry (tests/smoke.lua): what would have been installed
M.dry = {}

--- `pkgs`: names, or { name, needs = "binary" } for packages that can't work
--- without a toolchain (skipped with a warning when it's missing). `cb` runs
--- once everything asked for is installed; right away when it already is,
--- without loading Mason.
function M.ensure(pkgs, cb)
  cb = cb or function() end
  local missing = {}
  for _, pkg in ipairs(pkgs or {}) do
    local name = type(pkg) == "table" and pkg[1] or pkg
    local needs = type(pkg) == "table" and pkg.needs
    if not vim.uv.fs_stat(packages .. name) then
      if needs and vim.fn.executable(needs) == 0 then
        vim.notify(("Mason: skipping %s, it needs `%s`"):format(name, needs), vim.log.levels.WARN)
      else
        missing[#missing + 1] = name
      end
    end
  end
  if #missing == 0 then
    return cb()
  end
  if vim.g.mason_ensure_dry then
    vim.list_extend(M.dry, missing)
    return
  end

  local registry = require "mason-registry"
  registry.refresh(function()
    vim.notify("Mason: installing " .. table.concat(missing, ", "))
    local left = #missing
    local function done()
      left = left - 1
      if left == 0 then
        vim.schedule(cb)
      end
    end
    for _, name in ipairs(missing) do
      local ok, pkg = pcall(registry.get_package, name)
      if not ok then
        vim.notify("Mason: no package named " .. name, vim.log.levels.WARN)
        done()
      elseif pkg:is_installing() then
        pkg:once("install:success", done)
        pkg:once("install:failed", done)
      else
        pkg:install({}, function(success, err)
          if not success then
            vim.notify(("Mason: %s failed to install: %s"):format(name, tostring(err)), vim.log.levels.WARN)
          end
          done()
        end)
      end
    end
  end)
end

return M
