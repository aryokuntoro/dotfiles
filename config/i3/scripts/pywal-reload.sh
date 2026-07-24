#!/usr/bin/env bash

# ── Pywal post-generation hook ────────────────────────────────
# This runs after pywal generates colors

# Reload i3 colors
~/.config/i3/scripts/colorreload.sh

# Reload polybar
~/.config/polybar/launch.sh

# Reload dunst
killall dunst 2>/dev/null
dunst -config ~/.config/dunst/dunstrc &

# Reload picom
killall picom 2>/dev/null
picom -b --config ~/.config/picom/picom.conf

# Update terminal colors (kitty)
if [ -f ~/.config/kitty/kitty.conf ]; then
    killall -SIGUSR1 kitty 2>/dev/null
fi

# Update GTK theme via lxappearance
if [ -f ~/.cache/wal/colors.json ]; then
    # Generate GTK theme from pywal
    oomox-cli -m all ~/.cache/wal/colors -o PywalTheme 2>/dev/null || true
fi
