#!/usr/bin/env bash

# ── Polybar Monitor Brightness ───────────────────────────────────
# This machine is a desktop with an external monitor over
# HDMI/DisplayPort (no /sys/class/backlight panel exists here, so
# internal/backlight always reports "no such device"). ddcutil talks
# DDC/CI straight to the monitor's own OSD brightness control instead.
#
# Run with no args to render the polybar line (used by `exec`).
# Run with "up"/"down" to nudge brightness and pop an OSD-style
# notification with a progress bar (used by scroll-up/scroll-down).

ICON=$'\U0000f185' # fa-sun_o
NOTIFY_ID=9991

CONF="$HOME/.config/polybar/config.ini"
color() { grep -m1 "^$1 = " "$CONF" | sed 's/^[a-z-]* = //'; }
ACCENT=$(color accent)
FG=$(color foreground)

current_percentage() {
    read -r _ _ _ current max < <(ddcutil getvcp 10 --brief 2>/dev/null)
    [ -z "$current" ] && return 1
    echo $((current * 100 / max))
}

case "$1" in
up) ddcutil setvcp 10 + 5 >/dev/null 2>&1 ;;
down) ddcutil setvcp 10 - 5 >/dev/null 2>&1 ;;
esac

percentage=$(current_percentage)
[ -z "$percentage" ] && exit 0

if [ -n "$1" ]; then
    notify-send -r "$NOTIFY_ID" -h "int:value:$percentage" -t 1500 \
        "$ICON  Brightness" "${percentage}%"
    exit 0
fi

echo "%{F$ACCENT}$ICON%{F-} %{F$FG}${percentage}%%{F-}"
