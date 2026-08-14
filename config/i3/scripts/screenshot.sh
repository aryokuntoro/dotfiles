#!/usr/bin/env bash

# ── Screenshot with slop + ffmpeg ──────────────────────────────
dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
timestamp=$(date +"%Y%m%d_%H%M%S")

# Size of the whole X screen, e.g. "1920x1080". Read from xrandr's
# "Screen 0: ... current 1920 x 1080 ..." line rather than from the
# first connected output: with two monitors the desktop is the union
# of both, and taking the first output's mode would have cropped
# "Full Screen" down to just that one panel.
screen_size() {
    xrandr --query | grep -m1 '^Screen' | grep -oP 'current \K\d+ x \d+' | tr -d ' '
}

# Rofi menu for screenshot options
options=" Full Screen\n  Select Area\n  Pick Window\n  Active Window\n  Full Screen + Copy\n  Select Area + Copy\n  Pick Window + Copy"

choice=$(echo -e "$options" | rofi -dmenu -i -p "Screenshot:" \
    -theme ~/.config/rofi/themes/current.rasi -no-config -lines 7)

# The "+ Copy" arms MUST stay above the plain ones: every pattern here
# is wrapped in *...*, so *Full\ Screen* also matches the menu string
# " Full Screen + Copy". With the plain arms first, both Copy entries
# were unreachable -- picking them silently wrote a file instead of
# putting the image on the clipboard.
case "$choice" in
    *Full\ Screen\ +\ Copy*)
        ffmpeg -f x11grab -video_size "$(screen_size)" \
            -framerate 1 -i "$DISPLAY" -vframes 1 -f image2pipe -vcodec png - 2>/dev/null | xclip -selection clipboard -t image/png
        notify-send "  Screenshot" "Copied to clipboard"
        ;;
    *Select\ Area\ +\ Copy*)
        # -t 0 disables slop's click-to-select-a-window fallback (its
        # default tolerance of 2px still lets a very still/precise click
        # snap to whatever window is under the cursor instead of the
        # dragged rectangle) -- Select Area should always be a free-form
        # drag, never accidentally snap to a whole window the way Pick
        # Window's -t 999999 deliberately does.
        selection=$(slop -t 0 -f "%x,%y,%w,%h" -b 2 -c 0.8,0.8,0.8,0.5 -l)
        if [ -n "$selection" ]; then
            IFS=',' read -r x y w h <<< "$selection"
            ffmpeg -f x11grab -video_size "${w}x${h}" -framerate 1 \
                -i "$DISPLAY+$x,$y" -vframes 1 -f image2pipe -vcodec png - 2>/dev/null | xclip -selection clipboard -t image/png
            notify-send "  Screenshot" "Copied to clipboard"
        fi
        ;;
    *Pick\ Window\ +\ Copy*)
        # -t 999999 forces slop into click-only (no drag) window-picking
        # mode: click any visible window, even an unfocused one, to grab
        # its bounds -- unlike "Active Window", which can only capture
        # whichever window already has focus. -n strips window manager
        # decorations from the pick so the capture is just the window's
        # own content, matching what "Active Window" grabs.
        selection=$(slop -t 999999 -n -f "%x,%y,%w,%h" -b 2 -c 0.8,0.8,0.8,0.5 -l)
        if [ -n "$selection" ]; then
            IFS=',' read -r x y w h <<< "$selection"
            ffmpeg -f x11grab -video_size "${w}x${h}" -framerate 1 \
                -i "$DISPLAY+$x,$y" -vframes 1 -f image2pipe -vcodec png - 2>/dev/null | xclip -selection clipboard -t image/png
            notify-send "  Screenshot" "Copied to clipboard"
        fi
        ;;
    *Full\ Screen*)
        ffmpeg -f x11grab -video_size "$(screen_size)" \
            -framerate 1 -i "$DISPLAY" -vframes 1 "$dir/screenshot_$timestamp.png" -y 2>/dev/null
        notify-send "  Screenshot" "Saved: $dir/screenshot_$timestamp.png"
        ;;
    *Select\ Area*)
        # -t 0 disables slop's click-to-select-a-window fallback (its
        # default tolerance of 2px still lets a very still/precise click
        # snap to whatever window is under the cursor instead of the
        # dragged rectangle) -- Select Area should always be a free-form
        # drag, never accidentally snap to a whole window the way Pick
        # Window's -t 999999 deliberately does.
        selection=$(slop -t 0 -f "%x,%y,%w,%h" -b 2 -c 0.8,0.8,0.8,0.5 -l)
        if [ -n "$selection" ]; then
            IFS=',' read -r x y w h <<< "$selection"
            ffmpeg -f x11grab -video_size "${w}x${h}" -framerate 1 \
                -i "$DISPLAY+$x,$y" -vframes 1 "$dir/screenshot_$timestamp.png" -y 2>/dev/null
            notify-send "  Screenshot" "Saved: $dir/screenshot_$timestamp.png"
        fi
        ;;
    *Pick\ Window*)
        selection=$(slop -t 999999 -n -f "%x,%y,%w,%h" -b 2 -c 0.8,0.8,0.8,0.5 -l)
        if [ -n "$selection" ]; then
            IFS=',' read -r x y w h <<< "$selection"
            ffmpeg -f x11grab -video_size "${w}x${h}" -framerate 1 \
                -i "$DISPLAY+$x,$y" -vframes 1 "$dir/screenshot_$timestamp.png" -y 2>/dev/null
            notify-send "  Screenshot" "Saved: $dir/screenshot_$timestamp.png"
        fi
        ;;
    *Active\ Window*)
        active=$(xdotool getactivewindow)
        # Keys are anchored (^X=/^Y=) so the position parse cannot pick
        # up some other key that merely contains an X or a Y, and the
        # geometry is queried once instead of twice -- the window could
        # move or resize between two separate xdotool calls.
        geom=$(xdotool getwindowgeometry --shell "$active")
        size=$(printf '%s\n' "$geom" | grep -E '^(WIDTH|HEIGHT)=' | cut -d= -f2 | tr '\n' 'x' | sed 's/x$//')
        pos=$(printf '%s\n' "$geom" | grep -E '^(X|Y)=' | cut -d= -f2 | tr '\n' ',' | sed 's/,$//')
        ffmpeg -f x11grab -video_size "$size" \
            -framerate 1 -i "$DISPLAY+$pos" \
            -vframes 1 "$dir/screenshot_$timestamp.png" -y 2>/dev/null
        notify-send "  Screenshot" "Saved: $dir/screenshot_$timestamp.png"
        ;;
esac
