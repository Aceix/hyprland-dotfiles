output_json() {
  if ! pgrep -x "hyprsunset" > /dev/null; then
    echo '{ "text": "<span font=\"Material Icons Outlined\">bedtime_off</span>", "tooltip": "Toggle nightmode (disabled)", "class": "waysunset" }'
  else
    echo '{ "text": "<span font=\"Material Icons Outlined\">bedtime</span>", "tooltip": "Toggle nightmode (enabled)", "class": "waysunset" }'
  fi
}

toggle_nightmode() {
  if ! pgrep -x "hyprsunset" > /dev/null; then
    hyprctl dispatch exec hyprsunset
  else
    killall "hyprsunset"
  fi
}

case "$1" in
  toggle)
    toggle_nightmode
    ;;
  *)
    output_json
    ;;
esac
