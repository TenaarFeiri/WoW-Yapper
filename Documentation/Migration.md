# Migration notes (1.x → 2.x)

## Scope

This is for addon authors who previously integrated with internal `YapperTable.*` calls.

For new integrations, use `_G.YapperAPI` only (see [API.md](API.md)).

## Key 2.x changes

1. **Public API is the supported surface**
   - Register filters/callbacks through `_G.YapperAPI` instead of patching internals.

2. **Spellcheck dictionaries are Load-on-Demand sibling addons**
   - Dictionary bundles now register at runtime via:
     - `YapperAPI:RegisterLanguageEngine(...)`
     - `YapperAPI:RegisterDictionary(...)`
   - Locale addon mappings are controlled by `YapperAPI:RegisterLocaleAddon(...)` and `Spellcheck.LocaleAddons`.

3. **Dual config model is now explicit**
   - Account defaults in `YapperDB`.
   - Per-character overrides in `YapperLocalConf` (with inheritance from account defaults).
   - Draft/history data in `YapperLocalHistory`.

4. **Queue/send orchestration is API-hookable**
   - Use `PRE_SEND`, `PRE_CHUNK`, `PRE_DELIVER`, `POST_SEND`, `QUEUE_STALL`, `QUEUE_COMPLETE` rather than direct queue/router hooks.

## Practical migration checklist

- Replace direct `YapperTable` access with API calls where available.
- Move outbound message transforms to `PRE_SEND` / `PRE_CHUNK` filters.
- Move custom delivery ownership to `PRE_DELIVER` + `ResolvePost`.
- Move overlay lifecycle hooks to `EDITBOX_SHOW` / `EDITBOX_HIDE` callbacks.
- Guard integrations with `if _G.YapperAPI then ... end`.

## Version-Specific Integration Notes

### 2.1.18+ Active Chat Window Hijack (`ChatEdit_GetActiveWindow`)

In Yapper 2.1.18 and newer, Yapper hooks `_G.ChatEdit_GetActiveWindow` and `ChatFrameUtil.GetActiveWindow` to return Yapper's active editor (`YapperOverlayEditBox` or `Multiline.EditBox` in multiline mode) while active.

* **Impact**:
  * Standard helper functions like `ChatEdit_GetActiveWindow()` and `GetCurrentKeyBoardFocus()` will return the active Yapper editbox (`YapperOverlayEditBox`) instead of Blizzard's native `ChatFrame1EditBox` etc.
  * If your addon relies on resolving the native/source Blizzard edit box that Yapper is overlaying, checks like `isBlizzardChatEditBox(editBox)` will return `false`.
* **Migration**:
  * Proactively resolve the underlying source Blizzard edit box by querying Yapper's internal pointer: `_G.Yapper.EditBox.OrigEditBox`.

## Compatibility note

`_G.Yapper` remains available for advanced integrations, but it is internal and can change without notice. If you require a stable hook point that is not in `_G.YapperAPI`, open an issue requesting public API expansion.
