#!/usr/bin/env bash

# ── Polybar Bluetooth Status ────────────────────────────────────
# Shows Off / On / connected device name + battery % (if available)

if ! bluetoothctl show | grep -q "Powered: yes"; then
    echo "Off"
    exit 0
fi

mapfile -t connected < <(bluetoothctl devices Connected 2>/dev/null | awk '{print $2}')

if [ "${#connected[@]}" -eq 0 ]; then
    echo "On"
    exit 0
fi

mac="${connected[0]}"
info=$(bluetoothctl info "$mac")
name=$(echo "$info" | awk -F': ' '/^\tAlias/{print $2; exit}')
battery=$(echo "$info" | grep -oP 'Battery Percentage:.*\(\K[0-9]+(?=\))')

label="$name"
[ -n "$battery" ] && label="$label  ${battery}%"

extra=$(( ${#connected[@]} - 1 ))
[ "$extra" -gt 0 ] && label="$label +$extra"

echo "$label"
