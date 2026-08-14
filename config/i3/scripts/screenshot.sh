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

# Height in px of the polybar bar at the top of the screen, or empty if
# it isn't running. Queried live via xdotool rather than read out of
# polybar/config.ini's `height = 28pt`: that value is in points, and the
# actual pixel height it resolves to moves with Xft.dpi (rofi-monitor.sh's
# Scale menu), so a number copied from the config would drift out of
# sync with reality the next time the DPI changes.
#
# --classname (WM_CLASS *instance*, not class) matters here: polybar's
# systray also carries WM_CLASS class "Polybar", as its own small
# window docked at the bar's right edge -- matching on --class would
# occasionally pick that one instead depending on search order, giving
# a nonsense (tray-width, bar-height) exclusion. The instance name for
# the bar itself is "polybar"; the tray's is "tray".
polybar_height() {
    local win
    win=$(xdotool search --classname polybar 2>/dev/null | head -1)
    [ -n "$win" ] || return 1
    xdotool getwindowgeometry --shell "$win" 2>/dev/null | grep '^HEIGHT=' | cut -d= -f2
}

# Full screen, minus the polybar strip -- everything i3 actually tiles
# windows into, which on a tiling WM is however many windows happen to
# be visible in the current workspace (all of them, not just one), not
# a single picked window. Prints "WxH X,Y" as one space-separated line
# -- read -r var1 var2 splits *one* line on whitespace into multiple
# variables, it does not read a second line into a second variable, so
# this has to be one echo, not two. Falls back to the full screen
# untouched if polybar isn't running to ask.
pick_window_geometry() {
    local screen sw sh bar_h
    screen=$(screen_size)
    sw=${screen%x*}
    sh=${screen#*x}
    bar_h=$(polybar_height)
    if [[ "$bar_h" =~ ^[0-9]+$ ]] && [ "$bar_h" -lt "$sh" ]; then
        echo "${sw}x$((sh - bar_h)) 0,$bar_h"
    else
        echo "$screen 0,0"
    fi
}

# Rofi menu for screenshot options
options=" Full Screen\n  Select Area\n  Pick Window\n  Active Window\n  Full Screen + Copy\n  Select Area + Copy\n  Pick Window + Copy\n  Active Window + Copy"

choice=$(echo -e "$options" | rofi -dmenu -i -p "Screenshot:" \
    -theme ~/.config/rofi/themes/current.rasi -no-config -lines 8)

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
        read -r size pos < <(pick_window_geometry)
        ffmpeg -f x11grab -video_size "$size" -framerate 1 \
            -i "$DISPLAY+$pos" -vframes 1 -f image2pipe -vcodec png - 2>/dev/null | xclip -selection clipboard -t image/png
        notify-send "  Screenshot" "Copied to clipboard"
        ;;
    *Active\ Window\ +\ Copy*)
        active=$(xdotool getactivewindow)
        geom=$(xdotool getwindowgeometry --shell "$active")
        size=$(printf '%s\n' "$geom" | grep -E '^(WIDTH|HEIGHT)=' | cut -d= -f2 | tr '\n' 'x' | sed 's/x$//')
        pos=$(printf '%s\n' "$geom" | grep -E '^(X|Y)=' | cut -d= -f2 | tr '\n' ',' | sed 's/,$//')
        ffmpeg -f x11grab -video_size "$size" \
            -framerate 1 -i "$DISPLAY+$pos" \
            -vframes 1 -f image2pipe -vcodec png - 2>/dev/null | xclip -selection clipboard -t image/png
        notify-send "  Screenshot" "Copied to clipboard"
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
        read -r size pos < <(pick_window_geometry)
        ffmpeg -f x11grab -video_size "$size" -framerate 1 \
            -i "$DISPLAY+$pos" -vframes 1 "$dir/screenshot_$timestamp.png" -y 2>/dev/null
        notify-send "  Screenshot" "Saved: $dir/screenshot_$timestamp.png"
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
