#!/usr/bin/env bash

# ── Polybar Volume Control ────────────────────────────────────────
# Custom script instead of internal/pulseaudio so scroll-up/down can
# be hooked to a real OSD-style notification (internal/pulseaudio
# handles scroll itself with no hook for that).
#
# Run with no args to render the polybar line (used by `exec`).
# Run with "up"/"down"/"mute" to adjust and pop a notification with a
# progress bar (used by scroll-up/scroll-down/click-left).

ICON_VOLUME=$'\U0000f028' # fa-volume_up
ICON_MUTED=$'\U0000f026'  # fa-volume_off
NOTIFY_ID=9992

CONF="$HOME/.config/polybar/config.ini"
color() { grep -m1 "^$1 = " "$CONF" | sed 's/^[a-z-]* = //'; }
ACCENT=$(color accent)
FG=$(color foreground)
DISABLED=$(color disabled)

case "$1" in
up) pactl set-sink-volume @DEFAULT_SINK@ +5% >/dev/null 2>&1 ;;
down) pactl set-sink-volume @DEFAULT_SINK@ -5% >/dev/null 2>&1 ;;
mute) pactl set-sink-mute @DEFAULT_SINK@ toggle >/dev/null 2>&1 ;;
esac

percentage=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oP '\d+(?=%)' | head -1)
muted=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | grep -oP '(?<=Mute: )\w+')

[ -z "$percentage" ] && exit 0

if [ "$muted" = "yes" ]; then
    icon="$ICON_MUTED"
    label="muted"
else
    icon="$ICON_VOLUME"
    label="${percentage}%"
fi

if [ -n "$1" ]; then
    if [ "$muted" = "yes" ]; then
        notify-send -r "$NOTIFY_ID" -t 1500 "$icon  Volume" "Muted"
    else
        notify-send -r "$NOTIFY_ID" -h "int:value:$percentage" -t 1500 \
            "$icon  Volume" "${percentage}%"
    fi
    exit 0
fi

if [ "$muted" = "yes" ]; then
    echo "%{F$DISABLED}$icon $label%{F-}"
else
    echo "%{F$ACCENT}$icon%{F-} %{F$FG}$label%{F-}"
fi
