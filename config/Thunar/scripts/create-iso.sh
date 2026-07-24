#!/usr/bin/env bash

# ── Create an ISO from the selected files/folders ───────────────
# Bundles a mixed selection (txt, pdf, images, docx, pptx, folders,
# etc.) into a single ISO9660 image with Joliet + Rock Ridge
# extensions (so long filenames survive on both Windows and Linux),
# saved next to the selected files. Prompts for a name via rofi.

[ $# -eq 0 ] && exit 0

dir=$(dirname "$(readlink -f "$1")")

name=$(rofi -dmenu -i -p "ISO name:" -theme ~/.config/rofi/themes/current.rasi -no-config -lines 0 < /dev/null)
[ -z "$name" ] && exit 0

# Strip a .iso the user may have typed, then re-add it once.
name="${name%.iso}"
out="$dir/$name.iso"

if [ -e "$out" ]; then
    notify-send "  Create ISO" "$(basename "$out") already exists, aborting."
    exit 1
fi

# Graft each selected item at the ISO root under its own basename,
# so selected folders stay folders instead of having their contents
# flattened into the root (xorrisofs's default without -graft-points).
graft_args=()
for item in "$@"; do
    item=$(readlink -f "$item")
    graft_args+=("$(basename "$item")=$item")
done

if xorrisofs -iso-level 3 -rock -joliet -joliet-long -graft-points -volid "$name" -output "$out" "${graft_args[@]}" >/tmp/create-iso.log 2>&1; then
    notify-send "  Create ISO" "Created $(basename "$out")"
else
    notify-send "  Create ISO" "Failed -- see /tmp/create-iso.log"
fi
