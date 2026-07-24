#!/usr/bin/env bash

# ── Theme Switcher via Rofi ───────────────────────────────────
# Supports: Catppuccin, TokyoNight, Gruvbox, Nord
# Colors are taken directly from each theme's .rasi palette
# (no wallpaper/pywal dependency).

rofi_dir="$HOME/.config/rofi/themes"
current_link="$rofi_dir/current.rasi"

# Theme options
themes="Catppuccin Mocha
Catppuccin Frappe
Catppuccin Macchiato
Catppuccin Latte
TokyoNight Night
TokyoNight Storm
TokyoNight Moon
TokyoNight Day
Gruvbox Dark
Gruvbox Light
Nord Dark
Nord Light"

selected=$(echo -e "$themes" | rofi -dmenu -i -p "Theme:" \
    -theme "$rofi_dir/current.rasi" -no-config -lines 12)

# Convert selection to theme file name
case "$selected" in
    "Catppuccin Mocha")     theme_file="catppuccin-mocha.rasi" ;;
    "Catppuccin Frappe")    theme_file="catppuccin-frappe.rasi" ;;
    "Catppuccin Macchiato") theme_file="catppuccin-macchiato.rasi" ;;
    "Catppuccin Latte")     theme_file="catppuccin-latte.rasi" ;;
    "TokyoNight Night")     theme_file="tokyonight-night.rasi" ;;
    "TokyoNight Storm")     theme_file="tokyonight-storm.rasi" ;;
    "TokyoNight Moon")      theme_file="tokyonight-moon.rasi" ;;
    "TokyoNight Day")       theme_file="tokyonight-day.rasi" ;;
    "Gruvbox Dark")         theme_file="gruvbox-dark.rasi" ;;
    "Gruvbox Light")        theme_file="gruvbox-light.rasi" ;;
    "Nord Dark")            theme_file="nord-dark.rasi" ;;
    "Nord Light")           theme_file="nord-light.rasi" ;;
    *)                      exit 0 ;;
esac

# Update rofi theme symlink
ln -sf "$rofi_dir/$theme_file" "$current_link"

# Apply this theme's palette to i3, dunst, polybar, Xresources, kitty and GTK
~/.config/i3/scripts/apply-theme-colors.sh "$rofi_dir/$theme_file"

# Save current theme
echo "$selected" > ~/.config/current_theme

# Reload picom
killall picom 2>/dev/null
picom -b --config ~/.config/picom/picom.conf

notify-send "  Theme Changed" "$selected"
