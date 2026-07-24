#!/usr/bin/env bash

# ── Rofi Power Menu ────────────────────────────────────────────

dir="~/.config/rofi/icons"
confirm_exit="confirm"

# Options (Font Awesome glyphs)
shutdown=$'  Shutdown'
reboot=$'  Reboot'
lock=$'  Lock'
suspend=$'  Suspend'
logout=$'  Logout'
hibernate=$'  Hibernate'

# Variable passed to rofi
options="$shutdown\n$reboot\n$lock\n$suspend\n$hibernate\n$logout"

selected="$(echo -e "$options" | rofi -dmenu \
    -i \
    -p "Power Menu:" \
    -theme ~/.config/rofi/themes/current.rasi \
    -no-config \
    -lines 6)"

case $selected in
    *Shutdown*)
        systemctl poweroff
        ;;
    *Reboot*)
        systemctl reboot
        ;;
    *Lock*)
        betterlockscreen -l dim
        ;;
    *Suspend*)
        systemctl suspend
        ;;
    *Hibernate*)
        systemctl hibernate
        ;;
    *Logout*)
        i3-msg exit
        ;;
esac
