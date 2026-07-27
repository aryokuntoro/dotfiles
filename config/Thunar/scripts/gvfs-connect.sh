#!/usr/bin/env bash

# ── GVFS "Connect to Server" for Thunar ─────────────────────────────
# rofi picker to mount a network share (SMB/SFTP/FTP/WebDAV/NFS) via
# gvfs, then open it in Thunar. Only offers protocols whose gvfs
# backend is actually installed on this machine.
#
# The `gio mount` call runs inside a kitty window rather than directly:
# gio's username/password prompt is terminal-only (there is no GUI
# polkit/keyring askpass agent registered in this session), so without
# a real tty a share that requires a login would just hang forever.

ROFI_THEME="$HOME/.config/rofi/themes/current.rasi"

rofi_menu() {
    rofi -dmenu -i -p "$1" -theme "$ROFI_THEME"
}

rofi_input() {
    rofi -dmenu -i -p "$1" -mesg "$2" -theme "$ROFI_THEME" </dev/null
}

# Thunar has no D-Bus call to navigate an existing window (org.gtk.
# Application.Open is explicitly unimplemented), and plain `thunar
# <uri>` always opens a brand new window even while one is already
# open. So: if a real (non-helper) Thunar window exists, drive it
# directly -- focus, Ctrl+L, type the uri, Enter -- instead of
# spawning another one.
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

declare -a ORDER=()
declare -A SCHEME=()
declare -A HINT=()

# add_protocol <gvfsd binary> <nerd-font glyph> <label> <scheme> <address hint>
add_protocol() {
    local backend="$1" glyph="$2" label="$3" scheme="$4" hint="$5"
    [ -x "/usr/lib/$backend" ] || return
    local entry="${glyph}  ${label}"
    ORDER+=("$entry")
    SCHEME["$entry"]="$scheme"
    HINT["$entry"]="$hint"
}

add_protocol gvfsd-smb  $'' "Windows Share (SMB)" smb  "[user@]host/share"
add_protocol gvfsd-sftp $'' "SSH / SFTP"          sftp "[user@]host[:port]/path"
add_protocol gvfsd-ftp  $'' "FTP"                 ftp  "[user@]host/path"
add_protocol gvfsd-dav  $'' "WebDAV"              dav  "host/path"
add_protocol gvfsd-nfs  $'' "NFS"                 nfs  "host/export"

if [ ${#ORDER[@]} -eq 0 ]; then
    notify-send "  Connect to Server" "No gvfs network backends installed"
    exit 1
fi

choice=$(printf '%s\n' "${ORDER[@]}" | rofi_menu "Connect to Server")
[ -z "$choice" ] && exit 0

scheme="${SCHEME[$choice]}"
addr=$(rofi_input "Address" "Format: ${HINT[$choice]}")
[ -z "$addr" ] && exit 0

uri="${scheme}://${addr}"

kitty --title "Connect to Server" -e bash -c '
    uri="$1"
    echo "Connecting to $uri ..."
    if gio mount "$uri"; then
        exit 0
    else
        echo
        read -n1 -r -p "Failed to connect. Press any key to close..."
        exit 1
    fi
' _ "$uri"

if [ $? -eq 0 ]; then
    open_in_thunar "$uri"
    notify-send "  Connect to Server" "Connected to $uri"
else
    notify-send "  Connect to Server" "Failed to connect to $uri"
fi
