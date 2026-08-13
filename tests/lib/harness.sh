#!/usr/bin/env bash
#
# shellcheck disable=SC2329,SC2034
# (SC2329/SC2034: this is a library. Every helper and variable here is
# called or read by the *.test.sh files that source it, which shellcheck
# cannot see from inside this file.)
#
# Test harness for the rofi menu scripts.
#
# The scripts under test drive a real X server and a real rofi. This
# replaces both with hermetic stand-ins: xrandr answers read-only
# queries from a fixture file and only *logs* anything that would change
# the display, and rofi returns a scripted sequence of picks. Tests
# therefore need no display at all and behave the same on any machine.
#
# The read-only allowlist is the important part, and it is an allowlist
# on purpose. An earlier ad-hoc harness blocklisted the two subcommands
# that seemed dangerous (--mode, --scale), which left `--off` live --
# exercising the monitor menu then genuinely blanked the screen and took
# polybar down with it. Anything not explicitly recognised as read-only
# is logged and refused.

# ── Paths ─────────────────────────────────────────────────────────

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
REPO_ROOT="$(cd -- "$TESTS_DIR/.." && pwd -P)"
FIXTURES="$TESTS_DIR/fixtures"

# Scratch state, one set per test file, removed on exit.
HARNESS_TMP="$(mktemp -d)"
XRANDR_LOG="$HARNESS_TMP/xrandr.log"
APPLY_LOG="$HARNESS_TMP/apply.log"
NOTIFY_LOG="$HARNESS_TMP/notify.log"
PICK_QUEUE="$HARNESS_TMP/picks"
: > "$XRANDR_LOG"; : > "$APPLY_LOG"; : > "$NOTIFY_LOG"; : > "$PICK_QUEUE"
trap 'rm -rf -- "$HARNESS_TMP"' EXIT

# Which fixture xrandr answers from, and what a mutating call returns.
FIXTURE="$FIXTURES/xrandr-single.txt"
XRANDR_RC=0

# ── Stand-ins for the outside world ───────────────────────────────

# Defined before the script under test is sourced, so its startup
# dependency check is satisfied without rofi or xrandr being installed
# (command -v finds shell functions).
harness_preload() {
    xrandr() {
        case " $* " in
            *" --query "* | *" --props "* | *" --verbose "*)
                cat "$FIXTURE"
                ;;
            *)
                printf 'xrandr %s\n' "$*" >> "$XRANDR_LOG"
                return "$XRANDR_RC"
                ;;
        esac
    }
    xrdb() { printf 'Xft.dpi:\t%s\n' "${HARNESS_DPI:-144}"; }
    rofi() { :; }
    notify-send() { printf '%s\n' "${2-}" >> "$NOTIFY_LOG"; }
    autorandr() { printf 'autorandr %s\n' "$*" >> "$XRANDR_LOG"; }
    i3-msg() { :; }
    betterlockscreen() { :; }
    edid-decode() { :; }
}

# Redefines the things the script under test defines itself, so these
# have to be installed *after* sourcing it. apply() would otherwise save
# an autorandr profile and relaunch polybar; set_dpi() would rewrite the
# real ~/.Xresources and GTK settings.
harness_override() {
    apply() { printf '%s\n' "$1" >> "$APPLY_LOG"; }
    set_dpi() { printf 'set_dpi %s\n' "$1" >> "$APPLY_LOG"; }
}

# Scripted rofi. Each queued line is matched as a substring against the
# menu rows with pango markup stripped, and the matching *raw* row is
# returned -- so tests name rows the way a human sees them. An empty
# queue answers "Exit", which unwinds any menu instead of looping.
fake_rofi() {
    local menu pattern line plain
    menu=$(cat)
    pattern=$(head -1 "$PICK_QUEUE")
    sed -i 1d "$PICK_QUEUE" 2>/dev/null
    if [ -z "$pattern" ]; then
        printf 'Exit\n'
        return
    fi
    while IFS= read -r line; do
        plain=$(printf '%s' "$line" | sed 's/<[^>]*>//g')
        case "$plain" in
            *"$pattern"*) printf '%s\n' "$line"; return ;;
        esac
    done <<< "$menu"
    printf 'Exit\n'
}

# queue_picks "TV MONITOR" "Scale" " Back"
queue_picks() {
    printf '%s\n' "$@" > "$PICK_QUEUE"
}

# ── Loading the script under test ─────────────────────────────────

load_script() {
    harness_preload
    # shellcheck disable=SC1090  # path is built at runtime, by design
    source "$REPO_ROOT/$1"
    harness_override
    rofi_command="fake_rofi -p"
}

reset_logs() {
    : > "$XRANDR_LOG"; : > "$APPLY_LOG"; : > "$NOTIFY_LOG"
}

xrandr_calls() { grep -c . < "$XRANDR_LOG"; }

# ── Assertions ────────────────────────────────────────────────────

TESTS_RUN=0
TESTS_FAILED=0

_report() {
    local ok="$1" desc="$2" detail="${3-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$ok" = yes ]; then
        printf '  ok   %s\n' "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s\n' "$desc"
        [ -n "$detail" ] && printf '%s\n' "$detail" | sed 's/^/         /'
    fi
}

check_eq() {
    local desc="$1" actual="$2" expected="$3"
    if [ "$actual" = "$expected" ]; then
        _report yes "$desc"
    else
        _report no "$desc" "expected: $expected
actual:   $actual"
    fi
}

check_contains() {
    local desc="$1" haystack="$2" needle="$3"
    case "$haystack" in
        *"$needle"*) _report yes "$desc" ;;
        *) _report no "$desc" "expected to contain: $needle
actual:              $haystack" ;;
    esac
}

check_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    case "$haystack" in
        *"$needle"*) _report no "$desc" "expected NOT to contain: $needle
actual:                  $haystack" ;;
        *) _report yes "$desc" ;;
    esac
}

check_empty() {
    local desc="$1" actual="$2"
    if [ -z "$actual" ]; then
        _report yes "$desc"
    else
        _report no "$desc" "expected empty, got: $actual"
    fi
}

# Called at the end of every test file; its exit status is what the
# runner counts.
finish() {
    printf '  -- %s checks, %s failed\n' "$TESTS_RUN" "$TESTS_FAILED"
    [ "$TESTS_FAILED" -eq 0 ]
}
