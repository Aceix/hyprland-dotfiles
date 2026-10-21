#!/bin/sh

WALLPAPER_DIR="${HOME}/Pictures/wallpapers"
MONITOR=

# Nothing to do if the wallpaper dir does not exist.
[ -d "$WALLPAPER_DIR" ] || exit 0

# Get a random wallpaper from the directory
WALLPAPER=$(find "$WALLPAPER_DIR" -type f | shuf -n 1)

# Preload, then apply the wallpaper using hyprctl hyprpaper
#hyprctl hyprpaper preload "$WALLPAPER"
#hyprctl hyprpaper wallpaper "$MONITOR, $WALLPAPER"
#awww img --transition-type any "$WALLPAPER"
