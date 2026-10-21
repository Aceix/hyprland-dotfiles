#!/bin/bash

# Get the active workspace ID
workspace_id=$(hyprctl activeworkspace -j | jq '.id')

# Check for floating windows on the active workspace
has_floating_windows=$(hyprctl clients -j | jq --argjson workspace_id "$workspace_id" -e '.[] | select(.workspace.id == $workspace_id and .floating == true)')

# If there are floating windows, make all windows tiled
if [ -n "$has_floating_windows" ]; then

  hyprctl clients -j | jq -r --arg ws "$workspace_id" '.[] | select(.workspace.id == ($ws | tonumber)) | .address' | while read addr; do
    hyprctl dispatch settiled address:$addr
    sleep 0.1
  done

else
  # If there are no floating windows, make all windows floating

  hyprctl clients -j | jq -r --arg ws "$workspace_id" '.[] | select(.workspace.id == ($ws | tonumber)) | .address' | while read addr; do
    hyprctl dispatch setfloating address:$addr
    hyprctl dispatch resizewindow address:$addr 50% 50%
    sleep 0.1
  done

fi
