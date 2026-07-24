#!/usr/bin/env bash

# ── Rofi Network Manager ──────────────────────────────────────
# Delegates to NetManagerDM.sh, which actually scans for nearby
# networks (nmcli connection show only lists saved profiles).
exec ~/.config/rofi/scripts/NetManagerDM.sh --config ~/.config/rofi/themes/NetManagerDM.ini
