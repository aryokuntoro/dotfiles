#!/usr/bin/env bash

# ── Screen Recording with ffmpeg + Rofi ────────────────────────
dir="$HOME/Videos/Recordings"
mkdir -p "$dir"
timestamp=$(date +"%Y%m%d_%H%M%S")
output="$dir/recording_$timestamp.mp4"
pidfile="/tmp/ffmpeg_record.pid"

# The pidfile holds one "pid:file" line per concurrent ffmpeg process --
# Combined mode (the only mode before Separate existed) always writes
# exactly one, Separate mode writes one per stream (video + audio, or
# video + webcam). $output and $timestamp above are recomputed on every
# run of this script, so Stop reads the pid(s)/file(s) actually saved at
# start time rather than recomputing a filename that was generated
# seconds earlier and may not match what is really on disk.
save_rec() {
    printf '%s:%s\n' "$1" "$2" >> "$pidfile"
}
theme="$HOME/.config/rofi/themes/current.rasi"

# ── Hardware encoder detection ──────────────────────────────────
# Software x264 encodes every frame on the CPU -- fine on a fast one,
# but a high-end box with real encode silicon sitting unused is
# wasteful, and a genuinely weak CPU can drop frames trying to x264 a
# 1080p60 capture in realtime. Prefer hardware where it actually works,
# fall back to software (the previous unconditional default) everywhere
# else, so nothing regresses on a machine with neither.
#
# NVENC only, not VAAPI: VAAPI needs a real driver stack behind
# whatever /dev/dri/render* node is present, and that's not something a
# node's mere existence guarantees -- this very machine has one from
# the NVIDIA driver with no VAAPI backend behind it at all (confirmed:
# `ffmpeg -vaapi_device /dev/dri/renderD128 ... -c:v h264_vaapi` fails
# to initialize here), and VAAPI's rig for the Webcam arms' existing
# -filter_complex overlay adds real complexity on top. Shipping that
# without a working Intel/AMD box to verify against risks a silently
# broken recording rather than a working one, so it's left out; NVENC
# is simple to gate and this machine's GTX 1650 confirms it actually
# works.
#
# A real (tiny, throwaway) encode is attempted rather than trusting
# `command -v nvidia-smi` alone: the driver can be installed with no
# GPU actually reachable (a broken Optimus/PRIME setup, a headless
# card), and ffmpeg ships h264_nvenc regardless of whether any of that
# actually works. 256x144 is the smallest size that didn't fail outright
# with "Invalid argument" in testing -- h264_nvenc has an undocumented
# (in --help, at least) minimum encode resolution somewhere between
# 128x128 and 160x96. Cached so this only costs one real encode attempt
# per boot, not one per recording.
HWENC_CACHE="$HOME/.cache/recordrofi-hwenc"

detect_hwenc() {
    local cached
    cached=$(cat "$HWENC_CACHE" 2>/dev/null)
    case "$cached" in
        nvenc | software) echo "$cached"; return ;;
    esac

    if command -v nvidia-smi >/dev/null 2>&1 &&
        timeout 5 ffmpeg -hide_banner -y -f lavfi -i "testsrc=size=256x144:rate=5:duration=0.2" \
            -c:v h264_nvenc -f null - >/dev/null 2>&1; then
        echo nvenc > "$HWENC_CACHE"
    else
        echo software > "$HWENC_CACHE"
    fi
    cat "$HWENC_CACHE"
}

# Builds vcodec_opts for whatever detect_hwenc found, at a given
# quality tier. NVENC's -cq and x264's -crf are different encoders'
# quality knobs, not literally the same scale, but both run roughly
# 0 (best/largest) - 51 (worst/smallest) and the same number on either
# lands in the same ballpark -- close enough for this menu's three
# named tiers, which were never meant to be frame-accurate to begin
# with. p4 is NVENC's "medium" preset in the modern p1(fastest)-
# p7(slowest) scheme, the closest match to x264's "fast" as a
# speed/quality compromise for realtime capture.
#
# -pix_fmt yuv420p matters more than it looks like it should: x11grab's
# native capture format is full-chroma BGRA, and libx264 given that
# directly with no explicit -pix_fmt encodes it as yuv444p / "High 4:4:4
# Predictive" instead of downsampling to the universally-supported
# yuv420p / "High" -- confirmed with ffprobe, not assumed. Most players'
# hardware decode paths, mpv included, don't handle 4:4:4 well, which is
# exactly what "recording plays back laggy" turned out to be. NVENC
# happened to already default to yuv420p on this machine, but it costs
# nothing to pin it explicitly on both paths rather than depend on that
# holding true on a different GPU/driver/ffmpeg version too.
vcodec_opts_for_quality() {
    local value="$1"
    if [ "$(detect_hwenc)" = nvenc ]; then
        vcodec_opts=(-c:v h264_nvenc -rc vbr -cq "$value" -preset p4 -pix_fmt yuv420p)
    else
        vcodec_opts=(-c:v libx264 -preset fast -crf "$value" -pix_fmt yuv420p)
    fi
}

vcodec_opts_for_bitrate() {
    local bitrate="$1"
    if [ "$(detect_hwenc)" = nvenc ]; then
        vcodec_opts=(-c:v h264_nvenc -preset p4 -b:v "$bitrate" -pix_fmt yuv420p)
    else
        vcodec_opts=(-c:v libx264 -preset fast -b:v "$bitrate" -pix_fmt yuv420p)
    fi
}

# Check if already recording
if [ -f "$pidfile" ]; then
    choice=$(echo -e "  Stop Recording\n  Cancel" | rofi -dmenu -i -p "Recording Active:" \
        -theme "$theme" -no-config -lines 2)
    if [[ "$choice" == *"Stop"* ]]; then
        saved_files=()
        while IFS=: read -r rec_pid rec_file; do
            kill "$rec_pid" 2>/dev/null
            saved_files+=("$rec_file")
        done < "$pidfile"
        rm -f "$pidfile"
        joined=$(printf '%s, ' "${saved_files[@]}")
        notify-send "  Recording" "Stopped. Saved: ${joined%, }"
    fi
    exit 0
fi

# Recording options
options="  Full Screen Video\n  Select Area Video\n  Full Screen + Audio\n  Select Area + Audio\n  Full Screen + Webcam\n  Select Area + Webcam\n  GIF Full Screen\n  GIF Select Area"

choice=$(echo -e "$options" | rofi -dmenu -i -p "Record:" \
    -theme "$theme" -no-config -lines 8)
[ -z "$choice" ] && exit 0

# Get screen resolution
res=$(xrandr --query | grep ' connected' | grep -o '[0-9]*x[0-9]*' | head -1)

# ── Video quality/resolution/framerate prompts (video modes only) ──
scale_vf=""
framerate="30"
vcodec_opts=()
vcodec_opts_for_quality 23

if [[ "$choice" == *Video* || "$choice" == *Webcam* || "$choice" == *Audio* ]]; then
    res_choice=$(printf 'Native (%s)\n1920x1080\n1280x720\n854x480\nCustom...\n' "$res" | \
        rofi -dmenu -i -p "Resolution:" -theme "$theme" -no-config -lines 5)
    [ -z "$res_choice" ] && exit 0
    case "$res_choice" in
        1920x1080 | 1280x720 | 854x480) scale_vf="scale=$res_choice" ;;
        "Custom...")
            custom_res=$(rofi -dmenu -p "Custom resolution (e.g. 1600x900):" -theme "$theme" -no-config -lines 0)
            [ -z "$custom_res" ] && exit 0
            if [[ "$custom_res" =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]]; then
                scale_vf="scale=$custom_res"
            else
                notify-send "  Record" "Invalid resolution '$custom_res' -- expected WIDTHxHEIGHT, e.g. 1600x900"
                exit 1
            fi
            ;;
    esac

    fps_choice=$(printf '60\n30\n24\n15\n' | \
        rofi -dmenu -i -p "Framerate (fps):" -theme "$theme" -no-config -lines 4)
    [ -z "$fps_choice" ] && exit 0
    framerate="$fps_choice"

    # No "(CRF 18)"-style numbers in the labels: the actual value is a
    # -crf (software) or -cq (NVENC) target depending on what
    # detect_hwenc finds, and printing an x264-specific term here would
    # be wrong on a machine that ends up hardware-encoding instead.
    quality_choice=$(printf 'High Quality\nBalanced\nSmall File\nCustom Bitrate...\n' | \
        rofi -dmenu -i -p "Quality:" -theme "$theme" -no-config -lines 4)
    [ -z "$quality_choice" ] && exit 0
    case "$quality_choice" in
        "High Quality"*) vcodec_opts_for_quality 18 ;;
        "Small File"*)   vcodec_opts_for_quality 28 ;;
        "Custom Bitrate"*)
            bitrate=$(rofi -dmenu -p "Bitrate (e.g. 8M, 4000k):" -theme "$theme" -no-config -lines 0)
            [ -z "$bitrate" ] && exit 0
            vcodec_opts_for_bitrate "$bitrate"
            ;;
        *) vcodec_opts_for_quality 23 ;;
    esac
fi

# Surfaced in the "Started" notifications below (video/audio/webcam
# arms only, not GIF -- gif is always software) so it's visible which
# path actually got used without having to go looking for it. Empty,
# not "(software x264)", when nothing hardware-accelerated is going on
# -- that's the common/default case and not worth calling out every time.
hwenc_label=""
[ "$(detect_hwenc)" = nvenc ] && hwenc_label=" (NVENC)"

# ── Audio source (Audio modes only) ─────────────────────────────
# The literal string "default" -- which is what this used to hardcode
# as ffmpeg's own pulse input straight through -- does not actually
# work on this machine's ffmpeg/PipeWire-pulse: `ffmpeg -f pulse -i
# default` fails outright with "Error opening input: Input/output
# error", and so does `-i ""` (the documented ffmpeg-pulse convention
# for "use whatever the default is"). Resolved by hand instead, via
# pactl, which reliably returns real device names (confirmed: feeding
# one to ffmpeg works where the literal "default" string did not).
#
# "System Audio" and "Microphone" are two different pactl concepts, not
# one "default" -- a mic input (get-default-source) captures whatever a
# physical microphone picks up, near-silence most of the time, while
# system audio is the *.monitor of the default *sink* (get-default-
# sink), which is what's actually playing (a YouTube tab, etc). Putting
# only one ambiguous "System Default" in front of both, resolving to
# the mic, is exactly how a recording meant to capture a video's audio
# ends up silent -- so both are offered explicitly, System Audio first
# since "record what's on screen" is the more common reason to be in
# an Audio mode at all. Any other source pactl reports (a second mic, a
# non-default monitor) is still listed below both for less common cases.
default_sink=$(pactl get-default-sink 2>/dev/null)
default_source=$(pactl get-default-source 2>/dev/null)
audio_source="${default_sink:+${default_sink}.monitor}"
[ -z "$audio_source" ] && audio_source="${default_source:-default}"
if [[ "$choice" == *Audio* ]]; then
    mapfile -t all_sources < <(pactl list sources short 2>/dev/null | awk -F'\t' '{print $2}')
    audio_labels=()
    audio_values=()
    if [ -n "$default_sink" ]; then
        audio_labels+=("  System Audio (what's playing)")
        audio_values+=("${default_sink}.monitor")
    fi
    if [ -n "$default_source" ]; then
        audio_labels+=("  Microphone (default)")
        audio_values+=("$default_source")
    fi
    for src in "${all_sources[@]}"; do
        [ "$src" = "${default_sink}.monitor" ] && continue
        [ "$src" = "$default_source" ] && continue
        case "$src" in
            *.monitor) audio_labels+=("  System Audio -- $src") ;;
            *)         audio_labels+=("  Mic -- $src") ;;
        esac
        audio_values+=("$src")
    done
    if [ "${#audio_labels[@]}" -eq 0 ]; then
        notify-send "  Record" "No audio sources found (pactl list sources returned nothing)"
        exit 1
    fi
    audio_choice=$(printf '%s\n' "${audio_labels[@]}" | \
        rofi -dmenu -i -p "Audio Source:" -theme "$theme" -no-config -format i -lines "${#audio_labels[@]}")
    [ -z "$audio_choice" ] && exit 0
    audio_source="${audio_values[$audio_choice]}"
fi

# ── Webcam device (Webcam modes only) ───────────────────────────
# /dev/video0 used to be hardcoded -- on a machine with no webcam at
# all (this one included: no /dev/video* node exists here) that failed
# silently in the backgrounded ffmpeg process with nothing surfaced to
# the user, and on a machine with more than one camera it could just as
# easily have been the wrong one. Detected live instead: none found
# stops here with a real error instead of starting a recording that was
# always going to come up empty; exactly one is used without asking;
# more than one prompts, using v4l2-ctl's own device name as the label
# when it's installed, falling back to the bare device path otherwise.
webcam_device=""
if [[ "$choice" == *Webcam* ]]; then
    shopt -s nullglob
    webcam_devs=(/dev/video*)
    shopt -u nullglob
    if [ "${#webcam_devs[@]}" -eq 0 ]; then
        notify-send "  Record" "No webcam found (no /dev/video* device)"
        exit 1
    elif [ "${#webcam_devs[@]}" -eq 1 ]; then
        webcam_device="${webcam_devs[0]}"
    else
        webcam_labels=()
        for dev in "${webcam_devs[@]}"; do
            name=$(v4l2-ctl -d "$dev" --info 2>/dev/null | grep -oP '(?<=Card type\s{2}:\s).*')
            webcam_labels+=("  ${name:-$dev} ($dev)")
        done
        webcam_choice=$(printf '%s\n' "${webcam_labels[@]}" | \
            rofi -dmenu -i -p "Webcam:" -theme "$theme" -no-config -format i -lines "${#webcam_labels[@]}")
        [ -z "$webcam_choice" ] && exit 0
        webcam_device="${webcam_devs[$webcam_choice]}"
    fi
fi

# ── Combined vs Separate output (Audio/Webcam modes only) ──────────
# Combined (the only behavior before this existed) muxes/composites
# everything into the one file $output already points at. Separate
# writes each stream to its own file instead -- useful for pulling the
# recording into a real video editor later, where a pre-mixed track or
# a burned-in webcam overlay can't be undone, but a plain video-only
# capture next to a plain audio-only or webcam-only one still can.
output_mode="combined"
if [[ "$choice" == *Audio* || "$choice" == *Webcam* ]]; then
    mode_choice=$(printf '  Combined (one file)\n  Separate files\n' | \
        rofi -dmenu -i -p "Output:" -theme "$theme" -no-config -lines 2)
    [ -z "$mode_choice" ] && exit 0
    [[ "$mode_choice" == *Separate* ]] && output_mode="separate"
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

# Guaranteed not to exist yet at this point (the pidfile check above
# would have exited early otherwise) -- cleared defensively anyway so a
# leftover from a process that crashed mid-recording without cleaning up
# can never make save_rec's append land in a stale file.
rm -f "$pidfile"

case "$choice" in
    *Full\ Screen\ Video*)
        ffmpeg -f x11grab -video_size "$res" -framerate "$framerate" -i "$DISPLAY" \
            ${scale_vf:+-vf "$scale_vf"} "${vcodec_opts[@]}" "$output" -y &
        save_rec "$!" "$output"
        notify-send "  Recording" "Started: Full Screen Video$hwenc_label"
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
            notify-send "  Recording" "Started: Select Area Video$hwenc_label"
        fi
        ;;
    *Full\ Screen\ +\ Audio*)
        if [ "$output_mode" = separate ]; then
            video_out="$dir/recording_${timestamp}_video.mp4"
            audio_out="$dir/recording_${timestamp}_audio.m4a"
            ffmpeg -f x11grab -video_size "$res" -framerate "$framerate" -i "$DISPLAY" \
                ${scale_vf:+-vf "$scale_vf"} "${vcodec_opts[@]}" "$video_out" -y &
            save_rec "$!" "$video_out"
            ffmpeg -f pulse -i "$audio_source" -c:a aac -b:a 128k "$audio_out" -y &
            save_rec "$!" "$audio_out"
            notify-send "  Recording" "Started: Full Screen + Audio (separate files)$hwenc_label"
        else
            ffmpeg -f x11grab -video_size "$res" -framerate "$framerate" -i "$DISPLAY" \
                -f pulse -i "$audio_source" ${scale_vf:+-vf "$scale_vf"} "${vcodec_opts[@]}" \
                -c:a aac -b:a 128k "$output" -y &
            save_rec "$!" "$output"
            notify-send "  Recording" "Started: Full Screen + Audio$hwenc_label"
        fi
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
            if [ "$output_mode" = separate ]; then
                video_out="$dir/recording_${timestamp}_video.mp4"
                audio_out="$dir/recording_${timestamp}_audio.m4a"
                ffmpeg -f x11grab -video_size "${w}x${h}" -framerate "$framerate" \
                    -i "$DISPLAY+$x,$y" ${scale_vf:+-vf "$scale_vf"} "${vcodec_opts[@]}" "$video_out" -y &
                save_rec "$!" "$video_out"
                ffmpeg -f pulse -i "$audio_source" -c:a aac -b:a 128k "$audio_out" -y &
                save_rec "$!" "$audio_out"
                notify-send "  Recording" "Started: Select Area + Audio (separate files)$hwenc_label"
            else
                ffmpeg -f x11grab -video_size "${w}x${h}" -framerate "$framerate" \
                    -i "$DISPLAY+$x,$y" -f pulse -i "$audio_source" \
                    ${scale_vf:+-vf "$scale_vf"} "${vcodec_opts[@]}" -c:a aac -b:a 128k "$output" -y &
                save_rec "$!" "$output"
                notify-send "  Recording" "Started: Select Area + Audio$hwenc_label"
            fi
        fi
        ;;
    *Full\ Screen\ +\ Webcam*)
        webcam_res="320x240"
        if [ "$output_mode" = separate ]; then
            video_out="$dir/recording_${timestamp}_video.mp4"
            webcam_out="$dir/recording_${timestamp}_webcam.mp4"
            ffmpeg -f x11grab -video_size "$res" -framerate "$framerate" -i "$DISPLAY" \
                ${scale_vf:+-vf "$scale_vf"} "${vcodec_opts[@]}" "$video_out" -y &
            save_rec "$!" "$video_out"
            ffmpeg -f v4l2 -video_size "$webcam_res" -i "$webcam_device" \
                -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p "$webcam_out" -y &
            save_rec "$!" "$webcam_out"
            notify-send "  Recording" "Started: Full Screen + Webcam (separate files)$hwenc_label"
        else
            webcam_pos="main_w-overlay_w-10:10"
            if [ -n "$scale_vf" ]; then
                filter="[0:v]${scale_vf}[bg];[bg][1:v]overlay=$webcam_pos"
            else
                filter="[0:v][1:v]overlay=$webcam_pos"
            fi
            ffmpeg -f x11grab -video_size "$res" -framerate "$framerate" -i "$DISPLAY" \
                -f v4l2 -video_size "$webcam_res" -i "$webcam_device" \
                -filter_complex "$filter" \
                "${vcodec_opts[@]}" "$output" -y &
            save_rec "$!" "$output"
            notify-send "  Recording" "Started: Full Screen + Webcam$hwenc_label"
        fi
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
            if [ "$output_mode" = separate ]; then
                video_out="$dir/recording_${timestamp}_video.mp4"
                webcam_out="$dir/recording_${timestamp}_webcam.mp4"
                ffmpeg -f x11grab -video_size "${w}x${h}" -framerate "$framerate" \
                    -i "$DISPLAY+$x,$y" ${scale_vf:+-vf "$scale_vf"} "${vcodec_opts[@]}" "$video_out" -y &
                save_rec "$!" "$video_out"
                ffmpeg -f v4l2 -video_size "$webcam_res" -i "$webcam_device" \
                    -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p "$webcam_out" -y &
                save_rec "$!" "$webcam_out"
                notify-send "  Recording" "Started: Select Area + Webcam (separate files)$hwenc_label"
            else
                webcam_pos="main_w-overlay_w-10:10"
                if [ -n "$scale_vf" ]; then
                    filter="[0:v]${scale_vf}[bg];[bg][1:v]overlay=$webcam_pos"
                else
                    filter="[0:v][1:v]overlay=$webcam_pos"
                fi
                ffmpeg -f x11grab -video_size "${w}x${h}" -framerate "$framerate" \
                    -i "$DISPLAY+$x,$y" \
                    -f v4l2 -video_size "$webcam_res" -i "$webcam_device" \
                    -filter_complex "$filter" \
                    "${vcodec_opts[@]}" "$output" -y &
                save_rec "$!" "$output"
                notify-send "  Recording" "Started: Select Area + Webcam$hwenc_label"
            fi
        fi
        ;;
    *GIF\ Full\ Screen*)
        gif_output="$dir/recording_$timestamp.gif"
        ffmpeg -f x11grab -video_size "$res" -framerate "$gif_fps" -i "$DISPLAY" \
            -vf "fps=$gif_fps,scale=$gif_width:-1:flags=lanczos" -loop 0 "$gif_output" -y &
        save_rec "$!" "$gif_output"
        notify-send "  Recording" "Started: GIF Full Screen"
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
            notify-send "  Recording" "Started: GIF Select Area"
        fi
        ;;
esac
