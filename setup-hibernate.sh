#!/usr/bin/env bash
set -euo pipefail

# ── Set up disk-backed swap + kernel resume= params for hibernate ──
# `systemctl hibernate` needs a real disk-backed swap area at least as
# big as RAM to write the memory image to -- a RAM-backed zram swap
# (common on this machine and others) can't hold it, since it vanishes
# on power-off along with everything else. This creates a real
# swapfile sized to installed RAM and wires up the kernel `resume=`
# parameters so the bootloader can find it again after power-on.
#
# Handles both filesystem layouts:
#   - btrfs: swapfile must be NOCOW and never snapshotted, so this
#     creates a dedicated top-level @swap subvolume for it (matching
#     the @home/@pkg/@log convention already used on this machine)
#     rather than reusing an existing snapshot-managed subvolume.
#   - anything else (ext4, xfs, ...): a plain swapfile via fallocate.
# And both bootloaders:
#   - GRUB: edits GRUB_CMDLINE_LINUX_DEFAULT, backs up the file first,
#     regenerates grub.cfg.
#   - systemd-boot: appends to each /boot/loader/entries/*.conf.
#
# Safe to re-run -- every step checks whether it's already done first.
# A reboot is required afterward: `resume=` only takes effect for the
# kernel cmdline of the *next* boot, not the currently running one.
#
# Usage: sudo ./setup-hibernate.sh [size_in_GiB]

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0" >&2; exit 1; }

RAM_GIB=$(( ($(awk '/MemTotal/{print $2}' /proc/meminfo) + 1048575) / 1048576 ))
SIZE_GIB="${1:-$RAM_GIB}"
SWAPFILE=/swap/swapfile
ROOT_FSTYPE=$(findmnt -no FSTYPE /)
ROOT_UUID=$(findmnt -no UUID /)

echo "==> Root filesystem: $ROOT_FSTYPE, RAM: ${RAM_GIB}GiB, swapfile size: ${SIZE_GIB}GiB"

# Piping df into tail loses df's own exit status -- tail still exits 0
# on empty input, so a failed `df /swap` (the normal case on a first
# run, before the @swap subvolume below exists yet) never fell through
# to the `/` fallback and left avail_kib empty, which the free-space
# check below then read as 0 and aborted on every fresh install.
avail_kib=$(df --output=avail /swap 2>/dev/null | tail -1)
[ -n "$avail_kib" ] || avail_kib=$(df --output=avail / | tail -1)
if [ "$((avail_kib / 1024 / 1024))" -lt "$SIZE_GIB" ]; then
    echo "Not enough free space for a ${SIZE_GIB}GiB swapfile." >&2
    exit 1
fi

if swapon --show=NAME --noheadings | grep -qx "$SWAPFILE"; then
    echo "==> $SWAPFILE already active, skipping creation"
else
    if [ "$ROOT_FSTYPE" = btrfs ]; then
        echo "==> Creating dedicated @swap subvolume (never snapshotted)"
        if ! btrfs subvolume show /swap >/dev/null 2>&1; then
            btrfs subvolume create /swap
        fi
        grep -q "subvol=/@swap" /etc/fstab || \
            echo "UUID=$ROOT_UUID  /swap  btrfs  rw,relatime,ssd,discard=async,space_cache=v2,subvol=/@swap  0 0" >> /etc/fstab
        mountpoint -q /swap || mount /swap

        echo "==> Creating NOCOW swapfile (fallocate doesn't work reliably on btrfs)"
        rm -f "$SWAPFILE"
        touch "$SWAPFILE"
        chattr +C "$SWAPFILE"
        dd if=/dev/zero of="$SWAPFILE" bs=1M count=$((SIZE_GIB * 1024)) status=progress
    else
        echo "==> Creating swapfile"
        mkdir -p "$(dirname "$SWAPFILE")"
        fallocate -l "${SIZE_GIB}G" "$SWAPFILE"
    fi

    chmod 600 "$SWAPFILE"
    mkswap "$SWAPFILE"
    grep -qF "$SWAPFILE" /etc/fstab || echo "$SWAPFILE none swap defaults 0 0" >> /etc/fstab
    swapon "$SWAPFILE"
fi

echo "==> Computing resume offset"
if [ "$ROOT_FSTYPE" = btrfs ]; then
    RESUME_OFFSET=$(btrfs inspect-internal map-swapfile -r "$SWAPFILE" 2>/dev/null | tail -1)
else
    RESUME_OFFSET=$(filefrag -v "$SWAPFILE" | awk '$1=="0:"{gsub(/\./,"",$4); print $4; exit}')
fi
[[ "$RESUME_OFFSET" =~ ^[0-9]+$ ]] || { echo "Could not compute a resume offset, aborting before touching the bootloader." >&2; exit 1; }
echo "    resume=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET"

echo "==> Adding the mkinitcpio 'resume' hook"
if ! grep -qE '^HOOKS=.*\bresume\b' /etc/mkinitcpio.conf; then
    cp /etc/mkinitcpio.conf "/etc/mkinitcpio.conf.bak.$(date +%s)"
    sed -i 's/\(HOOKS=(.*\)\bfilesystems\b/\1resume filesystems/' /etc/mkinitcpio.conf
fi

# Fold in any extra kernel params the running system has (e.g.
# zswap.enabled=0) that grub-mkconfig itself wouldn't know to add, so
# regenerating grub.cfg doesn't silently drop them.
EXTRA_PARAMS=""
# read -ra rather than `for p in $(cat ...)`: /proc/cmdline is a single
# space-separated line, so word splitting is what we want here, but the
# unquoted command substitution also glob-expanded -- a kernel parameter
# containing * or ? would have been replaced by matching filenames.
read -ra CMDLINE_PARAMS < /proc/cmdline
for p in "${CMDLINE_PARAMS[@]}"; do
    case "$p" in
        BOOT_IMAGE=*|root=*|rootflags=*|rootfstype=*|resume=*|resume_offset=*|initrd=*) ;;
        *) grep -q -- "$p" /etc/default/grub 2>/dev/null || EXTRA_PARAMS="$EXTRA_PARAMS $p" ;;
    esac
done

if command -v grub-mkconfig >/dev/null 2>&1 && [ -f /etc/default/grub ]; then
    echo "==> GRUB detected -- updating /etc/default/grub"
    cp /etc/default/grub "/etc/default/grub.bak.$(date +%s)"
    if ! grep -q "resume=" /etc/default/grub; then
        sed -i "s|^\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)\"|\1 resume=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET$EXTRA_PARAMS\"|" /etc/default/grub
    fi
    echo "    New GRUB_CMDLINE_LINUX_DEFAULT:"
    grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub | sed 's/^/    /'
    grub-mkconfig -o /boot/grub/grub.cfg
elif command -v bootctl >/dev/null 2>&1 && [ -d /boot/loader/entries ]; then
    echo "==> systemd-boot detected -- updating loader entries"
    for entry in /boot/loader/entries/*.conf; do
        [ -f "$entry" ] || continue
        grep -q "resume=" "$entry" || {
            cp "$entry" "$entry.bak.$(date +%s)"
            sed -i "/^options /s/\$/ resume=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET$EXTRA_PARAMS/" "$entry"
        }
    done
else
    echo "Unrecognized bootloader -- add this manually to your kernel cmdline:" >&2
    echo "    resume=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET$EXTRA_PARAMS" >&2
fi

echo "==> Rebuilding initramfs"
mkinitcpio -P

echo "==> Done. Reboot required -- resume= only applies to the kernel cmdline of the *next* boot."
echo "    After rebooting, verify with: cat /proc/cmdline (should show resume=...) then systemctl hibernate"
