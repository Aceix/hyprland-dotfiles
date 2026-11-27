#!/bin/sh
# Headless startup + per-language check of this config. Exit status 0 = pass.
# State (sessions, shada, swap) goes to a throwaway dir, so the real ones are
# never touched; plugins and Mason tools are the installed ones.
config=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/state" "$tmp/work"
cd "$tmp/work" || exit 1
env -u KITTY_LISTEN_ON TERM=dumb XDG_STATE_HOME="$tmp/state" SMOKE_DIR="$tmp/work" \
  nvim --headless --cmd "luafile $config/tests/smoke_pre.lua" -c "luafile $config/tests/smoke.lua"
