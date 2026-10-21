#!/bin/bash

APP_NAME="$1"

echo "App = $1"

EXCEPTIONS=(
  "spotify"
)

for i in "${EXCEPTIONS[@]}"
do
  if [ "$i" == "$APP_NAME" ]; then
    # The app is on the exception list, so exit without playing a sound
    exit 0
  fi
done

if [ $(swaync-client -D) = "false" ]; then
  paplay ~/.config/hypr/sounds/notification.mp3
fi
