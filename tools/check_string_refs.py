#!/usr/bin/env python3
"""check_string_refs.py — guard UI string-key coverage.

The canonical string table is `Strings._enUS` in Src/Strings.lua.  Every
key referenced by a resolver call in shipped source must exist there:

    Strings:Get("ui.spellcheck.more")     L:Get("ui.emotes.hint")
    S("ui.spellcheck.split", i, v)        YapperAPI:GetString("ui.x")

Keys are dot-namespaced (e.g. "ui.spellcheck.more"); a reference is only
counted when the literal contains a dot, which keeps unrelated short
helper names like `S("plain")` from being mistaken for string lookups.

Checks:
  1. every referenced key exists in the enUS canonical table   [FAIL]
  2. every enUS key is referenced by at least one call site    [WARN]

Usage:
    python3 tools/check_string_refs.py       # check; exit 1 on failures
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Src"
STRINGS_LUA = SRC / "Strings.lua"

# `["key"] = "value"` entries inside the `Strings._enUS = { ... }` block.
ENUS_ENTRY_RE = re.compile(r'^\s*\[\s*"([A-Za-z_][\w.]*)"\s*\]\s*=')

# Resolver call sites; the literal must contain a dot (namespace separator).
CALL_RE = re.compile(
    r'(?:[A-Za-z_.]*Strings:Get|\bL:Get|\bS|GetString)\(\s*["\']([A-Za-z_][\w]*(?:\.[\w]+)+)["\']'
)


def load_enus_keys():
    text = STRINGS_LUA.read_text(encoding="utf-8")
    m = re.search(r"Strings\._enUS\s*=\s*\{", text)
    if not m:
        return None
    keys = set()
    for line in text[m.end():].splitlines():
        if re.match(r"^\s*\}", line):
            break
        km = ENUS_ENTRY_RE.match(line)
        if km:
            keys.add(km.group(1))
    return keys


def iter_lua_files():
    yield from sorted(SRC.rglob("*.lua"))


def collect_referenced_keys():
    refs = {}  # key -> first (file, line) seen
    for path in iter_lua_files():
        if path == STRINGS_LUA:
            continue
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except OSError:
            continue
        for lineno, line in enumerate(lines, 1):
            for m in CALL_RE.finditer(line):
                refs.setdefault(m.group(1), (path, lineno))
    return refs


def main():
    enus = load_enus_keys()
    if enus is None:
        print(f"  [FAIL] could not locate Strings._enUS table in {STRINGS_LUA}")
        return 1

    refs = collect_referenced_keys()

    errors = []
    for key, (path, lineno) in sorted(refs.items()):
        if key not in enus:
            errors.append(
                f"{path.relative_to(ROOT)}:{lineno}: unknown string key \"{key}\""
            )

    dead = sorted(enus - set(refs))
    for key in dead:
        print(f"  [WARN] enUS key \"{key}\" is never referenced (dead string?)")

    if errors:
        for e in errors:
            print(f"  [FAIL] {e}")
        print(f"\n{len(refs)} key(s) referenced, {len(enus)} defined, "
              f"{len(errors)} unknown")
        return 1

    print(f"  [OK] {len(refs)} key(s) referenced, {len(enus)} defined, "
          f"0 unknown, {len(dead)} unreferenced")
    return 0


if __name__ == "__main__":
    sys.exit(main())
