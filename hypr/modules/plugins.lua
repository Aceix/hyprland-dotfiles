---------------
-- PLUGINS ----
---------------

--- Apply a `plugin:<namespace>:...` config block.
--- These keys only exist once the plugin itself is loaded, and hyprpm loads ours
--- from the autostart block above -- so on the very first parse of this file
--- hl.config would report every one of them as an unknown config key. Hyprland
--- re-parses the config whenever a plugin loads, so the values land on that pass.
local function plugin_config(namespace, values)
	local probe, node = "plugin." .. namespace, values

	while type(node) == "table" do
		local key, value = next(node)
		if key == nil then
			return
		end
		probe, node = probe .. "." .. key, value
	end

	if hl.get_config(probe) ~= nil then
		hl.config({ plugin = { [namespace] = values } })
	end
end

plugin_config("hyprmodoro", {
	work_duration = 60,
	rest_duration = 5,

	title = {
		enabled = true,
		floating_window = true,
	},

	border = {
		enabled = true,
		floating_window = true,
		color = "rgba(255, 0, 255, .7)",
	},

	text = {
		size = 8,
	},

	hover = {
		-- text = true,
		height = 5,
		width = 10,
		buttons = true,
	},

	notification = {
		enabled = true,
		use_system_notifications = true,
		work_end = "Hyprmodoro: Work session complete",
		rest_end = "Hyprmodoro: Break over",
	},
})

-- Note: `dynamic-cursors` becomes `dynamic_cursors` here -- Hyprland maps `-` to
-- `_` when it exposes plugin options to Lua.
plugin_config("dynamic_cursors", {
	enabled = true,
	mode = "none",

	-- magnifies the cursor if its is being shaken
	shake = {
		-- enables shake to find
		enabled = true,

		-- show cursor behaviour `tilt`, `rotate`, etc. while shaking
		effects = false,

		-- controls how soon a shake is detected
		-- lower values mean sooner
		threshold = 6.0,

		-- magnification level immediately after shake start
		base = 2.0,

		-- magnification increase per second when continuing to shake
		speed = 4.0,

		-- how much the speed is influenced by the current shake intensitiy
		influence = 0.0,

		-- maximal magnification the cursor can reach
		-- values below 1 disable the limit (e.g. 0)
		limit = 0.0,

		-- time in millseconds the cursor will stay magnified after a shake has ended
		timeout = 1000,

		-- enable ipc events for shake
		ipc = false,
	},
})

plugin_config("hyprbars", {
	-- example config
	bar_height = 20,
})

-- example buttons (R -> L). The `hyprbars-button` keyword has no Lua equivalent;
-- hyprbars exposes `add_button` instead, and it requires an explicit fg_color.
if hl.plugin.hyprbars then
	hl.plugin.hyprbars.add_button({
		bg_color = "rgb(ff4040)",
		fg_color = "rgb(ffffff)",
		size = 10,
		icon = "󰖭",
		action = "hyprctl dispatch killactive",
	})
	hl.plugin.hyprbars.add_button({
		bg_color = "rgb(eeee11)",
		fg_color = "rgb(ffffff)",
		size = 10,
		icon = "",
		action = "hyprctl dispatch fullscreen 1",
	})
end

plugin_config("overview", {
	-- --- Layout & Positioning ---
	onBottom = true,
	panelHeight = 150, -- Thinner workspace bar at the bottom
	panelBorderWidth = 0, -- Completely removes the panel border
	workspaceBorderSize = 0, -- No visible borders around individual workspaces
	workspaceMargin = 10, -- Small spacing between workspace items

	-- --- Minimalist Color Theme (HEXA formats) ---
	-- Deep dark/translucent background for a clean overlay look
	panelColor = "rgba(15, 15, 15, 0.75)",

	-- Inactive workspaces blur out or subtly blend into the panel
	workspaceBg = "rgba(30, 30, 30, 0.4)",

	-- Active workspace is highlighted subtly without flashy accents
	workspaceActiveBg = "rgba(45, 45, 45, 0.8)",
	workspaceActiveBorderColor = "rgba(255, 255, 255, 0.0)", -- Set to 0.0 transparency to hide completely

	-- --- Visual Cleanliness ---
	drawActiveWorkspace = true, -- Keeps context of where you currently are
	showEmptyWorkspace = false, -- Hide workspaces that have no active windows
	showNewWorkspace = false, -- Hide the generic "+" workspace slot for a cleaner grid
	hideRealLayers = true, -- Clean look by hiding background wallpaper/bars during overview

	-- --- Behavior ---
	exitOnClick = true, -- Instantly drop back to the desktop when a workspace is clicked
	exitOnSwitch = true, -- Auto-close the overview interface when switching workspaces
})

plugin_config("scrolloverview", {
	gesture_distance = 300, -- how far is the "max" for the gesture
	scale = 0.5, -- preferred overview scale
	workspace_gap = 100,
	layout = "vertical", -- vertical or horizontal
	wallpaper = 0, -- 0: global only, 1: per-workspace only, 2: both
	blur = false, -- blur only the main overview wallpaper

	shadow = {
		enabled = false,
		range = 50,
		render_power = 3,
		color = "rgba(1a1a1aee)",
	},
})
