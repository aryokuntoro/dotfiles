#!/usr/bin/env bash
#
# Waits for the display(s) to actually reach the layout saved in
# autorandr's "default" profile, retrying for a while if they haven't.
# Sourced by autostart.sh; split out into its own file so it can be
# tested in isolation (see tests/autostart.test.sh) without dragging in
# autostart.sh's own unconditional side effects (killall, picom &,
# dunst &, gsettings, ...).
#
# A single `autorandr --change` used to be all autostart.sh did here:
# one attempt, no retry. On a cold boot, HDMI-0's link to this TV was
# measured hot-plugging on and off roughly 70 times over more than a
# minute before settling (grep Xorg.0.log for "HDMI-0): connected"
# after a reboot to see it happen again) -- a single autorandr --change
# landing mid-storm can miss the TV's EDID fingerprint entirely and
# apply nothing. The session then starts on whatever fallback mode the
# driver guessed blind (no EDID yet), and everything downstream --
# polybar, fonts, icons -- renders oversized against that smaller
# canvas until something eventually corrects it, which is the "why is
# my resolution huge right after login" most autorandr users on TVs
# eventually hit. This keeps nudging xrandr until the real layout is
# actually up, so polybar and everything after it only ever launch
# into the right one.

# Every "output <name>" block in the saved profile that isn't followed
# by "off", paired with its "mode WxH" line -- i.e. what the profile
# expects to be running once it's actually applied.
expected_layout() {
    awk '
        BEGIN { RS = "output "; FS = "\n" }
        NR > 1 {
            name = $1; mode = ""; isoff = 0
            for (i = 2; i <= NF; i++) {
                if ($i == "off") isoff = 1
                if ($i ~ /^mode /) { split($i, a, " "); mode = a[2] }
            }
            if (!isoff && mode != "") print name, mode
        }
    ' "$HOME/.config/autorandr/default/config"
}

# True once every output expected_layout lists is actually running at
# that resolution right now. A profile with everything off is
# vacuously satisfied -- there is nothing to wait for.
layout_matches() {
    local out mode active
    while read -r out mode; do
        active=$(xrandr --query | grep -m1 "^$out connected" | grep -oP '\d+x\d+(?=\+)')
        [ "$active" = "$mode" ] || return 1
    done < <(expected_layout)
    return 0
}

wait_for_expected_layout() {
    local profile="$HOME/.config/autorandr/default/config"
    local max_wait=90 waited=0

    # No saved profile at all (fresh install, nothing chosen yet) --
    # nothing to converge on, so don't wait for one.
    [ -f "$profile" ] || { autorandr --change; return; }

    autorandr --change
    while ! layout_matches && [ "$waited" -lt "$max_wait" ]; do
        sleep 1
        waited=$((waited + 1))
        # autorandr's own EDID-fingerprint match can keep missing
        # through a hotplug storm even once xrandr itself would
        # succeed -- retry both, autorandr mostly (it also restores
        # rotation/position/primary, which bare xrandr --auto does
        # not), xrandr --auto as the dumb fallback every third try.
        if [ "$((waited % 3))" -eq 0 ]; then
            xrandr --auto
        else
            autorandr --change
        fi
    done

    if ! layout_matches; then
        notify-send "  Monitor" "Display never reached its saved layout after ${waited}s -- check Resolution/Scale manually." 2>/dev/null
    fi
}

# Sourcing this file only defines the three functions above -- it does
# not wait for anything by itself. autostart.sh calls
# wait_for_expected_layout explicitly right after sourcing it;
# tests/autostart.test.sh sources it and calls the functions directly
# under its own stubs, and must not have a real wait fire as a side
# effect of merely reading the file.
