-------------------
-- KEYBINDINGS ----
-------------------

-- See https://wiki.hypr.land/Configuring/Keywords/

local vars = require("modules.variables")
local terminal = vars.programs.terminal
local fileManager = vars.programs.file_manager
local menu = vars.programs.menu
local webBrowser = vars.programs.web_browser
local codeEditor = vars.programs.code_editor
local calculator = vars.programs.calculator

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Example binds, see https://wiki.hypr.land/Configuring/Binds/ for more
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
-- hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.float())
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.center())
hl.bind(mainMod .. " + CTRL + F", hl.dsp.exec_cmd("~/.config/hypr/scripts/float_all_windows.sh"))
-- hl.bind(mainMod .. " + CTRL + F", hl.dsp.exec_cmd("hyprctl dispatch workspaceopt allfloat"))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen()) -- fullscreen
hl.bind(mainMod .. " + M", hl.dsp.window.fullscreen({ mode = "maximized" })) -- maximise
-- hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("if ! pgrep -x wofi > /dev/null; then " .. menu .. "; fi"))
hl.bind(mainMod .. " + P", hl.dsp.window.pin())
-- Toggle two adjacent windows between horizontal and vertical tiling.
-- Dwindle has a native `togglesplit`. hyprscrolling has no direct equivalent,
-- so approximate it: `promote` pulls the focused window out into its own column
-- (horizontal), while `movewindowto r` merges it into the neighbouring column
-- (vertical). A flag flips between the two on each press.
local scrollingStacked = false
hl.bind(mainMod .. " + J", function()
	if hl.get_config("general.layout") == "scrolling" then
		if scrollingStacked then
			hl.dispatch(hl.dsp.layout("promote"))
		else
			hl.dispatch(hl.dsp.layout("movewindowto r"))
		end
		scrollingStacked = not scrollingStacked
	else
		hl.dispatch(hl.dsp.layout("togglesplit"))
	end
end)
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(webBrowser))
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("noctalia msg panel-toggle control-center"))
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd(codeEditor))
hl.bind(mainMod .. " + SHIFT + Z", hl.dsp.exec_cmd("zeditor"))
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd(calculator))
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("gnome-characters"))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind(mainMod .. " + SHIFT + G", hl.dsp.exec_raw("google-chrome-stable --new-window --app=https://gemini.google.com"))
hl.bind(mainMod .. " + SHIFT + Y", hl.dsp.exec_raw("google-chrome-stable --new-window --app=https://www.youtube.com"))
hl.bind(mainMod .. " + SHIFT + A", hl.dsp.exec_cmd("antigravity"))

-- Overview plugin
hl.bind(mainMod .. " + o", function()
	vars.overview("toggle")
end)

-- Double-tap SUPER (within 400ms) to toggle the overview
local superTapPending = false
local superTapTimer
superTapTimer = hl.timer(function()
	superTapPending = false
	superTapTimer:set_enabled(false)
end, { timeout = 400, type = "repeat" })
superTapTimer:set_enabled(false)

hl.bind(mainMod .. " + SUPER_L", function()
	if superTapPending then
		superTapPending = false
		superTapTimer:set_enabled(false)
		vars.overview("toggle")
	else
		superTapPending = true
		superTapTimer:set_enabled(true)
	end
end, { release = true })

-- Move focus with mainMod + arrow keys.
-- In the scrolling layout, up/down switch workspaces (there's no vertical focus target); otherwise fall back to generic directional focus.
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", function()
	if hl.get_config("general.layout") == "scrolling" then
		hl.dispatch(hl.dsp.focus({ workspace = "e-1" }))
	else
		hl.dispatch(hl.dsp.focus({ direction = "up" }))
	end
end)
hl.bind(mainMod .. " + down", function()
	if hl.get_config("general.layout") == "scrolling" then
		hl.dispatch(hl.dsp.focus({ workspace = "e+1" }))
	else
		hl.dispatch(hl.dsp.focus({ direction = "down" }))
	end
end)

-- Swap active window with another.
-- In the scrolling layout, left/right swap the current column with its neighbor; otherwise fall back to the generic window swap.
hl.bind(mainMod .. " + ALT + left", function()
	if hl.get_config("general.layout") == "scrolling" then
		hl.dispatch(hl.dsp.layout("swapcol l"))
	else
		hl.dispatch(hl.dsp.window.swap({ direction = "left" }))
	end
end)
hl.bind(mainMod .. " + ALT + right", function()
	if hl.get_config("general.layout") == "scrolling" then
		hl.dispatch(hl.dsp.layout("swapcol r"))
	else
		hl.dispatch(hl.dsp.window.swap({ direction = "right" }))
	end
end)
hl.bind(mainMod .. " + ALT + up", hl.dsp.window.swap({ direction = "up" }))
hl.bind(mainMod .. " + ALT + down", hl.dsp.window.swap({ direction = "down" }))

-- Halve windows.
-- In the scrolling layout SUPER + SHIFT + H is modal: it waits up to 2s for a
-- direction. Left/right takes the active window plus its neighbouring column
-- to the next empty workspace ahead of the current one (a fresh workspace is
-- created when none is empty; it never wraps around) and splits them into two
-- half-width columns. Silence falls back to halving just the active window;
-- any other key cancels. Outside the scrolling layout it always halves the
-- active window immediately.
local function halveActive()
	-- The battle-tested script reads the exact size over hyprctl and resizes
	-- to half via an absolute dispatch; keep using it rather than guessing at
	-- the Lua-side representation of window sizes.
	hl.dispatch(hl.dsp.exec_cmd("~/.config/hypr/scripts/halve_active_window.sh"))
end

-- First workspace after fromId that is either empty or does not exist yet
-- (Hyprland creates it on arrival). Never wraps below fromId, unlike "e+1".
local function nextEmptyWorkspaceId(fromId)
	for id = fromId + 1, fromId + 100 do
		local ws = hl.get_workspace(tostring(id))
		if not ws or ws.windows == 0 then
			return id
		end
	end
	return fromId + 1
end

-- While waiting for a direction, the active window is dimmed by tagging it
-- and enabling a matching opacity/saturation/border rule. Toggling the rule
-- (rather than forcing property values) means the window returns to the
-- configured look as soon as the tag is gone. Hyprland has no per-window
-- brightness control, so grayscaling via saturation approximates darkness.
local halveDimRule = hl.window_rule({
	name = "halve-dim",
	match = { tag = "halving" },
	dim_around = true,
	border_color = require("noctalia").colors.secondary,
	enabled = false,
})
local halveDimTarget = nil

local function halveDim(win)
	halveDimTarget = win
	if win then
		hl.dispatch(hl.dsp.window.tag({ tag = "halving", window = win }))
		halveDimRule:set_enabled(true)
	end
end

local function halveUndim()
	local win = halveDimTarget
	halveDimTarget = nil
	if win then
		halveDimRule:set_enabled(false)
		hl.dispatch(hl.dsp.window.clear_tags({ window = win }))
	end
end

-- Move the active window and the column neighbouring it in `dir` to the next
-- empty workspace, then size both columns to half the screen.
local function halveWithNeighbour(dir)
	local active = hl.get_active_window()
	hl.dispatch(hl.dsp.focus({ direction = dir }))
	local neighbour = hl.get_active_window()
	if not active or not neighbour or neighbour.address == active.address then
		-- No neighbour in that direction: fall back to plain halving.
		halveActive()
		return
	end
	local currentWs = hl.get_active_workspace()
	local targetWs = nextEmptyWorkspaceId(currentWs and currentWs.id or 1)
	hl.dispatch(hl.dsp.window.move({ workspace = targetWs, window = active, follow = false }))
	hl.dispatch(hl.dsp.window.move({ workspace = targetWs }))
	hl.dispatch(hl.dsp.layout("colresize all 0.49"))
end

-- 2s deadline: if still armed when it fires, exit the submap and fall back to
-- halving the active window alone. A repeating timer is used because spent
-- oneshot timers cannot be revived with set_enabled(); it disables itself
-- after firing, and arming below always recycles it with a fresh countdown.
local halveArmed = false
local halveTimer
halveTimer = hl.timer(function()
	if not halveArmed then
		return
	end
	halveArmed = false
	halveTimer:set_enabled(false)
	if hl.get_current_submap() == "halve_dir" then
		hl.dispatch(hl.dsp.submap("reset"))
	end
	halveUndim()
	halveActive()
end, { timeout = 2000, type = "repeat" })
halveTimer:set_enabled(false)

hl.bind(mainMod .. " + SHIFT + H", function()
	if hl.get_config("general.layout") ~= "scrolling" then
		halveActive()
		return
	end
	halveArmed = true
	halveTimer:set_enabled(false)
	halveTimer:set_enabled(true)
	halveUndim() -- clean up any leaked tag from a previous cycle
	local win = hl.get_active_window()
	if not win then
		halveArmed = false
		halveTimer:set_enabled(false)
		return
	end
	halveDim(win)
	hl.dispatch(hl.dsp.submap("halve_dir"))
end)

-- The "reset" argument makes any bind below drop out of the submap after it
-- fires, so a single press always returns to the default keymap.
hl.define_submap("halve_dir", "reset", function()
	hl.bind("left", function()
		halveArmed = false
		halveTimer:set_enabled(false)
		halveUndim()
		halveWithNeighbour("left")
	end)
	hl.bind("right", function()
		halveArmed = false
		halveTimer:set_enabled(false)
		halveUndim()
		halveWithNeighbour("right")
	end)
	-- Any other key cancels the wait without acting.
	hl.bind("catchall", function()
		halveArmed = false
		halveTimer:set_enabled(false)
		halveUndim()
	end)
end)

-- resize acive window
hl.bind(mainMod .. " + SHIFT + left", hl.dsp.window.resize({ x = -20, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.resize({ x = 20, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + up", hl.dsp.window.resize({ x = 0, y = -20, relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + down", hl.dsp.window.resize({ x = 0, y = 20, relative = true }), { repeating = true })

-- Move active window
hl.bind(mainMod .. " + CTRL + left", hl.dsp.window.move({ x = -30, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.move({ x = 30, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + CTRL + up", hl.dsp.window.move({ x = 0, y = -30, relative = true }), { repeating = true })
hl.bind(mainMod .. " + CTRL + down", hl.dsp.window.move({ x = 0, y = 30, relative = true }), { repeating = true })

-- Cycle through windows
-- hl.bind("ALT + TAB", hl.dsp.exec_cmd("noctalia msg window-switcher"))
-- Cycle through all windows on the workspace (tiled + floating), in focus order.
hl.bind("ALT + TAB", hl.dsp.window.cycle_next({ next = false }))
hl.bind("ALT + SHIFT + TAB", hl.dsp.window.cycle_next())

-- Move window in z-axis
hl.bind(mainMod .. " + plus", hl.dsp.window.alter_zorder({ mode = "top" }))
hl.bind(mainMod .. " + minus", hl.dsp.window.alter_zorder({ mode = "bottom" }))

-- Switch between workspaces
hl.bind(mainMod .. " + TAB", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + SHIFT + TAB", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + SPACE", hl.dsp.focus({ workspace = "emptym" }))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
	local key = i % 10 -- 10 maps to key 0
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + SHIFT + SPACE", hl.dsp.window.move({ workspace = "emptynm" }))
hl.bind(mainMod .. " + SHIFT + ALT + left", hl.dsp.window.move({ workspace = "-1" }))
hl.bind(mainMod .. " + SHIFT + ALT + right", hl.dsp.window.move({ workspace = "+1" }))

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through existing workspaces with mainMod + scroll.
hl.bind(mainMod .. " + mouse_down", function()
	if hl.get_config("general.layout") == "scrolling" then
    hl.dispatch(hl.dsp.focus({ direction = "right" }))
	else
		hl.dispatch(hl.dsp.focus({ workspace = "e-1" }))
	end
end)
hl.bind(mainMod .. " + mouse_up", function()
	if hl.get_config("general.layout") == "scrolling" then
    hl.dispatch(hl.dsp.focus({ direction = "left" }))
	else
		hl.dispatch(hl.dsp.focus({ workspace = "e+1" }))
	end
end)

hl.bind(mainMod .. " + CTRL + SHIFT + left", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + CTRL + SHIFT + right", hl.dsp.focus({ workspace = "e+1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- -- Laptop multimedia keys for volume and LCD brightness
-- hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
-- hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
-- hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true, repeating = true })
-- hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, repeating = true })
-- hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 10%+"), { locked = true, repeating = true })
-- hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 10%-"), { locked = true, repeating = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("noctalia msg volume-up"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("noctalia msg volume-down"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("noctalia msg volume-mute"), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("noctalia msg mic-mute"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("noctalia msg brightness-up"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("noctalia msg brightness-down"), { locked = true, repeating = true })

hl.bind("XF86AudioNext", hl.dsp.exec_cmd("noctalia msg media next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("noctalia msg media toggle"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("noctalia msg media toggle"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("noctalia msg media previous"), { locked = true })

-- Screenshotting/recording
-- Screenshot selected area and save to Pictures, copy to clipboard, and notify
hl.bind("Print", hl.dsp.exec_cmd('grimblast copysave area && notify-send "Screenshot" "Region captured."'))
-- hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd("grimblast copysave screen && notify-send \"Screenshot\" \"Full screen captured.\""))
-- hl.bind(mainMod .. " + SHIFT + Print", hl.dsp.exec_cmd("grimblast copysave active && notify-send \"Screenshot\" \"Active window captured.\""))
-- hl.bind("XF86Launch5", hl.dsp.exec_cmd("grimblast copy area && notify-send \"Screenshot\" \"Region copied to clipboard.\""))

-- Screen recording
hl.bind(
	mainMod .. " + Print",
	hl.dsp.exec_cmd("~/.config/waybar/scripts/recorder.sh region >> ~/.config/waybar/scripts/logs/recorder.log 2>&1")
)
hl.bind(mainMod .. " + SHIFT + Print", hl.dsp.exec_cmd("~/.config/waybar/scripts/recorder.sh window"))
hl.bind(mainMod .. " + ALT + Print", hl.dsp.exec_cmd("~/.config/waybar/scripts/recorder.sh screen"))
hl.bind(mainMod .. " + CTRL + Print", hl.dsp.exec_cmd("~/.config/waybar/scripts/recorder.sh stop"))

-- Power button/Laptop lid actions. Requires acpi
hl.bind(
	"switch:Lid Switch",
	hl.dsp.exec_cmd("~/.config/hypr/scripts/laptop_switch.sh >> ~/.config/hypr/scripts/laptop_switch.log 2>&1"),
	{ locked = true }
)
hl.bind(
	"switch:on:power-button",
	hl.dsp.exec_cmd(
		"~/.config/hypr/scripts/power_button_actions.sh >> ~/.config/hypr/scripts/power_button_actions.log 2>&1"
	),
	{ locked = true }
)

hl.bind("SUPER + H", function()
	if hl.get_workspace("special:minimized") then
		hl.dispatch(hl.dsp.window.move({ workspace = hl.get_active_workspace(), window = "tag:minimized" }))
		hl.dispatch(hl.dsp.window.clear_tags({ window = "tag:minimized" }))
	else
		hl.dispatch(hl.dsp.window.tag({ tag = "minimized", window = hl.get_active_window() }))
		hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", follow = false }))
	end
end)

-- power button
-- hl.bind(
--   "XF86PowerOff",
--   hl.dsp.exec_cmd("loginctl lock-session && systemctl suspend"),
--   { locked = true }
-- )

