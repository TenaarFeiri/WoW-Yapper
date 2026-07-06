#!/usr/bin/env python3
"""check_doc_refs.py — guard against documentation line-reference drift.

Scans Documentation/*.md for markdown links whose target contains a
`#L<n>` (or `#L<n>-L<m>` range) fragment pointing into a source file,
then verifies:

  1. the target file exists,
  2. the referenced line(s) are within the file,
  3. when the link is adjacent to a backticked signature (the house style
     used in Internals.md / API.md, e.g.
         `Error:PrintError(code, ...) → nil` ([`../Src/Error.lua#L102`](../Src/Error.lua#L102))
     ), the referenced line actually contains that identifier's
     definition.

Usage:
    python3 tools/check_doc_refs.py          # check; exit 1 on hard drift
    python3 tools/check_doc_refs.py --fix    # rewrite drifted line numbers

Fix mode only rewrites references whose identifier resolves to exactly
one definition in the target file; ambiguous or unresolvable references
are reported for manual attention. Prose references without a nearby
identifier (common in Architecture.md) only get the existence/bounds
check, since there is nothing to match them against.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOC_DIR = ROOT / "Documentation"

# [text](path#Lstart) or [text](path#Lstart-Lend); path must be a .lua file.
LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)#]+\.lua)#L(\d+)(?:-L?(\d+))?\)")

# Signature immediately preceding the link: `Recv:Name(...) ...` ([
SIG_BEFORE_LINK_RE = re.compile(r"`([A-Za-z_][\w.:]*)\s*\([^`]*`\s*\(\[$")
# Fallback: any backticked identifier-ish token earlier on the line,
# e.g. `_G.YapperDB` ... initialised in [link]
TOKEN_RE = re.compile(r"`(?:_G\.)?([A-Za-z_][\w.:]*)`")


def find_definitions(lines, name, receiver=None):
    """Return 1-based line numbers where `name` looks defined."""
    pats = [
        re.compile(rf"^\s*function\s+[\w.]+[:.]{re.escape(name)}\s*\("),
        re.compile(rf"^\s*(local\s+)?function\s+{re.escape(name)}\s*\("),
        re.compile(rf"^\s*(local\s+)?{re.escape(name)}\s*="),
        re.compile(rf"^\s*[\w.]+\.{re.escape(name)}\s*="),
    ]
    hits = [i + 1 for i, ln in enumerate(lines) if any(p.match(ln) for p in pats)]
    if len(hits) > 1 and receiver:
        recv_hits = [n for n in hits
                     if re.match(rf"^\s*function\s+{re.escape(receiver)}[:.]", lines[n - 1])
                     or re.match(rf"^\s*{re.escape(receiver)}\.{re.escape(name)}\s*=", lines[n - 1])]
        if recv_hits:
            return recv_hits
    return hits


def extract_identifier(line, link_start):
    """Best-effort identifier for the link starting at column link_start."""
    before = line[:link_start]
    m = SIG_BEFORE_LINK_RE.search(before + "[")
    if m:
        full = m.group(1)          # e.g. Error:PrintError or Spellcheck.Foo
        parts = re.split(r"[:.]", full)
        name = parts[-1]
        receiver = parts[-2] if len(parts) > 1 else None
        return name, receiver, True     # confident: signature-adjacent
    tokens = [t for t in TOKEN_RE.findall(before) if ".lua" not in t and "#L" not in t]
    if tokens:
        parts = re.split(r"[:.]", tokens[-1])
        return parts[-1], (parts[-2] if len(parts) > 1 else None), False
    return None, None, False


def main():
    fix = "--fix" in sys.argv
    hard_errors = []
    warnings = []
    fixed = 0
    src_cache = {}

    for md in sorted(DOC_DIR.glob("*.md")):
        text = md.read_text(encoding="utf-8")
        out_lines = []
        changed = False

        for lineno, line in enumerate(text.splitlines(keepends=True), 1):
            new_line = line
            # release.sh annotates entries pending human confirmation with
            # [MISSING]/[NEW]; drift on those lines is expected until someone
            # confirms them, so report as warnings rather than failing CI.
            pending_confirmation = "[MISSING]" in line or "[NEW]" in line
            for m in LINK_RE.finditer(line):
                link_text, rel, start, end = m.group(1), m.group(2), int(m.group(3)), m.group(4)
                end = int(end) if end else None
                target = (md.parent / rel).resolve()
                where = f"{md.name}:{lineno}"

                if not target.exists():
                    (warnings if pending_confirmation else hard_errors).append(
                        f"{where}: missing file {rel}")
                    continue
                if target not in src_cache:
                    src_cache[target] = target.read_text(encoding="utf-8", errors="replace").splitlines()
                src = src_cache[target]

                if start < 1 or start > len(src) or (end and (end < start or end > len(src))):
                    msg = (f"{where}: {rel}#L{start}" + (f"-L{end}" if end else "")
                           + f" out of range (file has {len(src)} lines)")
                    (warnings if pending_confirmation else hard_errors).append(msg)
                    continue
                if end:  # ranges: bounds check only
                    continue

                name, receiver, confident = extract_identifier(line, m.start())
                if not name:
                    continue  # prose ref; bounds check was enough

                if name in src[start - 1]:
                    continue  # reference is accurate

                defs = find_definitions(src, name, receiver)
                msg = f"{where}: `{name}` not on {rel}#L{start}"
                if len(defs) == 1:
                    msg += f" (defined at L{defs[0]})"
                    if fix:
                        old = f"{rel}#L{start}"
                        new = f"{rel}#L{defs[0]}"
                        # Rewrite href and, if present, the matching display text.
                        replaced = new_line.replace(f"]({old})", f"]({new})")
                        replaced = replaced.replace(f"`{old}`", f"`{new}`")
                        replaced = replaced.replace(f"`#L{start}`", f"`#L{defs[0]}`")
                        if replaced != new_line:
                            new_line = replaced
                            changed = True
                            fixed += 1
                            continue
                elif len(defs) > 1:
                    msg += f" (ambiguous: defined at {', '.join('L' + str(d) for d in defs)})"
                else:
                    msg += " (no definition found)"

                (hard_errors if (confident and not pending_confirmation) else warnings).append(msg)

            out_lines.append(new_line)

        if fix and changed:
            md.write_text("".join(out_lines), encoding="utf-8")

    for w in warnings:
        print(f"  [WARN] {w}")
    for e in hard_errors:
        print(f"  [FAIL] {e}")
    if fixed:
        print(f"  [FIXED] {fixed} reference(s) updated")

    total = sum(1 for _ in LINK_RE.finditer("\n".join(
        p.read_text(encoding='utf-8') for p in DOC_DIR.glob('*.md'))))
    print(f"Checked {total} line references: "
          f"{len(hard_errors)} drifted, {len(warnings)} warnings"
          + (f", {fixed} fixed" if fixed else ""))

    if hard_errors:
        if not fix:
            print("Run `python3 tools/check_doc_refs.py --fix` to relocate "
                  "unambiguous references.")
        sys.exit(1)


if __name__ == "__main__":
    main()
