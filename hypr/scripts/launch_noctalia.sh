#!/bin/sh

# noctalia --daemon can be launched by Hyprland's exec-once before the
# Wayland socket is actually accepting connections, causing it to exit
# immediately with "fatal: failed to connect to Wayland display".
# Retry until it succeeds. Once connected, noctalia runs in the foreground
# here for as long as the daemon lives, so this also respawns it if it
# ever crashes later in the session.

# Some compositor-relative wrappers (hyprland-lua's exec_cmd) strip
# WAYLAND_DISPLAY, which makes noctalia fall back to displaying wayland-0.
# Detect the live compositor socket ourselves so the daemon connects.
if [ -z "$WAYLAND_DISPLAY" ] || [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
	for s in "$XDG_RUNTIME_DIR"/wayland-*; do
		if [ -S "$s" ]; then
			export WAYLAND_DISPLAY="$(basename "$s")"
			break
		fi
	done
fi

# If a daemon is already running (another launcher instance, or a manual
# start), treat that as success instead of retrying a doomed spawn.
# Match by exact process name: the daemon's cmdline is just "noctalia".
if pgrep -x noctalia >/dev/null 2>&1; then
	exit 0
fi

# Clear a stale instance lock from a crashed/previous run so it can't block
# a fresh start.
rm -f "$XDG_RUNTIME_DIR"/noctalia-wayland-*.lock

MAX_ATTEMPTS=15

i=1
while [ "$i" -le "$MAX_ATTEMPTS" ]; do
	if noctalia --daemon; then
		exit 0
	fi
	i=$((i + 1))
	sleep 1
done

exit 1
