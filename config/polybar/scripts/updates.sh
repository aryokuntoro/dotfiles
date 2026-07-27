#!/usr/bin/env bash

# ── Polybar update indicator: repo+AUR (paru) + flatpak ─────────
# Counts pending updates without ever installing anything itself.
# `paru -Qu` already covers official repos and AUR together (paru
# wraps pacman and syncs its own dbs internally); `paru -Qua`
# (AUR-only) is skipped because it crashes on this paru build. If
# paru itself fails or hiccups (e.g. AUR RPC unreachable), fall back
# to plain `pacman -Qu` -- otherwise a swallowed error silently reads
# as "0 updates" instead of just missing the AUR half.
# Click-left/right open a terminal to actually upgrade.

ICON=$'\U0000f019' # fa-download

CONF="$HOME/.config/polybar/config.ini"
color() {
    grep -m1 "^$1 = " "$CONF" | sed 's/^[a-z-]* = //'
}
ACCENT=$(color accent)
FG=$(color foreground)

repo_aur_out=$(paru -Qu 2>/dev/null) || repo_aur_out=$(pacman -Qu 2>/dev/null)
repo_aur=0
[ -n "$repo_aur_out" ] && repo_aur=$(printf '%s\n' "$repo_aur_out" | wc -l)
flat=$(flatpak remote-ls --updates 2>/dev/null | wc -l)
total=$((repo_aur + flat))

# Matches the rest of the bar's convention: icon in accent, label in
# foreground (e.g. cpu/memory/temperature/battery in config.ini).
echo "%{F$ACCENT}$ICON%{F-} %{F$FG}${total}%{F-} "
