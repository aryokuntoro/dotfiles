#!/usr/bin/env bash

# ── Reload i3/dunst/polybar colors from the active rofi theme ──
# Re-applies the palette from whatever ~/.config/rofi/themes/current.rasi
# currently points to.

current_link="$HOME/.config/rofi/themes/current.rasi"

if [ -L "$current_link" ]; then
    ~/.config/i3/scripts/apply-theme-colors.sh "$(readlink -f "$current_link")"
else
    echo "current.rasi is not a symlink, nothing to reload" >&2
    exit 1
fi
