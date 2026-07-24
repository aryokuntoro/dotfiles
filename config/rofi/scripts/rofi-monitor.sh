#!/usr/bin/env bash
#
# A rofi menu for monitor management: extend / duplicate (mirror) /
# single-display / refresh rate / scale / rotate, with the monitor's
# real brand+model pulled from its EDID.
#
# Depends on: rofi, xrandr, edid-decode, xxd, autorandr (optional,
# used to persist the resulting layout as a profile).

divider="---------"
goback=" Back"
# Saved into the same "default" profile autorandr already uses at
# login (not a separate name) -- a separate profile with the exact
# same connected-monitor fingerprint makes `autorandr --change`
# ambiguous about which one to restore, and it can silently pick the
# wrong one.
profile_name="default"

rofi_command="rofi -theme ~/.config/rofi/themes/Monitor.rasi -markup-rows -dmenu $* -p"

# ── EDID / identity ─────────────────────────────────────────────

# Prints the raw EDID hex blob (no whitespace) for a connected output,
# read straight from `xrandr --props` (avoids guessing how xrandr's
# output names map to /sys/class/drm/*/edid connector names).
edid_hex() {
    local output="$1"
    xrandr --props | awk -v out="$output" '
        /^[A-Za-z0-9-]+ (connected|disconnected)/ { inblock = ($0 ~ "^"out" "); next }
        inblock && /^\tEDID:/ { inedid = 1; next }
        inblock && inedid && /^\t\t/ { gsub(/[ \t]/, ""); printf "%s", $0; next }
        inblock && inedid { inedid = 0 }
    '
}

# Human-readable "Brand Model" string for an output, e.g. "HP Z24i".
# Falls back to the raw PNP manufacturer id + product code, then to
# the bare output name if there's no EDID at all (e.g. a VNC/virtual
# output).
monitor_label() {
    local output="$1"
    local hex decoded name mfg model
    hex=$(edid_hex "$output")
    [ -z "$hex" ] && { echo "$output"; return; }

    decoded=$(echo "$hex" | xxd -r -p 2>/dev/null | edid-decode - 2>/dev/null)
    name=$(echo "$decoded" | grep -oP "Display Product Name: '\K[^']+")
    if [ -n "$name" ]; then
        echo "$name"
        return
    fi

    mfg=$(echo "$decoded" | grep -oP "Manufacturer: \K\S+")
    model=$(echo "$decoded" | grep -oP "Model: \K\S+")
    if [ -n "$mfg" ] || [ -n "$model" ]; then
        echo "${mfg:-Unknown} ${model:-}"
    else
        echo "$output"
    fi
}

# ── xrandr state helpers ─────────────────────────────────────────

connected_outputs() {
    xrandr --query | awk '/ connected/ {print $1}'
}

is_active() {
    xrandr --query | grep -qE "^$1 connected (primary )?[0-9]+x[0-9]+"
}

is_primary() {
    xrandr --query | grep "^$1 connected" | grep -q " primary "
}

current_mode() {
    local output="$1"
    xrandr --query | awk -v out="$output" '
        $0 ~ "^"out" connected" { inblock = 1; next }
        /^[A-Za-z0-9-]+ (connected|disconnected)/ { inblock = 0 }
        inblock {
            res = $1
            for (i = 2; i <= NF; i++) {
                if ($i ~ /\*/) {
                    rate = $i; gsub(/[*+]/, "", rate)
                    print res "@" rate "Hz"
                }
            }
        }
    '
}

# All "<res>@<rate>Hz" combos this output supports, one per line.
list_modes() {
    local output="$1"
    xrandr --query | awk -v out="$output" '
        $0 ~ "^"out" connected" { inblock = 1; next }
        /^[A-Za-z0-9-]+ (connected|disconnected)/ { inblock = 0 }
        inblock {
            res = $1
            for (i = 2; i <= NF; i++) {
                rate = $i; gsub(/[*+]/, "", rate)
                print res "@" rate "Hz"
            }
        }
    '
}

# Renders each output as one "card" line, sized by importance:
# brand+model large & bold, mode/primary-tag smaller, bare output id
# smallest and dimmed at the end. (rofi's listview gives every row a
# uniform height regardless of theme padding, so a real multi-line
# stacked layout isn't achievable -- confirmed by testing -- hence
# one line with a Pango size hierarchy instead.)
status_line() {
    local output="$1" label mode primary_tag=""
    label=$(monitor_label "$output")
    if is_active "$output"; then
        mode=$(current_mode "$output")
        is_primary "$output" && primary_tag="  ·  Primary"
        printf '<span weight="bold" size="large">%s</span>   <span size="small" alpha="75%%">%s%s</span>   <span size="x-small" alpha="50%%">%s</span>' \
            "$label" "$mode" "$primary_tag" "$output"
    else
        printf '<span weight="bold" size="large">%s</span>   <span size="small" alpha="75%%">off</span>   <span size="x-small" alpha="50%%">%s</span>' \
            "$label" "$output"
    fi
}

# ── Apply + persist ──────────────────────────────────────────────

apply() {
    notify-send "  Monitor" "$1"
    autorandr --save "$profile_name" >/dev/null 2>&1
    ~/.config/polybar/launch.sh >/dev/null 2>&1
}

# ── Submenus ──────────────────────────────────────────────────────

resolution_menu() {
    local output="$1"
    local options
    options=$(list_modes "$output")
    options="$options\n$divider\n$goback\nExit"

    chosen=$(echo -e "$options" | $rofi_command "Resolution: $output")
    case "$chosen" in
        "" | "$divider") monitor_menu "$output" ;;
        "$goback") monitor_menu "$output" ;;
        "Exit") exit 0 ;;
        *)
            local res rate
            res=$(echo "$chosen" | cut -d'@' -f1)
            rate=$(echo "$chosen" | cut -d'@' -f2 | tr -d 'Hz')
            xrandr --output "$output" --mode "$res" --rate "$rate"
            apply "$output set to $res @ ${rate}Hz"
            monitor_menu "$output"
            ;;
    esac
}

scale_menu() {
    local output="$1"
    local options="100% (native)\n125%\n150%\n175%\n200%\n$divider\n$goback\nExit"

    chosen=$(echo -e "$options" | $rofi_command "Scale: $output")
    local factor=""
    case "$chosen" in
        "100% (native)") factor="1" ;;
        "125%") factor="0.8" ;;
        "150%") factor="0.6666" ;;
        "175%") factor="0.5714" ;;
        "200%") factor="0.5" ;;
        "$goback" | "" | "$divider") monitor_menu "$output"; return ;;
        "Exit") exit 0 ;;
    esac

    if [ -n "$factor" ]; then
        xrandr --output "$output" --scale "${factor}x${factor}" --filter bilinear
        apply "$output scale set to $chosen"
    fi
    monitor_menu "$output"
}

rotate_menu() {
    local output="$1"
    local options="Normal\nLeft\nRight\nInverted\n$divider\n$goback\nExit"

    chosen=$(echo -e "$options" | $rofi_command "Rotate: $output")
    local dir=""
    case "$chosen" in
        "Normal") dir="normal" ;;
        "Left") dir="left" ;;
        "Right") dir="right" ;;
        "Inverted") dir="inverted" ;;
        "$goback" | "" | "$divider") monitor_menu "$output"; return ;;
        "Exit") exit 0 ;;
    esac

    if [ -n "$dir" ]; then
        xrandr --output "$output" --rotate "$dir"
        apply "$output rotation set to $chosen"
    fi
    monitor_menu "$output"
}

# Per-monitor actions
monitor_menu() {
    local output="$1"
    local label mode primary_opt=" Set as Primary"
    label=$(monitor_label "$output")

    local options="$primary_opt\nResolution\nScale\nRotate\nTurn Off\n$divider\n$goback\nExit"

    chosen=$(echo -e "$options" | $rofi_command "$label ($output)")
    case "$chosen" in
        "" | "$divider") show_menu ;;
        "$goback") show_menu ;;
        "Exit") exit 0 ;;
        "$primary_opt")
            xrandr --output "$output" --primary
            apply "$output set as primary"
            show_menu
            ;;
        "Resolution") resolution_menu "$output" ;;
        "Scale") scale_menu "$output" ;;
        "Rotate") rotate_menu "$output" ;;
        "Turn Off")
            xrandr --output "$output" --off
            apply "$output turned off"
            show_menu
            ;;
    esac
}

# Pick a reference monitor, then a direction, to extend $1 relative to it
extend_menu() {
    local output="$1"
    local others
    others=$(connected_outputs | grep -v "^$output$")

    if [ -z "$others" ]; then
        notify-send "  Monitor" "Only one display connected -- nothing to extend against."
        show_menu
        return
    fi

    local options=""
    while IFS= read -r o; do
        options="${options}$(monitor_label "$o") ($o)\n"
    done <<< "$others"
    options="${options}$divider\n$goback\nExit"

    chosen=$(echo -e "$options" | $rofi_command "Extend $output relative to")
    case "$chosen" in
        "" | "$divider" | "$goback") show_menu; return ;;
        "Exit") exit 0 ;;
    esac

    local ref
    ref=$(echo "$chosen" | grep -oP '\(\K[^)]+(?=\)$)')
    [ -z "$ref" ] && { show_menu; return; }

    local dir_options="Right of\nLeft of\nAbove\nBelow\n$divider\n$goback\nExit"
    dir_chosen=$(echo -e "$dir_options" | $rofi_command "Position of $output")
    local flag=""
    case "$dir_chosen" in
        "Right of") flag="--right-of" ;;
        "Left of") flag="--left-of" ;;
        "Above") flag="--above" ;;
        "Below") flag="--below" ;;
        "$goback" | "" | "$divider") show_menu; return ;;
        "Exit") exit 0 ;;
    esac

    xrandr --output "$output" --auto --output "$ref" --auto
    xrandr --output "$output" "$flag" "$ref"
    apply "$output extended ${dir_chosen,,} $ref"
    show_menu
}

mirror_all() {
    local outputs primary rest
    outputs=$(connected_outputs)
    primary=$(echo "$outputs" | head -1)
    rest=$(echo "$outputs" | tail -n +2)

    xrandr --output "$primary" --auto
    while IFS= read -r o; do
        [ -z "$o" ] && continue
        xrandr --output "$o" --auto --same-as "$primary"
    done <<< "$rest"

    apply "All displays mirrored"
    show_menu
}

single_display_menu() {
    local outputs options
    outputs=$(connected_outputs)
    options=""
    while IFS= read -r o; do
        options="${options}$(monitor_label "$o") ($o)\n"
    done <<< "$outputs"
    options="${options}$divider\n$goback\nExit"

    chosen=$(echo -e "$options" | $rofi_command "Use only")
    case "$chosen" in
        "" | "$divider" | "$goback") show_menu; return ;;
        "Exit") exit 0 ;;
    esac

    local keep
    keep=$(echo "$chosen" | grep -oP '\(\K[^)]+(?=\)$)')
    [ -z "$keep" ] && { show_menu; return; }

    while IFS= read -r o; do
        if [ "$o" = "$keep" ]; then
            xrandr --output "$o" --auto --primary
        else
            xrandr --output "$o" --off
        fi
    done <<< "$outputs"

    apply "Using only $keep"
    show_menu
}

show_menu() {
    local outputs entries=""
    outputs=$(connected_outputs)

    while IFS= read -r o; do
        entries="${entries}$(status_line "$o")\n"
    done <<< "$outputs"

    local n
    n=$(echo "$outputs" | grep -c .)

    local extend_opt=" Extend Layout..."
    local mirror_opt=" Mirror All Displays"
    local single_opt=" Single Display Only..."
    local detect_opt=" Detect Displays (autorandr --change)"

    local options="$entries$divider\n"
    if [ "$n" -gt 1 ]; then
        options="${options}${extend_opt}\n${mirror_opt}\n${single_opt}\n"
    fi
    options="${options}${detect_opt}\nExit"

    chosen=$(echo -e "$options" | $rofi_command "Monitors")

    case "$chosen" in
        "" ) exit 0 ;;
        "$divider") show_menu ;;
        "Exit") exit 0 ;;
        "$detect_opt")
            autorandr --change
            apply "Displays re-detected"
            ;;
        "$mirror_opt") mirror_all ;;
        "$single_opt") single_display_menu ;;
        *)
            if [[ "$chosen" == *"Extend Layout"* ]]; then
                # Ambiguous with >1 monitor: ask which one to extend.
                local pick_opts=""
                while IFS= read -r o; do
                    pick_opts="${pick_opts}$(monitor_label "$o") ($o)\n"
                done <<< "$outputs"
                pick_opts="${pick_opts}$divider\n$goback\nExit"
                pick=$(echo -e "$pick_opts" | $rofi_command "Extend which display?")
                case "$pick" in
                    "" | "$divider" | "$goback") show_menu ;;
                    "Exit") exit 0 ;;
                    *)
                        local target
                        target=$(echo "$pick" | grep -oP '\(\K[^)]+(?=\)$)')
                        [ -n "$target" ] && extend_menu "$target" || show_menu
                        ;;
                esac
            else
                # status_line() always ends with the bare output name as
                # its last (dimmed) <span>, after the last closing tag.
                local output
                output="${chosen%</span>}"
                output="${output##*>}"
                if echo "$outputs" | grep -qx "$output"; then
                    monitor_menu "$output"
                else
                    show_menu
                fi
            fi
            ;;
    esac
}

show_menu
