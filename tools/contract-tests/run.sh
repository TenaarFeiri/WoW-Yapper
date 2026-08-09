#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SUITES="$ROOT/tools/contract-tests"
LUA="${LUA:-lua}"
LUAC="${LUAC:-luac}"
FAILED=0

for file in "$SUITES"/harness.lua "$SUITES"/test_*.lua; do
    if ! "$LUAC" -p "$file" > /dev/null 2>&1; then
        echo "[FAIL] syntax: ${file#$ROOT/}"
        "$LUAC" -p "$file" 2>&1 | head -2 | sed 's/^/       /'
        FAILED=1
    fi
done

if [ "$FAILED" -ne 0 ]; then
    exit 1
fi

for file in "$SUITES"/test_*.lua; do
    echo "[RUN ] ${file#$ROOT/}"
    if ! (cd "$ROOT" && "$LUA" "$file"); then
        FAILED=1
    fi
done

if [ "$FAILED" -ne 0 ]; then
    echo "Contract tests failed."
    exit 1
fi

echo "All contract tests passed."
