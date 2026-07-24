#!/usr/bin/env bash

# ── Polybar media controls via playerctl (MPRIS) ─────────────────
# Works with any MPRIS-compliant player/browser (Spotify, VLC, mpv,
# Firefox, Chromium, ...) with no per-app hardcoding: playerctl just
# enumerates whatever is on the session bus. When several players
# are running, the currently-Playing one is treated as "active"
# (recomputed on every render AND on every click, so a stale render
# never sends a command to the wrong player), falling back to the
# first player found if none are playing.
#
# Run with no args to render the polybar line (used by `exec`).
# Run with an arg (previous/play/pause/stop/next/shuffle/repeat) to
# act on the active player (used by the click actions below).

CONF="$HOME/.config/polybar/config.ini"
color() { grep -m1 "^$1 = " "$CONF" | sed 's/^[a-z-]* = //'; }
ACCENT=$(color accent)
FG=$(color foreground)
DISABLED=$(color disabled)

# Font Awesome only: FA has no dedicated "shuffle off" or "repeat one"
# glyphs, so those states reuse the base icon and rely on color
# (ACCENT vs DISABLED) to signal on/off, same as elsewhere in this bar.
ICON_PREV=$'\U0000f048'             # fa-step_backward
ICON_PLAY=$'\U0000f04b'             # fa-play
ICON_PAUSE=$'\U0000f04c'            # fa-pause
ICON_STOP=$'\U0000f04d'             # fa-stop
ICON_NEXT=$'\U0000f051'             # fa-step_forward
ICON_SHUFFLE_ON=$'\U0000f074'       # fa-shuffle
ICON_SHUFFLE_OFF=$'\U0000f074'      # fa-shuffle (dimmed)
ICON_REPEAT_PLAYLIST=$'\U0000f01e'  # fa-repeat
ICON_REPEAT_TRACK=$'\U0000f0b6'     # fa-repeat_alt
ICON_REPEAT_OFF=$'\U0000f01e'       # fa-repeat (dimmed)

active_player() {
    local players p
    players=$(playerctl -l 2>/dev/null)
    [ -z "$players" ] && return 1
    while IFS= read -r p; do
        [ "$(playerctl -p "$p" status 2>/dev/null)" = "Playing" ] && { echo "$p"; return 0; }
    done <<<"$players"
    head -n1 <<<"$players"
}

dispatch() {
    local player="$1" cmd="$2"
    case "$cmd" in
    play | pause | play-pause | stop | next | previous)
        playerctl -p "$player" "$cmd" 2>/dev/null
        ;;
    shuffle)
        if [ "$(playerctl -p "$player" shuffle 2>/dev/null)" = "On" ]; then
            playerctl -p "$player" shuffle Off 2>/dev/null
        else
            playerctl -p "$player" shuffle On 2>/dev/null
        fi
        ;;
    repeat)
        case "$(playerctl -p "$player" loop 2>/dev/null)" in
        None) playerctl -p "$player" loop Playlist 2>/dev/null ;;
        Playlist) playerctl -p "$player" loop Track 2>/dev/null ;;
        Track) playerctl -p "$player" loop None 2>/dev/null ;;
        esac
        ;;
    esac
}

PLAYER=$(active_player)

if [ -n "$1" ]; then
    [ -n "$PLAYER" ] && dispatch "$PLAYER" "$1"
    exit 0
fi

if [ -z "$PLAYER" ]; then
    echo ""
    exit 0
fi

status=$(playerctl -p "$PLAYER" status 2>/dev/null)
shuffle=$(playerctl -p "$PLAYER" shuffle 2>/dev/null)
loop=$(playerctl -p "$PLAYER" loop 2>/dev/null)

if [ "$status" = "Playing" ]; then
    play_icon="$ICON_PAUSE"
    play_cmd="pause"
else
    play_icon="$ICON_PLAY"
    play_cmd="play"
fi

case "$shuffle" in
On)
    shuffle_icon="$ICON_SHUFFLE_ON"
    shuffle_fg="$ACCENT"
    ;;
*)
    shuffle_icon="$ICON_SHUFFLE_OFF"
    shuffle_fg="$DISABLED"
    ;;
esac

case "$loop" in
Playlist)
    repeat_icon="$ICON_REPEAT_PLAYLIST"
    repeat_fg="$ACCENT"
    ;;
Track)
    repeat_icon="$ICON_REPEAT_TRACK"
    repeat_fg="$ACCENT"
    ;;
*)
    repeat_icon="$ICON_REPEAT_OFF"
    repeat_fg="$DISABLED"
    ;;
esac

artist=$(playerctl -p "$PLAYER" metadata artist 2>/dev/null)
title=$(playerctl -p "$PLAYER" metadata title 2>/dev/null)
if [ -n "$artist" ] && [ -n "$title" ]; then
    now_playing="$artist - $title"
else
    now_playing="${title:-$artist}"
fi
now_playing=${now_playing//%/%%}

# Running-text (marquee): slide a fixed-width window across the title,
# one char per tick. Offset persists across script invocations (each
# poll re-execs from scratch) via a state file, and resets whenever
# the track text changes.
WIDTH=30
SEP="   •   "
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/polybar-playerctl"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/scroll-state"

display="$now_playing"
if [ "${#now_playing}" -gt "$WIDTH" ]; then
    padded="${now_playing}${SEP}"
    plen=${#padded}
    doubled="${padded}${padded}"

    prev_text="" prev_offset=0
    if [ -f "$STATE_FILE" ]; then
        { IFS= read -r prev_text; IFS= read -r prev_offset; } <"$STATE_FILE"
    fi

    if [ "$prev_text" = "$now_playing" ]; then
        offset=$(((prev_offset + 1) % plen))
    else
        offset=0
    fi

    printf '%s\n%s\n' "$now_playing" "$offset" >"$STATE_FILE"
    display="${doubled:offset:WIDTH}"
else
    rm -f "$STATE_FILE" 2>/dev/null
fi

SELF="$HOME/.config/polybar/scripts/playerctl.sh"

line=""
line+="%{A1:$SELF previous:}%{F$ACCENT}$ICON_PREV%{F-}%{A} "
line+="%{A1:$SELF $play_cmd:}%{F$ACCENT}$play_icon%{F-}%{A} "
line+="%{A1:$SELF stop:}%{F$ACCENT}$ICON_STOP%{F-}%{A} "
line+="%{A1:$SELF next:}%{F$ACCENT}$ICON_NEXT%{F-}%{A} "
line+="%{A1:$SELF shuffle:}%{F$shuffle_fg}$shuffle_icon%{F-}%{A} "
line+="%{A1:$SELF repeat:}%{F$repeat_fg}$repeat_icon%{F-}%{A} "
[ -n "$display" ] && line+="%{F$FG}$display%{F-} "

echo "$line"
