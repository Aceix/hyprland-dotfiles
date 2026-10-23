-- Shared values used across more than one module.
-- `local`s don't cross file boundaries under require(), so anything needed
-- in multiple modules lives here and gets pulled in via `require("modules.variables")`.

return {
	monitors = {
		aoc = "HDMI-A-1",
		dell = "DP-1",
	},

	programs = {
		terminal = "kitty",
		file_manager = "nautilus",
		-- menu = "noctalia msg panel-toggle launcher",
		menu = "wofi --show drun",
		web_browser = "google-chrome-stable --disable-features=WaylandWpColorManagerV1",
		code_editor = "code",
		calculator = "gnome-calculator",
	},

	-- Run a hymission action, then hide Noctalia's bar/widgets while overview is open
	overview = function(action)
		hl.plugin.hymission[action]()
		hl.exec_cmd("~/.config/hypr/scripts/overview_noctalia.sh")
	end,
}
