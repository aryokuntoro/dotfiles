#!/usr/bin/env bash
#
# Rofi menu for the idle screen-off timer and whether it also locks the
# screen. Two independent settings, both applied immediately and
# persisted so xinitrc/idle-lock-wrapper.sh pick them up on next login
# and next screensaver activation respectively:
#   - Screen Timeout: how long until `xset s`/DPMS blanks the screen
#     ("Never" disables the timer -- see toggle-idle.sh for a one-key
#     shortcut that does the same thing).
#   - Auto-Lock on Blank: whether xss-lock actually runs the locker
#     when that timeout fires, independent of the timeout itself.
# Sleep/Hibernate live in powermenu.sh instead, not here.

TIMEOUT_CACHE="$HOME/.cache/idle-timeout"
LOCK_CACHE="$HOME/.cache/idle-lock-enabled"
ICON_TIMER=$''
ICON_LOCK=$''
divider="---------"
goback=" Back"

rofi_command="rofi -theme ~/.config/rofi/themes/current.rasi -dmenu $* -p"

current_timeout() {
    local t
    t=$(cat "$TIMEOUT_CACHE" 2>/dev/null)
    [[ "$t" =~ ^[0-9]+$ ]] || t=600
    echo "$t"
}

current_lock_enabled() {
    [ "$(cat "$LOCK_CACHE" 2>/dev/null)" = "0" ] && echo "0" || echo "1"
}

label_for_timeout() {
    local secs="$1"
    if [ "$secs" -eq 0 ]; then
        echo "Never"
    elif [ "$secs" -ge 3600 ] && [ "$((secs % 3600))" -eq 0 ]; then
        local hrs=$((secs / 3600))
        echo "$hrs hour$([ "$hrs" -ne 1 ] && echo s)"
    else
        echo "$((secs / 60)) min"
    fi
}

apply_timeout() {
    local secs="$1"
    echo "$secs" > "$TIMEOUT_CACHE"
    if [ "$secs" -eq 0 ]; then
        xset s off
        xset -dpms
    else
        xset s "$secs" "$secs"
        xset dpms "$secs" "$secs" "$secs"
    fi
}

timeout_menu() {
    local cur options chosen secs=""
    cur=$(current_timeout)
    options="1 min\n5 min\n10 min\n15 min\n30 min\n1 hour\n2 hours\n3 hours\n4 hours\n5 hours\nNever\n$divider\n$goback\nExit"

    chosen=$(echo -e "$options" | $rofi_command "Screen Timeout (current: $(label_for_timeout "$cur"))")
    case "$chosen" in
        "1 min") secs=60 ;;
        "5 min") secs=300 ;;
        "10 min") secs=600 ;;
        "15 min") secs=900 ;;
        "30 min") secs=1800 ;;
        "1 hour") secs=3600 ;;
        "2 hours") secs=7200 ;;
        "3 hours") secs=10800 ;;
        "4 hours") secs=14400 ;;
        "5 hours") secs=18000 ;;
        "Never") secs=0 ;;
        "$goback" | "" | "$divider") show_menu; return ;;
        "Exit") exit 0 ;;
    esac

    if [ -n "$secs" ]; then
        apply_timeout "$secs"
        notify-send "$ICON_TIMER  Screen Timeout" "Set to $(label_for_timeout "$secs")"
    fi
    show_menu
}

toggle_lock() {
    local new
    new=$([ "$(current_lock_enabled)" = "1" ] && echo 0 || echo 1)
    echo "$new" > "$LOCK_CACHE"
    notify-send "$ICON_LOCK  Auto-Lock" "$([ "$new" = "1" ] && echo Enabled || echo Disabled)"
    show_menu
}

show_menu() {
    local timeout_label lock_label options chosen
    timeout_label="Screen Timeout: $(label_for_timeout "$(current_timeout)")"
    lock_label="Auto-Lock on Blank: $([ "$(current_lock_enabled)" = "1" ] && echo On || echo Off)"

    options="$timeout_label\n$lock_label\n$divider\nExit"
    chosen=$(echo -e "$options" | $rofi_command "Idle & Lock")

    case "$chosen" in
        "$timeout_label") timeout_menu ;;
        "$lock_label") toggle_lock ;;
        "" | "$divider" | "Exit") exit 0 ;;
    esac
}

show_menu
