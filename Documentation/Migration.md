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

### Language-engine contract (post-2.4.5)

Dictionary addons now own **all** language logic and must satisfy the strict
engine contract (see [Dictionaries.md](Dictionaries.md)):

- `RegisterLanguageEngine` now **requires** `NormaliseWord`, `NormaliseVowels`,
  `GetPhoneticHash`, `HashWord`, `BlockedHashes`, `WordBytes` and
  `WordStartBytes` — previously only `GetPhoneticHash`/`BlockedHashes`/`HashWord`
  were checked. Optional extras (`StripAffixes`, `ShouldCheckWord`, `MatchCase`,
  `IsSaneWord`, `VariantRules`, `ScoreWeights`, `KBLayouts`, `DefaultLayout`,
  `Locales`, `DisplayName`) are type-checked and probed; unknown top-level keys
  fail registration (use an `X_` prefix for private fields).
- A dictionary **must** declare `languageFamily` (or inherit it via `extends`)
  and the family engine must be registered first — the implicit `"en"` default
  is gone. There is no silent English fallback.
- Engines are owner-locked: only the addon that first registered a family may
  replace it. A runtime error inside engine code purges the engine plus all
  dictionaries bound to its family.
- Removed internals: `Spellcheck._KB_LAYOUTS` and `Spellcheck:GetKBDistTable`
  are gone (layouts are engine data now). `Spellcheck.NormaliseWord`,
  `Spellcheck.NormaliseVowels`, `Spellcheck.IsWordByte`,
  `Spellcheck.IsWordStartByte` and `Spellcheck.IterWords` still exist but are
  now engine-delegating entry points.

### 2.1.18+ Active Chat Window Hijack (`ChatEdit_GetActiveWindow`)

In Yapper 2.1.18 and newer, Yapper hooks `_G.ChatEdit_GetActiveWindow` and `ChatFrameUtil.GetActiveWindow` to return Yapper's active editor (`YapperOverlayEditBox` or `Multiline.EditBox` in multiline mode) while active.

* **Impact**:
  * Standard helper functions like `ChatEdit_GetActiveWindow()` and `GetCurrentKeyBoardFocus()` will return the active Yapper editbox (`YapperOverlayEditBox`) instead of Blizzard's native `ChatFrame1EditBox` etc.
  * If your addon relies on resolving the native/source Blizzard edit box that Yapper is overlaying, checks like `isBlizzardChatEditBox(editBox)` will return `false`.
  * **Immediate Hide Timing**: Because modern Yapper hides the native Blizzard edit box synchronously on show, any visibility-based loops (e.g. checking `editBox:IsShown()`) will fail to find the active native box.
* **Migration & Best Practices**:
  1. **Source Discovery**: Proactively resolve the underlying source Blizzard edit box by querying Yapper's internal pointer: `_G.Yapper.EditBox.OrigEditBox`.
  2. **Timing-Proof Setup**: When setting up layouts inside callbacks (like `EDITBOX_SHOW`), verify and pull the target Blizzard box from `_G.Yapper.EditBox.OrigEditBox` if standard focus-based searches return `nil`.
  3. **Visual Label Updates**: Use the official `"EDITBOX_LABEL_UPDATED"` callback to drive visual alignments and gutter calculations in real-time, replacing fragile hooks on `RefreshLabel`.
     ```lua
     YapperAPI:RegisterCallback("EDITBOX_LABEL_UPDATED", function()
         -- Update custom gutter, labels, or alignment anchors here
     end)
     ```

## Compatibility note

`_G.Yapper` remains available for advanced integrations, but it is internal and can change without notice. If you require a stable hook point that is not in `_G.YapperAPI`, open an issue requesting public API expansion.
