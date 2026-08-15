#!/usr/bin/env bash

# ── Rofi yt-dlp Downloader ────────────────────────────────────
# Prompts for a URL (pre-filled from the clipboard if it looks
# like one), queries the actual formats available for that URL
# and lists every resolution/fps combo from smallest to largest
# with its source extension, then lets you pick an output format
# to remux/convert to, and runs yt-dlp in a kitty window so the
# progress bar is visible.

theme=~/.config/rofi/themes/current.rasi

clip=$(xclip -o -selection clipboard 2>/dev/null)
[[ "$clip" =~ ^https?:// ]] || clip=""

url=$(echo "$clip" | rofi -dmenu -i -p "yt-dlp URL:" -theme "$theme" -no-config -lines 0)
[ -z "$url" ] && exit 0

notify-send "  yt-dlp" "Fetching available formats..."

info=$(yt-dlp -J --no-warnings --no-playlist "$url" 2>/tmp/yt-dlp-formats.log)
if [ -z "$info" ]; then
    notify-send "  yt-dlp" "Failed to fetch formats -- see /tmp/yt-dlp-formats.log"
    exit 1
fi

# TSV per video format, low to high resolution/fps: id, height, fps, ext, acodec
mapfile -t rows < <(jq -r '
    [.formats[]? | select(.vcodec != "none" and .height != null)]
    | sort_by(.height, (.fps // 0))
    | .[]
    | [.format_id, (.height|tostring), ((.fps // 0)|tostring), .ext, (.acodec // "none")]
    | @tsv
' <<<"$info")

if [ ${#rows[@]} -eq 0 ]; then
    notify-send "  yt-dlp" "No video formats found for this URL."
    exit 1
fi

labels=("  Audio only")
format_ids=("")
has_audio=("")

for row in "${rows[@]}"; do
    IFS=$'\t' read -r fid height fps ext acodec <<<"$row"
    fps_label=""
    [ "$fps" != "0" ] && fps_label="${fps%.*}"
    audio_note="video only"
    [ "$acodec" != "none" ] && audio_note="with audio"
    labels+=("  ${height}p${fps_label} .${ext} ($audio_note)")
    format_ids+=("$fid")
    [ "$acodec" != "none" ] && has_audio+=("yes") || has_audio+=("no")
done

choice=$(printf '%s\n' "${labels[@]}" | rofi -dmenu -i -p "Resolution:" -theme "$theme" -no-config -format i -lines 12)
[ -z "$choice" ] && exit 0
# rofi -format i prints -1 for free text typed that doesn't match any
# listed row, not just for Escape/empty input -- bash silently resolves
# a negative array index to counting from the end instead of erroring,
# so an unrecognized entry used to pick the *last* format/conversion
# option with no indication anything was mistyped. Reject anything
# that isn't a real non-negative row index instead.
[[ "$choice" =~ ^[0-9]+$ ]] || exit 0

if [ "$choice" -eq 0 ]; then
    outdir="$HOME/Music"

    audio_formats=("  Keep original (best)" "  .mp3" "  .m4a" "  .opus" "  .wav" "  .flac")
    afmt_choice=$(printf '%s\n' "${audio_formats[@]}" | rofi -dmenu -i -p "Convert audio to:" -theme "$theme" -no-config -format i -lines 6)
    [ -z "$afmt_choice" ] && exit 0
    [[ "$afmt_choice" =~ ^[0-9]+$ ]] || exit 0

    if [ "$afmt_choice" -eq 0 ]; then
        args=(-x)
    else
        afmt="${audio_formats[$afmt_choice]#*.}"
        args=(-x --audio-format "$afmt")
    fi
else
    outdir="$HOME/Videos"
    fid="${format_ids[$choice]}"
    if [ "${has_audio[$choice]}" = "yes" ]; then
        fargs=(-f "$fid")
    else
        fargs=(-f "${fid}+bestaudio/best")
    fi

    video_formats=("  Keep original (no remux)" "  .mp4" "  .mkv" "  .webm" "  .mov" "  .avi")
    vfmt_choice=$(printf '%s\n' "${video_formats[@]}" | rofi -dmenu -i -p "Convert video to:" -theme "$theme" -no-config -format i -lines 6)
    [ -z "$vfmt_choice" ] && exit 0
    [[ "$vfmt_choice" =~ ^[0-9]+$ ]] || exit 0

    if [ "$vfmt_choice" -eq 0 ]; then
        args=("${fargs[@]}")
    else
        vfmt="${video_formats[$vfmt_choice]#*.}"
        args=("${fargs[@]}" --remux-video "$vfmt")
    fi
fi

mkdir -p "$outdir"
notify-send "  yt-dlp" "Starting download..."

kitty --hold -e yt-dlp "${args[@]}" -o "$outdir/%(title)s.%(ext)s" "$url"
