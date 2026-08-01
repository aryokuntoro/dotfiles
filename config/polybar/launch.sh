#!/usr/bin/env bash

# Serialize concurrent invocations (e.g. two i3 restarts firing
# exec_always in quick succession) -- without this, two overlapping
# runs can each pass the kill-and-wait check below before either has
# actually launched polybar, then both launch it, doubling every bar.
exec 9>"$HOME/.cache/polybar-launch.lock"
flock 9

# Kill existing polybar instances
killall -q polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 0.5; done

# Get monitor names -- retry if none are up yet. HDMI-0 here is a TV
# with a generic EDID and no DDC/CI (see xinitrc/apply-theme-colors.sh
# comments), so its hotplug is unreliable: xrandr can report every
# output disconnected for a few seconds even though the TV is still
# on. A bare re-query won't recover a dropped link on its own, so
# nudge it: `autorandr --change` first (fast, matches the saved
# profile when the TV's EDID comes back the same), then fall back to
# a bare `xrandr --auto` (slower but doesn't need an exact profile
# match -- covers this TV occasionally reporting a different mode
# list across reconnects).
MONITORS=$(xrandr --query | grep " connected" | cut -d" " -f1)
tries=0
while [ -z "$MONITORS" ] && [ "$tries" -lt 10 ]; do
    sleep 1
    if [ "$tries" -lt 3 ]; then
        autorandr --change >/dev/null 2>&1
    else
        xrandr --auto >/dev/null 2>&1
    fi
    MONITORS=$(xrandr --query | grep " connected" | cut -d" " -f1)
    tries=$((tries + 1))
done

if [ -z "$MONITORS" ]; then
    notify-send "Polybar" "No display detected after ${tries} retries" 2>/dev/null
    echo "Polybar: no connected monitor found, giving up" >&2
    exit 1
fi

# Launch polybar on each monitor. 9>&- closes the lock fd for these
# specific background jobs -- polybar runs forever, and an inherited
# copy of fd 9 would keep the flock held past this script's own exit,
# permanently deadlocking every future invocation.
for MONITOR in $MONITORS; do
    MONITOR=$MONITOR polybar -c ~/.config/polybar/config.ini main 9>&- >/dev/null 2>&1 &
done

echo "Polybar launched on: $MONITORS"
