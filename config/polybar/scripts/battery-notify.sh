#!/usr/bin/env bash

# ── Battery state-change notifications ───────────────────────────
# Laptop-only: exits immediately if there's no battery (desktop
# machines like this one). Meant to be backgrounded once from
# autostart.sh as a long-running loop -- not a one-shot script like
# the polybar module scripts (polybar/config.ini's [module/battery]
# only renders the bar label, it has no hook to fire notifications on
# its own).
#
# Notifies on charger plug/unplug and once when battery drops to
# LOW_AT% while discharging (re-armed the next time charging starts).

BAT=$(ls /sys/class/power_supply 2>/dev/null | grep -m1 '^BAT')
[ -z "$BAT" ] && exit 0

LOW_AT=20
POLL_SECONDS=30
STATE_FILE="$HOME/.cache/battery-notify-state"
NOTIFY_ID=9993

ICON_CHARGING=$'\U0000f0e7'   # fa-bolt
ICON_UNPLUGGED=$'\U0000f011'  # fa-power-off
ICON_LOW=$'\U0000f071'        # fa-triangle-exclamation

read -r prev_status low_notified < "$STATE_FILE" 2>/dev/null

while true; do
    status=$(cat "/sys/class/power_supply/$BAT/status" 2>/dev/null)
    percentage=$(cat "/sys/class/power_supply/$BAT/capacity" 2>/dev/null)

    if [ -n "$status" ] && [ "$status" != "$prev_status" ]; then
        case "$status" in
        Charging)
            notify-send -r "$NOTIFY_ID" -t 3000 "$ICON_CHARGING  Charger connected" "Charging (${percentage}%)"
            low_notified=0
            ;;
        Discharging)
            notify-send -r "$NOTIFY_ID" -t 3000 "$ICON_UNPLUGGED  Charger disconnected" "On battery (${percentage}%)"
            ;;
        esac
        prev_status="$status"
    fi

    if [ "$status" = "Discharging" ] && [ -n "$percentage" ] && [ "$percentage" -le "$LOW_AT" ] && [ "${low_notified:-0}" -eq 0 ]; then
        notify-send -u critical -r "$((NOTIFY_ID + 1))" -t 5000 "$ICON_LOW  Baterai lemah" "${percentage}% tersisa, colok charger"
        low_notified=1
    fi

    echo "$prev_status ${low_notified:-0}" > "$STATE_FILE"
    sleep "$POLL_SECONDS"
done
