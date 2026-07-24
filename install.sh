#!/usr/bin/env bash
set -euo pipefail

# ── Dotfiles installer ────────────────────────────────────────────
# Symlinks config/<app> -> ~/.config/<app> for every app in config/,
# and home/<file> -> ~/.<file> for loose home-directory dotfiles
# (.xinitrc, .Xresources), backing up whatever's already there first.
# Re-run anytime; it's idempotent (re-linking an existing correct
# symlink is a no-op).

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"

link_one() {
    local source="$1" target="$2"

    if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$(readlink -f "$source")" ]; then
        echo "==> $(basename "$target") already linked, skipping"
        return
    fi

    if [ -e "$target" ] || [ -L "$target" ]; then
        mkdir -p "$BACKUP_DIR"
        echo "==> Backing up existing $target -> $BACKUP_DIR/$(basename "$target")"
        mv "$target" "$BACKUP_DIR/$(basename "$target")"
    fi

    echo "==> Linking $target"
    ln -s "$source" "$target"
}

for app_dir in "$REPO_DIR"/config/*/; do
    app="$(basename "$app_dir")"
    link_one "$app_dir" "$HOME/.config/$app"
done

for home_file in "$REPO_DIR"/home/*; do
    name="$(basename "$home_file")"
    link_one "$home_file" "$HOME/.$name"
done

echo "==> Marking scripts executable"
find "$REPO_DIR/config" -type f -path "*/scripts/*.sh" -exec chmod +x {} +

echo
echo "Done. See README.md for required packages and the manual Samba"
echo "share setup (setup-samba-share.sh) -- that one needs sudo, so it"
echo "isn't run automatically here."
