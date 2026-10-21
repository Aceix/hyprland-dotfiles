#!/bin/bash

# Apps to start on login
apps=(
  "Telegram"
  "spotify"
)

# Note: hyprctl dispatch exec is parsed as Lua under hyprland-lua and fails
# for commands like "[workspace 1] Telegram". These apps are pinned to
# workspace 1 via window rules in modules/window-rules.lua instead.
for app in "${apps[@]}"; do
  "$app" &
  sleep 1
done
