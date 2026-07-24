#!/usr/bin/env bash

# ── Extract an ISO/IMG/UDF disk image to a writable folder ─────────
# xarchiver hardcodes 7z's `-tiso` mode for .iso files, which fails
# to recognize UDF-format images (common for large modern installers
# like Windows/Office ISOs -- "not recognized!"). 7z's own format
# auto-detection handles both ISO9660 and UDF correctly, so this
# calls it directly instead. Mainly useful to get a writable copy of
# a mounted-read-only image's contents (e.g. to delete/edit files,
# then re-package with "Create ISO").

for f in "$@"; do
    f=$(readlink -f "$f")
    dir=$(dirname "$f")
    name=$(basename "$f")
    out="$dir/${name%.*}"

    i=1
    base_out="$out"
    while [ -e "$out" ]; do
        out="${base_out} (${i})"
        i=$((i + 1))
    done

    mkdir -p "$out"
    if 7z x "$f" -o"$out" -y >/tmp/extract-iso.log 2>&1; then
        notify-send "  Extract ISO" "Extracted to $(basename "$out")"
    else
        # 7z reports "errors" for some UDF metadata streams even on
        # otherwise-successful extractions -- only treat it as a
        # real failure if nothing actually landed in the output dir.
        if [ -n "$(ls -A "$out" 2>/dev/null)" ]; then
            notify-send "  Extract ISO" "Extracted to $(basename "$out") (with warnings, see /tmp/extract-iso.log)"
        else
            notify-send "  Extract ISO" "Failed -- see /tmp/extract-iso.log"
            rmdir "$out" 2>/dev/null
        fi
    fi
done
