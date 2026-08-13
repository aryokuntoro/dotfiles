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

# Pixel resolution the output is running right now, as "1920x1080".
# Empty if the output is off (no geometry on its xrandr line).
output_px() {
    xrandr --query | grep -m1 "^$1 connected" | grep -oP '\d+x\d+(?=\+)'
}

# Physical panel size as "<width_mm> <height_mm>", taken from the
# "708mm x 398mm" xrandr prints from the output's EDID. Prints "0 0"
# when the display publishes no usable size -- projectors mostly,
# which have no panel to measure, but also anything behind an HDMI
# switch or capture box that rewrites the EDID.
output_size_mm() {
    local mm
    mm=$(xrandr --query | grep -m1 "^$1 connected" | grep -oP '\d+(?=mm)' | paste -sd' ' -)
    if [ -n "$mm" ]; then
        echo "$mm"
    else
        echo "0 0"
    fi
}

# The panel's real pixel density across its width. 0 when unknown.
physical_dpi() {
    local px mm
    px=$(output_px "$1" | cut -dx -f1)
    mm=$(output_size_mm "$1" | cut -d' ' -f1)
    [[ "$px" =~ ^[0-9]+$ ]] && [ "${mm:-0}" -gt 0 ] || { echo 0; return; }
    awk -v p="$px" -v m="$mm" 'BEGIN { printf "%d", p / (m / 25.4) + 0.5 }'
}

# Panel diagonal in inches. 0 when the EDID has no size.
diagonal_inches() {
    local w h
    read -r w h <<< "$(output_size_mm "$1")"
    [ "${w:-0}" -gt 0 ] && [ "${h:-0}" -gt 0 ] || { echo 0; return; }
    awk -v w="$w" -v h="$h" 'BEGIN { printf "%d", sqrt(w*w + h*h) / 25.4 + 0.5 }'
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

    # Cached lock screen images are rendered for whatever
    # resolution/layout was active at the time -- regenerate them for
    # the new one so betterlockscreen doesn't show a stretched/stale
    # image. Backgrounded since it takes ~10s.
    if [ -f ~/.config/i3/current_wallpaper ] && [ -f "$(cat ~/.config/i3/current_wallpaper)" ]; then
        betterlockscreen -u "$(cat ~/.config/i3/current_wallpaper)" >/dev/null 2>&1 &
    fi
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

# The scale steps the menu offers, as Xft.dpi values (96 = 100%).
dpi_steps="96 120 144 168 192"

# Current UI scale, as a DPI number. 96 is the unscaled baseline.
current_dpi() {
    local dpi
    dpi=$(xrdb -query 2>/dev/null | awk -F':[[:space:]]*' '/^Xft\.dpi/ {print $2}')
    [[ "$dpi" =~ ^[0-9]+$ ]] && echo "$dpi" || echo 96
}

# The DPI this particular display probably wants, snapped to one of
# the steps above. 0 when there's nothing to base a guess on.
#
# Scaling is really a question of *angular* size, not pixel density: a
# 24" desk monitor and a 32" TV can have the same dpi and still need
# very different UI sizes, because one is at arm's length and the
# other is across the room. So take the panel's real density from its
# EDID, guess the viewing distance from its diagonal, and solve for
# the scale that makes a UI element look the same size as it does at
# the desk-monitor baseline (96 dpi seen from 60cm):
#
#   dpi = physical_dpi x distance_m / 0.6
#
# For this TV -- 1920px across 708mm, so ~69 real dpi at 32", used
# from about a metre away -- that lands on 144, which is where the
# menu's own 150% entry sits. A 24" 1080p monitor lands back on 96,
# and a 27" 4K panel on 192.
#
# A projector reports no EDID size (there's no panel), so it gets no
# recommendation rather than a made-up one: its image is already metres
# wide and 100% is usually right.
recommended_dpi() {
    local pdpi diag dist
    pdpi=$(physical_dpi "$1")
    diag=$(diagonal_inches "$1")
    [ "$pdpi" -gt 0 ] && [ "$diag" -gt 0 ] || { echo 0; return; }

    # Assumed viewing distance in metres, guessed from the diagonal --
    # the only usage hint the EDID gives. The jump at 28" is deliberate
    # and abrupt rather than a smooth curve: below it a display is
    # almost always a panel at arm's length, above it almost always a
    # TV somewhere across a desk or a room, and there's no continuum of
    # real setups in between to interpolate over. 43-ish is the one
    # genuinely ambiguous size (a 43" 4K is sold both as a desk monitor
    # and as a TV) -- it gets the TV distance, so check the number it
    # suggests rather than taking it on faith there.
    if   [ "$diag" -lt 17 ]; then dist=0.5   # laptop panel
    elif [ "$diag" -lt 28 ]; then dist=0.6   # desk monitor, arm's length
    elif [ "$diag" -lt 34 ]; then dist=1.2   # TV used as a desk display
    elif [ "$diag" -lt 50 ]; then dist=1.8   # big TV, back of the desk
    else                          dist=2.2   # TV across the room
    fi

    awk -v p="$pdpi" -v d="$dist" -v steps="$dpi_steps" 'BEGIN {
        want = p * d / 0.6
        n = split(steps, s, " ")
        best = s[1]
        for (i = 1; i <= n; i++) {
            cur = (s[i] > want) ? s[i] - want : want - s[i]
            ref = (best > want) ? best - want : want - best
            if (cur < ref) best = s[i]
        }
        print best
    }'
}

# One row of the Scale menu: the percentage large, and underneath the
# things that actually decide the choice -- the dpi it sets and how
# much logical desktop is left at that scale (a 1920x1080 panel at
# 150% has only 1280x720 worth of room for windows).
scale_row() {
    local dpi="$1" px_w="$2" px_h="$3" rec="$4" cur="$5" tag=""
    [ "$dpi" = "$cur" ] && tag="$tag  ·  current"
    [ "$dpi" = "$rec" ] && tag="$tag  ·  recommended"
    printf '<span weight="bold" size="large">%s%%</span>   <span size="small" alpha="75%%">%s dpi  ·  %sx%s logical</span><span size="small" weight="bold">%s</span>' \
        "$((dpi * 100 / 96))" "$dpi" "$((px_w * 96 / dpi))" "$((px_h * 96 / dpi))" "$tag"
}

# Scaling is done by DPI, not by `xrandr --scale`.
#
# `--scale` shrinks the framebuffer and has the GPU stretch it back up
# to the panel (150% meant rendering the whole desktop at 1280x720 and
# bilinear-upscaling it onto a 1080p screen). That magnifies every
# pixel -- polybar included -- so the bar grows out of proportion and
# the entire desktop goes soft. Raising the DPI instead keeps the
# framebuffer at the panel's native resolution and asks each toolkit
# to draw its own text and UI larger, so everything stays sharp and
# scales by the same factor.
#
# The value has to be written to more than one place because there is
# no single scaling knob on X11: Xft.dpi covers Xft consumers and
# polybar (its config reads ${xrdb:Xft.dpi:96}), while GTK reads its
# own gtk-xft-dpi from settings.ini and would otherwise sit at 96
# while everything else scaled.
#
# Toolkits read the DPI once at startup, so only what gets restarted
# here changes size immediately; already-running kitty/GTK/Qt windows
# keep the old size until they are relaunched.
set_dpi() {
    local dpi="$1"

    # ~/.Xresources is the persistent copy -- autostart.sh merges it
    # into the X server on every login, so this survives a reboot.
    if grep -q '^Xft\.dpi:' "$HOME/.Xresources" 2>/dev/null; then
        sed -i "s/^Xft\.dpi:.*/Xft.dpi: $dpi/" "$HOME/.Xresources"
    else
        printf 'Xft.dpi: %s\n' "$dpi" >> "$HOME/.Xresources"
    fi
    printf 'Xft.dpi: %s\n' "$dpi" | xrdb -merge

    # GTK wants the DPI in 1024ths of a point.
    local gtk_dpi=$((dpi * 1024))
    local ini
    for ini in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
        [ -f "$ini" ] || continue
        if grep -qE '^gtk-xft-dpi[[:space:]]*=' "$ini"; then
            sed -i -E "s/^gtk-xft-dpi[[:space:]]*=.*/gtk-xft-dpi=$gtk_dpi/" "$ini"
        else
            sed -i "/^\[Settings\]/a gtk-xft-dpi=$gtk_dpi" "$ini"
        fi
    done

    # i3 re-reads its pango font, and its exec_always restarts
    # autostart.sh, which brings polybar and dunst back up at the new
    # DPI too.
    i3-msg restart >/dev/null 2>&1
}

scale_menu() {
    local output="$1"
    local res px_w px_h cur rec pdpi diag prompt options="" d

    res=$(output_px "$output")
    px_w=${res%x*}
    px_h=${res#*x}
    if ! [[ "$px_w" =~ ^[0-9]+$ ]]; then
        # Output is off, so there's no mode to divide down. Xft.dpi is
        # one global value for the whole X screen anyway (X11 has no
        # per-output DPI -- that's a Wayland thing), so scaling from a
        # dark output is legal, just show the numbers for the screen.
        res=$(xrandr --query | grep -m1 '^Screen' | grep -oP 'current \K\d+ x \d+' | tr -d ' ')
        px_w=${res%x*}
        px_h=${res#*x}
    fi
    # Last resort. Every row divides by these, so letting a non-number
    # through here would blow up the whole menu on an arithmetic error
    # rather than just showing a slightly wrong logical size.
    [[ "$px_w" =~ ^[1-9][0-9]*$ ]] || { px_w=1920; px_h=1080; res="1920x1080"; }
    [[ "$px_h" =~ ^[1-9][0-9]*$ ]] || { px_w=1920; px_h=1080; res="1920x1080"; }

    cur=$(current_dpi)
    rec=$(recommended_dpi "$output")
    pdpi=$(physical_dpi "$output")
    diag=$(diagonal_inches "$output")

    # Prompt carries what the recommendation was derived from, so the
    # suggested row isn't just an unexplained label.
    prompt="Scale: $(monitor_label "$output")  ·  $res"
    if [ "$pdpi" -gt 0 ]; then
        prompt="$prompt  ·  ${diag}in, ${pdpi}dpi panel"
    elif ! is_active "$output"; then
        # xrandr only prints the physical size for an output that is
        # driving a mode, so "no size" on a dark output means nothing
        # about its EDID -- don't accuse it of being a projector.
        prompt="$prompt  ·  output off, showing screen size"
    else
        prompt="$prompt  ·  no EDID size (projector?)"
    fi

    for d in $dpi_steps; do
        options="${options}$(scale_row "$d" "$px_w" "$px_h" "$rec" "$cur")\n"
    done
    options="${options}$divider\n$goback\nExit"

    chosen=$(echo -e "$options" | $rofi_command "$prompt")
    case "$chosen" in
        "$goback" | "" | "$divider") monitor_menu "$output"; return ;;
        "Exit") exit 0 ;;
    esac

    # Rows are pango markup, so read the choice back off the one
    # unambiguous number in it rather than matching the whole string.
    local dpi
    dpi=$(printf '%s' "$chosen" | grep -oP '\d+(?= dpi)' | head -1)
    if [[ "$dpi" =~ ^[0-9]+$ ]]; then
        # Clear any framebuffer scaling left over from the older
        # `--scale` approach (or restored from a profile saved back
        # then) -- the two stack, and the leftover transform would
        # keep the picture blurry no matter what the DPI says.
        xrandr --output "$output" --scale 1x1 --filter nearest
        # Persist the layout *before* touching the DPI. set_dpi ends
        # with an i3 restart, and i3's exec_always fires autostart.sh,
        # which runs `autorandr --change` -- letting that overlap with
        # apply()'s `autorandr --save` is a read/write race on the same
        # profile. Polybar is relaunched by both, which is harmless:
        # launch.sh serialises itself with a flock, and the one that
        # runs after the restart is the one that picks up the new DPI.
        apply "$output scale set to $((dpi * 100 / 96))% ($dpi dpi)"
        set_dpi "$dpi"
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
                        # Not `A && B || C`: extend_menu ends in a menu
                        # call whose exit status is whatever the user's
                        # last action returned, so a non-zero one there
                        # would have fallen through and opened show_menu
                        # a second time on top of it.
                        if [ -n "$target" ]; then
                            extend_menu "$target"
                        else
                            show_menu
                        fi
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
