#!/usr/bin/env bash

# ── Polybar workspace indicator: always shows slots 1-0 ─────────
# i3 destroys an empty workspace as soon as you leave it (unless it's
# the last one on that output), so a plain `type = internal/i3`
# module can only ever show workspaces that currently exist. This
# script always prints all slots for this bar's range, using state
# from `i3-msg -t get_workspaces` to color the focused/existing ones,
# and updates live via `i3-msg -t subscribe`.
#
# Range depends on how many monitors are connected, mirroring the
# split in i3/config (workspace $ws1-5 output primary, $ws6-10 output
# right): a single monitor shows all of 1-10; with two+ monitors, the
# bar on the primary output shows 1-5 and every other bar shows 6-10.
# launch.sh sets $MONITOR per bar instance, same as polybar itself.
#
# Run with no args to render the polybar line (used by `exec`).
# Run with "up"/"down" to switch to the next/previous workspace within
# this bar's range, wrapping at the ends (used by scroll-up/down).

CONF="$HOME/.config/polybar/config.ini"
ICON=$'\U0000f192' # circle-dot (fa-dot_circle_o), confirmed in JetBrainsMono Nerd Font

color() {
    grep -m1 "^$1 = " "$CONF" | sed 's/^[a-z-]* = //'
}

ACCENT=$(color accent)
FG_ALT=$(color foreground-alt)
DISABLED=$(color disabled)
ALERT=$(color alert)

range() {
    local count primary
    # Match only outputs actually driving a display (a resolution
    # after "connected"), not merely plugged in -- an output turned
    # off via rofi-monitor.sh's "Single Display Only" still shows up
    # as "connected" in xrandr's query, just without a mode.
    count=$(xrandr --query 2>/dev/null | grep -cE "^\S+ connected (primary )?[0-9]+x[0-9]+")
    if [ "$count" -le 1 ]; then
        echo "1 10"
        return
    fi
    primary=$(xrandr --query 2>/dev/null | awk '/ connected primary [0-9]/{print $1}')
    if [ "$MONITOR" = "$primary" ]; then
        echo "1 5"
    else
        echo "6 10"
    fi
}

read -r START END < <(range)

focused_num() {
    i3-msg -t get_workspaces 2>/dev/null | python3 -c "
import json, sys
for w in json.load(sys.stdin):
    if w['focused']:
        print(w['name'].split(':')[0])
        break
" 2>/dev/null
}

case "$1" in
up|down)
    current=$(focused_num)
    [ -z "$current" ] && exit 0
    delta=1
    [ "$1" = down ] && delta=-1
    span=$((END - START + 1))
    new=$(( (current - START + delta % span + span) % span + START ))
    i3-msg "workspace number $new" >/dev/null 2>&1
    exit 0
    ;;
esac

render() {
    local ws_json
    ws_json=$(i3-msg -t get_workspaces)
    WS_JSON="$ws_json" ICON="$ICON" ACCENT="$ACCENT" FG_ALT="$FG_ALT" \
        DISABLED="$DISABLED" ALERT="$ALERT" START="$START" END="$END" python3 -c "
import json, os

ws = json.loads(os.environ['WS_JSON'])
states = {}
for w in ws:
    num = w['name'].split(':')[0]
    try:
        n = int(num)
    except ValueError:
        continue
    states[n] = 'urgent' if w.get('urgent') else ('focused' if w.get('focused') else 'visible')

icon = os.environ['ICON']
colors = {
    'focused': os.environ['ACCENT'],
    'urgent': os.environ['ALERT'],
    'visible': os.environ['FG_ALT'],
    'empty': os.environ['DISABLED'],
}
start = int(os.environ['START'])
end = int(os.environ['END'])

parts = []
for n in range(start, end + 1):
    fg = colors[states.get(n, 'empty')]
    parts.append(f'%{{A1:i3-msg workspace number {n}:}}%{{F{fg}}}{icon}%{{F-}}%{{A}} ')
print(''.join(parts))
"
}

render

i3-msg -t subscribe -m '["workspace"]' | while read -r _; do
    render
done
