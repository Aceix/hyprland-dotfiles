#!/bin/bash

# A script to manage monitor layouts based on connected external monitors.
#
# The config is now Lua (hyprland.lua), which uses a non-legacy parser, so
# `hyprctl keyword` is refused with:
#   keyword can't work with non-legacy parsers. Use eval.
# Monitor rules therefore go through `hyprctl eval`, which runs the equivalent
# hl.monitor() call against the live config.

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
LOCK_FILE="$RUNTIME_DIR/monitor_switcher.lock"
PID_FILE="$RUNTIME_DIR/monitor_switcher.pid"

# Only ever run one copy. This script is started from the config.reloaded hook
# in modules/autostart.lua but never exits (it tails the event socket), so every
# reload would otherwise leave another instance behind, all racing to set
# monitor rules.
#
# The newest instance wins rather than the oldest. First-wins deadlocks the
# whole thing: the instance started by the very first config.reloaded races
# Hyprland's own startup and can come up before the IPC socket exists, and if
# that instance survives holding the lock, every later reload is turned away and
# the layout is never applied. Taking over means a reload is always able to
# recover the layout.
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  old_pid=$(cat "$PID_FILE" 2>/dev/null)
  if [[ $old_pid =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
    echo "monitor_switcher: taking over from pid $old_pid" >&2
    kill "$old_pid" 2>/dev/null
  else
    # No usable pid file: either an instance from before this file existed, or
    # one that lost it. Fall back to whoever holds the lock fd, otherwise a
    # stuck instance blocks takeover forever, which is the deadlock above.
    #
    # Not `fuser -k`: we hold the lock file open on fd 9 ourselves, so that
    # kills this process too. Skip our own pid explicitly.
    holders=$(fuser "$LOCK_FILE" 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$')
    for holder in $holders; do
      [[ $holder == "$$" ]] && continue
      echo "monitor_switcher: no pid file, killing lock holder $holder" >&2
      kill "$holder" 2>/dev/null
    done
  fi
  # Wait for it to die and drop the lock.
  if ! flock -w 5 9; then
    echo "monitor_switcher: could not take over from pid ${old_pid:-unknown}, exiting" >&2
    exit 1
  fi
fi
echo "$$" >"$PID_FILE"

cleanup() {
  [[ -n $EVENT_READER_PID ]] && kill "$EVENT_READER_PID" 2>/dev/null
  # Only clear the pid file if it is still ours; a successor that killed us has
  # to wait for the lock, which we only drop after this trap has run.
  [[ $(cat "$PID_FILE" 2>/dev/null) == "$$" ]] && rm -f "$PID_FILE"
}
trap cleanup EXIT

# Define monitor names from your setup
LAPTOP_MONITOR="eDP-1"
DELL_MONITOR="DP-1"
AOC_MONITOR="HDMI-A-1"

# Explicit modes rather than 'preferred'. The AOC is an ultrawide whose EDID
# also advertises 16:9 modes (including 3840x2160), so 'preferred' is both
# ambiguous and, when it does pick the ultrawide mode, picks the 60Hz variant
# over the 100Hz one this panel supports over HDMI. The AOC width also has to
# match DELL_POSITION below, so it cannot be left to chance.
AOC_MODE="3440x1440@99.98"
DELL_MODE="1920x1080@60"
LAPTOP_MODE="1920x1080@60"

# The Dell is rotated 90 degrees (transform = 1) and sits to the right of the
# AOC, so its x offset is the AOC's width. The -400 lifts its taller rotated
# 1080x1920 face so it straddles the AOC vertically.
DELL_POSITION="3440x-400"

# Apply one hl.monitor() spec. Takes the table body, e.g.
#   set_monitor "output = 'eDP-1', disabled = true"
# Lua strings are single-quoted so the shell can still expand our variables.
set_monitor() {
  local result
  result=$(hyprctl eval "hl.monitor({ $1 })" 2>&1)

  # hyprctl exits 0 even when the Lua call fails (it prints "error: ..."),
  # so failures have to be surfaced by hand or they vanish into the log.
  if [[ "$result" != "ok" ]]; then
    echo "monitor_switcher: hl.monitor({ $1 }) -> $result" >&2
    return 1
  fi
}

# True when the named output is currently plugged in. Disconnected outputs drop
# out of `monitors all` completely, while merely disabled ones stay listed, so
# presence here means "connected" regardless of whether we disabled it earlier.
is_connected() {
  grep -Fxq "$1" <<<"$CONNECTED_MONITORS"
}

# Populate CONNECTED_MONITORS, or fail. The JSON output is parsed instead of
# grepping for "Monitor", which also matches description lines.
#
# The failure has to be caught: when the IPC socket is not up yet, hyprctl
# prints a plain-text error, jq rejects it, and CONNECTED_MONITORS silently
# ends up empty. Every is_connected() then reports false and the script
# confidently applies the "laptop only" layout to a docked machine.
refresh_monitor_list() {
  local json
  json=$(hyprctl monitors all -j 2>/dev/null) || return 1
  CONNECTED_MONITORS=$(jq -r '.[].name' <<<"$json" 2>/dev/null) || return 1
  [[ -n $CONNECTED_MONITORS ]]
}

# Block until Hyprland's IPC answers. config.reloaded fires while Hyprland is
# still coming up, so on login this script reliably beats the socket into
# existence and every hyprctl call fails.
wait_for_ipc() {
  local i
  for ((i = 0; i < 150; i++)); do
    refresh_monitor_list && return 0
    sleep 0.2
  done
  return 1
}

# Function to apply the correct monitor configuration
apply_config() {
  refresh_monitor_list || {
    echo "monitor_switcher: could not read monitor list, skipping this pass" >&2
    return 1
  }

  # `mirror = 'none'` is set on every rule below. The catch-all rule in
  # modules/monitors.lua is what a freshly connected output picks up first, and
  # an inherited mirror would otherwise survive our mode and position.

  # Check if both external monitors are connected
  if is_connected "$DELL_MONITOR" && is_connected "$AOC_MONITOR"; then
    # Disable the laptop monitor and arrange external monitors
    set_monitor "output = '$LAPTOP_MONITOR', disabled = true"
    set_monitor "output = '$AOC_MONITOR', mode = '$AOC_MODE', position = '0x0', scale = 1, mirror = 'none', disabled = false"
    set_monitor "output = '$DELL_MONITOR', mode = '$DELL_MODE', position = '$DELL_POSITION', scale = 1, transform = 1, mirror = 'none', disabled = false"
  else
    # Enable the laptop monitor. `disabled = false` is required: unlike the old
    # `keyword monitor` form, giving hl.monitor() a mode does not implicitly
    # bring a disabled output back, so without it the laptop panel would stay
    # black after unplugging the dual-external setup.
    set_monitor "output = '$LAPTOP_MONITOR', mode = '$LAPTOP_MODE', position = 'auto', scale = 1, mirror = 'none', disabled = false"

    # Make sure external monitors are handled if they're still connected,
    # but the laptop is the primary display now
    if is_connected "$DELL_MONITOR"; then
      set_monitor "output = '$DELL_MONITOR', mode = '$DELL_MODE', position = 'auto', scale = 1, transform = 1, mirror = 'none', disabled = false"
    fi
    if is_connected "$AOC_MONITOR"; then
      set_monitor "output = '$AOC_MONITOR', mode = '$AOC_MODE', position = 'auto', scale = 1, mirror = 'none', disabled = false"
    fi
  fi
}

if ! wait_for_ipc; then
  echo "monitor_switcher: Hyprland IPC never became available, exiting" >&2
  exit 1
fi

# Apply the config once on startup
apply_config

# Now, listen for monitor events and re-apply the config.
# The HYPRLAND_INSTANCE_SIGNATURE is a temporary file created by hyprland
# that is used to allow external processes to communicate with it.
#
# Read through a process substitution rather than `socat | while read`: a pipe
# puts the loop in a subshell, so nothing set there survives and the script
# cannot clean the reader up on exit.
exec 8< <(socat -u "UNIX-CONNECT:$RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" -)
EVENT_READER_PID=$!

while read -r line <&8; do
  case $line in
  monitoradded* | monitorremoved*) ;;
  *) continue ;;
  esac

  # A single hotplug emits a burst of events, and Hyprland is still re-scanning
  # outputs while they arrive. Drain the burst and let it settle, otherwise the
  # first pass applies rules against a half-populated monitor list.
  while read -r -t 0.5 -u 8 _; do :; done

  apply_config
done
