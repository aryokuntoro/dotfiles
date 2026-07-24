#!/usr/bin/env bash
set -euo pipefail

# ── Dotfiles installer ────────────────────────────────────────────
# Copies config/<app> -> ~/.config/<app> for every app directory in
# config/, config/<file> -> ~/.config/<file> for loose files directly
# in config/ (e.g. mimeapps.list), home/<file> -> ~/.<file> for loose
# home-directory dotfiles (.xinitrc, .Xresources, .bashrc, .gitconfig),
# and each file under config/applications/ ->
# ~/.local/share/applications/<file> individually (that directory is
# shared across every installed app's launcher entries, so it gets
# per-file copies instead of replacing the whole thing like
# config/<app> does). Backs up whatever's already there first. Re-run
# anytime; it's idempotent (re-copying identical content is a no-op).
#
# These are plain copies, NOT symlinks: editing a file under
# ~/.config or ~/.<dotfile> after install does not change anything in
# this repo. Edit the source here instead, then re-run ./install.sh to
# push the change out to $HOME.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"

copy_one() {
    local source="$1" target="$2"

    if [ -e "$target" ] && [ ! -L "$target" ] && diff -rq "$source" "$target" >/dev/null 2>&1; then
        echo "==> $(basename "$target") already up to date, skipping"
        return
    fi

    if [ -e "$target" ] || [ -L "$target" ]; then
        mkdir -p "$BACKUP_DIR"
        echo "==> Backing up existing $target -> $BACKUP_DIR/$(basename "$target")"
        mv "$target" "$BACKUP_DIR/$(basename "$target")"
    fi

    echo "==> Copying to $target"
    cp -r "$source" "$target"
}

echo "==> Marking scripts executable"
find "$REPO_DIR/config" -type f -path "*/scripts/*.sh" -exec chmod +x {} +

for app_dir in "$REPO_DIR"/config/*/; do
    app="$(basename "$app_dir")"
    [ "$app" = "applications" ] && continue
    copy_one "${app_dir%/}" "$HOME/.config/$app"
done

for config_file in "$REPO_DIR"/config/*; do
    [ -f "$config_file" ] || continue
    name="$(basename "$config_file")"
    copy_one "$config_file" "$HOME/.config/$name"
done

for home_file in "$REPO_DIR"/home/*; do
    name="$(basename "$home_file")"
    target="$HOME/.$name"
    # gitconfig is a seed, not a synced file: once it exists, it's
    # expected to carry machine-local user.name/user.email that
    # aren't in the repo (see README), so re-running install.sh must
    # never overwrite it.
    if [ "$name" = "gitconfig" ] && [ -e "$target" ]; then
        echo "==> .gitconfig already present, leaving local identity untouched"
        continue
    fi
    copy_one "$home_file" "$target"
done

mkdir -p "$HOME/.local/share/applications"
for desktop_file in "$REPO_DIR"/config/applications/*; do
    name="$(basename "$desktop_file")"
    copy_one "$desktop_file" "$HOME/.local/share/applications/$name"
done

echo
echo "Done. See README.md for required packages and the manual Samba"
echo "share setup (setup-samba-share.sh) -- that one needs sudo, so it"
echo "isn't run automatically here."
