#!/usr/bin/env bash

# ── Screen Recording with ffmpeg + Rofi ────────────────────────
dir="$HOME/Videos/Recordings"
mkdir -p "$dir"
timestamp=$(date +"%Y%m%d_%H%M%S")
output="$dir/recording_$timestamp.mp4"
pidfile="/tmp/ffmpeg_record.pid"

# The pidfile holds two lines: the ffmpeg pid, and the file it is
# actually writing. Both are needed at stop time -- $output and
# $timestamp above are recomputed on every run of this script, so the
# stop branch used to report a filename that was generated seconds
# earlier and never existed on disk (and always ".mp4", even when the
# recording in progress was a GIF).
save_rec() {
    printf '%s\n%s\n' "$1" "$2" > "$pidfile"
}
theme="$HOME/.config/rofi/themes/current.rasi"

# Check if already recording
if [ -f "$pidfile" ]; then
    choice=$(echo -e "  Stop Recording\n  Cancel" | rofi -dmenu -i -p "Recording Active:" \
        -theme "$theme" -no-config -lines 2)
    if [[ "$choice" == *"Stop"* ]]; then
        { read -r rec_pid; read -r rec_file; } < "$pidfile"
        kill "$rec_pid" 2>/dev/null
        rm -f "$pidfile"
        notify-send "  Recording" "Stopped. Saved: ${rec_file:-$dir}"
    fi
    exit 0
fi

# Recording options
options="  Full Screen Video\n  Select Area Video\n  Full Screen + Audio\n  Select Area + Audio\n  Full Screen + Webcam\n  Select Area + Webcam\n  GIF Full Screen\n  GIF Select Area"

choice=$(echo -e "$options" | rofi -dmenu -i -p "Record:" \
    -theme "$theme" -no-config -lines 8)
[ -z "$choice" ] && exit 0

# Get screen resolution
res=$(xrandr --query | grep ' connected' | grep -o '[0-9]*x[0-9]*' | head -1)

# ── Video quality/resolution/framerate prompts (video modes only) ──
scale_vf=""
framerate="30"
vcodec_opts=(-c:v libx264 -preset fast -crf 23)

if [[ "$choice" == *Video* || "$choice" == *Webcam* || "$choice" == *Audio* ]]; then
    res_choice=$(printf 'Native (%s)\n1920x1080\n1280x720\n854x480\n' "$res" | \
        rofi -dmenu -i -p "Resolution:" -theme "$theme" -no-config -lines 4)
    [ -z "$res_choice" ] && exit 0
    case "$res_choice" in
        1920x1080 | 1280x720 | 854x480) scale_vf="scale=$res_choice" ;;
    esac

    fps_choice=$(printf '60\n30\n24\n15\n' | \
        rofi -dmenu -i -p "Framerate (fps):" -theme "$theme" -no-config -lines 4)
    [ -z "$fps_choice" ] && exit 0
    framerate="$fps_choice"

    quality_choice=$(printf 'High Quality (CRF 18)\nBalanced (CRF 23)\nSmall File (CRF 28)\nCustom Bitrate...\n' | \
        rofi -dmenu -i -p "Quality:" -theme "$theme" -no-config -lines 4)
    [ -z "$quality_choice" ] && exit 0
    case "$quality_choice" in
        "High Quality"*) vcodec_opts=(-c:v libx264 -preset fast -crf 18) ;;
        "Small File"*)   vcodec_opts=(-c:v libx264 -preset fast -crf 28) ;;
        "Custom Bitrate"*)
            bitrate=$(rofi -dmenu -p "Bitrate (e.g. 8M, 4000k):" -theme "$theme" -no-config -lines 0)
            [ -z "$bitrate" ] && exit 0
            vcodec_opts=(-c:v libx264 -preset fast -b:v "$bitrate")
            ;;
        *) vcodec_opts=(-c:v libx264 -preset fast -crf 23) ;;
    esac
fi

# ── GIF width/fps prompts (GIF modes only) ─────────────────────────
gif_width="800"
gif_fps="10"
if [[ "$choice" == *GIF* ]]; then
    gif_width_choice=$(printf '480\n640\n800\n1024\n' | \
        rofi -dmenu -i -p "GIF Width (px):" -theme "$theme" -no-config -lines 4)
    [ -z "$gif_width_choice" ] && exit 0
    gif_width="$gif_width_choice"

    gif_fps_choice=$(printf '10\n15\n20\n' | \
        rofi -dmenu -i -p "GIF Framerate (fps):" -theme "$theme" -no-config -lines 3)
    [ -z "$gif_fps_choice" ] && exit 0
    gif_fps="$gif_fps_choice"
fi

case "$choice" in
    *Full\ Screen\ Video*)
        ffmpeg -f x11grab -video_size "$res" -framerate "$framerate" -i "$DISPLAY" \
            ${scale_vf:+-vf "$scale_vf"} "${vcodec_opts[@]}" "$output" -y &
        save_rec "$!" "$output"
        notify-send "  Recording" "Started: Full Screen Video"
        ;;
    *Select\ Area\ Video*)
        # -t 0 disables slop's click-to-select-a-window fallback (its
        # default tolerance still lets a very still/precise click snap to
        # whatever window is under the cursor instead of the dragged
        # rectangle) -- these are all "select an area" arms and should
        # always be a free-form drag, same reasoning as screenshot.sh's
        # Select Area vs. Pick Window.
        selection=$(slop -t 0 -f "%x,%y,%w,%h" -b 2 -c 0.8,0.8,0.8,0.5 -l)
        if [ -n "$selection" ]; then
            IFS=',' read -r x y w h <<< "$selection"
            ffmpeg -f x11grab -video_size "${w}x${h}" -framerate "$framerate" \
                -i "$DISPLAY+$x,$y" ${scale_vf:+-vf "$scale_vf"} "${vcodec_opts[@]}" "$output" -y &
            save_rec "$!" "$output"
            notify-send "  Recording" "Started: Select Area Video"
        fi
        ;;
    *Full\ Screen\ +\ Audio*)
        ffmpeg -f x11grab -video_size "$res" -framerate "$framerate" -i "$DISPLAY" \
            -f pulse -i default ${scale_vf:+-vf "$scale_vf"} "${vcodec_opts[@]}" \
            -c:a aac -b:a 128k "$output" -y &
        save_rec "$!" "$output"
        notify-send "  Recording" "Started: Full Screen + Audio"
        ;;
    *Select\ Area\ +\ Audio*)
        # -t 0 disables slop's click-to-select-a-window fallback (its
        # default tolerance still lets a very still/precise click snap to
        # whatever window is under the cursor instead of the dragged
        # rectangle) -- these are all "select an area" arms and should
        # always be a free-form drag, same reasoning as screenshot.sh's
        # Select Area vs. Pick Window.
        selection=$(slop -t 0 -f "%x,%y,%w,%h" -b 2 -c 0.8,0.8,0.8,0.5 -l)
        if [ -n "$selection" ]; then
            IFS=',' read -r x y w h <<< "$selection"
            ffmpeg -f x11grab -video_size "${w}x${h}" -framerate "$framerate" \
                -i "$DISPLAY+$x,$y" -f pulse -i default \
                ${scale_vf:+-vf "$scale_vf"} "${vcodec_opts[@]}" -c:a aac -b:a 128k "$output" -y &
            save_rec "$!" "$output"
            notify-send "  Recording" "Started: Select Area + Audio"
        fi
        ;;
    *Full\ Screen\ +\ Webcam*)
        webcam_res="320x240"
        webcam_pos="main_w-overlay_w-10:10"
        if [ -n "$scale_vf" ]; then
            filter="[0:v]${scale_vf}[bg];[bg][1:v]overlay=$webcam_pos"
        else
            filter="[0:v][1:v]overlay=$webcam_pos"
        fi
        ffmpeg -f x11grab -video_size "$res" -framerate "$framerate" -i "$DISPLAY" \
            -f v4l2 -video_size "$webcam_res" -i /dev/video0 \
            -filter_complex "$filter" \
            "${vcodec_opts[@]}" "$output" -y &
        save_rec "$!" "$output"
        notify-send "  Recording" "Started: Full Screen + Webcam"
        ;;
    *Select\ Area\ +\ Webcam*)
        # -t 0 disables slop's click-to-select-a-window fallback (its
        # default tolerance still lets a very still/precise click snap to
        # whatever window is under the cursor instead of the dragged
        # rectangle) -- these are all "select an area" arms and should
        # always be a free-form drag, same reasoning as screenshot.sh's
        # Select Area vs. Pick Window.
        selection=$(slop -t 0 -f "%x,%y,%w,%h" -b 2 -c 0.8,0.8,0.8,0.5 -l)
        if [ -n "$selection" ]; then
            IFS=',' read -r x y w h <<< "$selection"
            webcam_res="320x240"
            webcam_pos="main_w-overlay_w-10:10"
            if [ -n "$scale_vf" ]; then
                filter="[0:v]${scale_vf}[bg];[bg][1:v]overlay=$webcam_pos"
            else
                filter="[0:v][1:v]overlay=$webcam_pos"
            fi
            ffmpeg -f x11grab -video_size "${w}x${h}" -framerate "$framerate" \
                -i "$DISPLAY+$x,$y" \
                -f v4l2 -video_size "$webcam_res" -i /dev/video0 \
                -filter_complex "$filter" \
                "${vcodec_opts[@]}" "$output" -y &
            save_rec "$!" "$output"
            notify-send "  Recording" "Started: Select Area + Webcam"
        fi
        ;;
    *GIF\ Full\ Screen*)
        gif_output="$dir/recording_$timestamp.gif"
        ffmpeg -f x11grab -video_size "$res" -framerate "$gif_fps" -i "$DISPLAY" \
            -vf "fps=$gif_fps,scale=$gif_width:-1:flags=lanczos" -loop 0 "$gif_output" -y &
        save_rec "$!" "$gif_output"
        notify-send "  Recording" "Started: GIF Full Screen"
        ;;
    *GIF\ Select\ Area*)
        # -t 0 disables slop's click-to-select-a-window fallback (its
        # default tolerance still lets a very still/precise click snap to
        # whatever window is under the cursor instead of the dragged
        # rectangle) -- these are all "select an area" arms and should
        # always be a free-form drag, same reasoning as screenshot.sh's
        # Select Area vs. Pick Window.
        selection=$(slop -t 0 -f "%x,%y,%w,%h" -b 2 -c 0.8,0.8,0.8,0.5 -l)
        if [ -n "$selection" ]; then
            IFS=',' read -r x y w h <<< "$selection"
            gif_output="$dir/recording_$timestamp.gif"
            ffmpeg -f x11grab -video_size "${w}x${h}" -framerate "$gif_fps" \
                -i "$DISPLAY+$x,$y" -vf "fps=$gif_fps,scale=$gif_width:-1:flags=lanczos" \
                -loop 0 "$gif_output" -y &
            save_rec "$!" "$gif_output"
            notify-send "  Recording" "Started: GIF Select Area"
        fi
        ;;
esac
