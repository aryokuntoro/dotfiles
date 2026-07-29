#!/usr/bin/env bash
#
# Quick "presentation mode" toggle ($mod+Shift+x): disables the
# screen-off timer entirely (and with it the auto-lock that rides on
# the same X screensaver event, since xss-lock only fires when it
# activates), remembering the prior timeout to restore on next toggle.
# For per-duration control or to toggle auto-lock independent of the
# timer, use rofi-idle.sh ($mod+F7) instead.

TIMEOUT_CACHE="$HOME/.cache/idle-timeout"
PREV_CACHE="$HOME/.cache/idle-timeout-prev"
ICON_TIMER=$''

cur=$(cat "$TIMEOUT_CACHE" 2>/dev/null)
[[ "$cur" =~ ^[0-9]+$ ]] || cur=600

if [ "$cur" -eq 0 ]; then
    prev=$(cat "$PREV_CACHE" 2>/dev/null)
    [[ "$prev" =~ ^[0-9]+$ ]] && [ "$prev" -gt 0 ] || prev=600
    xset s "$prev" "$prev"
    xset dpms "$prev" "$prev" "$prev"
    echo "$prev" > "$TIMEOUT_CACHE"
    notify-send "$ICON_TIMER  Screen Timeout" "Enabled ($((prev / 60)) min)"
else
    echo "$cur" > "$PREV_CACHE"
    xset s off
    xset -dpms
    echo 0 > "$TIMEOUT_CACHE"
    notify-send "$ICON_TIMER  Screen Timeout" "Disabled (presentation mode)"
fi
