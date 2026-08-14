#!/usr/bin/env bash

# ── Autostart Script ──────────────────────────────────────────

# ── Xresources ────────────────────────────────────────────────
# Merged here, not only in ~/.xinitrc: ly can launch i3 straight from
# /usr/share/xsessions/i3.desktop, which never sources .xinitrc. On
# that login path nothing else loads Xft.* at all, so the UI scale set
# via rofi-monitor.sh (Xft.dpi) -- along with cursor size and font
# hinting -- would silently come back at the X server defaults, and
# polybar, which reads its dpi from ${xrdb:Xft.dpi:96}, would start at
# 96 while GTK apps came up at whatever settings.ini says.
[ -f ~/.Xresources ] && xrdb -merge ~/.Xresources

# Kill existing instances
killall picom dunst polybar greenclip udiskie autotiling xss-lock 2>/dev/null
pkill -f polkit-gnome-authentication-agent 2>/dev/null
sleep 0.5

# ── Polkit ────────────────────────────────────────────────────
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

# ── Compositor ────────────────────────────────────────────────
picom -b --config ~/.config/picom/picom.conf &

# ── Notifications ──────────────────────────────────────────────
dunst -config ~/.config/dunst/dunstrc &

# ── Clipboard Manager ─────────────────────────────────────────
greenclip daemon &

# ── Auto-tiling ────────────────────────────────────────────────
autotiling &

# ── Auto monitor detection ────────────────────────────────────
# Runs (and finishes) before the status bar so polybar's own monitor
# detection in launch.sh sees the final, restored layout -- both
# backgrounded would race, and polybar could start splitting
# workspaces for whatever layout X happened to auto-configure instead
# of the one autorandr is about to apply.
#
# A single `autorandr --change` used to be all this was: one attempt,
# no retry. On a cold boot, HDMI-0's link to this TV was measured
# hot-plugging on and off roughly 70 times over more than a minute
# before settling (grep Xorg.0.log for "HDMI-0): connected" after a
# reboot to see it happen again) -- a single autorandr --change landing
# mid-storm can miss the TV's EDID fingerprint entirely and apply
# nothing, leaving the session on whatever fallback mode the driver
# guessed blind. See scripts/wait-for-layout.sh, which retries until
# the real layout is actually up (or gives up and says so) -- split
# into its own file so tests/autostart.test.sh can exercise it without
# dragging in everything below (killall, picom &, gsettings, ...).
# shellcheck source=config/autostart/scripts/wait-for-layout.sh
source ~/.config/autostart/scripts/wait-for-layout.sh
wait_for_expected_layout

# ── Status Bar ────────────────────────────────────────────────
~/.config/polybar/launch.sh &

# ── Battery notifications (laptop-only, no-op if no battery) ──
~/.config/polybar/scripts/battery-notify.sh &

# ── USB automount ─────────────────────────────────────────────
udiskie --tray &

# ── Wallpaper ─────────────────────────────────────────────────
# Restores whatever wallpaper.sh last set (saved to current_wallpaper);
# falls back to the default if nothing was ever picked.
if [ -f ~/.config/i3/current_wallpaper ] && [ -f "$(cat ~/.config/i3/current_wallpaper)" ]; then
    wallpaper="$(cat ~/.config/i3/current_wallpaper)"
else
    wallpaper=~/Pictures/Wallpapers/wallpaper.jpg
fi
feh --bg-scale "$wallpaper"

# wallpaper.sh keeps betterlockscreen's cache in sync on every change;
# this only bootstraps it on a fresh install where it's never run yet
# (~10s to render, so it's backgrounded either way).
[ -d ~/.cache/betterlockscreen/current ] || betterlockscreen -u "$wallpaper" >/dev/null 2>&1 &

# ── Restore software brightness (DDC-less displays) ──────────
# backlight.sh falls back to xrandr gamma scaling when the display
# doesn't support DDC/CI (see UNSUPPORTED_CACHE in backlight.sh) --
# that scaling lives on the X server and resets to full brightness on
# every new session, so reapply whatever percentage was last set.
if [ -f ~/.cache/ddcutil-unsupported ] && [ -f ~/.cache/xrandr-brightness ]; then
    pct=$(cat ~/.cache/xrandr-brightness)
    output=$(xrandr --query | awk '/ connected/{print $1; exit}')
    if [[ "$pct" =~ ^[0-9]+$ ]] && [ -n "$output" ]; then
        xrandr --output "$output" --brightness "$(awk -v p="$pct" 'BEGIN{printf "%.2f", p/100}')"
    fi
fi

# ── Set default rofi theme ────────────────────────────────────
# Must name the same theme the rest of the shipped configs are
# coloured for (everforest-dark): the fallback only fires on a fresh
# install, where install.sh has just copied current.rasi in as a plain
# file rather than a symlink -- so it always fires there, and pointing
# it at a different theme than i3/polybar/dunst/kitty were snapshotted
# with is exactly how rofi ended up the one mismatched piece until
# theme-switch.sh was run once by hand.
if [ ! -L ~/.config/rofi/themes/current.rasi ]; then
    ln -sf ~/.config/rofi/themes/everforest-dark.rasi ~/.config/rofi/themes/current.rasi
fi

# ── Set icon theme ────────────────────────────────────────────
gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"

# ── Set cursor ────────────────────────────────────────────────
gsettings set org.gnome.desktop.interface cursor-theme "Bibata-Modern-Classic"

# ── Set font ──────────────────────────────────────────────────
gsettings set org.gnome.desktop.interface font-name "JetBrainsMono Nerd Font 11"

# nm-applet/blueman-applet are intentionally not used -- network and
# bluetooth are managed through rofi (NetManagerDM.sh, rofi-bluetooth.sh)
# and their polybar modules instead, and no polybar tray is configured.

# ── Screen timeout + blanking ─────────────────────────────────
# Lives here rather than ~/.xinitrc because ly can launch i3 straight
# from /usr/share/xsessions/i3.desktop, bypassing .xinitrc entirely --
# this exec_always is the one startup path that's guaranteed to run
# regardless of which session entry was picked at login. Adjustable
# via rofi-idle.sh ($mod+F7) or toggled off entirely via the
# presentation-mode shortcut ($mod+Shift+x,
# config/i3/scripts/toggle-idle.sh); falls back to the previous 600s
# default if the cache is missing/invalid.
idle_timeout=$(cat ~/.cache/idle-timeout 2>/dev/null)
[[ "$idle_timeout" =~ ^[0-9]+$ ]] || idle_timeout=600
if [ "$idle_timeout" -eq 0 ]; then
    xset s off
    xset -dpms
else
    xset s "$idle_timeout" "$idle_timeout"
    xset dpms "$idle_timeout" "$idle_timeout" "$idle_timeout"
fi

# Lock the screen when the timeout above blanks it -- xss-lock listens
# for the X screensaver "activate" event that `xset s` triggers.
# idle-lock-wrapper.sh checks the "Auto-Lock" toggle from rofi-idle.sh
# so locking can be disabled independently of the timeout itself.
command -v xss-lock >/dev/null 2>&1 && xss-lock -- ~/.config/i3/scripts/idle-lock-wrapper.sh &

# ── Numlock ────────────────────────────────────────────────────
# Retried: on cold boot the X server can still be finishing keyboard
# device init right after start, which makes an immediate `numlockx
# on` a no-op -- and how long that takes varies with system load, so
# a single fixed sleep sometimes still loses the race. Poll `xset
# q`'s actual indicator state instead of guessing a delay, and keep
# retrying `numlockx on` until it reports on or we give up.
(
    for _ in $(seq 1 10); do
        sleep 0.5
        xset q | grep -qE "Num Lock:[[:space:]]*on" && break
        numlockx on
    done
) &

# ── HDMI color range (NVIDIA + TV output) ─────────────────────
# NVIDIA sends Full range (0-255) RGB by default. HDMI-0 here is a TV
# rather than a real PC monitor and washes out/crushes blacks under
# Full range, so force Limited (16-235) -- what TVs actually expect
# over HDMI. No-ops harmlessly on a machine without nvidia-settings or
# without an HDMI-0 output.
# Delayed (like numlockx above): right after X starts, the NVIDIA
# driver is still repeatedly probing/mode-setting the TV over HDMI for
# a couple seconds, and a ColorRange set during that window gets
# silently reset once probing settles. Give it a few seconds first.
( sleep 3; command -v nvidia-settings >/dev/null 2>&1 && nvidia-settings -a "[HDMI-0]/ColorRange=1" >/dev/null 2>&1 ) &

echo "Autostart complete."
