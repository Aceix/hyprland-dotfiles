-- Project interpreter lookup shared by the Python LSP (configs/lspconfig.lua),
-- the debugger (configs/dap.lua) and the test runner (configs/neotest.lua), so
-- all three agree on the venv without it having to be activated first.
local M = {}

---@param root? string project directory, defaults to the cwd
---@return string
function M.path(root)
  root = root or vim.fn.getcwd()
  local candidates = {
    vim.env.VIRTUAL_ENV and (vim.env.VIRTUAL_ENV .. "/bin/python"),
    root .. "/.venv/bin/python",
    root .. "/venv/bin/python",
  }
  for _, path in pairs(candidates) do
    if vim.fn.executable(path) == 1 then
      return path
    end
  end
  return vim.fn.exepath "python3"
end

return M
