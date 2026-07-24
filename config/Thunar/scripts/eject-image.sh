#!/usr/bin/env bash

# ── Eject a mounted disk image (counterpart to mount-image.sh) ─────
# Finds the loop device backing the given image file, unmounts it,
# then tears down the loop device.

for f in "$@"; do
    f=$(readlink -f "$f")
    name=$(basename "$f")

    loop_dev=$(losetup -j "$f" 2>/dev/null | cut -d: -f1 | head -1)
    if [ -z "$loop_dev" ]; then
        notify-send "  Eject Image" "$name is not mounted"
        continue
    fi

    udisksctl unmount -b "$loop_dev" >/dev/null 2>&1
    udisksctl loop-delete -b "$loop_dev" >/dev/null 2>&1
    notify-send "  Eject Image" "Ejected $name"
done
