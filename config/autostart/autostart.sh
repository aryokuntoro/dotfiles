#!/usr/bin/env bash

# ── Autostart Script ──────────────────────────────────────────

# Kill existing instances
killall picom dunst polybar greenclip udiskie autotiling 2>/dev/null
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
autorandr --change

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

# ── Set default rofi theme ────────────────────────────────────
if [ ! -L ~/.config/rofi/themes/current.rasi ]; then
    ln -sf ~/.config/rofi/themes/catppuccin-mocha.rasi ~/.config/rofi/themes/current.rasi
fi

# ── Set icon theme ────────────────────────────────────────────
gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"

# ── Set cursor ────────────────────────────────────────────────
gsettings set org.gnome.desktop.interface cursor-theme "Bibata-Modern-Classic"

# ── Set font ──────────────────────────────────────────────────
gsettings set org.gnome.desktop.interface font-name "JetBrainsMono Nerd Font 11"

# xset/numlockx are already set once in ~/.xinitrc at X session start;
# nm-applet/blueman-applet are intentionally not used -- network and
# bluetooth are managed through rofi (NetManagerDM.sh, rofi-bluetooth.sh)
# and their polybar modules instead, and no polybar tray is configured.

echo "Autostart complete."
