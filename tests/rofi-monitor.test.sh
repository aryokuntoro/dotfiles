#!/usr/bin/env bash
#
# Tests for config/rofi/scripts/rofi-monitor.sh.
#
# Weighted towards the things that were actually wrong at some point:
# the mode flags that used to be stripped, the guard that stops the last
# display being switched off, xrandr's exit status being ignored, layout
# changes that were split across several calls, and the navigation depth.

# shellcheck source=tests/lib/harness.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"
load_script config/rofi/scripts/rofi-monitor.sh

# ── Reading the display ───────────────────────────────────────────

check_eq "output_px reads the active mode" \
    "$(output_px HDMI-0)" "1920x1080"

check_eq "output_size_mm reads the EDID size" \
    "$(output_size_mm HDMI-0)" "708 398"

check_eq "physical_dpi computes the panel density" \
    "$(physical_dpi HDMI-0)" "69"

check_eq "diagonal_inches computes the panel diagonal" \
    "$(diagonal_inches HDMI-0)" "32"

check_eq "active_outputs lists only outputs driving a mode" \
    "$(active_outputs | tr '\n' ' ')" "HDMI-0 "

# list_modes must keep xrandr's own markers: "*" current, "+" native.
# Stripping them is why the Resolution menu had no recommendation.
check_eq "list_modes keeps the current+native flags" \
    "$(list_modes HDMI-0 | head -1)" "$(printf '1920x1080@60.00Hz\t*+')"

check_eq "list_modes leaves other modes unflagged" \
    "$(list_modes HDMI-0 | sed -n 2p)" "$(printf '1920x1080@59.94Hz\t')"

# ── Scale recommendation ──────────────────────────────────────────

check_eq "recommended_dpi suggests 150% for this 32in 69dpi panel" \
    "$(recommended_dpi HDMI-0)" "144"

check_contains "scale rows show dpi and the usable area" \
    "$(scale_row 144 1920 1080 144 96)" "144 dpi  ·  apps see 1280x720"

check_contains "the recommended row is tagged" \
    "$(scale_row 144 1920 1080 144 96)" "recommended"

check_not_contains "a non-recommended row is not tagged" \
    "$(scale_row 96 1920 1080 144 96)" "recommended"

# ── Rotation ──────────────────────────────────────────────────────

check_eq "current_rotation reports normal when xrandr omits it" \
    "$(current_rotation HDMI-0)" "normal"

FIXTURE="$FIXTURES/xrandr-rotated.txt"
check_eq "current_rotation reads an actual rotation" \
    "$(current_rotation HDMI-0)" "left"
check_eq "a connected but dark output is not counted as active" \
    "$(active_outputs | tr '\n' ' ')" "HDMI-0 "
FIXTURE="$FIXTURES/xrandr-single.txt"

# ── Mirroring ─────────────────────────────────────────────────────

FIXTURE="$FIXTURES/xrandr-dual.txt"

# 2560x1440 is DP-1's native but HDMI-0 cannot do it; 1920x1080 is the
# largest both share. Picking each panel's own preferred mode instead is
# what silently produced a crop rather than a mirror.
check_eq "common_mode picks the largest shared resolution" \
    "$(common_mode)" "1920x1080"

reset_logs
mirror_all
check_eq "mirror_all issues exactly one xrandr call" \
    "$(xrandr_calls)" "1"
check_contains "mirror_all puts both panels on the shared mode" \
    "$(cat "$XRANDR_LOG")" \
    "--output HDMI-0 --mode 1920x1080 --pos 0x0 --output DP-1 --mode 1920x1080 --pos 0x0"

reset_logs
queue_picks "HDMI-0"
single_display_menu
check_eq "single_display_menu issues exactly one xrandr call" \
    "$(xrandr_calls)" "1"
check_contains "single_display_menu keeps one output and darkens the rest" \
    "$(cat "$XRANDR_LOG")" "--output HDMI-0 --auto --primary --pos 0x0 --output DP-1 --off"

reset_logs
queue_picks "HDMI-0" "Right of"
extend_menu DP-1
check_eq "extend_menu issues exactly one xrandr call" \
    "$(xrandr_calls)" "1"
check_contains "extend_menu enables and positions in the same call" \
    "$(cat "$XRANDR_LOG")" "--output HDMI-0 --auto --output DP-1 --auto --right-of HDMI-0"

# ── Refusing to black out the last display ────────────────────────

# With two outputs live, turning one off is allowed.
reset_logs
queue_picks "Turn Off"
monitor_menu HDMI-0
check_contains "turning off one of two displays is allowed" \
    "$(cat "$XRANDR_LOG")" "--output HDMI-0 --off"

# With one, it must be refused -- and must not reach apply(), because
# apply() saves the layout into the autorandr profile that is restored
# at login. That is what turned a misclick into a black screen on boot.
FIXTURE="$FIXTURES/xrandr-single.txt"
reset_logs
queue_picks "Turn Off"
monitor_menu HDMI-0
check_empty "the last active display is not switched off" \
    "$(cat "$XRANDR_LOG")"
check_empty "and nothing is persisted for it" \
    "$(cat "$APPLY_LOG")"
check_contains "the refusal is reported to the user" \
    "$(cat "$NOTIFY_LOG")" "Refusing to turn off the only active display"

# ── xrandr's exit status ──────────────────────────────────────────

reset_logs
XRANDR_RC=0
run_xrandr "mode changed" --output HDMI-0 --mode 1920x1080
check_contains "a successful change is applied" "$(cat "$APPLY_LOG")" "mode changed"

reset_logs
XRANDR_RC=1
if run_xrandr "must not appear" --output HDMI-0 --mode 9999x9999; then
    check_eq "run_xrandr reports failure" "succeeded" "failed"
else
    _report yes "run_xrandr reports failure"
fi
check_empty "a rejected change is never applied or persisted" \
    "$(cat "$APPLY_LOG")"
check_contains "the xrandr error is surfaced" "$(cat "$NOTIFY_LOG")" "xrandr failed"
XRANDR_RC=0

# ── Navigation ────────────────────────────────────────────────────

# Every goto must name a state the dispatch loop handles, and every
# state must resolve to a function that exists. The rewrite from mutual
# recursion to a dispatch loop was mechanical, so a typo here would be
# silent until a user happened to walk that path.
script="$REPO_ROOT/config/rofi/scripts/rofi-monitor.sh"
dispatch=$(sed -n '/── Dispatch ──/,$p' "$script")
missing=""
while read -r state; do
    printf '%s' "$dispatch" | grep -qE "^ +$state\)" || missing="$missing $state"
done < <(grep -oP 'goto \K[a-z]+' "$script" | sort -u)
check_empty "every goto target is handled by the dispatch loop" "$missing"

missing=""
while read -r fn; do
    grep -q "^$fn() {" "$script" || missing="$missing $fn"
done < <(printf '%s' "$dispatch" | grep -oP '^ +[a-z]+\)\s+\K[a-z_]+' | sort -u)
check_empty "every dispatch state resolves to a real function" "$missing"

# Depth used to grow by two frames per transition and never unwind.
reset_logs
depth_log="$HARNESS_TMP/depth"
: > "$depth_log"
for fn in show_menu monitor_menu resolution_menu scale_menu rotate_menu; do
    eval "orig_$fn() $(declare -f "$fn" | tail -n +2)"
    eval "$fn() { printf '%s\n' \"\${#FUNCNAME[@]}\" >> '$depth_log'; orig_$fn \"\$@\"; }"
done
picks=()
for _ in 1 2 3 4 5 6; do
    picks+=("HDMI-0" "Scale" " Back" "Resolution" " Back" "Rotate" " Back" " Back")
done

# In a subshell: the walk ends when the queue empties, fake_rofi then
# answers "Exit", and the Exit arms of these menus call `exit 0` -- in
# this process that would take the whole test file with it, silently
# skipping everything below. The depth log is a file, so it survives.
(
    queue_picks "${picks[@]}"
    goto main
    while [ -n "$nav_state" ]; do
        _state="$nav_state"; _arg="$nav_arg"; nav_state=""; nav_arg=""
        case "$_state" in
            main) show_menu ;; monitor) monitor_menu "$_arg" ;;
            resolution) resolution_menu "$_arg" ;; scale) scale_menu "$_arg" ;;
            rotate) rotate_menu "$_arg" ;; *) break ;;
        esac
    done
) >/dev/null 2>&1
transitions=$(grep -c . < "$depth_log")
depths=$(sort -u "$depth_log" | tr '\n' ' ')
check_eq "a long menu walk really happened" "$([ "$transitions" -gt 40 ] && echo yes)" "yes"
check_eq "call depth stays constant across $transitions transitions" "$depths" "2 "

finish
