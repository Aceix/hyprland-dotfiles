-----------------
-- AUTOSTART ----
-----------------

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
-- Or execute your favorite apps at launch like this:

-- exec-once
hl.on("hyprland.start", function()
	-- hl.exec_cmd("~/.config/hypr/scripts/set_dunst_output_device.sh >> ~/.config/hypr/scripts/logs/set_dunst_output_device.log 2>&1")
	-- hl.exec_cmd("nm-applet")
	hl.exec_cmd("paplay ~/.config/hypr/sounds/login.mp3 > /dev/null")
	hl.exec_cmd("~/.config/hypr/scripts/waybar_auto_hide &")

	hl.exec_cmd("hypridle")
	hl.exec_cmd("/usr/lib/hyprpolkitagent")
	-- hl.exec_cmd("hyprpaper")
	-- hl.exec_cmd("hyprsunset")
	-- hl.exec_cmd("swaync") -- replaced by noctalia
	-- hl.exec_cmd("swayosd-server") -- replaced by noctalia

	hl.exec_cmd("~/.config/hypr/scripts/startup_apps.sh >> ~/.config/hypr/scripts/logs/startup_apps.log 2>&1")
	hl.exec_cmd("~/.config/hypr/scripts/dnd-toggle.sh")
	hl.exec_cmd("~/.config/hypr/scripts/launch_noctalia.sh >> ~/.config/hypr/scripts/logs/launch_noctalia.log 2>&1")

  hl.exec_cmd("hyprctl plugin load /home/aceix/src/hyprmodoro/hyprmodoro.so")
end)

-- exec (runs on every config load, including the first)
hl.on("config.reloaded", function()
	-- hl.exec_cmd("~/.config/hypr/scripts/monitor_switcher.sh >> ~/.config/hypr/scripts/logs/monitor_switcher.log 2>&1")
	-- hl.exec_cmd("systemctl --user restart waybar.service")

	-- hl.exec_cmd("awww-daemon")
	hl.exec_cmd("~/.config/hypr/scripts/conditional_binds.sh >> ~/.config/hypr/scripts/logs/conditional_binds.log 2>&1")
	hl.exec_cmd(
		"sleep 2 && ~/.config/hypr/scripts/random_hyprpaper.sh >> ~/.config/hypr/scripts/logs/random_hyprpaper.log 2>&1"
	)

	-- DARK THEME
	hl.exec_cmd('gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"') -- for GTK4 apps
	hl.exec_cmd('gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-dark"') -- for GTK3 apps

  hl.exec_cmd("hyprpm reload")
end)

-- exec-shutdown
hl.on("hyprland.shutdown", function()
	hl.exec_cmd("paplay ~/.config/hypr/sounds/login.mp3 > /dev/null")
end)
