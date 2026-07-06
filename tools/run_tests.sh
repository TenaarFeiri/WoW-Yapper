#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run_tests.sh — Yapper test runner
#
# Usage:
#   tools/run_tests.sh            # gating tests (what CI runs)
#   tools/run_tests.sh --syntax   # syntax pass only
#
# Exit code is non-zero if any syntax check or gating suite fails.
#
# Suite classification lives here on purpose: it is the single source of
# truth for what gates a commit. See tools/2.0testsuites/README.md for
# the full inventory including diagnostics and quarantined suites.
# ---------------------------------------------------------------------------
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUITES="$ROOT/tools/2.0testsuites"
LUA="${LUA:-lua}"
LUAC="${LUAC:-luac}"

# Gating suites executed from the repo root (they loadfile "Src/...").
GATING_FROM_ROOT=(
    test_state
    test_utils
    test_history
    test_migrations
    test_router
    test_chunking
    test_emotes
    test_channel_policy_chat_modes
    test_channel_policy_stress_sim
    test_editbox_pipeline_stress_sim
    test_icon_gallery_api
    test_queue_stall
    test_lockdown_fsm
)

# Gating suites executed from the suite directory (they loadfile "../../Src/...").
GATING_FROM_SUITEDIR=(
    test_api_error
    test_api_features
    test_yallm_logic
    test_yallm_extended
    test_yallm_pruning_decay_pipeline
    test_autocomplete_api
)

PASSED=0
FAILED=0
FAILED_NAMES=()

section() { printf '\n=== %s ===\n' "$1"; }

# ---------------------------------------------------------------------------
# Phase 1: syntax check every shipped Lua file.
# (A malformed generated dictionary once shipped silently; this gate is why
#  that can't happen again.)
# ---------------------------------------------------------------------------
section "Syntax check (luac -p)"
SYNTAX_FAIL=0
while IFS= read -r f; do
    if ! "$LUAC" -p "$f" > /dev/null 2>&1; then
        echo "  [FAIL] $f"
        "$LUAC" -p "$f" 2>&1 | head -2 | sed 's/^/         /'
        SYNTAX_FAIL=1
    fi
done < <(find "$ROOT" -maxdepth 1 -name '*.lua' -type f; \
         find "$ROOT/Src" "$ROOT/Dictionaries" -name '*.lua' -type f)
if [ "$SYNTAX_FAIL" -eq 0 ]; then
    echo "  [PASS] all shipped Lua files parse"
else
    FAILED=$((FAILED + 1))
    FAILED_NAMES+=("syntax")
fi

if [ "${1:-}" = "--syntax" ]; then
    [ "$SYNTAX_FAIL" -eq 0 ] && exit 0 || exit 1
fi

# ---------------------------------------------------------------------------
# Phase 1b: documentation line-reference drift.
# ---------------------------------------------------------------------------
section "Documentation references (check_doc_refs.py)"
if command -v python3 > /dev/null 2>&1; then
    if python3 "$ROOT/tools/check_doc_refs.py"; then
        echo "  [PASS] documentation line references"
    else
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("doc-refs")
        echo "  [FAIL] documentation line references drifted"
        echo "         run: python3 tools/check_doc_refs.py --fix"
    fi
else
    echo "  [SKIP] python3 not available"
fi

# ---------------------------------------------------------------------------
# Phase 2 & 3: gating suites.
# ---------------------------------------------------------------------------
run_suite() {
    local name="$1" cwd="$2"
    local out
    out=$( cd "$cwd" && timeout 120 "$LUA" "$SUITES/$name.lua" 2>&1 )
    local code=$?
    if [ "$code" -eq 0 ]; then
        PASSED=$((PASSED + 1))
        echo "  [PASS] $name"
    else
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("$name")
        echo "  [FAIL] $name (exit $code)"
        echo "$out" | grep -E 'FAIL|error|FATAL' | head -5 | sed 's/^/         /'
    fi
}

section "Gating suites (repo root)"
for t in "${GATING_FROM_ROOT[@]}"; do run_suite "$t" "$ROOT"; done

section "Gating suites (suite dir)"
for t in "${GATING_FROM_SUITEDIR[@]}"; do run_suite "$t" "$SUITES"; done

# ---------------------------------------------------------------------------
section "Summary"
echo "  Suites passed: $PASSED"
echo "  Failures:      $FAILED"
if [ "$FAILED" -gt 0 ]; then
    printf '  Failed: %s\n' "${FAILED_NAMES[*]}"
    exit 1
fi
echo "  All gating tests passed."
