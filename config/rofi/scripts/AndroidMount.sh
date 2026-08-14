#!/bin/sh
# =============================================================
# gh0stzk
# https://github.com/gh0stzk/dotfiles
# 10.07.2024 07:05:25
# Mount and unmount Android device using simple-mtpfs and Rofi
#
# Copyright (C) 2021-2026 gh0stzk <z0mbi3.zk@protonmail.com>
# Licensed under GPL-3.0 license
# =============================================================

BASE_MOUNT_POINT="$HOME/Android_Mount"
ROFI_THEME="$HOME/.config/rofi/themes/Android.rasi"

# Fail loudly instead of showing an empty/broken rofi menu -- simple-mtpfs
# is an AUR package (not in the official repos) and easy to be missing on
# a system this hasn't been installed on yet.
for dep in rofi simple-mtpfs dunstify; do
	if ! command -v "$dep" >/dev/null 2>&1; then
		notify-send "  Android Mount" "Missing required command: $dep" 2>/dev/null
		echo "AndroidMount: missing required command: $dep" >&2
		exit 1
	fi
done

# fusermount (FUSE2) vs fusermount3 (FUSE3): which name exists depends on
# how libfuse was installed, and a future/different system may ship only
# one of the two.
if command -v fusermount3 >/dev/null 2>&1; then
	FUSERMOUNT="fusermount3"
elif command -v fusermount >/dev/null 2>&1; then
	FUSERMOUNT="fusermount"
else
	notify-send "  Android Mount" "Missing required command: fusermount/fusermount3" 2>/dev/null
	echo "AndroidMount: missing required command: fusermount/fusermount3" >&2
	exit 1
fi

list_devices() {
	simple-mtpfs -l | awk -F': ' '{print $1 " " $2}' | rofi -dmenu -p "Select device" -theme "$ROFI_THEME"
}

is_mounted() {
	mount | grep "$1" >/dev/null
}

mount_device() {
	DEVICE_NUM=$1
	MOUNT_POINT=$2
	if [ ! -d "$MOUNT_POINT" ]; then
		mkdir -p "$MOUNT_POINT"
	fi

	if simple-mtpfs --device "$DEVICE_NUM" "$MOUNT_POINT"; then
		dunstify -i phone -a Android "Android Mount" "Android device $DEVICE_NUM mounted at $MOUNT_POINT"
	else
		dunstify -i phone -a Android "Android Mount" "Failed to mount Android device $DEVICE_NUM"
	fi
}

unmount_device() {
	MOUNT_POINT=$1
	if "$FUSERMOUNT" -u "$MOUNT_POINT"; then
		dunstify -i phone -a Android "Android Unmount" "Android device unmounted from $MOUNT_POINT"
		rmdir "$MOUNT_POINT"
	else
		dunstify -i phone -a Android "Android Unmount" "Failed to unmount Android device"
	fi
}

DEVICE=$(list_devices)
DEVICE_NUM=$(echo "$DEVICE" | awk '{print $1}')
DEVICE_NAME=$(echo "$DEVICE" | awk '{$1=""; print $0}' | xargs) # Remove the leading number and trim whitespace
MOUNT_POINT="$BASE_MOUNT_POINT/$DEVICE_NAME"

if [ -z "$DEVICE_NUM" ]; then
	dunstify -i phone -a Android "Android Mount" "No device selected"
	exit 1
fi

if is_mounted "$MOUNT_POINT"; then
	ACTION=$(echo "Unmount" | rofi -dmenu -p "$DEVICE_NAME is mounted" -theme "$ROFI_THEME")
	if [ "$ACTION" = "Unmount" ]; then
		unmount_device "$MOUNT_POINT"
	fi
else
	ACTION=$(echo "Mount" | rofi -dmenu -p "$DEVICE_NAME is not mounted" -theme "$ROFI_THEME")
	if [ "$ACTION" = "Mount" ]; then
		mount_device "$DEVICE_NUM" "$MOUNT_POINT"
	fi
fi
