---
name: release
description: Build a Yapper release by running tools/release.sh (trigger on "release" or "release.sh")
allowed-tools:
  - exec
  - read
triggers:
  - user
  - model
---

Run the WoW-Yapper release build by executing `./tools/release.sh` from the repository root.

After running:
- Report the extracted version from `Yapper.toc`.
- Report the output zip path and size.
- Note any documentation syncs performed by `tools/sync.sh`.
- Do not commit changes or push the zip unless explicitly asked.
