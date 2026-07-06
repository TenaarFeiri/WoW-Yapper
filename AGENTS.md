# Yapper — agent/contributor notes

WoW retail chat addon. Lua 5.1 semantics (WoW's runtime). Entry point
`Yapper.toc` defines the load order — file order matters; modules
re-localise `YapperTable.*` upvalues at load time.

## Verification

```
tools/run_tests.sh            # all gating tests + syntax pass (what CI runs)
tools/run_tests.sh --syntax   # luac -p over every shipped .lua only
```

- Tests live in `tools/2.0testsuites/`; see the README there for the
  gating / diagnostic / quarantined classification and house style.
- CI: `.github/workflows/tests.yml` runs the same script on push/PR.
- Always syntax-check generated dictionaries (`Dictionaries/**/*.lua`);
  they are produced by `tools/generate_phonetic_dict.py` and a malformed
  one fails silently in-game.

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
