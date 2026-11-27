-- Next-edit suggestions from Copilot: after a change, the edit it predicts
-- next (anywhere in the file) is shown as a diff; <Tab> jumps to it, <Tab>
-- again applies it (plugins/blink.lua, mappings.lua). <leader>uN toggles.
-- The Copilot language server itself is enabled in configs/lspconfig.lua,
-- which also draws the as-you-type ghost text. Only the suggestions are used
-- here; the CLI side is plugins/claudecode.lua.
return {
  "folke/sidekick.nvim",
  event = "User FilePost",
  opts = {
    cli = { mux = { enabled = false } },
  },
}
