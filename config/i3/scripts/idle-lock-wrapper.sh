#!/usr/bin/env bash
#
# The locker command xss-lock runs when the X screensaver activates
# (the timeout xinitrc sets via `xset s`). Gated behind
# idle-lock-enabled so the "Auto-Lock" toggle in rofi-idle.sh can
# disable locking while still letting the screen blank/DPMS-off on
# its own timer -- xss-lock treats this exiting cleanly as "nothing to
# lock", so the screen still goes dark, it just doesn't lock.

[ "$(cat ~/.cache/idle-lock-enabled 2>/dev/null)" = "0" ] && exit 0
exec betterlockscreen -l dim
