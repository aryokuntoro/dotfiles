#!/usr/bin/env bash
#
# Tests for config/autostart/scripts/wait-for-layout.sh -- the retry
# loop that replaced a single, non-retrying `autorandr --change`. See
# that file's header comment for why: a cold-boot HDMI hotplug storm on
# this TV was measured lasting over a minute, well past what a one-shot
# call or a short retry budget assumes.
#
# Not run through tests/lib/harness.sh: that harness is built around
# sourcing rofi-monitor.sh (rofi stubs, a fake_rofi pick queue) which
# this script has no use for. It reuses only the assertion helpers.

# shellcheck source=tests/lib/harness.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

# harness.sh's own trap already cleans up $HARNESS_TMP; layer a real
# HOME under it so expected_layout() has an ~/.config/autorandr/default
# to read without touching the actual machine's profile.
export HOME="$HARNESS_TMP/home"
mkdir -p "$HOME/.config/autorandr/default"

write_profile() {
    printf '%s\n' "$1" > "$HOME/.config/autorandr/default/config"
}

# shellcheck source=config/autostart/scripts/wait-for-layout.sh
source "$REPO_ROOT/config/autostart/scripts/wait-for-layout.sh"

# ── expected_layout parsing ────────────────────────────────────────

write_profile 'output DVI-D-0
off
output HDMI-0
crtc 0
mode 1920x1080
pos 0x0
primary
rate 60.00'

check_eq "expected_layout skips off outputs" \
    "$(expected_layout)" "HDMI-0 1920x1080"

write_profile 'output HDMI-0
crtc 0
mode 1920x1080
pos 0x0
primary
output DP-1
crtc 1
mode 2560x1440
pos 1920x0'

check_eq "expected_layout lists every output that is on" \
    "$(expected_layout | tr '\n' ';')" "HDMI-0 1920x1080;DP-1 2560x1440;"

write_profile 'output HDMI-0
off
output DP-1
off'

check_empty "expected_layout is empty when everything is off" \
    "$(expected_layout)"

# ── layout_matches ────────────────────────────────────────────────

write_profile 'output HDMI-0
crtc 0
mode 1920x1080
pos 0x0
primary'

xrandr() {
    case " $* " in
        *" --query "*) printf 'HDMI-0 connected primary 1920x1080+0+0 (normal) 708mm x 398mm\n   1920x1080 60.00*+\n' ;;
    esac
}
if layout_matches; then _report yes "layout_matches is true when the active mode matches"; else _report no "layout_matches is true when the active mode matches"; fi

xrandr() {
    case " $* " in
        *" --query "*) printf 'HDMI-0 connected primary 640x480+0+0 (normal) 708mm x 398mm\n   1920x1080 60.00+  640x480 60.00*\n' ;;
    esac
}
if layout_matches; then _report no "layout_matches is false on a fallback mode"; else _report yes "layout_matches is false on a fallback mode"; fi

write_profile 'output HDMI-0
off'
if layout_matches; then _report yes "layout_matches is vacuously true when nothing is expected on"; else _report no "layout_matches is vacuously true when nothing is expected on"; fi

# ── wait_for_expected_layout: fast path, retry, and giving up ───────

sleep() { :; }  # pacing isn't what's under test; make retries instant

write_profile 'output HDMI-0
crtc 0
mode 1920x1080
pos 0x0
primary'

# Fast path: correct from the first query, no retry needed.
xrandr() {
    case " $* " in
        *" --query "*) printf 'HDMI-0 connected primary 1920x1080+0+0 (normal) 708mm x 398mm\n   1920x1080 60.00*+\n' ;;
    esac
}
CALLS=0
autorandr() { CALLS=$((CALLS + 1)); }
notify-send() { echo "unexpected notify: $2" >&2; }
wait_for_expected_layout
check_eq "an already-correct layout needs exactly one autorandr call" "$CALLS" "1"

# Recovers mid-storm: wrong for a while, then right, like the ~70s of
# real hotplug flapping this was written for -- just compressed, since
# sleep is stubbed to a no-op above.
TRY=0
xrandr() {
    case " $* " in
        *" --query "*)
            if [ "$TRY" -ge 10 ]; then
                printf 'HDMI-0 connected primary 1920x1080+0+0 (normal) 708mm x 398mm\n   1920x1080 60.00*+\n'
            else
                printf 'HDMI-0 connected primary 640x480+0+0 (normal) 708mm x 398mm\n   1920x1080 60.00+  640x480 60.00*\n'
            fi
            ;;
    esac
}
CALL_LOG=""
autorandr() { CALL_LOG="${CALL_LOG}A"; TRY=$((TRY + 1)); }
NOTICE=""
notify-send() { NOTICE="$2"; }
wait_for_expected_layout
check_eq "recovery mid-storm needs no failure notification" "$NOTICE" ""
check_eq "recovery mid-storm converges by the 10th attempt" "$TRY" "10"

# Every third retry falls back to bare `xrandr --auto` rather than
# autorandr again -- verified by making convergence depend on it: this
# xrandr stub only reports the correct mode once *it itself* has been
# invoked in the --auto role.
TRY=0
XRANDR_AUTO_CALLS=0
xrandr() {
    case " $* " in
        *--auto*) XRANDR_AUTO_CALLS=$((XRANDR_AUTO_CALLS + 1)) ;;
        *) : ;;
    esac
    case " $* " in
        *" --query "*)
            if [ "$XRANDR_AUTO_CALLS" -ge 1 ]; then
                printf 'HDMI-0 connected primary 1920x1080+0+0 (normal) 708mm x 398mm\n   1920x1080 60.00*+\n'
            else
                printf 'HDMI-0 connected primary 640x480+0+0 (normal) 708mm x 398mm\n   1920x1080 60.00+  640x480 60.00*\n'
            fi
            ;;
    esac
}
autorandr() { :; }
wait_for_expected_layout
check_eq "xrandr --auto is tried when autorandr alone never converges" "$XRANDR_AUTO_CALLS" "1"

# Never recovers: must stop retrying (not hang) and report failure.
xrandr() {
    case " $* " in
        *" --query "*) printf 'HDMI-0 connected primary 640x480+0+0 (normal) 708mm x 398mm\n   1920x1080 60.00+  640x480 60.00*\n' ;;
    esac
}
autorandr() { :; }
NOTICE=""
notify-send() { NOTICE="$2"; }
wait_for_expected_layout
check_contains "giving up reports how long it waited" "$NOTICE" "90s"
check_contains "giving up points at the menu to fix it manually" "$NOTICE" "Resolution/Scale"

# A profile with nothing on must not spin through the retry budget --
# regression test for a bug caught while writing this: layout_matches
# used to treat "nothing expected" as "nothing satisfied".
write_profile 'output HDMI-0
off'
xrandr() {
    case " $* " in
        *" --query "*) printf 'HDMI-0 disconnected (normal)\n' ;;
    esac
}
CALLS=0
autorandr() { CALLS=$((CALLS + 1)); }
notify-send() { echo "unexpected notify: $2" >&2; }
wait_for_expected_layout
check_eq "an all-off profile does not trigger the retry loop" "$CALLS" "1"

finish
