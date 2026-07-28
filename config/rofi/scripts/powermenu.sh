#!/usr/bin/env bash

# ── Rofi Power Menu ────────────────────────────────────────────

dir="~/.config/rofi/icons"
confirm_exit="confirm"

# Options -- icon glyphs only, no text label
shutdown=$''
reboot=$''
lock=$''
suspend=$''
logout=$''
hibernate=$''

# Variable passed to rofi
options="$shutdown\n$reboot\n$lock\n$suspend\n$hibernate\n$logout"

selected="$(echo -e "$options" | rofi -dmenu \
    -i \
    -p "Power Menu:" \
    -theme ~/.config/rofi/themes/powermenu.rasi \
    -no-config)"

case "$selected" in
    "$shutdown")
        systemctl poweroff
        ;;
    "$reboot")
        systemctl reboot
        ;;
    "$lock")
        betterlockscreen -l dim
        ;;
    "$suspend")
        systemctl suspend
        ;;
    "$hibernate")
        systemctl hibernate
        ;;
    "$logout")
        i3-msg exit
        ;;
esac
