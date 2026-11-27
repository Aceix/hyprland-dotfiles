-- Runs before init.lua (--cmd): see tests/smoke.sh
_G.Smoke = { notes = {} }

-- Warnings and errors raised during startup. Plugins that take over
-- vim.notify later (fidget) wrap this one, so it keeps collecting.
local notify = vim.notify
vim.notify = function(msg, level, opts)
  if (level or vim.log.levels.INFO) >= vim.log.levels.WARN then
    Smoke.notes[#Smoke.notes + 1] = tostring(msg)
  end
  return notify(msg, level, opts)
end

-- No UI attaches in headless mode; NvChad waits for one before firing the
-- `User FilePost` event that LSP, gitsigns, ... load on
vim.g.ui_entered = true

-- utils/mason_ensure.lua records what it would install instead of installing
vim.g.mason_ensure_dry = true
