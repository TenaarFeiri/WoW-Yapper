# Yapper — agent/contributor notes

WoW retail chat addon. Lua 5.1 semantics (WoW's runtime). Entry point
`Yapper.toc` defines the load order — file order matters; modules
re-localise `YapperTable.*` upvalues at load time.

## Verification

```
tools/run_tests.sh                      # gating tests + syntax + doc refs (what CI runs)
tools/run_tests.sh --syntax             # luac -p over every shipped .lua only
python3 tools/check_doc_refs.py         # verify Documentation/ #L line references
python3 tools/check_doc_refs.py --fix   # auto-relocate drifted references
```

- Tests live in `tools/2.0testsuites/`; see the README there for the
  gating / diagnostic / quarantined classification and house style.
- CI: `.github/workflows/tests.yml` runs the same script on push/PR.
- Always syntax-check generated dictionaries (`Dictionaries/**/*.lua`);
  they are produced by `tools/generate_phonetic_dict.py` and a malformed
  one fails silently in-game.
- Documentation uses `file.lua#L<n>` links next to backticked signatures;
  `check_doc_refs.py` verifies them and can relocate drifted ones. Lines
  annotated `[MISSING]`/`[NEW]` come from release.sh and require agent
  confirmation — the checker treats those as warnings, not failures.

## Release documentation protocol

When `tools/release.sh` or `tools/sync.sh` reports documentation entries marked `[MISSING]` or `[NEW]`, do not blindly accept the generated diff or remove the marker automatically.

### `[MISSING]`

For every missing entry:

1. Search the current source for the exact symbol and plausible renamed or replacement implementations.
2. Trace callers, public API exposure, bridge consumers, and load-order references before deciding it is dead.
3. If the symbol is confirmed removed, delete the entire stale documentation bullet and its `[MISSING]` marker. Remove related prose only when it is also obsolete.
4. If the symbol still exists, restore or correct its documentation link and remove the marker.
5. If it is intentionally undocumented, add or update an explicit entry in the synchronizer's `IGNORED_FUNCTIONS` with a rationale rather than leaving a permanent marker.

### `[NEW]`

For every new entry:

1. Inspect the implementation, its callers, and whether it is public, user-facing, or internal.
2. Document it in the correct API or Internals section with an accurate description, signature, and source link.
3. For public or integration-facing methods, document behavior and lifecycle expectations rather than only copying the generated summary.
4. Remove `[NEW]` only after the documentation has been reviewed and the link checker passes.
5. If it is intentionally undocumented, add or update an explicit `IGNORED_FUNCTIONS` entry with a rationale instead of suppressing it ad hoc.

After resolving all markers, run `python3 tools/check_doc_refs.py`, inspect the complete documentation diff, and rerun the relevant tests. Never use `--fix` as a substitute for investigating a missing or newly detected symbol.

## Gotchas

- State-machine style: several modules gate behavior on write-once flags
  (e.g. `EditBox._lockdown.*`). After refactors, grep that every consumed
  flag still has a producer (`rg 'flagName = true'`) — a write-never flag
  regression here caused a long-lived user-facing bug.
- Secure/keybind code: the keybind buttons fire on key DOWN
  (`RegisterForClicks("AnyDown")`) to match Blizzard's OPENCHAT timing.
  Do not remove; on-release firing reintroduces action-bar bleed-through.
- `CHAT_FOCUS_OVERRIDE` (via `ChatFrameUtil.SetChatFocusOverride`) is kept
  pointed at the overlay edit while Yapper is active; it MUST be cleared
  during lockdown handoff or Blizzard's `OpenChat` focuses a hidden frame
  and Enter presses are silently eaten.

## Design notes

- The single-line multiline onboarding hint is runtime-only and is owned by the
  overlay lifecycle. It is created lazily as a non-interactive UIParent child so
  screen-space positioning remains correct across scaled or undocked chat
  frames; its session flag is not persisted because it should reappear after a
  reload. The overlay hide hook cancels its timer because multiline entry hides
  the overlay directly rather than going through `EditBox:Hide()`.
