#!/usr/bin/env bash

# ── Rofi Network Manager ──────────────────────────────────────
# Delegates to NetManagerDM.sh, which actually scans for nearby
# networks (nmcli connection show only lists saved profiles).
#
# Checked here rather than left to NetManagerDM.sh itself: when the
# --config path below doesn't exist, that upstream script silently
# falls back to its own default (~/.config/bspwm/config/NetManagerDM.ini
# -- a leftover from its original bspwm-focused project, unrelated to
# this i3 setup) and, finding no config there either, drops into an
# interactive first-run setup that calls Python's input(). This is
# launched from an i3 keybinding with no terminal attached, so that
# would just hang (or throw EOFError) with nothing on screen -- worth
# catching here with a clear notification instead. Same idea for the
# Python/GObject-Introspection NetworkManager bindings it imports at
# module load time: missing on a fresh/different system, they'd abort
# the whole script with a traceback nobody sees, for a keypress that
# looks like it silently did nothing.
theme="$HOME/.config/rofi/themes/NetManagerDM.ini"
script="$HOME/.config/rofi/scripts/NetManagerDM.sh"

if ! command -v python3 >/dev/null 2>&1; then
    notify-send "  Network" "python3 not found"
    exit 1
fi

if ! python3 -c "import gi; gi.require_version('NM', '1.0'); from gi.repository import NM" 2>/dev/null; then
    notify-send "  Network" "Missing python-gobject / libnm (GObject-Introspection NM bindings)"
    exit 1
fi

if [ ! -f "$theme" ]; then
    notify-send "  Network" "Config not found: $theme -- reinstall the dotfiles (install.sh) to restore it"
    exit 1
fi

exec "$script" --config "$theme"
