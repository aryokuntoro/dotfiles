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

# `paru -Qu` exits non-zero both on a real failure and on the
# everyday case of simply having nothing to upgrade -- `||
# pacman -Qu` treated both the same, so every ordinary "0 updates"
# poll re-ran pacman for no reason, doubling pacman invocations on
# this bar's poll interval. stderr is what actually distinguishes
# them: a genuine failure (AUR RPC unreachable, paru itself broken)
# prints something there; "0 updates" does not.
repo_aur_err_file=$(mktemp)
trap 'rm -f "$repo_aur_err_file"' EXIT
repo_aur_out=$(paru -Qu 2>"$repo_aur_err_file")
if [ -s "$repo_aur_err_file" ]; then
    repo_aur_out=$(pacman -Qu 2>/dev/null)
fi
repo_aur=0
[ -n "$repo_aur_out" ] && repo_aur=$(printf '%s\n' "$repo_aur_out" | wc -l)
flat=$(flatpak remote-ls --updates 2>/dev/null | wc -l)
total=$((repo_aur + flat))

# Matches the rest of the bar's convention: icon in accent, label in
# foreground (e.g. cpu/memory/temperature/battery in config.ini).
echo "%{F$ACCENT}$ICON%{F-} %{F$FG}${total}%{F-} "
