#!/bin/sh
# Hide Noctalia's bar + desktop widgets for as long as the hymission overview is open.
exec 9>"$XDG_RUNTIME_DIR/overview_noctalia.lock"; flock -n 9 || exit 0
active() { hyprctl hymission-overview-state | grep -q '"active":true'; }

sleep 0.1; active || exit 0
noctalia msg bar-hide; noctalia msg desktop-widgets-hide
trap 'noctalia msg bar-show; noctalia msg desktop-widgets-show' EXIT
while active; do sleep 0.2; done
