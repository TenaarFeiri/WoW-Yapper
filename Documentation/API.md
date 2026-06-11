# Yapper public API (`_G.YapperAPI`)

> ⚠️ `_G.YapperAPI` is the stable interaction point between integrating add-ons and Yapper's platform. Prefer this over internals where possible, ask for new API if you feel it would be appropriate.
> When API is updated or calls are slated to be changed or removed, existing API will be protected in the codebase for up to **6 months** either as an alias (common for renames) or as a wrapper around
> new API slated to replace old (for example in cases of consolidation, etc.). An in-game notice about deprecated API usage will appear once per session.
> Once the 6-month grace period ends, deprecated API calls are no longer protected and may be removed or rendered unusable at any time.
>
> Every effort will be made to keep the API a stable interface between Yapper and other add-ons for as long as reasonably possible. If you use a deprecated API function and receive a notice about it
> in-game, please update your add-on ASAP to prevent future interruption of service.

Source of truth: [`Src/API.lua`](../Src/API.lua).

## Stability and usage

- Public object is created at [`Src/API.lua#L191`](../Src/API.lua#L191).
- Registrations are sandboxed (`pcall`) so consumer errors do not crash Yapper.
- Filters are cancellable pre-hooks; callbacks are post events.

## Filters

Register/unregister:

- `YapperAPI:RegisterFilter(hookPoint: string, callback: function, priority?: number) → handle|nil` ([`#L204`](../Src/API.lua#L204))
- `YapperAPI:UnregisterFilter(handle: number) → nil` ([`#L257`](../Src/API.lua#L257))

### `PRE_EDITBOX_SHOW`

- Signature: `callback(payload) → payload|false`
- Payload: `{ chatType: string|nil, target: string|nil }`
- Fired from [`Src/Hooks/Blizzard.lua#L122`](../Src/Hooks/Blizzard.lua#L122) and [`Src/EditBox/Keybinds.lua#L155`](../Src/EditBox/Keybinds.lua#L155).
- Return `false` to suppress overlay open.

### `PRE_SEND`

- Payload: `{ text: string, chatType: string, language: any, target: string|number|nil }`
- Fired from [`Src/Chat.lua#L104`](../Src/Chat.lua#L104) and [`Src/Multiline.lua#L889`](../Src/Multiline.lua#L889).
- Return `false` to cancel send.

### `PRE_CHUNK`

- Payload: `{ text: string, limit: number }`
- Fired from [`Src/Chat.lua#L169`](../Src/Chat.lua#L169).
- Return `false` to abort chunking path.

### `PRE_DELIVER`

- Payload: `{ text: string, chatType: string, language: any, target: string|number|nil }`
- Fired from [`Src/Chat.lua#L251`](../Src/Chat.lua#L251).
- Return `false` to claim delivery; this emits `POST_CLAIMED` and starts delegation timeout.

### `PRE_SPELLCHECK`

- Payload: `{ text: string }`
- Fired from [`Src/Spellcheck/Engine.lua#L83`](../Src/Spellcheck/Engine.lua#L83).
- Return `false` to skip spellcheck for that text.

### `PRE_SPELLCHECK_SUGGESTIONS`

- Payload: `{ word: string, suggestions: table[], locale: string }`
- Fired from [`Src/Spellcheck/Engine.lua#L1231`](../Src/Spellcheck/Engine.lua#L1231).
- Fires after the engine has scored, sorted, and formatted the suggestion list for a misspelled word, but before the result is cached and shown.
- Each entry in `suggestions` is a table: `{ kind="word", value=string, score=number, baseScore=number }` or `{ kind="add", value=string }` or `{ kind="ignore", value=string }` or `{ kind="split", value=string }`.
- Plugins may reorder, append, remove, or rewrite suggestions by mutating the `suggestions` array and returning the payload.
- Return `false` to suppress the suggestion popup entirely.
- To force a refresh after changing plugin state, call `YapperAPI:ClearSuggestionCache()`.

### `PRE_MULTILINE_SHOW`

- Payload: `{ text: string, chatType: string, language: any, target: string|number|nil }`
- Fired from [`Src/Multiline.lua#L574`](../Src/Multiline.lua#L574).
- Fires before the expanded multiline editor opens.
- Modify payload to change initial text/channel or return false to block.

### `PRE_ICON_GALLERY_SHOW`

- Payload: `{ rawEditBox: EditBox, query: string }`
- Fired from [`Src/IconGallery.lua#L81`](../Src/IconGallery.lua#L81).
- Fires before the raid-icon gallery popup is shown.
- Modify `query` to change the pre-filter string or return false to suppress the gallery.

## Callbacks

Register/unregister:

- `YapperAPI:RegisterCallback(event: string, callback: function) → handle|nil` ([`Src/API.lua#L275`](../Src/API.lua#L275))
- `YapperAPI:UnregisterCallback(handle: number) → nil` ([`Src/API.lua#L319`](../Src/API.lua#L319))

### Event list

- `POST_SEND(text, chatType, language, target)`
- `POST_CLAIMED(handle, text, chatType, language, target)`
- `CONFIG_CHANGED(path, value)`
- `STATE_CHANGED(newState, oldState, ...)`
- `EDITBOX_SHOW(chatType, target)`
- `EDITBOX_HIDE()`
- `EDITBOX_TEXT_CHANGED(text, isUserInput, box)`
- `EDITBOX_CHANNEL_CHANGED(chatType, target)`
- `EDITBOX_LABEL_UPDATED(label, r, g, b)`
- `THEME_CHANGED(themeName)`
- `SPELLCHECK_SUGGESTION(word, suggestions)`
- `SPELLCHECK_SUGGESTION_HIGHLIGHTED(text, index, total)`
- `SPELLCHECK_APPLIED(original, replacement)`
- `SPELLCHECK_CLOSED()`
- `SPELLCHECK_WORD_ADDED(word, locale)`
- `SPELLCHECK_WORD_IGNORED(word, locale)`
- `YALLM_WORD_LEARNED(word, locale)` [DEPRECATED - Automatically aliased to YAS_WORD_LEARNED]
- `YAS_WORD_LEARNED(word, locale)`
- `QUEUE_STALL(chatType, policyClass, chunksRemaining)`
- `QUEUE_COMPLETE()`
- `ICON_GALLERY_SHOW(query)`
- `ICON_GALLERY_HIDE()`
- `ICON_GALLERY_SELECT(index, text, code)`
- `API_ERROR(kind, hook, handlerInfo, errorMessage, data, ...)`

Emission sites: [`Src/Chat.lua`](../Src/Chat.lua), [`Src/Queue.lua`](../Src/Queue.lua), [`Src/Interface/Config.lua`](../Src/Interface/Config.lua), [`Src/EditBox/Hooks.lua`](../Src/EditBox/Hooks.lua), [`Src/EditBox/Handlers.lua`](../Src/EditBox/Handlers.lua), [`Src/Theme.lua`](../Src/Theme.lua), [`Src/IconGallery.lua`](../Src/IconGallery.lua), [`Src/Spellcheck.lua`](../Src/Spellcheck.lua), [`Src/Spellcheck/UI.lua`](../Src/Spellcheck/UI.lua), [`Src/Spellcheck/Adaptive.lua`](../Src/Spellcheck/Adaptive.lua), [`Src/State.lua`](../Src/State.lua), [`Src/Autocomplete.lua`](../Src/Autocomplete.lua).

### `API_ERROR` ownership/scoping

When a handler faults, Yapper first attempts to route `API_ERROR` only to handlers owned by the same addon/module (owner captured at registration from source path). If no owner-matched handlers exist, it falls back to broadcasting all `API_ERROR` handlers; if none exist, it emits debug output. See [`Src/API.lua#L334-L355`](../Src/API.lua#L334-L355).

## Methods

### Registration / lifecycle

- `YapperAPI:GetVersion() → string` ([`#L334`](../Src/API.lua#L334))
- `YapperAPI:GetCurrentTheme() → string|nil` ([`#L342`](../Src/API.lua#L342))
- `YapperAPI:IsOverlayShown() → boolean` ([`#L353`](../Src/API.lua#L353))
- `YapperAPI:GetConfig(path: string) → any` ([`#L371`](../Src/API.lua#L371))
- `YapperAPI:GetDelineator() → string|nil` ([`#L397`](../Src/API.lua#L397))
- `YapperAPI:OpenBlizzardChat() → nil` ([`#L363`](../Src/API.lua#L363))
  Force the Yapper overlay to close and open the original Blizzard editbox. Equivalent to the user pressing the "Bypass Yapper" keybind (Shift-Enter).
- `YapperAPI:GetState() → string` ([`#L406`](../Src/API.lua#L406))
- `YapperAPI:IsState(state: string) → boolean` ([`#L415`](../Src/API.lua#L415))
- `YapperAPI:GetStates() → string[]` ([`#L424`](../Src/API.lua#L424))
- `YapperAPI:GetStateLogs() → table` ([`#L438`](../Src/API.lua#L438)) — returns the full circular buffer of state transitions (max 200 entries).
- `YapperAPI:GetStateLog(index: number) → table|nil` ([`#L448`](../Src/API.lua#L448)) — returns a specific transition entry from the history.
- `YapperAPI:GetStateLogCount() → number` ([`#L457`](../Src/API.lua#L457)) — returns the current number of transitions stored in the buffer.

### Spellcheck helpers

- `YapperAPI:IsSpellcheckEnabled() → boolean` ([`#L514`](../Src/API.lua#L514))
- `YapperAPI:CheckWord(word: string) → boolean` ([`#L523`](../Src/API.lua#L523))
- `YapperAPI:GetSuggestions(word: string) → string[]|nil` ([`#L533`](../Src/API.lua#L533))
- `YapperAPI:GetSpellcheckLocale() → string|nil` ([`#L554`](../Src/API.lua#L554))
- `YapperAPI:AddToDictionary(word: string) → boolean` ([`#L564`](../Src/API.lua#L564))
- `YapperAPI:IgnoreWord(word: string) → boolean` ([`#L577`](../Src/API.lua#L577))
- `YapperAPI:FindMisspellings(text: string) → table[]|nil` ([`#L622`](../Src/API.lua#L622))
- `YapperAPI:IsSuggestionOpen() → boolean` ([`#L589`](../Src/API.lua#L589))
- `YapperAPI:HideSuggestions() → boolean` ([`#L598`](../Src/API.lua#L598))
- `YapperAPI:ApplySuggestion(index: number) → boolean` ([`#L609`](../Src/API.lua#L609))

### Dictionary / language engine

- `YapperAPI:RegisterDictionary(locale: string, data: table) → boolean` ([`#L642`](../Src/API.lua#L642))
  Register a dictionary. If the dictionary belongs to a language family, that family must have a registered engine that satisfies the security validation (see `RegisterLanguageEngine`). Registration will fail if no secure engine is found for the associated family.
- `YapperAPI:RegisterLanguageEngine(familyId: string, engine: table) → boolean` ([`#L659`](../Src/API.lua#L659))
  Register a language engine. **Security Requirement**: The `engine` table MUST provide a `BlockedHashes` table and a `HashWord` function. Registration is blocked if these are missing.
- `YapperAPI:IsLanguageEngineRegistered(familyId: string) → boolean` ([`#L673`](../Src/API.lua#L673))
- `YapperAPI:RegisterLocaleAddon(locale: string, addonName: string) → boolean` ([`#L692`](../Src/API.lua#L692))

### Queue

- `YapperAPI:GetQueueState() → { active, stalled, chatType, policyClass, pending, inFlight }` ([`#L785`](../Src/API.lua#L785))
- `YapperAPI:CancelQueue() → number` ([`#L798`](../Src/API.lua#L798))
- `YapperAPI:ResolvePost(handle: number) → boolean` ([`#L974`](../Src/API.lua#L974))

### Theme

- `YapperAPI:RegisterTheme(name: string, data: table) → boolean` ([`#L814`](../Src/API.lua#L814))
- `YapperAPI:SetTheme(name: string) → boolean` ([`#L824`](../Src/API.lua#L824))
- `YapperAPI:GetRegisteredThemes() → string[]` ([`#L832`](../Src/API.lua#L832))
- `YapperAPI:GetTheme(name?: string) → table|nil` ([`#L840`](../Src/API.lua#L840))

### Utility wrappers

- `YapperAPI:IsChatLockdown() → boolean` ([`#L853`](../Src/API.lua#L853))
- `YapperAPI:IsSecret(value: any) → boolean` ([`#L866`](../Src/API.lua#L866))
- `YapperAPI:GetChatParent() → Frame` ([`#L887`](../Src/API.lua#L887))
- `YapperAPI:MakeFullscreenAware(frame: Frame) → nil` ([`#L897`](../Src/API.lua#L897))

### Icon gallery

- `YapperAPI:ShowIconGallery(editBox: EditBox, anchorFrame?: Frame, query?: string) → nil` ([`#L996`](../Src/API.lua#L996))
- `YapperAPI:HideIconGallery() → nil` ([`#L1004`](../Src/API.lua#L1004))
- `YapperAPI:IsIconGalleryShown() → boolean` ([`#L1010`](../Src/API.lua#L1010))
- `YapperAPI:GetRaidIconData() → table[]` ([`#L1017`](../Src/API.lua#L1017))

### Ghost text / autocomplete

- `YapperAPI:GetAutocompleteSuggestion(word: string) → string|nil` ([`#L1032`](../Src/API.lua#L1032)) — returns the best autocomplete suggestion for the given partial word, or `nil`.
- `YapperAPI:GetCaretOffset(editBox: EditBox) → number` ([`#L1042`](../Src/API.lua#L1042)) — returns the current pixel x-offset of the cursor/caret within an EditBox.
- `YapperAPI:GetGhostFrame() → table|nil` ([`#L1059`](../Src/API.lua#L1059)) — returns the shared FontString used for ghost text rendering.
- `YapperAPI:ShowGhostText(text: string, editBox: EditBox, prefix: string, textUpToCursor: string) → nil` ([`#L1071`](../Src/API.lua#L1071)) — manually show ghost text on a specific EditBox.
- `YapperAPI:HideGhostText() → nil` ([`#L1087`](../Src/API.lua#L1087)) — hide the ghost text.
- `YapperAPI:SetGhostTextOffset(offsetX: number, offsetY: number) → nil` ([`#L1096`](../Src/API.lua#L1096)) — set a manual pixel offset for ghost text alignment.
- `YapperAPI:SyncGhostTextFont() → nil` ([`#L1104`](../Src/API.lua#L1104)) — force the ghost text to re-synchronise its font with its current parent EditBox.
- `YapperAPI:SetSpellcheckTooltipOffset(hintX: number, hintY: number, suggestX: number, suggestY: number) → nil` ([`#L1116`](../Src/API.lua#L1116)) — set manual pixel offsets for spellcheck hint and suggestion tooltips.

### State / frames

- `YapperAPI:SetState(stateName: string) → nil` ([`#L468`](../Src/API.lua#L468)) — transition the state machine to a new state. Prefer `State:Transition` internally; use via API for external orchestration.
- `YapperAPI:ListFrames() → table` ([`#L481`](../Src/API.lua#L481)) — returns a table mapping internal frame names to their WoW frame objects.

### Text insertion

- `YapperAPI:InsertText(text: string) → nil` ([`#L762`](../Src/API.lua#L762)) — insert `text` at the current cursor position in the active Yapper editbox.

### Link protocols

- `YapperAPI:RegisterLinkProtocol(prefix: string) → nil` ([`#L716`](../Src/API.lua#L716)) — declare a `|H` link protocol prefix as a known, first-class link type (prevents it being treated as plain text).
- `YapperAPI:IsLinkProtocolRegistered(prefix: string) → boolean` ([`#L734`](../Src/API.lua#L734)) — returns `true` if `prefix` has been registered via `RegisterLinkProtocol`.
- `YapperAPI:GetRegisteredLinkProtocols() → string[]` ([`#L724`](../Src/API.lua#L724)) — returns a shallow copy of all registered link protocol prefixes.

### Atomic patterns

- `YapperAPI:RegisterAtomicPattern(pattern: string) → nil` ([`#L746`](../Src/API.lua#L746)) — register a custom Lua string pattern that the Yapper chunker should never split across chunk boundaries.
- `YapperAPI:GetRegisteredAtomicPatterns() → string[]` ([`#L753`](../Src/API.lua#L753)) — returns an array of all registered atomic patterns.

### Language engine (public accessor)

- `YapperAPI:GetLanguageEngine(familyId: string) → table|nil` ([`#L681`](../Src/API.lua#L681)) — returns the registered language engine for `familyId`, or `nil` if not found.

## Public API

- Methods:
  - [NEW] `YapperAPI:OpenSettingsCategory(id) → boolean success`: Open Yapper's settings window to a specific category. ([`../Src/API.lua#L1277`](../Src/API.lua#L1277))
  - [NEW] `YapperAPI:GetRegisteredSettingsCategories() → table`: Get a list of registered settings categories (excludes internal ones). ([`../Src/API.lua#L1264`](../Src/API.lua#L1264))
  - [NEW] `YapperAPI:UnregisterSettingsCategory(id) → nil`: Unregister a previously registered settings category. ([`../Src/API.lua#L1246`](../Src/API.lua#L1246))
  - [NEW] `YapperAPI:RegisterSettingsCategory(id, label, options) → boolean success`: Register a settings category in Yapper's settings window. ([`../Src/API.lua#L1206`](../Src/API.lua#L1206))
  - `YapperAPI:Deleet(word) → string`: Convert leetspeak characters back to their base alphabet equivalents. ([`../Src/API.lua#L877`](../Src/API.lua#L877))
  - `YapperAPI:ClearSuggestionCache() → nil`: Clear the spellcheck suggestion cache, forcing re-generation (and re-filtering) ([`../Src/API.lua#L1125`](../Src/API.lua#L1125))
