#!/usr/bin/env bash

# ── Streaming with ffmpeg + Rofi ──────────────────────────────
pidfile="/tmp/ffmpeg_stream.pid"

# Check if already streaming
if [ -f "$pidfile" ]; then
    choice=$(echo -e "  Stop Stream\n  Cancel" | rofi -dmenu -i -p "Stream Active:" \
        -theme ~/.config/rofi/themes/current.rasi -no-config -lines 2)
    if [[ "$choice" == *"Stop"* ]]; then
        kill "$(cat "$pidfile")" 2>/dev/null
        rm -f "$pidfile"
        notify-send "  Stream" "Stopped."
    fi
    exit 0
fi

# Stream options
options="  Twitch\n  YouTube\n  Custom RTMP\n  Local File Stream\n  Screen + Webcam + Audio\n  Screen + Audio Only"

choice=$(echo -e "$options" | rofi -dmenu -i -p "Stream to:" \
    -theme ~/.config/rofi/themes/current.rasi -no-config -lines 6)

res=$(xrandr --query | grep ' connected' | grep -o '[0-9]*x[0-9]*' | head -1)

case "$choice" in
    *Twitch*)
        stream_key=$(rofi -dmenu -i -p "Twitch Stream Key:" \
            -theme ~/.config/rofi/themes/current.rasi -no-config -password)
        if [ -n "$stream_key" ]; then
            ffmpeg -f x11grab -video_size "$res" -framerate 30 -i "$DISPLAY" \
                -f pulse -i default -c:v libx264 -preset fast -b:v 3000k \
                -maxrate 3000k -bufsize 6000k -pix_fmt yuv420p -g 60 \
                -c:a aac -b:a 128k -ar 44100 -f flv \
                "rtmp://live.twitch.tv/app/$stream_key" &
            echo $! > "$pidfile"
            notify-send "  Stream" "Started streaming to Twitch"
        fi
        ;;
    *YouTube*)
        stream_key=$(rofi -dmenu -i -p "YouTube Stream Key:" \
            -theme ~/.config/rofi/themes/current.rasi -no-config -password)
        if [ -n "$stream_key" ]; then
            ffmpeg -f x11grab -video_size "$res" -framerate 30 -i "$DISPLAY" \
                -f pulse -i default -c:v libx264 -preset fast -b:v 3000k \
                -maxrate 3000k -bufsize 6000k -pix_fmt yuv420p -g 60 \
                -c:a aac -b:a 128k -ar 44100 -f flv \
                "rtmp://a.rtmp.youtube.com/live2/$stream_key" &
            echo $! > "$pidfile"
            notify-send "  Stream" "Started streaming to YouTube"
        fi
        ;;
    *Custom\ RTMP*)
        rtmp_url=$(rofi -dmenu -i -p "RTMP URL:" \
            -theme ~/.config/rofi/themes/current.rasi -no-config)
        if [ -n "$rtmp_url" ]; then
            ffmpeg -f x11grab -video_size "$res" -framerate 30 -i "$DISPLAY" \
                -f pulse -i default -c:v libx264 -preset fast -b:v 3000k \
                -maxrate 3000k -bufsize 6000k -pix_fmt yuv420p -g 60 \
                -c:a aac -b:a 128k -ar 44100 -f flv "$rtmp_url" &
            echo $! > "$pidfile"
            notify-send "  Stream" "Started streaming to $rtmp_url"
        fi
        ;;
    *Local\ File\ Stream*)
        output_dir="$HOME/Recordings"
        mkdir -p "$output_dir"
        timestamp=$(date +"%Y%m%d_%H%M%S")
        output="$output_dir/stream_$timestamp.mp4"
        ffmpeg -f x11grab -video_size "$res" -framerate 30 -i "$DISPLAY" \
            -f pulse -i default -c:v libx264 -preset fast -crf 23 \
            -c:a aac -b:a 128k "$output" -y &
 echo $! > "$pidfile"
        notify-send "  Stream" "Recording to: $output"
        ;;
    *Screen\ +\ Webcam\ +\ Audio*)
        stream_key=$(rofi -dmenu -i -p "Stream Key / RTMP URL:" \
            -theme ~/.config/rofi/themes/current.rasi -no-config -password)
        if [ -n "$stream_key" ]; then
            webcam_res="320x240"
            ffmpeg -f x11grab -video_size "$res" -framerate 30 -i "$DISPLAY" \
                -f v4l2 -video_size "$webcam_res" -i /dev/video0 \
                -f pulse -i default \
                -filter_complex "[0:v][1:v]overlay=main_w-overlay_w-10:10[v]" \
                -map "[v]" -map 2:a -c:v libx264 -preset fast -b:v 3000k \
                -pix_fmt yuv420p -g 60 -c:a aac -b:a 128k -f flv "$stream_key" &
            echo $! > "$pidfile"
            notify-send "  Stream" "Started: Screen + Webcam + Audio"
        fi
        ;;
    *Screen\ +\ Audio\ Only*)
        stream_key=$(rofi -dmenu -i -p "Stream Key / RTMP URL:" \
            -theme ~/.config/rofi/themes/current.rasi -no-config -password)
        if [ -n "$stream_key" ]; then
            ffmpeg -f x11grab -video_size "$res" -framerate 30 -i "$DISPLAY" \
                -f pulse -i default -c:v libx264 -preset fast -b:v 3000k \
                -pix_fmt yuv420p -g 60 -c:a aac -b:a 128k -f flv "$stream_key" &
            echo $! > "$pidfile"
            notify-send "  Stream" "Started: Screen + Audio"
        fi
        ;;
esac
