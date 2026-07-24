#!/usr/bin/env bash

# ── Polybar update indicator: repo+AUR (paru) + flatpak ─────────
# Counts pending updates without ever installing anything itself.
# `paru -Qu` already covers official repos and AUR together (paru
# wraps pacman and syncs its own dbs internally); `paru -Qua`
# (AUR-only) is skipped because it crashes on this paru build.
# Click-left/right open a terminal to actually upgrade.

ICON=$'\U0000f019' # fa-download

CONF="$HOME/.config/polybar/config.ini"
color() {
    grep -m1 "^$1 = " "$CONF" | sed 's/^[a-z-]* = //'
}
ACCENT=$(color accent)
FG=$(color foreground)

repo_aur=$(paru -Qu 2>/dev/null | wc -l)
flat=$(flatpak remote-ls --updates 2>/dev/null | wc -l)
total=$((repo_aur + flat))

# Matches the rest of the bar's convention: icon in accent, label in
# foreground (e.g. cpu/memory/temperature/battery in config.ini).
echo "%{F$ACCENT}$ICON%{F-} %{F$FG}${total}%{F-} "
