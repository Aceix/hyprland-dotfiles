#!/usr/bin/env bash
# Halve the width and height of the active window.
# Hyprland's resize dispatcher can't multiply the current size, so read it and
# resize to exactly half using an absolute (exact) resize.
#
# This is a Lua-configured Hyprland: `hyprctl dispatch <arg>` evaluates <arg> as
# `return hl.dispatch(<arg>)`, so the dispatch must be a Lua dispatcher
# expression, not classic `resizeactive exact W H` syntax. `hl.dsp.window.resize`
# with x/y (and no `relative`) resizes to an exact/absolute size.

set -euo pipefail

read -r width height < <(hyprctl activewindow -j | jq -r '.size | "\(.[0]) \(.[1])"')

# Guard against a missing/empty active window.
[ -n "${width:-}" ] && [ "${width}" != "null" ] || exit 0

hyprctl dispatch "hl.dsp.window.resize({ x = $((width / 2)), y = $((height / 2)) })"
