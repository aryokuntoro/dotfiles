#!/usr/bin/env bash

# ── Polybar workspace indicator: always shows slots 1-0 ─────────
# i3 destroys an empty workspace as soon as you leave it (unless it's
# the last one on that output), so a plain `type = internal/i3`
# module can only ever show workspaces that currently exist. This
# script always prints all 10 slots (1-9, 0 for the 10th), using
# state from `i3-msg -t get_workspaces` to color the focused/existing
# ones, and updates live via `i3-msg -t subscribe`.

CONF="$HOME/.config/polybar/config.ini"
ICON=$'' # circle-dot (fa-dot_circle_o), confirmed in JetBrainsMono Nerd Font

color() {
    grep -m1 "^$1 = " "$CONF" | sed 's/^[a-z-]* = //'
}

ACCENT=$(color accent)
FG_ALT=$(color foreground-alt)
DISABLED=$(color disabled)
ALERT=$(color alert)

render() {
    local ws_json
    ws_json=$(i3-msg -t get_workspaces)
    WS_JSON="$ws_json" ICON="$ICON" ACCENT="$ACCENT" FG_ALT="$FG_ALT" \
        DISABLED="$DISABLED" ALERT="$ALERT" python3 -c "
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

parts = []
for n in range(1, 11):
    fg = colors[states.get(n, 'empty')]
    parts.append(f'%{{A1:i3-msg workspace number {n}:}}%{{F{fg}}}{icon}%{{F-}}%{{A}} ')
print(''.join(parts))
"
}

render

i3-msg -t subscribe -m '["workspace"]' | while read -r _; do
    render
done
