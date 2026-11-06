-- The current block drawn as an outline (╭─ │ ╰─>) or a plain guide line,
-- see plugins/snacks.lua. <leader>ub switches, for this session.
local M = {}

function M.toggle()
  local chunk = require("snacks").config.indent.chunk
  chunk.enabled = not chunk.enabled
  -- snacks.indent reads its config when enabled
  local indent = require "snacks.indent"
  indent.disable()
  indent.enable()
  vim.notify("Block outline " .. (chunk.enabled and "on" or "off"), vim.log.levels.INFO)
end

return M
