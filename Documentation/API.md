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

- Public object is created at [`Src/API.lua#L235`](../Src/API.lua#L235).
- Registrations are sandboxed (`pcall`) so consumer errors do not crash Yapper.
- Filters are cancellable pre-hooks; callbacks are post events.

## Filters

Register/unregister:

- `YapperAPI:RegisterFilter(hookPoint: string, callback: function, priority?: number) → handle|nil` ([`#L248`](../Src/API.lua#L248))
- `YapperAPI:UnregisterFilter(handle: number) → nil` ([`#L319`](../Src/API.lua#L319))

### `PRE_EDITBOX_SHOW`

- Signature: `callback(payload) → payload|false`
- Payload: `{ chatType: string|nil, target: string|nil }`
- Fired from [`Src/Hooks/Blizzard.lua#L174`](../Src/Hooks/Blizzard.lua#L174), [`Src/Hooks/Blizzard.lua#L458`](../Src/Hooks/Blizzard.lua#L458), and [`Src/EditBox/Keybinds.lua#L165`](../Src/EditBox/Keybinds.lua#L165).
- Return `false` to suppress overlay open.

### `PRE_SEND`

- Payload: `{ text: string, chatType: string, language: any, target: string|number|nil }`
- Fired from [`Src/Chat.lua#L100`](../Src/Chat.lua#L100) and [`Src/Multiline.lua#L968`](../Src/Multiline.lua#L968).
- Return `false` to cancel send.

### `PRE_CHUNK`

- Payload: `{ text: string, limit: number, chatType: string }`
- Fired from [`Src/Chat.lua#L159`](../Src/Chat.lua#L159).
- Return `false` to abort chunking path.

### `PRE_DELIVER`

- Payload: `{ text: string, chatType: string, language: any, target: string|number|nil }`
- Fired from [`Src/Chat.lua#L243`](../Src/Chat.lua#L243).
- Return `false` to claim delivery; this emits `POST_CLAIMED` and starts delegation timeout.

### `PRE_SPELLCHECK`

- Payload: `{ text: string }`
- Fired from [`Src/Spellcheck/Engine.lua#L88`](../Src/Spellcheck/Engine.lua#L88).
- Return `false` to skip spellcheck for that text.

### `PRE_SPELLCHECK_SUGGESTIONS`

- Payload: `{ word: string, suggestions: table[], locale: string }`
- Fired from [`Src/Spellcheck/Engine.lua#L1246`](../Src/Spellcheck/Engine.lua#L1246).
- Fires after the engine has scored, sorted, and formatted the suggestion list for a misspelled word, but before the result is cached and shown.
- Each entry in `suggestions` is a table: `{ kind="word", value=string, score=number, baseScore=number }` or `{ kind="add", value=string }` or `{ kind="ignore", value=string }` or `{ kind="split", value=string }`.
- Plugins may reorder, append, remove, or rewrite suggestions by mutating the `suggestions` array and returning the payload.
- Return `false` to suppress the suggestion popup entirely.
- To force a refresh after changing plugin state, call `YapperAPI:ClearSuggestionCache()`.

### `PRE_MULTILINE_SHOW`

- Payload: `{ text: string, chatType: string, language: any, target: string|number|nil }`
- Fired from [`Src/Multiline.lua#L629`](../Src/Multiline.lua#L629).
- Fires before the expanded multiline editor opens.
- Modify payload to change initial text/channel or return false to block.

### `PRE_ICON_GALLERY_SHOW`

- Payload: `{ rawEditBox: EditBox, query: string }`
- Fired from [`Src/IconGallery.lua#L82`](../Src/IconGallery.lua#L82).
- Fires before the raid-icon gallery popup is shown.
- Modify `query` to change the pre-filter string or return false to suppress the gallery.

## Callbacks

Register/unregister:

- `YapperAPI:RegisterCallback(event: string, callback: function) → handle|nil` ([`Src/API.lua#L337`](../Src/API.lua#L337))
- `YapperAPI:UnregisterCallback(handle: number) → nil` ([`Src/API.lua#L397`](../Src/API.lua#L397))

### Event list

- `POST_SEND(text, chatType, language, target)` — [`Src/Chat.lua#L273`](../Src/Chat.lua#L273), [`Src/API.lua#L1012`](../Src/API.lua#L1012)
- `POST_CLAIMED(handle, text, chatType, language, target)` — [`Src/Chat.lua#L254`](../Src/Chat.lua#L254)
- `CONFIG_CHANGED(path, value)` — [`Src/Interface/Config.lua#L395`](../Src/Interface/Config.lua#L395)
- `STATE_CHANGED(newState, oldState, ...)` — [`Src/State.lua#L162`](../Src/State.lua#L162)
- `EDITBOX_SHOW(chatType, target)` — [`Src/Hooks/ShowHide.lua#L409`](../Src/Hooks/ShowHide.lua#L409)
- `EDITBOX_HIDE()` — [`Src/Hooks/ShowHide.lua#L483`](../Src/Hooks/ShowHide.lua#L483)
- `EDITBOX_TEXT_CHANGED(text, isUserInput, box)` — [`Src/EditBox/Handlers.lua#L45`](../Src/EditBox/Handlers.lua#L45), [`Src/Multiline.lua#L526`](../Src/Multiline.lua#L526), [`Src/Autocomplete.lua#L782`](../Src/Autocomplete.lua#L782), [`Src/Spellcheck/UI.lua#L1171`](../Src/Spellcheck/UI.lua#L1171)
- `EDITBOX_CHANNEL_CHANGED(chatType, target)` — [`Src/Hooks/Label.lua#L264`](../Src/Hooks/Label.lua#L264)
- `EDITBOX_LABEL_UPDATED(label, r, g, b)` — [`Src/Hooks/Label.lua#L210`](../Src/Hooks/Label.lua#L210)
- `THEME_CHANGED(themeName)` — [`Src/Theme.lua#L112`](../Src/Theme.lua#L112), [`Src/Theme.lua#L239`](../Src/Theme.lua#L239)
- `SPELLCHECK_SUGGESTION(word, suggestions)` — [`Src/Spellcheck/UI.lua#L961`](../Src/Spellcheck/UI.lua#L961)
- `SPELLCHECK_SUGGESTION_HIGHLIGHTED(text, index, total)` — [`Src/Spellcheck/UI.lua#L807`](../Src/Spellcheck/UI.lua#L807)
- `SPELLCHECK_APPLIED(original, replacement)` — [`Src/Spellcheck/UI.lua#L1142`](../Src/Spellcheck/UI.lua#L1142), [`Src/Spellcheck/UI.lua#L1197`](../Src/Spellcheck/UI.lua#L1197)
- `SPELLCHECK_CLOSED()` — [`Src/Spellcheck/UI.lua#L1000`](../Src/Spellcheck/UI.lua#L1000)
- `SPELLCHECK_WORD_ADDED(word, locale)` — [`Src/Spellcheck.lua#L592`](../Src/Spellcheck.lua#L592)
- `SPELLCHECK_WORD_IGNORED(word, locale)` — [`Src/Spellcheck.lua#L615`](../Src/Spellcheck.lua#L615)
- `YALLM_WORD_LEARNED(word, locale)` [DEPRECATED — automatically aliased to YAS_WORD_LEARNED]
- `YAS_WORD_LEARNED(word, locale)` — [`Src/Spellcheck/Adaptive.lua#L605`](../Src/Spellcheck/Adaptive.lua#L605)
- `QUEUE_STALL(chatType, policyClass, chunksRemaining)` — [`Src/Queue.lua#L662`](../Src/Queue.lua#L662)
- `QUEUE_COMPLETE()` — [`Src/Queue.lua#L504`](../Src/Queue.lua#L504), [`Src/Queue.lua#L830`](../Src/Queue.lua#L830)
- `ICON_GALLERY_SHOW(query)` — [`Src/IconGallery.lua#L106`](../Src/IconGallery.lua#L106)
- `ICON_GALLERY_HIDE()` — [`Src/IconGallery.lua#L118`](../Src/IconGallery.lua#L118)
- `ICON_GALLERY_SELECT(index, text, code)` — [`Src/IconGallery.lua#L168`](../Src/IconGallery.lua#L168)
- `API_ERROR(kind, hook, handlerInfo, errorMessage, data, ...)` — [`Src/API.lua#L152`](../Src/API.lua#L152) (internal dispatch, not via `Fire`)

Emission sites: [`Src/Chat.lua`](../Src/Chat.lua), [`Src/Queue.lua`](../Src/Queue.lua), [`Src/Interface/Config.lua`](../Src/Interface/Config.lua), [`Src/Hooks/ShowHide.lua`](../Src/Hooks/ShowHide.lua), [`Src/Hooks/Label.lua`](../Src/Hooks/Label.lua), [`Src/EditBox/Handlers.lua`](../Src/EditBox/Handlers.lua), [`Src/Theme.lua`](../Src/Theme.lua), [`Src/IconGallery.lua`](../Src/IconGallery.lua), [`Src/Spellcheck.lua`](../Src/Spellcheck.lua), [`Src/Spellcheck/UI.lua`](../Src/Spellcheck/UI.lua), [`Src/Spellcheck/Adaptive.lua`](../Src/Spellcheck/Adaptive.lua), [`Src/State.lua`](../Src/State.lua), [`Src/Autocomplete.lua`](../Src/Autocomplete.lua), [`Src/Multiline.lua`](../Src/Multiline.lua), [`Src/API.lua`](../Src/API.lua).

### `API_ERROR` ownership/scoping

When a handler faults, Yapper first attempts to route `API_ERROR` only to handlers owned by the same addon/module (owner captured at registration from source path). If no owner-matched handlers exist, it falls back to broadcasting all `API_ERROR` handlers; if none exist, it emits debug output. See [`Src/API.lua#L152-L192`](../Src/API.lua#L152-L192).

## Methods

### Registration / lifecycle

- `YapperAPI:GetVersion() → string` ([`#L412`](../Src/API.lua#L412))
- `YapperAPI:GetCurrentTheme() → string|nil` ([`#L420`](../Src/API.lua#L420))
- `YapperAPI:IsOverlayShown() → boolean` ([`#L431`](../Src/API.lua#L431))
- `YapperAPI:GetConfig(path: string) → any` ([`#L449`](../Src/API.lua#L449))
- `YapperAPI:GetDelineator() → string|nil` ([`#L475`](../Src/API.lua#L475))
- `YapperAPI:OpenBlizzardChat() → nil` ([`#L441`](../Src/API.lua#L441))
  Force the Yapper overlay to close and open the original Blizzard editbox. Equivalent to the user pressing the "Bypass Yapper" keybind (Shift-Enter).
- `YapperAPI:GetState() → string` ([`#L484`](../Src/API.lua#L484))
- `YapperAPI:IsState(state: string) → boolean` ([`#L493`](../Src/API.lua#L493))
- `YapperAPI:GetStates() → string[]` ([`#L502`](../Src/API.lua#L502))
- `YapperAPI:GetStateLogs() → table` ([`#L516`](../Src/API.lua#L516)) — returns the full circular buffer of state transitions (max 200 entries).
- `YapperAPI:GetStateLog(index: number) → table|nil` ([`#L526`](../Src/API.lua#L526)) — returns a specific transition entry from the history.
- `YapperAPI:GetStateLogCount() → number` ([`#L535`](../Src/API.lua#L535)) — returns the current number of transitions stored in the buffer.

### Spellcheck helpers

- `YapperAPI:IsSpellcheckEnabled() → boolean` ([`#L592`](../Src/API.lua#L592))
- `YapperAPI:CheckWord(word: string) → boolean` ([`#L601`](../Src/API.lua#L601))
- `YapperAPI:GetSuggestions(word: string) → string[]|nil` ([`#L611`](../Src/API.lua#L611))
- `YapperAPI:GetSpellcheckLocale() → string|nil` ([`#L632`](../Src/API.lua#L632))
- `YapperAPI:AddToDictionary(word: string) → boolean` ([`#L642`](../Src/API.lua#L642))
- `YapperAPI:IgnoreWord(word: string) → boolean` ([`#L655`](../Src/API.lua#L655))
- `YapperAPI:FindMisspellings(text: string) → table[]|nil` ([`#L700`](../Src/API.lua#L700))
- `YapperAPI:IsSuggestionOpen() → boolean` ([`#L667`](../Src/API.lua#L667))
- `YapperAPI:HideSuggestions() → boolean` ([`#L676`](../Src/API.lua#L676))
- `YapperAPI:ApplySuggestion(index: number) → boolean` ([`#L687`](../Src/API.lua#L687))

### Dictionary / language engine

- `YapperAPI:RegisterDictionary(locale: string, data: table) → boolean` ([`#L720`](../Src/API.lua#L720))
  Register a dictionary. If the dictionary belongs to a language family, that family must have a registered engine that satisfies the security validation (see `RegisterLanguageEngine`). Registration will fail if no secure engine is found for the associated family.
- `YapperAPI:RegisterLanguageEngine(familyId: string, engine: table) → boolean` ([`#L737`](../Src/API.lua#L737))
  Register a language engine. **Security Requirement**: The `engine` table MUST provide a `BlockedHashes` table and a `HashWord` function. Registration is blocked if these are missing.
- `YapperAPI:IsLanguageEngineRegistered(familyId: string) → boolean` ([`#L751`](../Src/API.lua#L751))
- `YapperAPI:RegisterLocaleAddon(locale: string, addonName: string) → boolean` ([`#L770`](../Src/API.lua#L770))

### Queue

- `YapperAPI:GetQueueState() → { active, stalled, chatType, policyClass, pending, inFlight }` ([`#L863`](../Src/API.lua#L863))
- `YapperAPI:CancelQueue() → number` ([`#L876`](../Src/API.lua#L876))
- `YapperAPI:ResolvePost(handle: number) → boolean` ([`#L1052`](../Src/API.lua#L1052))

### Theme

- `YapperAPI:RegisterTheme(name: string, data: table) → boolean` ([`#L892`](../Src/API.lua#L892))
- `YapperAPI:SetTheme(name: string) → boolean` ([`#L902`](../Src/API.lua#L902))
- `YapperAPI:GetRegisteredThemes() → string[]` ([`#L910`](../Src/API.lua#L910))
- `YapperAPI:GetTheme(name?: string) → table|nil` ([`#L918`](../Src/API.lua#L918))

### Utility wrappers

- `YapperAPI:IsChatLockdown() → boolean` ([`#L931`](../Src/API.lua#L931))
- `YapperAPI:IsSecret(value: any) → boolean` ([`#L944`](../Src/API.lua#L944))
- `YapperAPI:GetChatParent() → Frame` ([`#L965`](../Src/API.lua#L965))
- `YapperAPI:MakeFullscreenAware(frame: Frame) → nil` ([`#L975`](../Src/API.lua#L975))

### Icon gallery

- `YapperAPI:ShowIconGallery(editBox: EditBox, anchorFrame?: Frame, query?: string) → nil` ([`#L1074`](../Src/API.lua#L1074))
- `YapperAPI:HideIconGallery() → nil` ([`#L1082`](../Src/API.lua#L1082))
- `YapperAPI:IsIconGalleryShown() → boolean` ([`#L1088`](../Src/API.lua#L1088))
- `YapperAPI:GetRaidIconData() → table[]` ([`#L1095`](../Src/API.lua#L1095))

### Ghost text / autocomplete

- `YapperAPI:GetAutocompleteSuggestion(word: string) → string|nil` ([`#L1110`](../Src/API.lua#L1110)) — returns the best autocomplete suggestion for the given partial word, or `nil`.
- `YapperAPI:GetCaretOffset(editBox: EditBox) → number` ([`#L1120`](../Src/API.lua#L1120)) — returns the current pixel x-offset of the cursor/caret within an EditBox.
- `YapperAPI:GetGhostFrame() → table|nil` ([`#L1137`](../Src/API.lua#L1137)) — returns the shared FontString used for ghost text rendering.
- `YapperAPI:ShowGhostText(text: string, editBox: EditBox, prefix: string, textUpToCursor: string) → nil` ([`#L1149`](../Src/API.lua#L1149)) — manually show ghost text on a specific EditBox.
- `YapperAPI:HideGhostText() → nil` ([`#L1165`](../Src/API.lua#L1165)) — hide the ghost text.
- `YapperAPI:SetGhostTextOffset(offsetX: number, offsetY: number) → nil` ([`#L1174`](../Src/API.lua#L1174)) — set a manual pixel offset for ghost text alignment.
- `YapperAPI:SyncGhostTextFont() → nil` ([`#L1182`](../Src/API.lua#L1182)) — force the ghost text to re-synchronise its font with its current parent EditBox.
- `YapperAPI:SetSpellcheckTooltipOffset(hintX: number, hintY: number, suggestX: number, suggestY: number) → nil` ([`#L1194`](../Src/API.lua#L1194)) — set manual pixel offsets for spellcheck hint and suggestion tooltips.

### State / frames

- `YapperAPI:SetState(stateName: string) → nil` ([`#L546`](../Src/API.lua#L546)) — transition the state machine to a new state. Prefer `State:Transition` internally; use via API for external orchestration.
- `YapperAPI:ListFrames() → table` ([`#L559`](../Src/API.lua#L559)) — returns a table mapping internal frame names to their WoW frame objects.

### Text insertion

- `YapperAPI:InsertText(text: string) → nil` ([`#L840`](../Src/API.lua#L840)) — insert `text` at the current cursor position in the active Yapper editbox.

### Link protocols

- `YapperAPI:RegisterLinkProtocol(prefix: string) → nil` ([`#L794`](../Src/API.lua#L794)) — declare a `|H` link protocol prefix as a known, first-class link type (prevents it being treated as plain text).
- `YapperAPI:IsLinkProtocolRegistered(prefix: string) → boolean` ([`#L812`](../Src/API.lua#L812)) — returns `true` if `prefix` has been registered via `RegisterLinkProtocol`.
- `YapperAPI:GetRegisteredLinkProtocols() → string[]` ([`#L802`](../Src/API.lua#L802)) — returns a shallow copy of all registered link protocol prefixes.

### Atomic patterns

- `YapperAPI:RegisterAtomicPattern(pattern: string) → nil` ([`#L824`](../Src/API.lua#L824)) — register a custom Lua string pattern that the Yapper chunker should never split across chunk boundaries.
- `YapperAPI:GetRegisteredAtomicPatterns() → string[]` ([`#L831`](../Src/API.lua#L831)) — returns an array of all registered atomic patterns.

### Language engine (public accessor)

- `YapperAPI:GetLanguageEngine(familyId: string) → table|nil` ([`#L759`](../Src/API.lua#L759)) — returns the registered language engine for `familyId`, or `nil` if not found.

## Public API

- Methods:
  - [NEW] `YapperAPI:OpenSettingsCategory(id) → boolean success`: Open Yapper's settings window to a specific category. ([`../Src/API.lua#L1355`](../Src/API.lua#L1355))
  - [NEW] `YapperAPI:GetRegisteredSettingsCategories() → table`: Get a list of registered settings categories (excludes internal ones). ([`../Src/API.lua#L1342`](../Src/API.lua#L1342))
  - [NEW] `YapperAPI:UnregisterSettingsCategory(id) → nil`: Unregister a previously registered settings category. ([`../Src/API.lua#L1324`](../Src/API.lua#L1324))
  - [NEW] `YapperAPI:RegisterSettingsCategory(id, label, options) → boolean success`: Register a settings category in Yapper's settings window. ([`../Src/API.lua#L1284`](../Src/API.lua#L1284))
  - `YapperAPI:Deleet(word) → string`: Convert leetspeak characters back to their base alphabet equivalents. ([`../Src/API.lua#L955`](../Src/API.lua#L955))
  - `YapperAPI:ClearSuggestionCache() → nil`: Clear the spellcheck suggestion cache, forcing re-generation (and re-filtering) ([`../Src/API.lua#L1203`](../Src/API.lua#L1203))
