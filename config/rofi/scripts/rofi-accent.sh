#!/usr/bin/env bash
#
# Accent color picker for the active theme family ($mod+F8).
# Independent of theme-switch.sh: pick a flavor/mode there first, then
# use this to swap which color that family already ships is used as
# the UI accent, without changing anything else. The actual hex
# lookup and GTK folder resolution both live in
# apply-theme-colors.sh -- this script only lists names and persists
# the choice, so there's one source of truth for the data.

ACCENT_CACHE="$HOME/.cache/theme-accent"
current_link="$HOME/.config/rofi/themes/current.rasi"
rofi_command="rofi -theme ~/.config/rofi/themes/current.rasi -dmenu -p"

if [ ! -L "$current_link" ]; then
    notify-send "  Accent" "No active theme -- pick one with the theme switcher first"
    exit 1
fi

theme_file=$(basename "$(readlink -f "$current_link")")

case "$theme_file" in
    catppuccin-*.rasi) family="catppuccin" ;;
    tokyonight-*.rasi) family="tokyonight" ;;
    gruvbox-*.rasi)     family="gruvbox" ;;
    everforest-*.rasi)  family="everforest" ;;
    nord-*.rasi)        family="nordic" ;;
    *)                  family="" ;;
esac

case "$family" in
    catppuccin)
        accents="Default
Rosewater
Flamingo
Pink
Mauve
Red
Maroon
Peach
Yellow
Green
Teal
Sky
Sapphire
Blue
Lavender
Grey" ;;
    gruvbox | tokyonight | everforest)
        accents="Default
Red
Pink
Purple
Blue
Teal
Green
Yellow
Orange
Grey" ;;
    nordic)
        notify-send "  Accent" "Nordic doesn't have accent variants"
        exit 0 ;;
    *)
        notify-send "  Accent" "No active theme -- pick one with the theme switcher first"
        exit 1 ;;
esac

chosen=$(echo -e "$accents" | $rofi_command "Accent ($family)")
[ -z "$chosen" ] && exit 0

echo "$chosen" | tr '[:upper:]' '[:lower:]' > "$ACCENT_CACHE"

~/.config/i3/scripts/apply-theme-colors.sh "$(readlink -f "$current_link")"
notify-send "  Accent" "$chosen"
