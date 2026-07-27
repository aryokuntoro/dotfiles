#!/usr/bin/env bash

# ── Polybar Monitor Brightness ───────────────────────────────────
# On a real laptop panel (/sys/class/backlight has an entry),
# brightnessctl drives it directly. This machine is a desktop with an
# external monitor over HDMI/DisplayPort instead (no backlight panel
# exists here, so internal/backlight always reports "no such
# device"), so it falls back to ddcutil talking DDC/CI straight to the
# monitor's own OSD brightness control.
#
# Run with no args to render the polybar line (used by `exec`).
# Run with "up"/"down" to nudge brightness and pop an OSD-style
# notification with a progress bar (used by scroll-up/scroll-down).
#
# Without --bus, ddcutil re-scans every I2C bus on each call looking
# for a DDC-capable display (~300ms) before it even reads/writes
# anything -- that's what made scroll feel laggy. Cache the bus number
# from `ddcutil detect` instead, and only re-detect if the cached bus
# stops responding (monitor moved to a different port, etc).
#
# --sleep-multiplier shrinks ddcutil's built-in inter-message delays
# on top of that, and --disable-dynamic-sleep stops it from adaptively
# re-lengthening those delays mid-session (that adaptive retuning was
# still spiking calls back up to ~300ms even with a low multiplier).
# 0.1 tested reliably on this monitor (20+ back-to-back get/set calls,
# no dropped reads), giving a consistent ~100ms per call. Bump the
# multiplier back up or drop --disable-dynamic-sleep if a different
# monitor starts returning empty reads.
#
# Icon ramps with the current level (same idea as volume.sh) instead
# of a single static glyph.

ICON_1=$'\U000f00da' # md-brightness_1 (1-25%)
ICON_2=$'\U000f00dc' # md-brightness_3 (26-50%)
ICON_3=$'\U000f00de' # md-brightness_5 (51-75%)
ICON_4=$'\U000f00e0' # md-brightness_7 (76-100%)
NOTIFY_ID=9991
BUS_CACHE="$HOME/.cache/ddcutil-bus"

CONF="$HOME/.config/polybar/config.ini"
color() { grep -m1 "^$1 = " "$CONF" | sed 's/^[a-z-]* = //'; }
ACCENT=$(color accent)
FG=$(color foreground)

PANEL=$(ls /sys/class/backlight 2>/dev/null | head -1)

if [ -n "$PANEL" ]; then
    case "$1" in
    up) brightnessctl -d "$PANEL" set +5% -q ;;
    down) brightnessctl -d "$PANEL" set 5%- -q ;;
    esac

    current_percentage() {
        brightnessctl -d "$PANEL" -m 2>/dev/null | awk -F, '{print $4}' | tr -d '%'
    }
else
    detect_bus() { ddcutil detect --brief 2>/dev/null | grep -oP '(?<=/dev/i2c-)\d+' | head -1; }

    mkdir -p "$(dirname "$BUS_CACHE")"
    BUS=$(cat "$BUS_CACHE" 2>/dev/null)
    if [ -z "$BUS" ]; then
        BUS=$(detect_bus)
        [ -n "$BUS" ] && echo "$BUS" > "$BUS_CACHE"
    fi

    case "$1" in
    up) ddcutil --bus "$BUS" --disable-dynamic-sleep --sleep-multiplier 0.1 setvcp 10 + 5 >/dev/null 2>&1 ;;
    down) ddcutil --bus "$BUS" --disable-dynamic-sleep --sleep-multiplier 0.1 setvcp 10 - 5 >/dev/null 2>&1 ;;
    esac

    current_percentage() {
        read -r _ _ _ current max < <(ddcutil --bus "$BUS" --disable-dynamic-sleep --sleep-multiplier 0.1 getvcp 10 --brief 2>/dev/null)
        if [ -z "$current" ]; then
            BUS=$(detect_bus)
            [ -n "$BUS" ] && echo "$BUS" > "$BUS_CACHE"
            read -r _ _ _ current max < <(ddcutil --bus "$BUS" --disable-dynamic-sleep --sleep-multiplier 0.1 getvcp 10 --brief 2>/dev/null)
        fi
        [ -z "$current" ] && return 1
        echo $((current * 100 / max))
    }
fi

percentage=$(current_percentage)
[ -z "$percentage" ] && exit 0

if [ "$percentage" -le 25 ]; then
    icon="$ICON_1"
elif [ "$percentage" -le 50 ]; then
    icon="$ICON_2"
elif [ "$percentage" -le 75 ]; then
    icon="$ICON_3"
else
    icon="$ICON_4"
fi

if [ -n "$1" ]; then
    notify-send -r "$NOTIFY_ID" -h "int:value:$percentage" -t 1500 \
        "$icon  Brightness" "${percentage}%"
    exit 0
fi

echo "%{F$ACCENT}$icon%{F-} %{F$FG}${percentage}%%{F-}"
