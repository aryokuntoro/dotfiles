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
# Some "monitors" (e.g. a TV plugged in over HDMI) show up in `ddcutil
# detect` with a real I2C bus but don't actually implement DDC/CI --
# every getvcp/setvcp against them fails with EIO, and ddcutil logs
# that failure straight to the journal via syslog regardless of shell
# redirection, so retrying every poll floods the journal forever. Once
# getvcp comes back empty even after a fresh bus re-detect, we assume
# this display will never support DDC/CI, cache that verdict, and skip
# calling ddcutil entirely from then on. Delete UNSUPPORTED_CACHE to
# force a re-check (e.g. after swapping in an actual monitor).
#
# Once that verdict is cached there's no hardware lever left to pull,
# so brightness falls back to RandR's per-output gamma scale (`xrandr
# --brightness`) instead. That's a software darken of the rendered
# pixels, not real backlight control -- it works on literally any
# RandR output regardless of what the display supports -- so it's the
# last resort, not the first choice. Floored at MIN_PCT because gamma
# scaling much below that makes text unreadable rather than "dim".
#
# Icon ramps with the current level (same idea as volume.sh) instead
# of a single static glyph.

ICON_1=$'\U000f00da' # md-brightness_1 (1-25%)
ICON_2=$'\U000f00dc' # md-brightness_3 (26-50%)
ICON_3=$'\U000f00de' # md-brightness_5 (51-75%)
ICON_4=$'\U000f00e0' # md-brightness_7 (76-100%)
NOTIFY_ID=9991
BUS_CACHE="$HOME/.cache/ddcutil-bus"
UNSUPPORTED_CACHE="$HOME/.cache/ddcutil-unsupported"

CONF="$HOME/.config/polybar/config.ini"
color() { grep -m1 "^$1 = " "$CONF" | sed 's/^[a-z-]* = //'; }
ACCENT=$(color accent)
FG=$(color foreground)

# Glob rather than `ls | head -1`: same result, but it cannot be tripped
# up by an odd filename and it does not fork.
PANEL=""
for panel_path in /sys/class/backlight/*; do
    [ -e "$panel_path" ] || continue   # no match -- the glob stayed literal
    PANEL=${panel_path##*/}
    break
done

if [ -n "$PANEL" ]; then
    case "$1" in
    up) brightnessctl -d "$PANEL" set +5% -q ;;
    down) brightnessctl -d "$PANEL" set 5%- -q ;;
    esac

    current_percentage() {
        brightnessctl -d "$PANEL" -m 2>/dev/null | awk -F, '{print $4}' | tr -d '%'
    }
elif [ -f "$UNSUPPORTED_CACHE" ]; then
    BRIGHTNESS_CACHE="$HOME/.cache/xrandr-brightness"
    MIN_PCT=20

    pct=$(cat "$BRIGHTNESS_CACHE" 2>/dev/null)
    [[ "$pct" =~ ^[0-9]+$ ]] || pct=100

    case "$1" in
    up) pct=$((pct + 5 > 100 ? 100 : pct + 5)) ;;
    down) pct=$((pct - 5 < MIN_PCT ? MIN_PCT : pct - 5)) ;;
    esac

    # Looked up only when actually changing brightness. polybar runs
    # this script every 2s just to print the current value, and
    # `xrandr --query` costs ~67ms on this NVIDIA setup -- it was two
    # thirds of the total cost of every status bar refresh, spent on a
    # value that gets discarded unless $1 is set.
    if [ -n "$1" ]; then
        XRANDR_OUTPUT=$(xrandr --query | awk '/ connected/{print $1; exit}')
        if [ -n "$XRANDR_OUTPUT" ]; then
            xrandr --output "$XRANDR_OUTPUT" --brightness "$(awk -v p="$pct" 'BEGIN{printf "%.2f", p/100}')"
            echo "$pct" > "$BRIGHTNESS_CACHE"
        fi
    fi

    current_percentage() { echo "$pct"; }
else
    mkdir -p "$(dirname "$BUS_CACHE")"

    detect_bus() { ddcutil detect --brief 2>/dev/null | grep -oP '(?<=/dev/i2c-)\d+' | head -1; }

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
        if ! [[ "$current" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ ]]; then
            BUS=$(detect_bus)
            [ -n "$BUS" ] && echo "$BUS" > "$BUS_CACHE"
            read -r _ _ _ current max < <(ddcutil --bus "$BUS" --disable-dynamic-sleep --sleep-multiplier 0.1 getvcp 10 --brief 2>/dev/null)
        fi
        # A lock-contended or DDC-incapable display can print flock/error
        # diagnostics on stdout instead of leaving it empty, so validate
        # both fields are actually numeric before doing arithmetic on them.
        if ! [[ "$current" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ ]]; then
            touch "$UNSUPPORTED_CACHE"
            return 1
        fi
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
