local M = {}

-- Kitty background opacity used for the transparent look. Restored to 1.0
-- (fully opaque) when Neovim leaves or the user toggles to opaque.
local kitty_opacity = 0.85
M.kitty_opacity = kitty_opacity

--- Lower/raise the ambient terminal's background opacity, so Neovim's own
--- transparency actually shows the wallpaper instead of Kitty's solid
--- background. No-op outside a socket-enabled Kitty window.
function M.set_kitty_opacity(value)
  local socket = vim.env.KITTY_LISTEN_ON
  if socket then
    -- async + detached: a blocking system() here cost ~30 ms on VimEnter and
    -- VimLeave, and detach lets the VimLeave call outlive Neovim
    vim.system({ "kitty", "@", "--to=" .. socket, "set-background-opacity", tostring(value) }, { detach = true })
  end
end

--- Flip between transparent and fully opaque, for the current session only.
--- Toggles base46's highlight transparency in memory (chadrc.lua is left
--- alone, so Neovim keeps opening transparent) and syncs Kitty's background
--- opacity to match.
function M.toggle()
  local nvconfig = require "nvconfig"
  local transparent = not nvconfig.base46.transparency

  nvconfig.base46.transparency = transparent
  require("base46").load_all_highlights()

  M.set_kitty_opacity(transparent and kitty_opacity or 1.0)
end

return M
