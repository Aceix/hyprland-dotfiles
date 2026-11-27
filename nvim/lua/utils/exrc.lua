-- Project-local config. 'exrc' (options.lua) reads a trusted `.nvim.lua` from
-- the directory Neovim starts in; this does the same when the project changes
-- mid-session (<C-o>, a restored session). Untrusted files prompt once, as at
-- startup (:trust).
local M = {}

local seen = { [vim.fn.getcwd()] = true } -- startup's is 'exrc''s

function M.setup()
  vim.api.nvim_create_autocmd("DirChanged", {
    group = vim.api.nvim_create_augroup("ProjectExrc", { clear = true }),
    pattern = "global",
    callback = function()
      local cwd = vim.fn.getcwd()
      local path = cwd .. "/.nvim.lua"
      if seen[cwd] or not vim.uv.fs_stat(path) then
        return
      end
      seen[cwd] = true
      local code = vim.secure.read(path)
      if type(code) ~= "string" then
        return
      end
      local chunk, err = load(code, "@" .. path)
      local ok, run_err = pcall(chunk or error, err)
      if not ok then
        vim.notify(("%s: %s"):format(path, run_err), vim.log.levels.ERROR)
      end
    end,
  })
end

return M
