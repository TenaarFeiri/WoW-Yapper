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

- `YapperAPI:RegisterFilter(hookPoint: string, callback: function, priority?: number) → handle|nil` ([`#L249`](../Src/API.lua#L249))
- `YapperAPI:UnregisterFilter(handle: number) → nil` ([`#L320`](../Src/API.lua#L320))

### `PRE_EDITBOX_SHOW`

- Signature: `callback(payload) → payload|false`
- Payload: `{ chatType: string|nil, target: string|nil }`
- Fired from [`Src/Hooks/BlizzardHookCtl/20_EditBoxHooks.lua#L119`](../Src/Hooks/BlizzardHookCtl/20_EditBoxHooks.lua#L119), [`Src/Hooks/BlizzardHookCtl/20_EditBoxHooks.lua#L543`](../Src/Hooks/BlizzardHookCtl/20_EditBoxHooks.lua#L543), and [`Src/EditBox/Keybinds.lua#L165`](../Src/EditBox/Keybinds.lua#L165).
- Return `false` to suppress overlay open.

### `PRE_EDITBOX_LABEL`

- Payload: `{ chatType: string|nil, target: string|number|nil, channelName: string|nil, label: string|nil, unit: string|nil }`
- Fired from [`Src/EditBox/Overlay.lua#L259`](../Src/EditBox/Overlay.lua#L259).
- Fires when `BuildLabelText` resolves label text for the editbox UI.
- Intended use: mutate `payload.label` for specific channels (for example EMOTE/RP name formatting).
- This hook is non-blocking: returning `false` is ignored and Yapper falls back to default label logic.
- Yapper snapshots the original payload (deep copy) before filter execution and restores from that snapshot if a filter returns malformed/corrupted payload data.

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

- `YapperAPI:RegisterCallback(event: string, callback: function) → handle|nil` ([`Src/API.lua#L338`](../Src/API.lua#L338))
- `YapperAPI:UnregisterCallback(handle: number) → nil` ([`Src/API.lua#L398`](../Src/API.lua#L398))

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

- `YapperAPI:GetVersion() → string` ([`#L413`](../Src/API.lua#L413))
- `YapperAPI:GetCurrentTheme() → string|nil` ([`#L421`](../Src/API.lua#L421))
- `YapperAPI:IsOverlayShown() → boolean` ([`#L432`](../Src/API.lua#L432))
- `YapperAPI:GetConfig(path: string) → any` ([`#L450`](../Src/API.lua#L450))
- `YapperAPI:GetDelineator() → string|nil` ([`#L476`](../Src/API.lua#L476))
- `YapperAPI:OpenBlizzardChat() → nil` ([`#L442`](../Src/API.lua#L442))
  Force the Yapper overlay to close and open the original Blizzard editbox. Equivalent to the user pressing the "Bypass Yapper" keybind (Shift-Enter).
- `YapperAPI:GetState() → string` ([`#L485`](../Src/API.lua#L485))
- `YapperAPI:IsState(state: string) → boolean` ([`#L494`](../Src/API.lua#L494))
- `YapperAPI:GetStates() → string[]` ([`#L503`](../Src/API.lua#L503))
- `YapperAPI:GetStateLogs() → table` ([`#L517`](../Src/API.lua#L517)) — returns the full circular buffer of state transitions (max 200 entries).
- `YapperAPI:GetStateLog(index: number) → table|nil` ([`#L527`](../Src/API.lua#L527)) — returns a specific transition entry from the history.
- `YapperAPI:GetStateLogCount() → number` ([`#L536`](../Src/API.lua#L536)) — returns the current number of transitions stored in the buffer.

### Spellcheck helpers

- `YapperAPI:IsSpellcheckEnabled() → boolean` ([`#L593`](../Src/API.lua#L593))
- `YapperAPI:CheckWord(word: string) → boolean` ([`#L602`](../Src/API.lua#L602))
- `YapperAPI:GetSuggestions(word: string) → string[]|nil` ([`#L612`](../Src/API.lua#L612))
- `YapperAPI:GetSpellcheckLocale() → string|nil` ([`#L633`](../Src/API.lua#L633))
- `YapperAPI:AddToDictionary(word: string) → boolean` ([`#L643`](../Src/API.lua#L643))
- `YapperAPI:IgnoreWord(word: string) → boolean` ([`#L656`](../Src/API.lua#L656))
- `YapperAPI:FindMisspellings(text: string) → table[]|nil` ([`#L701`](../Src/API.lua#L701))
- `YapperAPI:IsSuggestionOpen() → boolean` ([`#L668`](../Src/API.lua#L668))
- `YapperAPI:HideSuggestions() → boolean` ([`#L677`](../Src/API.lua#L677))
- `YapperAPI:ApplySuggestion(index: number) → boolean` ([`#L688`](../Src/API.lua#L688))

### Dictionary / language engine

- `YapperAPI:RegisterDictionary(locale: string, data: table) → boolean` ([`#L721`](../Src/API.lua#L721))
  Register a dictionary. If the dictionary belongs to a language family, that family must have a registered engine that satisfies the security validation (see `RegisterLanguageEngine`). Registration will fail if no secure engine is found for the associated family.
- `YapperAPI:RegisterLanguageEngine(familyId: string, engine: table) → boolean` ([`#L738`](../Src/API.lua#L738))
  Register a language engine. **Security Requirement**: The `engine` table MUST provide a `BlockedHashes` table and a `HashWord` function. Registration is blocked if these are missing.
- `YapperAPI:IsLanguageEngineRegistered(familyId: string) → boolean` ([`#L752`](../Src/API.lua#L752))
- `YapperAPI:RegisterLocaleAddon(locale: string, addonName: string) → boolean` ([`#L771`](../Src/API.lua#L771))

### Queue

- `YapperAPI:GetQueueState() → { active, stalled, chatType, policyClass, pending, inFlight }` ([`#L864`](../Src/API.lua#L864))
- `YapperAPI:CancelQueue() → number` ([`#L877`](../Src/API.lua#L877))
- `YapperAPI:ResolvePost(handle: number) → boolean` ([`#L1053`](../Src/API.lua#L1053))

### Theme

- `YapperAPI:RegisterTheme(name: string, data: table) → boolean` ([`#L893`](../Src/API.lua#L893))
- `YapperAPI:SetTheme(name: string) → boolean` ([`#L903`](../Src/API.lua#L903))
- `YapperAPI:GetRegisteredThemes() → string[]` ([`#L911`](../Src/API.lua#L911))
- `YapperAPI:GetTheme(name?: string) → table|nil` ([`#L919`](../Src/API.lua#L919))

### Utility wrappers

- `YapperAPI:IsChatLockdown() → boolean` ([`#L932`](../Src/API.lua#L932))
- `YapperAPI:IsSecret(value: any) → boolean` ([`#L945`](../Src/API.lua#L945))
- `YapperAPI:GetChatParent() → Frame` ([`#L966`](../Src/API.lua#L966))
- `YapperAPI:MakeFullscreenAware(frame: Frame) → nil` ([`#L976`](../Src/API.lua#L976))

### Icon gallery

- `YapperAPI:ShowIconGallery(editBox: EditBox, anchorFrame?: Frame, query?: string) → nil` ([`#L1075`](../Src/API.lua#L1075))
- `YapperAPI:HideIconGallery() → nil` ([`#L1083`](../Src/API.lua#L1083))
- `YapperAPI:IsIconGalleryShown() → boolean` ([`#L1089`](../Src/API.lua#L1089))
- `YapperAPI:GetRaidIconData() → table[]` ([`#L1096`](../Src/API.lua#L1096))

### Ghost text / autocomplete

- `YapperAPI:GetAutocompleteSuggestion(word: string) → string|nil` ([`#L1111`](../Src/API.lua#L1111)) — returns the best autocomplete suggestion for the given partial word, or `nil`.
- `YapperAPI:GetCaretOffset(editBox: EditBox) → number` ([`#L1121`](../Src/API.lua#L1121)) — returns the current pixel x-offset of the cursor/caret within an EditBox.
- `YapperAPI:GetGhostFrame() → table|nil` ([`#L1138`](../Src/API.lua#L1138)) — returns the shared FontString used for ghost text rendering.
- `YapperAPI:ShowGhostText(text: string, editBox: EditBox, prefix: string, textUpToCursor: string) → nil` ([`#L1150`](../Src/API.lua#L1150)) — manually show ghost text on a specific EditBox.
- `YapperAPI:HideGhostText() → nil` ([`#L1166`](../Src/API.lua#L1166)) — hide the ghost text.
- `YapperAPI:SetGhostTextOffset(offsetX: number, offsetY: number) → nil` ([`#L1175`](../Src/API.lua#L1175)) — set a manual pixel offset for ghost text alignment.
- `YapperAPI:SyncGhostTextFont() → nil` ([`#L1183`](../Src/API.lua#L1183)) — force the ghost text to re-synchronise its font with its current parent EditBox.
- `YapperAPI:SetSpellcheckTooltipOffset(hintX: number, hintY: number, suggestX: number, suggestY: number) → nil` ([`#L1195`](../Src/API.lua#L1195)) — set manual pixel offsets for spellcheck hint and suggestion tooltips.

### State / frames

- `YapperAPI:SetState(stateName: string) → nil` ([`#L547`](../Src/API.lua#L547)) — transition the state machine to a new state. Prefer `State:Transition` internally; use via API for external orchestration.
- `YapperAPI:ListFrames() → table` ([`#L560`](../Src/API.lua#L560)) — returns a table mapping internal frame names to their WoW frame objects.

### Text insertion

- `YapperAPI:InsertText(text: string) → nil` ([`#L841`](../Src/API.lua#L841)) — insert `text` at the current cursor position in the active Yapper editbox.

### Link protocols

- `YapperAPI:RegisterLinkProtocol(prefix: string) → nil` ([`#L795`](../Src/API.lua#L795)) — declare a `|H` link protocol prefix as a known, first-class link type (prevents it being treated as plain text).
- `YapperAPI:IsLinkProtocolRegistered(prefix: string) → boolean` ([`#L813`](../Src/API.lua#L813)) — returns `true` if `prefix` has been registered via `RegisterLinkProtocol`.
- `YapperAPI:GetRegisteredLinkProtocols() → string[]` ([`#L803`](../Src/API.lua#L803)) — returns a shallow copy of all registered link protocol prefixes.

### Atomic patterns

- `YapperAPI:RegisterAtomicPattern(pattern: string) → nil` ([`#L825`](../Src/API.lua#L825)) — register a custom Lua string pattern that the Yapper chunker should never split across chunk boundaries.
- `YapperAPI:GetRegisteredAtomicPatterns() → string[]` ([`#L832`](../Src/API.lua#L832)) — returns an array of all registered atomic patterns.

### Language engine (public accessor)

- `YapperAPI:GetLanguageEngine(familyId: string) → table|nil` ([`#L760`](../Src/API.lua#L760)) — returns the registered language engine for `familyId`, or `nil` if not found.

## Public API

- Methods:
  - [NEW] `YapperAPI:OpenSettingsCategory(id) → boolean success`: Open Yapper's settings window to a specific category. ([`../Src/API.lua#L1356`](../Src/API.lua#L1356))
  - [NEW] `YapperAPI:GetRegisteredSettingsCategories() → table`: Get a list of registered settings categories (excludes internal ones). ([`../Src/API.lua#L1343`](../Src/API.lua#L1343))
  - [NEW] `YapperAPI:UnregisterSettingsCategory(id) → nil`: Unregister a previously registered settings category. ([`../Src/API.lua#L1325`](../Src/API.lua#L1325))
  - [NEW] `YapperAPI:RegisterSettingsCategory(id, label, options) → boolean success`: Register a settings category in Yapper's settings window. ([`../Src/API.lua#L1285`](../Src/API.lua#L1285))
  - `YapperAPI:Deleet(word) → string`: Convert leetspeak characters back to their base alphabet equivalents. ([`../Src/API.lua#L956`](../Src/API.lua#L956))
  - `YapperAPI:ClearSuggestionCache() → nil`: Clear the spellcheck suggestion cache, forcing re-generation (and re-filtering) ([`../Src/API.lua#L1204`](../Src/API.lua#L1204))
