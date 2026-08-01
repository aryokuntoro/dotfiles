#!/usr/bin/env bash
set -euo pipefail

# ── One-line remote install ─────────────────────────────────────────
#   curl -fsSL https://raw.githubusercontent.com/aryokuntoro/dotfiles/master/bootstrap.sh | bash
#
# Clones (or updates) the repo, then hands off to install.sh's TUI.
# Piping to bash means this script's own stdin is the download itself,
# not the terminal -- the `< /dev/tty` on the final exec below
# reconnects stdin to the real terminal so the installer can actually
# read keyboard input. That requires a real interactive terminal to
# run this from; a `curl | bash` with no controlling tty (e.g. inside
# another script or CI) has no /dev/tty to reconnect to and will fail.
#
# Set DOTFILES_DIR to clone somewhere other than the default.

REPO_URL="https://github.com/aryokuntoro/dotfiles.git"
REPO_DIR="${DOTFILES_DIR:-$HOME/Projects/dotfiles}"

for bin in git cargo; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "$bin not found. Install it first:" >&2
        case "$bin" in
            git) echo "  sudo pacman -S git" >&2 ;;
            cargo) echo "  sudo pacman -S rust" >&2 ;;
        esac
        exit 1
    fi
done

if [ -d "$REPO_DIR/.git" ]; then
    echo "==> $REPO_DIR already exists, pulling the latest instead of re-cloning"
    git -C "$REPO_DIR" pull --ff-only
else
    echo "==> Cloning to $REPO_DIR"
    git clone "$REPO_URL" "$REPO_DIR"
fi

exec "$REPO_DIR/install.sh" < /dev/tty
