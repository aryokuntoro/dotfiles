#!/usr/bin/env bash

# ── Pre-instantiate all workspaces ──────────────────────────────
# i3 only creates a workspace object once it's actually visited, so
# polybar's workspace indicator only shows workspaces used so far in
# the session. Touch all 10 once at startup so 1-0 always appear,
# then return to workspace 1. Uses "workspace number" so it matches
# by leading digit regardless of any suffix already on the name.

for n in 1 2 3 4 5 6 7 8 9 10; do
    i3-msg workspace number "$n" >/dev/null
done
i3-msg workspace number 1 >/dev/null
