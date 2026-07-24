#!/usr/bin/env bash

# ── Apply UI colors from a rofi theme's .rasi palette ──────────
# Propagates the theme's color block to i3, dunst, and polybar.
# Usage: apply-theme-colors.sh /path/to/theme.rasi

theme_path="$1"

if [ -z "$theme_path" ] && [ -L ~/.config/rofi/themes/current.rasi ]; then
    theme_path=$(readlink -f ~/.config/rofi/themes/current.rasi)
fi

if [ ! -f "$theme_path" ]; then
    echo "Theme file not found: $theme_path" >&2
    exit 1
fi

get_color() {
    grep -oP "^\s*$1:\s*\K[^;]+" "$theme_path" | tr -d ' ' | head -1
}

bg=$(get_color bg)
bg_alt=$(get_color bg-alt)
bg_hover=$(get_color bg-hover)
fg=$(get_color fg)
fg_alt=$(get_color fg-alt)
accent=$(get_color accent)
accent2=$(get_color accent2)
red=$(get_color red)
green=$(get_color green)
yellow=$(get_color yellow)
blue=$(get_color blue)
urgent=$(get_color urgent)
selected=$(get_color selected)
[ -z "$selected" ] && selected="$bg_hover"

purple=$(get_color purple)
[ -z "$purple" ] && purple=$(get_color mauve)
[ -z "$purple" ] && purple="$accent"

aqua=$(get_color aqua)
[ -z "$aqua" ] && aqua=$(get_color teal)
[ -z "$aqua" ] && aqua=$(get_color cyan)
[ -z "$aqua" ] && aqua="$blue"

orange=$(get_color orange)
[ -z "$orange" ] && orange="$accent2"

# ── GTK theme name lookup ─────────────────────────────────────────
# Single source of truth for theme_file -> GTK theme package name,
# shared by theme-switch.sh and colorreload.sh.
case "$(basename "$theme_path")" in
    catppuccin-mocha.rasi)     gtk_theme="catppuccin-mocha-mauve-standard+default"; color_scheme="prefer-dark" ;;
    catppuccin-frappe.rasi)    gtk_theme="catppuccin-frappe-mauve-standard+default"; color_scheme="prefer-dark" ;;
    catppuccin-macchiato.rasi) gtk_theme="catppuccin-macchiato-mauve-standard+default"; color_scheme="prefer-dark" ;;
    catppuccin-latte.rasi)     gtk_theme="catppuccin-latte-mauve-standard+default"; color_scheme="prefer-light" ;;
    # tokyonight-gtk-theme-git only ships Dark/Light (no Storm/Moon
    # variants), so both dark flavors share Tokyonight-Dark.
    tokyonight-night.rasi)     gtk_theme="Tokyonight-Dark"; color_scheme="prefer-dark" ;;
    tokyonight-storm.rasi)     gtk_theme="Tokyonight-Dark"; color_scheme="prefer-dark" ;;
    tokyonight-moon.rasi)      gtk_theme="Tokyonight-Dark"; color_scheme="prefer-dark" ;;
    tokyonight-day.rasi)       gtk_theme="Tokyonight-Light"; color_scheme="prefer-light" ;;
    gruvbox-dark.rasi)         gtk_theme="Gruvbox-Dark"; color_scheme="prefer-dark" ;;
    gruvbox-light.rasi)        gtk_theme="Gruvbox-Light"; color_scheme="prefer-light" ;;
    # nordic-theme only ships one (dark) variant -- no Darker/Light.
    nord-dark.rasi)            gtk_theme="Nordic"; color_scheme="prefer-dark" ;;
    nord-light.rasi)           gtk_theme="Nordic"; color_scheme="prefer-light" ;;
    *)                         gtk_theme=""; color_scheme="prefer-dark" ;;
esac

# ── System dark/light signal (xdg-desktop-portal -> Firefox etc) ──
# GTK's own gtk-application-prefer-dark-theme (settings.ini) only
# affects GTK apps directly. Portal-aware apps (Firefox, GTK4 apps
# using libadwaita) read org.freedesktop.appearance.color-scheme
# instead, which xdg-desktop-portal-gtk derives from this gsettings
# key -- so it needs to be kept in sync with the theme separately.
gsettings set org.gnome.desktop.interface color-scheme "$color_scheme" 2>/dev/null

# ── i3 ──────────────────────────────────────────────────────────
# i3's `include` directive does not feed `set` variables from the
# included file into the parent config's substitution pass, so the
# color block lives directly inside i3/config between markers.
i3_config="$HOME/.config/i3/config"

new_block=$(cat << EOF
# COLORS-START
set \$bg         $bg
set \$bg-alt     $bg_alt
set \$bg-hover   $bg_hover
set \$bg-urgent  $urgent
set \$fg         $fg
set \$fg-alt     $fg_alt
set \$fg-urgent  $bg
set \$accent     $accent
set \$accent2    $accent2
set \$red        $red
set \$green      $green
set \$yellow     $yellow
set \$blue       $blue
set \$purple     $purple
set \$aqua       $aqua
set \$orange     $orange
# COLORS-END
EOF
)

awk -v block="$new_block" '
    /# COLORS-START/ { print block; skip=1; next }
    /# COLORS-END/ { skip=0; next }
    !skip { print }
' "$i3_config" > "$i3_config.tmp" && mv "$i3_config.tmp" "$i3_config"

# ── Dunst ───────────────────────────────────────────────────────
dunstrc="$HOME/.config/dunst/dunstrc"

sed -i "0,/frame_color = /s/frame_color = .*/frame_color = \"$accent\"/" "$dunstrc"
sed -i "0,/background = /s/background = .*/background = \"$bg\"/" "$dunstrc"
sed -i "0,/foreground = /s/foreground = .*/foreground = \"$fg\"/" "$dunstrc"

sed -i "/\[urgency_low\]/,/^\[/ s/background = .*/background = \"$bg\"/" "$dunstrc"
sed -i "/\[urgency_low\]/,/^\[/ s/foreground = .*/foreground = \"$fg\"/" "$dunstrc"
sed -i "/\[urgency_low\]/,/^\[/ s/frame_color = .*/frame_color = \"$blue\"/" "$dunstrc"

sed -i "/\[urgency_normal\]/,/^\[/ s/background = .*/background = \"$bg\"/" "$dunstrc"
sed -i "/\[urgency_normal\]/,/^\[/ s/foreground = .*/foreground = \"$fg\"/" "$dunstrc"
sed -i "/\[urgency_normal\]/,/^\[/ s/frame_color = .*/frame_color = \"$accent\"/" "$dunstrc"

sed -i "/\[urgency_critical\]/,/^\[/ s/background = .*/background = \"$urgent\"/" "$dunstrc"
sed -i "/\[urgency_critical\]/,/^\[/ s/foreground = .*/foreground = \"$bg\"/" "$dunstrc"
sed -i "/\[urgency_critical\]/,/^\[/ s/frame_color = .*/frame_color = \"$urgent\"/" "$dunstrc"

# ── Polybar ─────────────────────────────────────────────────────
polybar_ini="$HOME/.config/polybar/config.ini"

sed -i "/\[colors\]/,/^\[/ s/^background = .*/background = $bg/" "$polybar_ini"
sed -i "/\[colors\]/,/^\[/ s/^background-alt = .*/background-alt = $bg_alt/" "$polybar_ini"
sed -i "/\[colors\]/,/^\[/ s/^foreground = .*/foreground = $fg/" "$polybar_ini"
sed -i "/\[colors\]/,/^\[/ s/^foreground-alt = .*/foreground-alt = $fg_alt/" "$polybar_ini"
sed -i "/\[colors\]/,/^\[/ s/^primary = .*/primary = $accent/" "$polybar_ini"
sed -i "/\[colors\]/,/^\[/ s/^secondary = .*/secondary = $accent2/" "$polybar_ini"
sed -i "/\[colors\]/,/^\[/ s/^alert = .*/alert = $red/" "$polybar_ini"
sed -i "/\[colors\]/,/^\[/ s/^disabled = .*/disabled = $fg_alt/" "$polybar_ini"
sed -i "/\[colors\]/,/^\[/ s/^accent = .*/accent = $accent/" "$polybar_ini"

# ── Rofi shared palette (Bluetooth/NetManagerDM/Android/etc menus) ──
# These special-purpose rofi themes @import shared.rasi instead of
# current.rasi, so they need their own palette synced here.
cat > "$HOME/.config/rofi/themes/shared.rasi" << EOF
* {
    font: "JetBrainsMono NF Bold 9";
    background: $bg;
    background-alt: $bg_alt;
    bg-hover: $bg_hover;
    foreground: $fg;
    foreground-alt: $fg_alt;
    accent: $accent;
    accent2: $accent2;
    selected: $selected;
    active: $green;
    urgent: $urgent;
}
EOF

# ── Xresources ───────────────────────────────────────────────────
# Drives Xft.* consumers and any Xresources-based app (URxvt, xterm,
# emacs, etc). Regenerated between fixed markers, then merged live.
xresources="$HOME/.Xresources"

new_xblock=$(cat << EOF
! COLORS-START
*.background:  $bg
*.foreground:  $fg
*.cursorColor: $fg
*.color0:      $bg
*.color8:      $bg_alt
*.color1:      $red
*.color9:      $red
*.color2:      $green
*.color10:     $green
*.color3:      $yellow
*.color11:     $yellow
*.color4:      $blue
*.color12:     $blue
*.color5:      $purple
*.color13:     $purple
*.color6:      $aqua
*.color14:     $aqua
*.color7:      $fg_alt
*.color15:     $fg
! COLORS-END
EOF
)

awk -v block="$new_xblock" '
    /! COLORS-START/ { print block; skip=1; next }
    /! COLORS-END/ { skip=0; next }
    !skip { print }
' "$xresources" > "$xresources.tmp" && mv "$xresources.tmp" "$xresources"

xrdb -merge "$xresources" 2>/dev/null

# ── Kitty ───────────────────────────────────────────────────────
mkdir -p "$HOME/.config/kitty"
cat > "$HOME/.config/kitty/current-theme.conf" << EOF
background            $bg
foreground             $fg
cursor                 $fg
selection_background   $selected
selection_foreground   $fg
color0                 $bg
color8                 $bg_alt
color1                 $red
color9                 $red
color2                 $green
color10                $green
color3                 $yellow
color11                $yellow
color4                 $blue
color12                $blue
color5                 $purple
color13                $purple
color6                 $aqua
color14                $aqua
color7                 $fg_alt
color15                $fg
active_border_color    $accent
inactive_border_color  $bg_alt
active_tab_background  $bg
active_tab_foreground  $accent
inactive_tab_background $bg_alt
inactive_tab_foreground $fg_alt
url_color               $accent
EOF

kitty @ --to unix:@mykitty set-colors --all --configured "$HOME/.config/kitty/current-theme.conf" >/dev/null 2>&1

# ── GTK 3/4 ─────────────────────────────────────────────────────
# No xsettings daemon runs under i3, so gsettings alone never reaches
# real GTK3/4 apps (Thunar, file pickers, etc) -- they read
# gtk-*.0/settings.ini directly. Patch both files here as well.
if [ -n "$gtk_theme" ]; then
    sed -i "s/^gtk-theme-name=.*/gtk-theme-name=$gtk_theme/" "$HOME/.config/gtk-3.0/settings.ini"
    sed -i "s/^gtk-theme-name = .*/gtk-theme-name = $gtk_theme/" "$HOME/.config/gtk-4.0/settings.ini"
fi

# ── Qt (qt5ct / qt6ct) ────────────────────────────────────────────
# Both plugins read the same #AARRGGBB QPalette-role-ordered format;
# one generated file is copied to both. Style/icon-theme/font are
# static (set once in qt5ct.conf/qt6ct.conf), only the palette here
# needs to track the active theme.
argb() {
    # $1 = "#rrggbb", $2 = alpha byte (default ff)
    local hex="${1#\#}" alpha="${2:-ff}"
    echo "#${alpha}${hex}"
}

qt_scheme=$(cat << EOF
[ColorScheme]
active_colors=$(argb "$fg"), $(argb "$bg_alt"), $(argb "$bg_hover"), $(argb "$bg_alt"), $(argb "$bg"), $(argb "$bg_alt"), $(argb "$fg"), $(argb "$fg"), $(argb "$fg"), $(argb "$bg"), $(argb "$bg"), $(argb "$bg"), $(argb "$accent"), $(argb "$bg"), $(argb "$accent"), $(argb "$purple"), $(argb "$bg_alt"), $(argb "$fg"), $(argb "$bg_alt"), $(argb "$fg"), $(argb "$fg_alt" 80)
disabled_colors=$(argb "$fg_alt"), $(argb "$bg_alt"), $(argb "$bg_hover"), $(argb "$bg_alt"), $(argb "$bg"), $(argb "$bg_alt"), $(argb "$fg_alt"), $(argb "$fg_alt"), $(argb "$fg_alt"), $(argb "$bg"), $(argb "$bg"), $(argb "$bg"), $(argb "$bg_alt"), $(argb "$fg_alt"), $(argb "$accent"), $(argb "$purple"), $(argb "$bg_alt"), $(argb "$fg_alt"), $(argb "$bg_alt"), $(argb "$fg_alt"), $(argb "$fg_alt" 80)
inactive_colors=$(argb "$fg"), $(argb "$bg_alt"), $(argb "$bg_hover"), $(argb "$bg_alt"), $(argb "$bg"), $(argb "$bg_alt"), $(argb "$fg"), $(argb "$fg"), $(argb "$fg"), $(argb "$bg"), $(argb "$bg"), $(argb "$bg"), $(argb "$accent"), $(argb "$bg"), $(argb "$accent"), $(argb "$purple"), $(argb "$bg_alt"), $(argb "$fg"), $(argb "$bg_alt"), $(argb "$fg"), $(argb "$fg_alt" 80)
EOF
)

mkdir -p "$HOME/.config/qt5ct/colors" "$HOME/.config/qt6ct/colors"
echo "$qt_scheme" > "$HOME/.config/qt5ct/colors/current.conf"
echo "$qt_scheme" > "$HOME/.config/qt6ct/colors/current.conf"

# ── Reload ──────────────────────────────────────────────────────
i3-msg reload >/dev/null 2>&1

killall dunst 2>/dev/null
dunst -config "$dunstrc" &

~/.config/polybar/launch.sh >/dev/null 2>&1
