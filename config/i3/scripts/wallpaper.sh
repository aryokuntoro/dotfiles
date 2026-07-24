#!/usr/bin/env bash

# ── Wallpaper Selector via Rofi ────────────────────────────────
wall_dir="$HOME/Pictures/Wallpapers"

# Get all images
images=$(find "$wall_dir" -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" -o -name "*.webp" \) | sort)

if [ -z "$images" ]; then
    notify-send "  Wallpaper" "No wallpapers found in $wall_dir"
    exit 1
fi

# Create display names
displays=""
while IFS= read -r img; do
    name=$(basename "$img")
    displays+="$name\n"
done <<< "$images"

# Show rofi menu
selected=$(echo -e "$displays" | rofi -dmenu -i -p "Wallpaper:" \
    -theme ~/.config/rofi/themes/current.rasi -no-config)

if [ -n "$selected" ]; then
    # Find full path
    wallpaper=$(find "$wall_dir" -name "$selected" -type f | head -1)
    
    if [ -n "$wallpaper" ]; then
        # Set wallpaper
        feh --bg-scale "$wallpaper"
        echo "$wallpaper" > ~/.config/i3/current_wallpaper

        notify-send "  Wallpaper" "Changed to: $selected"
    fi
fi
