#!/usr/bin/env bash
# Runs every headless check for the Godot project, failing fast:
#   1. import/parse (godot --editor --quit)
#   2. tests/scripts_parse_test.gd (compiles every script; the import step does
#      not report parse errors in scripts that no scene loads)
#   3. tests/smoke_test.gd, then every other tests/*_test.gd
#   4. a short launch of the main scene (--quit-after 5)
# Usage (from anywhere): game/tests/run_all.sh [--clean]
#   --clean (or CLEAN_IMPORT=1) deletes game/.godot before the import step so
#   every asset is re-imported from scratch. CI always passes it.
# Env: GODOT=/path/to/godot   TEST_TIMEOUT=seconds per step (default 180)
#
# Known crash: after new or changed WAV assets land (e.g. a merge that brings
# in regenerated audio), a stale game/.godot import cache can make the import
# step or the first test segfault (exit code 139). Re-run with --clean.
# A step fails on a non-zero exit, a timeout, or "SCRIPT ERROR" in its output.
#
# Autoloads in --script mode (verified on Godot 4.7.2):
#   - Autoload nodes (Events, RunState) ARE instantiated and attached under
#     /root before the test's _initialize() runs. Their _enter_tree() has run,
#     but their _ready() only runs on the first frame, after _initialize().
#   - Their global identifiers (`Events`, `RunState`) are NOT available to the
#     test script or to anything it preload()s/const-references, because those
#     compile before the autoloads are registered. The compile error makes
#     Godot fall back to an empty SceneTree that never quits (a hang, hence the
#     per-step timeout here).
#   - Therefore tests reach autoloads with get_root().get_node("RunState") and
#     load() game scripts/scenes at runtime (inside _initialize or later).
#     Pure-logic modules that never mention an autoload may still be preloaded.
set -uo pipefail

GODOT="${GODOT:-godot}"
CLEAN_IMPORT="${CLEAN_IMPORT:-0}"
for arg in "$@"; do
    case "$arg" in
        --clean) CLEAN_IMPORT=1 ;;
        -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "run_all.sh: unknown argument '$arg' (use --clean)" >&2; exit 2 ;;
    esac
done
STEP_TIMEOUT="${TEST_TIMEOUT:-180}"
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dcc-tests.XXXXXX")"
declare -a RESULTS=()

if ! command -v "$GODOT" >/dev/null 2>&1; then
    echo "run_all.sh: Godot binary '$GODOT' not found (set GODOT=...)" >&2
    exit 2
fi

summary() {
    echo
    echo "==================== test summary ===================="
    for line in "${RESULTS[@]}"; do
        echo "  $line"
    done
    echo "======================================================"
}

run_step() {
    local name="$1"
    shift
    local log="$LOG_DIR/${name//[^A-Za-z0-9_.-]/_}.log"
    local started=$SECONDS
    echo "---- $name"
    timeout "$STEP_TIMEOUT" "$GODOT" --headless --path "$GAME_DIR" "$@" >"$log" 2>&1
    local code=$?
    local elapsed=$((SECONDS - started))
    local reason=""
    if [ "$code" -eq 124 ]; then
        reason="timed out after ${STEP_TIMEOUT}s (a compile error in a --script test hangs Godot)"
    elif [ "$code" -eq 139 ] && [ "$CLEAN_IMPORT" != "1" ]; then
        reason="exit code 139 (segfault; a stale .godot import cache? re-run with --clean)"
    elif [ "$code" -ne 0 ]; then
        reason="exit code $code"
    elif grep -q "SCRIPT ERROR" "$log"; then
        reason="SCRIPT ERROR in output"
    fi
    if [ -n "$reason" ]; then
        RESULTS+=("FAIL  $name  ($reason)")
        echo "     FAIL: $reason. Last 40 lines of $log:"
        tail -n 40 "$log" | sed 's/^/     | /'
        summary
        echo "FAILED at step: $name"
        exit 1
    fi
    local pass_line
    pass_line="$(grep -m1 '^PASS' "$log" || true)"
    RESULTS+=("PASS  $name  (${elapsed}s)")
    echo "     ok (${elapsed}s) ${pass_line}"
}

"$GODOT" --version
if [ "$CLEAN_IMPORT" = "1" ]; then
    echo "---- clean import: removing $GAME_DIR/.godot"
    rm -rf "$GAME_DIR/.godot"
fi
run_step "import" --editor --quit
run_step "tests/scripts_parse_test.gd" --script res://tests/scripts_parse_test.gd
run_step "tests/smoke_test.gd" --script res://tests/smoke_test.gd
for test in "$GAME_DIR"/tests/*_test.gd; do
    rel="tests/$(basename "$test")"
    case "$rel" in
        tests/smoke_test.gd|tests/scripts_parse_test.gd) continue ;;
    esac
    run_step "$rel" --script "res://$rel"
done
run_step "launch main scene (--quit-after 5)" --quit-after 5

summary
echo "ALL PASSED (logs: $LOG_DIR)"
