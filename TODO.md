# TODO

## Deferred from forever-support review (revisit after more in-game testing)

- Enter fallback commits unverifiable partial target when extractor returns nil
  (`Src/EditBox/Handlers.lua` ~L331).
- UnitPopup fallback not byte-identical to Blizzard's `GetFullPlayerName`
  (rare fallback-only paths).
- Retail intent matching can equate differing realm suffixes after
  normalisation (`20_EditBoxHooks.lua` ~L293).
- `Utils:IsForeverClient()` currently unused — keep or cut.
- Missing coverage: Enter-padding and nil-adoption paths.
