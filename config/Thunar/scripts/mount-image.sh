#!/usr/bin/env bash

# ── Mount a disk image (ISO/IMG/UDF) like Windows Explorer does ────
# Sets up a loop device via udisksctl, mounts it, and opens the
# result in Thunar. Registered as the default handler for
# application/x-iso9660-image, x-cd-image and x-raw-disk-image (so
# double-clicking an image mounts it), and also available as a
# right-click custom action.
#
# udiskie (the tray auto-mounter) races this script for newly
# appeared loop devices and usually wins, so `udisksctl mount` here
# very often reports "AlreadyMounted" rather than a fresh success --
# that is not a failure. findmnt against the loop device (not
# udisksctl's own stdout) is treated as the single source of truth
# for whether -- and where -- the image ended up mounted.

# Poll findmnt for up to ~2s for a mount point to appear on $1.
wait_for_mount() {
    local dev="$1" i
    for i in $(seq 1 10); do
        local mp
        mp=$(findmnt -n -o TARGET "$dev" 2>/dev/null | head -1)
        if [ -n "$mp" ]; then
            echo "$mp"
            return 0
        fi
        sleep 0.2
    done
    return 1
}

# Thunar has no D-Bus call to navigate an existing window (org.gtk.
# Application.Open is explicitly unimplemented: "Application does not
# open files"), and plain `thunar <path>` always opens a brand new
# window even while one is already open. So: if a real (non-helper)
# Thunar window exists, drive it directly -- focus, Ctrl+L, type the
# path, Enter -- instead of spawning another one.
open_in_thunar() {
    local path="$1" w width height win=""
    for w in $(xdotool search --class Thunar 2>/dev/null); do
        width=$(xdotool getwindowgeometry --shell "$w" 2>/dev/null | grep '^WIDTH=' | cut -d= -f2)
        height=$(xdotool getwindowgeometry --shell "$w" 2>/dev/null | grep '^HEIGHT=' | cut -d= -f2)
        if [ -n "$width" ] && [ "$width" -gt 100 ] && [ -n "$height" ] && [ "$height" -gt 100 ]; then
            win="$w"
            break
        fi
    done

    if [ -n "$win" ]; then
        xdotool windowactivate --sync "$win"
        sleep 0.2
        xdotool key --window "$win" ctrl+l
        sleep 0.2
        xdotool type --window "$win" --delay 10 -- "$path"
        xdotool key --window "$win" Return
    else
        thunar "$path" &
    fi
}

for f in "$@"; do
    f=$(readlink -f "$f")
    name=$(basename "$f")

    # Already set up as a loop device from a previous run? Reuse it
    # instead of mapping the same file twice.
    loop_dev=$(losetup -j "$f" 2>/dev/null | cut -d: -f1 | head -1)

    if [ -z "$loop_dev" ]; then
        loop_dev=$(udisksctl loop-setup -f "$f" --no-user-interaction 2>&1 | grep -oP '/dev/loop\d+')
        if [ -z "$loop_dev" ]; then
            notify-send "  Mount Image" "Failed to set up loop device for $name"
            continue
        fi
    fi

    # Already mounted (by udiskie, or a previous run)? Don't fight it.
    mount_point=$(findmnt -n -o TARGET "$loop_dev" 2>/dev/null | head -1)

    if [ -z "$mount_point" ]; then
        udisksctl mount -b "$loop_dev" >/dev/null 2>&1
        mount_point=$(wait_for_mount "$loop_dev")
    fi

    if [ -n "$mount_point" ]; then
        open_in_thunar "$mount_point"
        notify-send "  Mount Image" "Mounted $name"
    else
        notify-send "  Mount Image" "Failed to mount $name"
        udisksctl loop-delete -b "$loop_dev" 2>/dev/null
    fi
done
