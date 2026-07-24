#!/usr/bin/env bash

# ── Polybar Network Status ──────────────────────────────────────
# type = internal/network does not register clicks reliably on this
# polybar build, so this mirrors it as a custom/script module instead.
#
# Icon reflects the actual link in use (wifi vs wired), detected via
# /sys/class/net/<iface>/wireless -- it can't be a static config.ini
# format-prefix since it has to follow whichever interface is up.

ICON_WIFI=$'\U0000f1eb'     # fa-wifi
ICON_ETHERNET=$'\U0000ef44' # fa-ethernet

CONF="$HOME/.config/polybar/config.ini"
color() { grep -m1 "^$1 = " "$CONF" | sed 's/^[a-z-]* = //'; }
ACCENT=$(color accent)
FG=$(color foreground)
DISABLED=$(color disabled)

read -r iface ip < <(ip -o -4 addr show scope global 2>/dev/null | awk '{print $2, $4}' | cut -d/ -f1 | head -1)

# Matches the rest of the bar's convention: icon in accent, label in
# foreground (e.g. cpu/memory/temperature/battery in config.ini).
if [ -z "$ip" ]; then
    echo "%{F$DISABLED}$ICON_WIFI%{F-} %{F$FG}offline%{F-}"
    exit 0
fi

if [ -d "/sys/class/net/$iface/wireless" ]; then
    icon="$ICON_WIFI"
else
    icon="$ICON_ETHERNET"
fi

echo "%{F$ACCENT}$icon%{F-} %{F$FG}$ip%{F-}"
