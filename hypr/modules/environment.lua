-------------------------------
-- ENVIRONMENT VARIABLES ------
-------------------------------

-- See https://wiki.hypr.land/Configuring/Environment-variables/

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

hl.env("QT_QPA_PLATFORMTHEME", "qt6ct") -- for Qt apps
hl.env("QT_QPA_PLATFORM", "wayland,xcb")

hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")

-- configure wayland apps to use intell iGPU driver via libva
hl.env("LIBVA_DRIVER_NAME", "iHD")

