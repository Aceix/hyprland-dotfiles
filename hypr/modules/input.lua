-------------
-- INPUT ----
-------------

-- https://wiki.hypr.land/Configuring/Variables/#input
hl.config({
	input = {
		kb_layout = "us",
		numlock_by_default = true,
		follow_mouse = 2, -- 1 - usual behavior, 2 - GNOME behavior (without focus decoration for cursor)
		focus_on_close = 1,
		sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

		touchpad = {
			natural_scroll = true,
			clickfinger_behavior = true,
			tap_to_click = false,
			tap_and_drag = false,
		},
	},
})

hl.config({
	cursor = {
		zoom_factor = 1,
		no_hardware_cursors = 1,
	},
})

-- https://wiki.hypr.land/Configuring/Variables/#gestures
hl.config({
	gestures = {
		workspace_swipe_forever = false, -- true
		workspace_swipe_direction_lock = false,
	},
})

hl.gesture({ fingers = 3, direction = "vertical", action = "workspace" })

-- Bind 3 finger swipe up to open overview
hl.gesture({ fingers = 4, direction = "up", action = function() hl.plugin.hymission.open() end })

-- Bind 3 finger swipe down to close overview
hl.gesture({ fingers = 4, direction = "down", action = function() hl.plugin.hymission.close() end })

-- 3 finger swipe left focuses the window to the right, swipe right focuses the window to the left
hl.gesture({ fingers = 3, direction = "left", action = function() hl.dispatch(hl.dsp.focus({ direction = "right" })) end })
hl.gesture({ fingers = 3, direction = "right", action = function() hl.dispatch(hl.dsp.focus({ direction = "left" })) end })

-- Example per-device config
-- See https://wiki.hypr.land/Configuring/Keywords/#per-device-input-configs for more
hl.device({
	name = "epic-mouse-v1",
	sensitivity = -0.5,
})
