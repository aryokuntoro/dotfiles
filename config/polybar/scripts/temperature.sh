#!/usr/bin/env bash

# ── Polybar CPU Temperature ────────────────────────────────────────
# type = internal/temperature needs a hardcoded thermal-zone index, and
# that index does not name the same sensor across machines -- on this
# box thermal_zone0 is "acpitz" (a generic ACPI/motherboard reading, not
# the CPU) while thermal_zone1 is "x86_pkg_temp", the actual CPU package
# temperature that a warning threshold should track. Numbering is not
# guaranteed stable across kernels/motherboards either, so a fixed index
# is both wrong here and not portable to different hardware.
#
# Auto-detect instead: prefer a thermal_zone whose type names a real CPU
# package sensor, then fall back to the hwmon coretemp (Intel) /
# k10temp|zenpower (AMD) drivers, then to thermal_zone0 as a last resort
# so this still shows something rather than going blank on a machine
# with neither.

WARN_TEMP=75
ICON=$'\Uf2c7' # fa-thermometer-half

CONF="$HOME/.config/polybar/config.ini"
color() { grep -m1 "^$1 = " "$CONF" | sed 's/^[a-z-]* = //'; }
ACCENT=$(color accent)
FG=$(color foreground)
ALERT=$(color alert)

find_temp_millideg() {
    local zone zone_type
    for zone in /sys/class/thermal/thermal_zone*; do
        [ -e "$zone/type" ] || continue
        zone_type=$(cat "$zone/type" 2>/dev/null)
        case "$zone_type" in
        x86_pkg_temp | cpu-thermal | soc_thermal)
            cat "$zone/temp" 2>/dev/null
            return
            ;;
        esac
    done

    local hwmon hwmon_name
    for hwmon in /sys/class/hwmon/hwmon*; do
        [ -e "$hwmon/name" ] || continue
        hwmon_name=$(cat "$hwmon/name" 2>/dev/null)
        case "$hwmon_name" in
        coretemp | k10temp | zenpower)
            cat "$hwmon/temp1_input" 2>/dev/null
            return
            ;;
        esac
    done

    # Whatever the system numbers as zone 0, even unconfirmed -- matches
    # the old internal/temperature default this replaced.
    cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null
}

millideg=$(find_temp_millideg)
[[ "$millideg" =~ ^[0-9]+$ ]] || exit 0
celsius=$((millideg / 1000))

if [ "$celsius" -ge "$WARN_TEMP" ]; then
    echo "%{F$ALERT}$ICON%{F-} %{F$ALERT}${celsius}°C%{F-}"
else
    echo "%{F$ACCENT}$ICON%{F-} %{F$FG}${celsius}°C%{F-}"
fi
