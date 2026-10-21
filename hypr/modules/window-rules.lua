---------------------
-- WINDOWS RULES ----
---------------------

-- See https://wiki.hypr.land/Configuring/Window-Rules/ for more
-- See https://wiki.hypr.land/Configuring/Workspace-Rules/ for workspace rules

-- Example windowrule
-- hl.window_rule({ name = "float-kitty", match = { class = "^(kitty)$", title = "^(kitty)$" }, float = true })

-- Ignore maximize requests from apps. You'll probably like this.
-- Persist all floating window sizes across relaunches.
hl.window_rule({
	name = "windowrule-1",
	match = {
		class = ".*",
	},
	suppress_event = "maximize",
	persistent_size = true,
})

-- Fix some dragging issues with XWayland
hl.window_rule({
	name = "windowrule-2",
	match = {
		class = "^$",
		title = "^$",
		xwayland = true,
		float = true,
		fullscreen = false,
		pin = false,
	},
	no_focus = true,
})

hl.window_rule({
	name = "windowrule-3",
	match = {
		class = "^(org.gnome.Calculator)$",
	},
	float = true,
})

-- Keep the browser PiP window floating, and pinned so it renders above
-- everything on the workspace, including fullscreen windows.
hl.window_rule({
	name = "float-picture-in-picture",
	match = {
		title = "[Pp]icture[ -][Ii]n[ -][Pp]icture",
	},
	float = true,
	pin = true,
	move = { "30", "50" },
})

hl.window_rule({
	name = "windowrule-4",
	match = {
		class = "^(kitty)$",
		title = "^SystemUpdater$",
	},
	float = true,
})

hl.window_rule({
	name = "windowrule-5",
	match = {
		class = "^org.gnome.Characters$",
	},
	float = true,
	size = { 570, 390 },
	move = { "(cursor_x+(16))", "(cursor_y+(16))" },
})

-- Float all modal dialogs and file selectors
hl.window_rule({
	name = "windowrule-6",
	match = {
		modal = true,
	},
	float = true,
	stay_focused = true,
})

hl.window_rule({
	name = "windowrule-7",
	match = {
		title = "^(Open File)$",
	},
	float = true,
	center = true,
})

hl.window_rule({
	name = "windowrule-8",
	match = {
		title = "^(Save File)$",
	},
	float = true,
	center = true,
})

hl.window_rule({
	name = "windowrule-9",
	match = {
		title = "^(Open Folder)$",
	},
	float = true,
})

hl.window_rule({
	name = "windowrule-10",
	match = {
		title = "^(Save As)$",
	},
	float = true,
	center = true,
})

hl.window_rule({
	name = "windowrule-11",
	match = {
		title = "^(Select a File)$",
	},
	float = true,
})

hl.window_rule({
	name = "windowrule-12",
	match = {
		title = "^(Select a Folder)$",
	},
	float = true,
})

hl.window_rule({
	name = "windowrule-13",
	match = {
		title = "^(Choose)$",
	},
	float = true,
})

hl.window_rule({
	name = "windowrule-14",
	match = {
		class = "^(xdg-desktop-portal)$",
	},
	float = true,
	center = true,
})

hl.window_rule({
	name = "windowrule-15",
	match = {
		class = "^(xdg-desktop-portal-gtk)$",
	},
	float = true,
	center = true,
})

hl.window_rule({
	name = "windowrule-16",
	match = {
		class = "^(xdg-desktop-portal-gnome)$",
	},
	float = true,
})

hl.window_rule({
	name = "windowrule-17",
	match = {
		class = "^(xdg-desktop-portal-kde)$",
	},
	float = true,
})

hl.window_rule({
	name = "windowrule-18",
	match = {
		class = "^(\\.xdg-desktop-portal-gtk)$",
	},
	float = true,
})

hl.window_rule({
	name = "windowrule-19",
	match = {
		class = "^(file-roller)$",
	},
	float = true,
})

hl.window_rule({
	name = "windowrule-20",
	match = {
		class = "^(file_progress)$",
	},
	float = true,
})

hl.window_rule({
	name = "windowrule-21",
	match = {
		class = "^(confirm)$",
	},
	float = true,
})

hl.window_rule({
	name = "windowrule-22",
	match = {
		class = "^(dialog)$",
	},
	float = true,
	stay_focused = true,
	center = true,
})

hl.window_rule({
	name = "windowrule-23",
	match = {
		class = "^(download)$",
	},
	float = true,
})

hl.window_rule({
	name = "windowrule-24",
	match = {
		class = "^(notification)$",
	},
	float = true,
})

hl.window_rule({
	name = "windowrule-25",
	match = {
		class = "^(error)$",
	},
	float = true,
})

hl.window_rule({
	name = "windowrule-26",
	match = {
		class = "^(confirmreset)$",
	},
	float = true,
})

hl.window_rule({
	name = "windowrule-27",
	match = {
		class = "^(splash)$",
	},
	float = true,
})

hl.window_rule({
	name = "windowrule-28",
	match = {
		class = "^(toolbar)$",
	},
	float = true,
})

-- Float windows with specific window types (modal dialogs, utility windows, etc.)
hl.window_rule({
	name = "windowrule-29",
	match = {
		xwayland = true,
		title = "^()$",
		class = "^()$",
	},
	float = true,
})

hl.window_rule({
	name = "windowrule-30",
	match = {
		title = "^()$",
		class = "^(steam)$",
	},
	stay_focused = true,
	min_size = { 1, 1 },
})

-- assign telegram and spotify to workspace 1
hl.window_rule({
	name = "windowrule-31",
	match = {
		class = "^(org.telegram.desktop)$",
	},
	workspace = "1",
})

hl.window_rule({
	name = "windowrule-32",
	match = {
		class = "^(telegram-desktop)$",
	},
	workspace = "1",
})

hl.window_rule({
	name = "windowrule-33",
	match = {
		class = "^(Spotify)$",
	},
	workspace = "1",
})

hl.window_rule({
	name = "windowrule-34",
	match = {
		class = "^(spotify)$",
	},
	workspace = "1",
})

-- -- set telegram to 1:5 ratio on the left side
-- hl.window_rule({
-- 	name = "windowrule-35",
-- 	match = {
-- 		class = "^(org.telegram.desktop)$",
-- 		workspace = "1",
-- 	},
-- 	size = { "(monitor_w*0.16666)", "(monitor_h*1)" },
-- 	move = { "(0)", "(0)" },
-- })

hl.window_rule({
	name = "windowrule-36",
	match = {
		class = "^(telegram-desktop)$",
		workspace = "1",
	},
	-- size = { "(monitor_w*0.16666)", "(monitor_h*1)" },
	move = { "(0)", "(0)" },
	size = { 496, -1 },
})

-- open telegram windows at a fixed 496px width; -1 leaves height untouched
hl.window_rule({
	name = "windowrule-37",
	match = {
		class = "^(org.telegram.desktop)$",
	},
	size = { 496, -1 },
})

-- make workspaces floating
-- hl.window_rule({
--     name = "floating-workspace",
--     match = {
--         -- Only match workspaces that are NOT workspace 1
--         workspace = "not:1",
--         class = ".*",
--     },
--     float = true,
--     size = { "50%", "40%" },
-- })

-- hl.window_rule({
-- 	name = "float-all-windows",
-- 	match = {
-- 		class = ".*",
-- 		workspace = "s[0]",
-- 	},
-- 	float = true,
-- })

-- only apply titlebars on floating windows
if hl.plugin.hyprbars then
	hl.window_rule({
		name = "titlebars-on-float",
		match = {
			float = false,
		},
		["hyprbars:no_bar"] = true,
	})
end
