#!/bin/bash

# Define commands for power actions
CMD_SHUTDOWN="systemctl poweroff"
CMD_REBOOT="systemctl reboot"
CMD_SUSPEND="systemctl suspend"
CMD_LOGOUT="hyprctl dispatch exit" # Command to exit Hyprland session

# Define icons (Requires Nerd Fonts configured in your Waybar's style.css)
ICON_SHUTDOWN="⏻" # Power symbol
ICON_REBOOT="󰑓"   # Restart symbol
ICON_SUSPEND="󰤄"  # Sleep/Suspend symbol
ICON_LOGOUT="󰍃"   # Logout symbol

# Options to display in Wofi
OPTIONS="$ICON_SHUTDOWN Shutdown\n$ICON_REBOOT Reboot\n$ICON_SUSPEND Suspend\n$ICON_LOGOUT Logout"

# Use Wofi to get user choice
CHOICE=$(echo -e "$OPTIONS" | wofi -dmen)

case "$CHOICE" in
    "$ICON_SHUTDOWN Shutdown")
        exec $CMD_SHUTDOWN
        ;;
    "$ICON_REBOOT Reboot")
        exec $CMD_REBOOT
        ;;
    "$ICON_SUSPEND Suspend")
        exec $CMD_SUSPEND
        ;;
    "$ICON_LOGOUT Logout")
        exec $CMD_LOGOUT
        ;;
    *)
        # Do nothing if selection is empty or cancelled
        ;;
esac
