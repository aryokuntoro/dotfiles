#!/usr/bin/env bash
set -euo pipefail

# ── Dotfiles installer ────────────────────────────────────────────
# Symlinks config/<app> -> ~/.config/<app> for every app in config/,
# backing up whatever's already there first. Re-run anytime; it's
# idempotent (re-linking an existing correct symlink is a no-op).

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="$REPO_DIR/config"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"

for app_dir in "$CONFIG_SRC"/*/; do
    app="$(basename "$app_dir")"
    target="$HOME/.config/$app"

    if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$(readlink -f "$app_dir")" ]; then
        echo "==> $app already linked, skipping"
        continue
    fi

    if [ -e "$target" ] || [ -L "$target" ]; then
        mkdir -p "$BACKUP_DIR"
        echo "==> Backing up existing ~/.config/$app -> $BACKUP_DIR/$app"
        mv "$target" "$BACKUP_DIR/$app"
    fi

    echo "==> Linking $app"
    ln -s "$app_dir" "$target"
done

echo "==> Marking scripts executable"
find "$CONFIG_SRC" -type f -path "*/scripts/*.sh" -exec chmod +x {} +

echo
echo "Done. See README.md for required packages and the manual Samba"
echo "share setup (setup-samba-share.sh) -- that one needs sudo, so it"
echo "isn't run automatically here."
