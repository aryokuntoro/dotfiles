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
#
# Themes are built from source into ~/.themes (catppuccin/gruvbox-gtk-
# theme/tokyonight-gtk-theme/everforest-gtk-theme upstream install.sh,
# Nordic plain-copied) rather than the old catppuccin-gtk-theme-*/
# gruvbox-gtk-theme-git/tokyonight-gtk-theme-git/nordic-theme AUR
# packages, so this repo no longer depends on paru for GTK theming.
# Mauve is the fixed accent across every Catppuccin flavor to match
# what was already active.
case "$(basename "$theme_path")" in
    catppuccin-mocha.rasi)     gtk_theme="Catppuccin-Mauve-Dark"; color_scheme="prefer-dark"; theme_family="catppuccin"; theme_mode="mocha" ;;
    catppuccin-frappe.rasi)    gtk_theme="Catppuccin-Frappe-Mauve-Dark"; color_scheme="prefer-dark"; theme_family="catppuccin"; theme_mode="frappe" ;;
    catppuccin-macchiato.rasi) gtk_theme="Catppuccin-Macchiato-Mauve-Dark"; color_scheme="prefer-dark"; theme_family="catppuccin"; theme_mode="macchiato" ;;
    catppuccin-latte.rasi)     gtk_theme="Catppuccin-Mauve-Light"; color_scheme="prefer-light"; theme_family="catppuccin"; theme_mode="latte" ;;
    # Tokyonight-GTK-Theme only ships Dark/Light (no Storm/Moon
    # variants), so both dark flavors share Tokyonight-Dark.
    tokyonight-night.rasi)     gtk_theme="Tokyonight-Dark"; color_scheme="prefer-dark"; theme_family="tokyonight"; theme_mode="dark" ;;
    tokyonight-storm.rasi)     gtk_theme="Tokyonight-Dark"; color_scheme="prefer-dark"; theme_family="tokyonight"; theme_mode="dark" ;;
    tokyonight-moon.rasi)      gtk_theme="Tokyonight-Dark"; color_scheme="prefer-dark"; theme_family="tokyonight"; theme_mode="dark" ;;
    tokyonight-day.rasi)       gtk_theme="Tokyonight-Light"; color_scheme="prefer-light"; theme_family="tokyonight"; theme_mode="light" ;;
    gruvbox-dark.rasi)         gtk_theme="Gruvbox-Dark"; color_scheme="prefer-dark"; theme_family="gruvbox"; theme_mode="dark" ;;
    gruvbox-light.rasi)        gtk_theme="Gruvbox-Light"; color_scheme="prefer-light"; theme_family="gruvbox"; theme_mode="light" ;;
    everforest-dark.rasi)      gtk_theme="Everforest-Dark"; color_scheme="prefer-dark"; theme_family="everforest"; theme_mode="dark" ;;
    everforest-light.rasi)     gtk_theme="Everforest-Light"; color_scheme="prefer-light"; theme_family="everforest"; theme_mode="light" ;;
    # Nordic only ships one (dark) variant -- no Darker/Light, and no
    # accent system -- theme_family stays unset so the accent override
    # below is a no-op for it.
    nord-dark.rasi)            gtk_theme="Nordic"; color_scheme="prefer-dark" ;;
    nord-light.rasi)           gtk_theme="Nordic"; color_scheme="prefer-light" ;;
    *)                         gtk_theme=""; color_scheme="prefer-dark" ;;
esac

# ── Accent override ────────────────────────────────────────────
# rofi-accent.sh ($mod+F8) persists a per-session accent name here,
# independent of the flavor/mode picked in theme-switch.sh. Hex values
# below are copied straight from each theme's own upstream sass
# palette (~/Downloads/*-GTK-Theme/themes/src/sass/_color-palette-
# *.scss at install time), not re-derived, so they match the actual
# built GTK theme exactly. A name that doesn't exist for the current
# family (e.g. a Catppuccin-only accent while Gruvbox is active), or
# no saved choice at all, leaves accent/gtk_theme at the family's own
# default set above.
accent_hex() {
    case "$1:$2:$3" in
        catppuccin:mocha:default)   echo "#27a1b9" ;;
        catppuccin:mocha:rosewater) echo "#f5e0dc" ;;
        catppuccin:mocha:flamingo)  echo "#f2cdcd" ;;
        catppuccin:mocha:pink)      echo "#f5c2e7" ;;
        catppuccin:mocha:mauve)     echo "#cba6f7" ;;
        catppuccin:mocha:red)       echo "#f38ba8" ;;
        catppuccin:mocha:maroon)    echo "#eba0ac" ;;
        catppuccin:mocha:peach)     echo "#fab387" ;;
        catppuccin:mocha:yellow)    echo "#f9e2af" ;;
        catppuccin:mocha:green)     echo "#a6e3a1" ;;
        catppuccin:mocha:teal)      echo "#94e2d5" ;;
        catppuccin:mocha:sky)       echo "#89dceb" ;;
        catppuccin:mocha:sapphire)  echo "#74c7ec" ;;
        catppuccin:mocha:blue)      echo "#89b4fa" ;;
        catppuccin:mocha:lavender)  echo "#b4befe" ;;
        catppuccin:mocha:grey)      echo "#6c7086" ;;
        catppuccin:latte:default)   echo "#006a83" ;;
        catppuccin:latte:rosewater) echo "#dc8a78" ;;
        catppuccin:latte:flamingo)  echo "#dd7878" ;;
        catppuccin:latte:pink)      echo "#ea76cb" ;;
        catppuccin:latte:mauve)     echo "#8839ef" ;;
        catppuccin:latte:red)       echo "#d20f39" ;;
        catppuccin:latte:maroon)    echo "#e64553" ;;
        catppuccin:latte:peach)     echo "#fe640b" ;;
        catppuccin:latte:yellow)    echo "#df8e1d" ;;
        catppuccin:latte:green)     echo "#40a02b" ;;
        catppuccin:latte:teal)      echo "#179299" ;;
        catppuccin:latte:sky)       echo "#04a5e5" ;;
        catppuccin:latte:sapphire)  echo "#209fb5" ;;
        catppuccin:latte:blue)      echo "#1e66f5" ;;
        catppuccin:latte:lavender)  echo "#7287fd" ;;
        catppuccin:latte:grey)      echo "#ccd0da" ;;
        catppuccin:frappe:default)   echo "#29a4bd" ;;
        catppuccin:frappe:rosewater) echo "#f2d5cf" ;;
        catppuccin:frappe:flamingo)  echo "#eebebe" ;;
        catppuccin:frappe:pink)      echo "#f4b8e4" ;;
        catppuccin:frappe:mauve)     echo "#ca9ee6" ;;
        catppuccin:frappe:red)       echo "#e78284" ;;
        catppuccin:frappe:maroon)    echo "#ea999c" ;;
        catppuccin:frappe:peach)     echo "#ef9f76" ;;
        catppuccin:frappe:yellow)    echo "#e5c890" ;;
        catppuccin:frappe:green)     echo "#a6d189" ;;
        catppuccin:frappe:teal)      echo "#81c8be" ;;
        catppuccin:frappe:sky)       echo "#99d1db" ;;
        catppuccin:frappe:sapphire)  echo "#85c1dc" ;;
        catppuccin:frappe:blue)      echo "#8caaee" ;;
        catppuccin:frappe:lavender)  echo "#babbf1" ;;
        catppuccin:frappe:grey)      echo "#6c7086" ;;
        catppuccin:macchiato:default)   echo "#589ed7" ;;
        catppuccin:macchiato:rosewater) echo "#f4dbd6" ;;
        catppuccin:macchiato:flamingo)  echo "#f0c6c6" ;;
        catppuccin:macchiato:pink)      echo "#f5bde6" ;;
        catppuccin:macchiato:mauve)     echo "#c6a0f6" ;;
        catppuccin:macchiato:red)       echo "#ed8796" ;;
        catppuccin:macchiato:maroon)    echo "#ee99a0" ;;
        catppuccin:macchiato:peach)     echo "#f5a97f" ;;
        catppuccin:macchiato:yellow)    echo "#eed49f" ;;
        catppuccin:macchiato:green)     echo "#a6da95" ;;
        catppuccin:macchiato:teal)      echo "#8bd5ca" ;;
        catppuccin:macchiato:sky)       echo "#91d7e3" ;;
        catppuccin:macchiato:sapphire)  echo "#7dc4e4" ;;
        catppuccin:macchiato:blue)      echo "#8aadf4" ;;
        catppuccin:macchiato:lavender)  echo "#b7bdf8" ;;
        catppuccin:macchiato:grey)      echo "#6c7086" ;;
        gruvbox:dark:default) echo "#7daea3" ;;
        gruvbox:dark:red)     echo "#ea6962" ;;
        gruvbox:dark:pink)    echo "#d3869b" ;;
        gruvbox:dark:purple)  echo "#d386cd" ;;
        gruvbox:dark:blue)    echo "#7daea3" ;;
        gruvbox:dark:teal)    echo "#89b482" ;;
        gruvbox:dark:green)   echo "#a9b665" ;;
        gruvbox:dark:yellow)  echo "#d8a657" ;;
        gruvbox:dark:orange)  echo "#e78a4e" ;;
        gruvbox:dark:grey)    echo "#7c6f64" ;;
        gruvbox:light:default) echo "#45707a" ;;
        gruvbox:light:red)     echo "#c14a4a" ;;
        gruvbox:light:pink)    echo "#b16286" ;;
        gruvbox:light:purple)  echo "#ab62b1" ;;
        gruvbox:light:blue)    echo "#45707a" ;;
        gruvbox:light:teal)    echo "#4c7a5d" ;;
        gruvbox:light:green)   echo "#6c782e" ;;
        gruvbox:light:yellow)  echo "#b47109" ;;
        gruvbox:light:orange)  echo "#c35e0a" ;;
        gruvbox:light:grey)    echo "#d5c4a1" ;;
        tokyonight:dark:default) echo "#27a1b9" ;;
        tokyonight:dark:red)     echo "#f7768e" ;;
        tokyonight:dark:pink)    echo "#ff007c" ;;
        tokyonight:dark:purple)  echo "#bb9af7" ;;
        tokyonight:dark:blue)    echo "#7aa2f7" ;;
        tokyonight:dark:teal)    echo "#1abc9c" ;;
        tokyonight:dark:green)   echo "#73daca" ;;
        tokyonight:dark:yellow)  echo "#e0af68" ;;
        tokyonight:dark:orange)  echo "#ff9e64" ;;
        tokyonight:dark:grey)    echo "#737aa2" ;;
        tokyonight:light:default) echo "#006a83" ;;
        tokyonight:light:red)     echo "#f52a65" ;;
        tokyonight:light:pink)    echo "#d20065" ;;
        tokyonight:light:purple)  echo "#7847bd" ;;
        tokyonight:light:blue)    echo "#2e7de9" ;;
        tokyonight:light:teal)    echo "#118c74" ;;
        tokyonight:light:green)   echo "#387068" ;;
        tokyonight:light:yellow)  echo "#8c6c3e" ;;
        tokyonight:light:orange)  echo "#b15c00" ;;
        tokyonight:light:grey)    echo "#c7c7d1" ;;
        everforest:dark:default) echo "#7fbbb3" ;;
        everforest:dark:red)     echo "#e67e80" ;;
        everforest:dark:orange)  echo "#e69875" ;;
        everforest:dark:purple)  echo "#d699b6" ;;
        everforest:dark:blue)    echo "#7fbbb3" ;;
        everforest:dark:teal)    echo "#83c092" ;;
        everforest:dark:green)   echo "#a7c080" ;;
        everforest:dark:yellow)  echo "#dbbc7f" ;;
        everforest:dark:pink)    echo "#d3869b" ;;
        everforest:dark:grey)    echo "#56635f" ;;
        everforest:light:default) echo "#3a94c5" ;;
        everforest:light:red)     echo "#f85552" ;;
        everforest:light:orange)  echo "#f57d26" ;;
        everforest:light:purple)  echo "#df69ba" ;;
        everforest:light:blue)    echo "#3a94c5" ;;
        everforest:light:teal)    echo "#35a77c" ;;
        everforest:light:green)   echo "#8da101" ;;
        everforest:light:yellow)  echo "#dfa000" ;;
        everforest:light:pink)    echo "#b16286" ;;
        everforest:light:grey)    echo "#e0dcc7" ;;
    esac
}

gtk_folder_for_accent() {
    local family="$1" mode="$2" accent="$3" cap=""
    if [ -n "$accent" ] && [ "$accent" != "default" ]; then
        cap="$(tr '[:lower:]' '[:upper:]' <<< "${accent:0:1}")${accent:1}-"
    fi
    case "$family:$mode" in
        catppuccin:mocha)     echo "Catppuccin-${cap}Dark" ;;
        catppuccin:latte)     echo "Catppuccin-${cap}Light" ;;
        catppuccin:frappe)    echo "Catppuccin-Frappe-${cap}Dark" ;;
        catppuccin:macchiato) echo "Catppuccin-Macchiato-${cap}Dark" ;;
        gruvbox:dark)         echo "Gruvbox-${cap}Dark" ;;
        gruvbox:light)        echo "Gruvbox-${cap}Light" ;;
        tokyonight:dark)      echo "Tokyonight-${cap}Dark" ;;
        tokyonight:light)     echo "Tokyonight-${cap}Light" ;;
        everforest:dark)      echo "Everforest-${cap}Dark" ;;
        everforest:light)     echo "Everforest-${cap}Light" ;;
    esac
}

saved_accent=$(cat "$HOME/.cache/theme-accent" 2>/dev/null)
accent_overridden=""
if [ -n "$theme_family" ] && [ -n "$saved_accent" ]; then
    override_hex=$(accent_hex "$theme_family" "$theme_mode" "$saved_accent")
    override_folder=$(gtk_folder_for_accent "$theme_family" "$theme_mode" "$saved_accent")
    if [ -n "$override_hex" ] && [ -d "$HOME/.themes/$override_folder" ]; then
        accent="$override_hex"
        gtk_theme="$override_folder"
        accent_overridden=1
    fi
fi

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

# ── Rofi's own primary theme file ─────────────────────────────────
# current.rasi is a symlink (managed by theme-switch.sh) into this
# live ~/.config/rofi/themes copy of the family file ($theme_path) --
# every drun/run/window/calc/emoji/clipboard/wallpaper invocation reads
# it directly rather than shared.rasi above, so without this, an accent
# picked in rofi-accent.sh reached i3/dunst/polybar/the special-purpose
# menus but never rofi's own primary menus, which kept showing the
# family's built-in accent regardless of what was picked.
#
# Appended as its own cascading block rather than editing the file's
# own top-of-file "accent: ..." line in place: that line is also this
# script's *read* source for the un-overridden default (get_color,
# above) on every future run, for this family and every other one --
# overwriting it would make an old override stick permanently as the
# new "default" once written, surviving even switching to a different
# theme and back. rofi's rasi cascade applies later blocks over
# earlier ones for the same property (confirmed with `rofi
# -dump-theme`), so a small block appended at the end wins for actual
# rendering while leaving the original line, and therefore get_color's
# reading of it, untouched.
strip_marker="/* ACCENT-OVERRIDE-START */"
awk -v strip="$strip_marker" '
    $0 == strip { skip = 1; next }
    /\/\* ACCENT-OVERRIDE-END \*\// { skip = 0; next }
    !skip { print }
' "$theme_path" > "$theme_path.tmp"
if [ -n "$accent_overridden" ]; then
    {
        cat "$theme_path.tmp"
        printf '\n%s\n* { accent: %s; }\n/* ACCENT-OVERRIDE-END */\n' "$strip_marker" "$accent"
    } > "$theme_path"
    rm -f "$theme_path.tmp"
else
    mv "$theme_path.tmp" "$theme_path"
fi

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
