#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# run_tests.py — Yapper test runner (Windows-friendly port of run_tests.sh)
#
# Usage:
#   python tools/run_tests.py            # gating tests (what CI runs)
#   python tools/run_tests.py --syntax   # syntax pass only
#
# Exit code is non-zero if any syntax check or gating suite fails.
#
# The gating manifest below mirrors tools/run_tests.sh — keep the two in
# sync; that script remains the single source of truth for CI.
# ---------------------------------------------------------------------------

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SUITES = ROOT / "tools" / "2.0testsuites"
CONTRACT = ROOT / "tools" / "contract-tests"

# Gating suites executed from the repo root (they loadfile "Src/...").
GATING_FROM_ROOT = [
    "test_state",
    "test_utils",
    "test_history",
    "test_migrations",
    "test_router",
    "test_chunking",
    "test_emotes",
    "test_channel_policy_chat_modes",
    "test_channel_policy_stress_sim",
    "test_editbox_pipeline_stress_sim",
    "test_icon_gallery_api",
    "test_queue_stall",
    "test_keybinds",
    "test_slash_forwarding",
    "test_lockdown_fsm",
    "test_sticky_sync",
    "test_forever_names",
    "test_recolour",
    "test_engine_contract",
    "test_autocorrect",
    "test_toast",
    "test_sendposts_strip",
    "test_shadow_tint",
    "test_help_content",
]

# Gating suites executed from the suite directory (they loadfile "../../Src/...").
GATING_FROM_SUITEDIR = [
    "test_strings",
    "test_api_error",
    "test_api_features",
    "test_yallm_logic",
    "test_yallm_extended",
    "test_yallm_pruning_decay_pipeline",
    "test_autocomplete_api",
    "test_spellcheck_en_variant_inheritance",
]

passed = 0
failed = 0
failed_names = []


def section(title):
    print(f"\n=== {title} ===")


def find_tool(env_var, *names):
    """Resolve a tool path: env var -> PATH -> common Windows install dirs."""
    override = os.environ.get(env_var)
    if override:
        return override
    for name in names:
        hit = shutil.which(name)
        if hit:
            return hit
    for name in names:
        for base in (
            r"C:\Program Files (x86)\Lua\5.1",
            r"C:\Program Files\Lua\5.1",
            r"C:\Program Files (x86)\Lua",
            r"C:\Program Files\Lua",
        ):
            candidate = Path(base) / f"{name}.exe"
            if candidate.is_file():
                return str(candidate)
    return None


LUA = find_tool("LUA", "lua", "lua5.1", "luajit")
LUAC = find_tool("LUAC", "luac", "luac5.1")

if not LUA:
    print("ERROR: no lua interpreter found (set LUA env var or add lua to PATH)")
    sys.exit(2)
if not LUAC:
    print("ERROR: no luac found (set LUAC env var or add luac to PATH)")
    sys.exit(2)


# ---------------------------------------------------------------------------
# Phase 1: syntax check every shipped Lua file.
# ---------------------------------------------------------------------------
section("Syntax check (luac -p)")
syntax_fail = 0

shipped = sorted(ROOT.glob("*.lua"))
shipped += sorted((ROOT / "Src").rglob("*.lua"))
shipped += sorted((ROOT / "Dictionaries").rglob("*.lua"))

for f in shipped:
    proc = subprocess.run(
        [LUAC, "-p", str(f)], capture_output=True, text=True
    )
    if proc.returncode != 0:
        print(f"  [FAIL] {f.relative_to(ROOT)}")
        for line in (proc.stderr or proc.stdout).splitlines()[:2]:
            print(f"         {line}")
        syntax_fail = 1

if syntax_fail == 0:
    print("  [PASS] all shipped Lua files parse")
else:
    failed += 1
    failed_names.append("syntax")

if len(sys.argv) > 1 and sys.argv[1] == "--syntax":
    sys.exit(0 if syntax_fail == 0 else 1)


# ---------------------------------------------------------------------------
# Phase 1b: documentation line-reference drift.
# ---------------------------------------------------------------------------
section("Documentation references (check_doc_refs.py)")
proc = subprocess.run(
    [sys.executable, str(ROOT / "tools" / "check_doc_refs.py")], cwd=ROOT
)
if proc.returncode == 0:
    print("  [PASS] documentation line references")
else:
    failed += 1
    failed_names.append("doc-refs")
    print("  [FAIL] documentation line references drifted")
    print("         run: python3 tools/check_doc_refs.py --fix")


# ---------------------------------------------------------------------------
# Phase 1c: UI string-key coverage.
# ---------------------------------------------------------------------------
section("String-key coverage (check_string_refs.py)")
proc = subprocess.run(
    [sys.executable, str(ROOT / "tools" / "check_string_refs.py")], cwd=ROOT
)
if proc.returncode == 0:
    print("  [PASS] string-key coverage")
else:
    failed += 1
    failed_names.append("string-refs")
    print("  [FAIL] unknown string keys referenced")


# ---------------------------------------------------------------------------
# Phase 2 & 3: gating suites.
# ---------------------------------------------------------------------------
def run_suite(name, cwd):
    global passed, failed
    try:
        proc = subprocess.run(
            [LUA, str(SUITES / f"{name}.lua")],
            cwd=cwd, capture_output=True, text=True, timeout=120,
        )
        out = (proc.stdout or "") + (proc.stderr or "")
        code = proc.returncode
    except subprocess.TimeoutExpired:
        out, code = "suite timed out after 120s", 124
    if code == 0:
        passed += 1
        print(f"  [PASS] {name}")
    else:
        failed += 1
        failed_names.append(name)
        print(f"  [FAIL] {name} (exit {code})")
        shown = 0
        for line in out.splitlines():
            if any(tag in line for tag in ("FAIL", "error", "FATAL")):
                print(f"         {line}")
                shown += 1
                if shown >= 5:
                    break


section("Gating suites (repo root)")
for t in GATING_FROM_ROOT:
    run_suite(t, ROOT)

section("Gating suites (suite dir)")
for t in GATING_FROM_SUITEDIR:
    run_suite(t, SUITES)


# ---------------------------------------------------------------------------
# Contract tests: syntax-check fixtures, then run each test_*.lua from root.
# ---------------------------------------------------------------------------
section("Chat contract tests")
contract_fail = 0

fixtures = [CONTRACT / "harness.lua"] + sorted(CONTRACT.glob("test_*.lua"))
for f in fixtures:
    proc = subprocess.run([LUAC, "-p", str(f)], capture_output=True, text=True)
    if proc.returncode != 0:
        print(f"[FAIL] syntax: {f.relative_to(ROOT)}")
        for line in (proc.stderr or proc.stdout).splitlines()[:2]:
            print(f"       {line}")
        contract_fail = 1

if contract_fail == 0:
    for f in sorted(CONTRACT.glob("test_*.lua")):
        print(f"[RUN ] {f.relative_to(ROOT)}")
        proc = subprocess.run([LUA, str(f)], cwd=ROOT)
        if proc.returncode != 0:
            contract_fail = 1

if contract_fail == 0:
    print("  [PASS] chat contract tests")
else:
    failed += 1
    failed_names.append("contract-tests")
    print("  [FAIL] chat contract tests")


# ---------------------------------------------------------------------------
section("Summary")
print(f"  Suites passed: {passed}")
print(f"  Failures:      {failed}")
if failed > 0:
    print(f"  Failed: {' '.join(failed_names)}")
    sys.exit(1)
print("  All gating tests passed.")
