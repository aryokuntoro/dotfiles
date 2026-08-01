#!/usr/bin/env bash
set -euo pipefail

# ── Dotfiles installer launcher ────────────────────────────────────
# The actual installer is installer/ (Rust + ratatui, a TUI checklist
# of dotfiles groups and GTK theme downloads -- see installer/src).
# This is just a thin launcher so `./install.sh` stays the documented
# entry point and works on a bare tty (no X/Wayland needed, ratatui
# talks ANSI straight to the terminal). It needs cargo/rustc, which a
# fresh Arch install doesn't have by default -- `pacman -S rust` first.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v cargo >/dev/null 2>&1; then
    echo "cargo/rustc not found. Install it first, then re-run this:" >&2
    echo "  sudo pacman -S rust" >&2
    exit 1
fi

exec cargo run --manifest-path "$REPO_DIR/installer/Cargo.toml" --release
