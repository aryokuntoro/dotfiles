#!/usr/bin/env bash

# ── Wallpaper Selector via Rofi ────────────────────────────────
wall_dir="$HOME/Pictures/Wallpapers"

# Get all images
images=$(find "$wall_dir" -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" -o -name "*.webp" \) | sort)

if [ -z "$images" ]; then
    notify-send "  Wallpaper" "No wallpapers found in $wall_dir"
    exit 1
fi

# Create display entries with the image itself as the rofi icon, so
# the picker shows an actual thumbnail per wallpaper instead of plain text.
# The basename -> full path mapping is kept here rather than re-`find`-ing
# by name after selection: that treated the selected name as a shell glob
# (breaking on filenames containing *, ?, or [...]), and arbitrarily
# picked whichever match `find`'s traversal order happened to hit first
# when two wallpapers in different subdirectories shared a basename.
declare -A wall_paths
entries=""
while IFS= read -r img; do
    name=$(basename "$img")
    wall_paths["$name"]="$img"
    entries+="$name\x00icon\x1f$img\n"
done <<< "$images"

# Show rofi menu
selected=$(echo -e "$entries" | rofi -dmenu -i -p "Wallpaper:" -show-icons \
    -theme ~/.config/rofi/themes/wallpaper.rasi -no-config)

if [ -n "$selected" ]; then
    wallpaper="${wall_paths[$selected]}"

    if [ -n "$wallpaper" ]; then
        # Set wallpaper
        feh --bg-scale "$wallpaper"
        echo "$wallpaper" > ~/.config/i3/current_wallpaper

        # Keep the lock screen in sync -- takes ~10s to render all the
        # effect variants, so background it instead of blocking here.
        betterlockscreen -u "$wallpaper" >/dev/null 2>&1 &

        notify-send "  Wallpaper" "Changed to: $selected"
    fi
fi
