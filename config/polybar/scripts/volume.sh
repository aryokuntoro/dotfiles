#!/usr/bin/env bash

# ── Polybar Volume Control ────────────────────────────────────────
# Custom script instead of internal/pulseaudio so scroll-up/down can
# be hooked to a real OSD-style notification (internal/pulseaudio
# handles scroll itself with no hook for that).
#
# Icon ramps with the current level (muted/0%/low/mid/high) instead
# of a single static glyph -- same idea as the battery module's
# charging animation, just level-based since volume has no ongoing
# "process" to animate over time.
#
# Run with no args to render the polybar line (used by `exec`).
# Run with "up"/"down"/"mute" to adjust and pop a notification with a
# progress bar (used by scroll-up/scroll-down/click-left).

ICON_MUTED=$'\U0000f6a9'    # fa-volume-xmark
ICON_OFF=$'\U0000f026'      # fa-volume-off (0%)
ICON_LOW=$'\U0001f508'      # fa-volume-low
ICON_MID=$'\U0001f509'      # fa-volume (medium)
ICON_HIGH=$'\U0001f50a'     # fa-volume-high
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
elif [ "$percentage" -eq 0 ]; then
    icon="$ICON_OFF"
    label="${percentage}%"
elif [ "$percentage" -le 33 ]; then
    icon="$ICON_LOW"
    label="${percentage}%"
elif [ "$percentage" -le 66 ]; then
    icon="$ICON_MID"
    label="${percentage}%"
else
    icon="$ICON_HIGH"
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
