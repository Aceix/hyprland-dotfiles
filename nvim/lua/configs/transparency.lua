local M = {}

-- Terminal background opacity used for the transparent look. Restored to 1.0
-- (fully opaque) when Neovim leaves or the user toggles to opaque.
local terminal_opacity = 0.85
M.terminal_opacity = terminal_opacity
M.kitty_opacity = terminal_opacity -- old name, kept for callers

-- Ghostty (Linux) has no per-window remote control. Instead the config
-- includes ~/.config/ghostty/overrides/opacity last (`config-file =
-- ?overrides/opacity`); we rewrite that file and ask the running Ghostty to
-- reload over D-Bus. Ghostty is single-instance, so this changes every
-- Ghostty window, not just the one running Neovim.
local ghostty_override = (vim.env.XDG_CONFIG_HOME or vim.fn.expand "~/.config") .. "/ghostty/overrides/opacity"

--- Which terminal is drawing this window: "kitty", "ghostty" or nil.
--- Decided by TERM (set fresh by every terminal) before TERM_PROGRAM /
--- KITTY_LISTEN_ON, which are inherited when one terminal is launched from
--- inside the other (e.g. `ghostty -e nvim` typed in a kitty shell).
function M.terminal()
  local term = vim.env.TERM or ""
  if term:find("ghostty", 1, true) or (vim.env.TERM_PROGRAM == "ghostty" and not term:find("kitty", 1, true)) then
    return "ghostty"
  end
  if vim.env.KITTY_LISTEN_ON and (term:find("kitty", 1, true) or vim.env.TERM_PROGRAM ~= "ghostty") then
    return "kitty"
  end
  return nil
end

--- True when Neovim runs in a terminal whose background opacity we can drive.
function M.supported()
  local t = M.terminal()
  return t == "kitty" or (t == "ghostty" and vim.fn.has "linux" == 1 and vim.fn.executable "gdbus" == 1)
end

--- Lower/raise the ambient terminal's background opacity, so Neovim's own
--- transparency actually shows the wallpaper instead of the terminal's solid
--- background. No-op outside a socket-enabled kitty or a Linux Ghostty window.
function M.set_terminal_opacity(value)
  local t = M.terminal()
  if t == "kitty" then
    -- async + detached: a blocking system() here cost ~30 ms on VimEnter and
    -- VimLeave, and detach lets the VimLeave call outlive Neovim
    local socket = vim.env.KITTY_LISTEN_ON
    vim.system({ "kitty", "@", "--to=" .. socket, "set-background-opacity", tostring(value) }, { detach = true })
  elseif t == "ghostty" and vim.fn.has "linux" == 1 then
    vim.fn.mkdir(vim.fn.fnamemodify(ghostty_override, ":h"), "p")
    local ok = pcall(vim.fn.writefile, { ("background-opacity = %.2f"):format(value) }, ghostty_override)
    if ok and vim.fn.executable "gdbus" == 1 then
      vim.system({
        "gdbus", "call", "--session",
        "--dest", "com.mitchellh.ghostty",
        "--object-path", "/com/mitchellh/ghostty",
        "--method", "org.gtk.Actions.Activate", "reload-config", "[]", "{}",
      }, { detach = true })
    end
  end
end
M.set_kitty_opacity = M.set_terminal_opacity -- old name, kept for callers

--- Flip between transparent and fully opaque, for the current session only.
--- Toggles base46's highlight transparency in memory (chadrc.lua is left
--- alone, so Neovim keeps opening transparent) and syncs the terminal's
--- background opacity to match.
function M.toggle()
  local nvconfig = require "nvconfig"
  local transparent = not nvconfig.base46.transparency

  nvconfig.base46.transparency = transparent
  require("base46").load_all_highlights()

  M.set_terminal_opacity(transparent and terminal_opacity or 1.0)
end

return M
