#!/usr/bin/env bash
#
# Runs every tests/*.test.sh and summarises the result.
#
# Deliberately not bats or shellspec: this repo is meant to bring up a
# bare Arch install, and `make test` should work before anything beyond
# bash and coreutils exists. The assertion helpers live in
# tests/lib/harness.sh.
#
# Exit status: 0 when every file passes, 1 otherwise.

set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

shopt -s nullglob
files=("$TESTS_DIR"/*.test.sh)
shopt -u nullglob

if [ "${#files[@]}" -eq 0 ]; then
    printf 'No test files found in %s\n' "$TESTS_DIR" >&2
    exit 1
fi

failed=0
for file in "${files[@]}"; do
    printf '%s\n' "${file##*/}"

    # Captured rather than streamed so the summary line can be checked
    # for. The scripts under test call `exit 0` on their Exit menu arms;
    # one leaking into a test file would end it early with a success
    # status, and every remaining check would be silently skipped while
    # the run still reported green. A file that does not reach finish()
    # is a failure regardless of its exit status.
    output=$(bash "$file" 2>&1)
    status=$?
    printf '%s\n' "$output"

    if [ "$status" -ne 0 ]; then
        failed=$((failed + 1))
    elif ! printf '%s' "$output" | grep -q -- '-- [0-9]* checks'; then
        printf '  FAIL %s exited before finish() -- checks were skipped\n' "${file##*/}"
        failed=$((failed + 1))
    fi
    printf '\n'
done

if [ "$failed" -eq 0 ]; then
    printf 'All %s test file(s) passed.\n' "${#files[@]}"
    exit 0
fi

printf '%s of %s test file(s) failed.\n' "$failed" "${#files[@]}" >&2
exit 1
