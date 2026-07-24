#!/usr/bin/env bash

# Kill existing polybar instances
killall -q polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 0.5; done

# Get monitor names
MONITORS=$(xrandr --query | grep " connected" | cut -d" " -f1)

# Launch polybar on each monitor
for MONITOR in $MONITORS; do
    MONITOR=$MONITOR polybar -c ~/.config/polybar/config.ini main 2>/dev/null &
done

echo "Polybar launched on: $MONITORS"
