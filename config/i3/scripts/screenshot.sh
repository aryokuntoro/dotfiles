#!/usr/bin/env bash

# ── Screenshot with slop + ffmpeg ──────────────────────────────
dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
timestamp=$(date +"%Y%m%d_%H%M%S")

# Rofi menu for screenshot options
options=" Full Screen\n  Select Area\n  Active Window\n  Full Screen + Copy\n  Select Area + Copy"

choice=$(echo -e "$options" | rofi -dmenu -i -p "Screenshot:" \
    -theme ~/.config/rofi/themes/current.rasi -no-config -lines 5)

case "$choice" in
    *Full\ Screen*)
        ffmpeg -f x11grab -video_size "$(xrandr --query | grep ' connected' | grep -o '[0-9]*x[0-9]*' | head -1)" \
            -framerate 1 -i "$DISPLAY" -vframes 1 "$dir/screenshot_$timestamp.png" -y 2>/dev/null
        notify-send "  Screenshot" "Saved: $dir/screenshot_$timestamp.png"
        ;;
    *Select\ Area*)
        selection=$(slop -f "%x,%y,%w,%h" -b 2 -c 0.8,0.8,0.8,0.5 -l)
        if [ -n "$selection" ]; then
            IFS=',' read -r x y w h <<< "$selection"
            ffmpeg -f x11grab -video_size "${w}x${h}" -framerate 1 \
                -i "$DISPLAY+$x,$y" -vframes 1 "$dir/screenshot_$timestamp.png" -y 2>/dev/null
            notify-send "  Screenshot" "Saved: $dir/screenshot_$timestamp.png"
        fi
        ;;
    *Active\ Window*)
        active=$(xdotool getactivewindow)
        ffmpeg -f x11grab -video_size "$(xdotool getwindowgeometry --shell $active | grep -E 'WIDTH|HEIGHT' | cut -d= -f2 | tr '\n' 'x' | sed 's/x$//')" \
            -framerate 1 -i "$DISPLAY+$(xdotool getwindowgeometry --shell $active | grep -E 'X|Y' | cut -d= -f2 | tr '\n' ',' | sed 's/,$//')" \
            -vframes 1 "$dir/screenshot_$timestamp.png" -y 2>/dev/null
        notify-send "  Screenshot" "Saved: $dir/screenshot_$timestamp.png"
        ;;
    *Full\ Screen\ +\ Copy*)
        ffmpeg -f x11grab -video_size "$(xrandr --query | grep ' connected' | grep -o '[0-9]*x[0-9]*' | head -1)" \
            -framerate 1 -i "$DISPLAY" -vframes 1 -f image2pipe -vcodec png - 2>/dev/null | xclip -selection clipboard -t image/png
        notify-send "  Screenshot" "Copied to clipboard"
        ;;
    *Select\ Area\ +\ Copy*)
        selection=$(slop -f "%x,%y,%w,%h" -b 2 -c 0.8,0.8,0.8,0.5 -l)
        if [ -n "$selection" ]; then
            IFS=',' read -r x y w h <<< "$selection"
            ffmpeg -f x11grab -video_size "${w}x${h}" -framerate 1 \
                -i "$DISPLAY+$x,$y" -vframes 1 -f image2pipe -vcodec png - 2>/dev/null | xclip -selection clipboard -t image/png
            notify-send "  Screenshot" "Copied to clipboard"
        fi
        ;;
esac
