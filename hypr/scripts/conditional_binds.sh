#!/bin/sh

mainMod=SUPER

# Check if the hyprmodoro plugin is enabled
if hyprctl plugin list 2>/dev/null | grep -q hyprmodoro; then
    echo "Hyprmodoro plugin is enabled. Binding keys..."
    # Bind SUPER + TAB to the hyprexpo:expo dispatcher
    hyprctl keyword bind "SUPER, TAB, hyprexpo:expo, toggle"

    hyprctl keyword bind "$mainMod CTRL SHIFT, 1, hyprmodoro:set, 10"
    hyprctl keyword bind "$mainMod CTRL SHIFT, 1, hyprmodoro:start"
    hyprctl keyword bind "$mainMod CTRL SHIFT, 2, hyprmodoro:set, 20"
    hyprctl keyword bind "$mainMod CTRL SHIFT, 2, hyprmodoro:start"
    hyprctl keyword bind "$mainMod CTRL SHIFT, 3, hyprmodoro:set, 30"
    hyprctl keyword bind "$mainMod CTRL SHIFT, 3, hyprmodoro:start"
    hyprctl keyword bind "$mainMod CTRL SHIFT, 4, hyprmodoro:set, 60"
    hyprctl keyword bind "$mainMod CTRL SHIFT, 4, hyprmodoro:start"
    hyprctl keyword bind "$mainMod CTRL SHIFT, 5, hyprmodoro:set, 120"
    hyprctl keyword bind "$mainMod CTRL SHIFT, 5, hyprmodoro:start"
    hyprctl keyword bind "$mainMod CTRL SHIFT, 0, hyprmodoro:stop"

else
    echo "Hyprmodoro plugin is not enabled. Skipping keybinds."
fi
