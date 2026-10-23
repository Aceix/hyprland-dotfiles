-- Lua equivalent of hyprland.conf
-- Refer to the wiki for more information.
-- https://wiki.hypr.land/Configuring/

-- Please note not all available settings / options are set here.
-- For a full list, see the wiki

-- Split into functionality-grouped modules under ./modules. require() paths
-- resolve relative to this file, dot-separated, with the .lua extension omitted.
-- `local`s don't cross file boundaries, so anything shared between modules
-- (monitor names, program commands) lives in modules/variables.lua.

require("modules.monitors")
require("modules.debug")
require("modules.autostart")
require("modules.environment")
require("modules.permissions")
require("modules.appearance")
require("modules.input")
require("modules.plugins")
require("modules.keybindings")
require("modules.window-rules")
require("modules.workspace-rules")
require("modules.layers")


-- For Noctalia Color templates
require("noctalia").apply_theme()

-- Added by hyprmoncfg: its generated monitor rules load last, so nothing before this can override the applied layout.
do local path = os.getenv("HOME") .. "/.config/hypr/hyprmoncfg-monitors.lua"; local file = io.open(path, "r"); if file then file:close(); dofile(path) end end
