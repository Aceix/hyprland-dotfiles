-- Disabled: not currently enabled alongside codecompanion.lua. Kept for reference.
return {}

-- {
--   "ravitemer/codecompanion-history.nvim",
--   dependencies = { "olimorris/codecompanion.nvim" },
--   event = "VeryLazy",
--   config = function()
--     -- This function safe-guards initialization until lazy finishes cloning the repository
--     local status, history = pcall(require, "codecompanion-history")
--     if not status then return end
--
--     history.setup({
--       auto_save = true,
--       dir_to_save = vim.fn.stdpath("data") .. "/codecompanion-history",
--       continue_last_chat = true,
--     })
--   end,
-- },
