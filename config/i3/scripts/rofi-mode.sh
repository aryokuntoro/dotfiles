#!/usr/bin/env bash

# ── Rofi drun/run/window launcher ──────────────────────────────
# Wraps the rofi invocation so i3's own config parser never sees
# the literal { } from -theme-str (i3 uses { } for its own block
# syntax, so passing it directly in a bindsym exec breaks parsing).

mode="$1"
extra_args=("${@:2}")

exec rofi -show "$mode" -theme ~/.config/rofi/themes/current.rasi \
    -theme-str 'case-indicator { enabled: false; }' \
    "${extra_args[@]}"
