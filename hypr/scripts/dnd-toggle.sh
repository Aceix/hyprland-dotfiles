#!/bin/bash

socat - UNIX-CONNECT:/$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock | while read line; do
  if [[ $line == "fullscreen>>1" ]]; then
    # A window entered fullscreen
    noctalia msg notification-dnd-set on
  elif [[ $line == "fullscreen>>0" ]]; then
    # A window exited fullscreen
    noctalia msg notification-dnd-set off
  fi
done
