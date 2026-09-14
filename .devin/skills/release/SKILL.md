---
name: release
description: Build a Yapper release by running tools/release.ps1 (Windows) or tools/release.sh (trigger on "release" or "release.sh")
allowed-tools:
  - exec
  - read
triggers:
  - user
  - model
---

Run the WoW-Yapper release build from the repository root. Choose the script by platform:

- Windows: `powershell -ExecutionPolicy Bypass -File tools/release.ps1` (or run it in the active PowerShell session as `.\tools\release.ps1`)
- Linux/macOS (bash/WSL): `./tools/release.sh`

The scripts are equivalent: both sync documentation, stage a whitelist of shipped files into `.release/stage`, copy the enabled dictionary locales as sibling addons, and zip the result to `.release/Yapper-<version>.zip`.

After running:
- Report the extracted version from `Yapper.toc`.
- Report the output zip path and size.
- Note any documentation syncs performed (via `tools/sync.sh` or `sync_all_docs.py --inject`).
- Do not commit changes or push the zip unless explicitly asked.

Documentation confirmation protocol:
- Treat every `[MISSING]` and `[NEW]` annotation emitted by the documentation sync as an investigation task, not an automatic documentation decision.
- For `[MISSING]`, search for the exact symbol and plausible replacements, trace callers/public consumers/load order, then either restore the link, remove the confirmed-stale documentation entry, or add a justified `IGNORED_FUNCTIONS` entry.
- For `[NEW]`, inspect the implementation and usage, classify it as public/user-facing/internal, document it accurately in the correct section, and remove the tag only after review.
- Never use `tools/check_doc_refs.py --fix` as a substitute for investigating `[MISSING]` or `[NEW]`; it is only for relocating verified references.
- Before reporting the release complete, inspect the full documentation diff, run `python3 tools/check_doc_refs.py`, and run the relevant tests.
