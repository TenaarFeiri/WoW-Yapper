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

- `YapperAPI:RegisterFilter(hookPoint: string, callback: function, priority?: number) → handle|nil` ([`#L253`](../Src/API.lua#L253))
- `YapperAPI:UnregisterFilter(handle: number) → nil` ([`#L324`](../Src/API.lua#L324))

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
- Fired from [`Src/Chat.lua#L154`](../Src/Chat.lua#L154), inside `Chat:SendPosts` — the single send pipeline shared by the single-line overlay and the multiline composer.
- Fires **once per send**, before chunking, and after the raw input has been recorded to history.
- `payload.text` may contain `\n`. Yapper treats every line as a separate chat message, so a filter that prepends a prefix must prepend it to each line, not just the first.
- A filter may rewrite `chatType`, `language` and `target`; the resolved values are what Yapper routes with and what the sticky-channel state is persisted from.
- Return `false` to cancel the send.

### `PRE_CHUNK`

- Payload: `{ text: string, limit: number, chatType: string|nil, language: any }`
- Fired from [`Src/Chunking.lua#L408`](../Src/Chunking.lua#L408), inside `Chunking:Split`.
- Fires **once per contiguous text unit about to be chunked**, after paragraph isolation, and for every post — including posts short enough to need no splitting.
- A filter may lower `payload.limit` or rewrite `payload.text`.
- A filter may set `payload.continuationPrefix: string`, which the chunker prepends to every chunk after the first and charges against the byte budget automatically. Do not also reduce `limit` to make room for it.
- Ordering within a continuation chunk is `<delineator><continuationPrefix><text>` — for example `» [Common] text`.
- A filter may also set `payload.continuationPrefixFirst: boolean`. Set it when the prefix is parsed by a receiving addon that requires it at the head of the message; the chunker then emits `<continuationPrefix><delineator><text>` instead. Yapper's delineator is user-configurable free text, so a prefix with a strict anchor should not assume what precedes it.
- Return `false` to cancel the send; `Chunking:Split` then returns `nil` and the caller aborts.

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

- `YapperAPI:RegisterCallback(event: string, callback: function) → handle|nil` ([`Src/API.lua#L342`](../Src/API.lua#L342))
- `YapperAPI:UnregisterCallback(handle: number) → nil` ([`Src/API.lua#L402`](../Src/API.lua#L402))

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

- `YapperAPI:GetVersion() → string` ([`#L419`](../Src/API.lua#L419))
- `YapperAPI:GetCurrentTheme() → string|nil` ([`#L425`](../Src/API.lua#L425))
- `YapperAPI:IsOverlayShown() → boolean` ([`#L436`](../Src/API.lua#L436))
- `YapperAPI:GetConfig(path: string) → any` ([`#L454`](../Src/API.lua#L454))
- `YapperAPI:GetDelineator() → string|nil` ([`#L488`](../Src/API.lua#L488))
- `YapperAPI:OpenBlizzardChat() → nil` ([`#L448`](../Src/API.lua#L448))
  Force the Yapper overlay to close and open the original Blizzard editbox. Equivalent to the user pressing the "Bypass Yapper" keybind (Shift-Enter).
- `YapperAPI:GetState() → string` ([`#L497`](../Src/API.lua#L497))
- `YapperAPI:IsState(state: string) → boolean` ([`#L506`](../Src/API.lua#L506))
- `YapperAPI:GetStates() → string[]` ([`#L515`](../Src/API.lua#L515))
- `YapperAPI:GetStateLogs() → table` ([`#L529`](../Src/API.lua#L529)) — returns the full circular buffer of state transitions (max 200 entries).
- `YapperAPI:GetStateLog(index: number) → table|nil` ([`#L539`](../Src/API.lua#L539)) — returns a specific transition entry from the history.
- `YapperAPI:GetStateLogCount() → number` ([`#L548`](../Src/API.lua#L548)) — returns the current number of transitions stored in the buffer.

### Spellcheck helpers

- `YapperAPI:IsSpellcheckEnabled() → boolean` ([`#L605`](../Src/API.lua#L605))
- `YapperAPI:CheckWord(word: string) → boolean` ([`#L614`](../Src/API.lua#L614))
- `YapperAPI:GetSuggestions(word: string) → string[]|nil` ([`#L624`](../Src/API.lua#L624))
- `YapperAPI:GetSpellcheckLocale() → string|nil` ([`#L645`](../Src/API.lua#L645))
- `YapperAPI:AddToDictionary(word: string) → boolean` ([`#L655`](../Src/API.lua#L655))
- `YapperAPI:IgnoreWord(word: string) → boolean` ([`#L668`](../Src/API.lua#L668))
- `YapperAPI:FindMisspellings(text: string) → table[]|nil` ([`#L713`](../Src/API.lua#L713))
- `YapperAPI:IsSuggestionOpen() → boolean` ([`#L682`](../Src/API.lua#L682))
- `YapperAPI:HideSuggestions() → boolean` ([`#L691`](../Src/API.lua#L691))
- `YapperAPI:ApplySuggestion(index: number) → boolean` ([`#L700`](../Src/API.lua#L700))

### Dictionary / language engine

- `YapperAPI:RegisterDictionary(locale: string, data: table) → boolean` ([`#L733`](../Src/API.lua#L733))
  Register a dictionary. If the dictionary belongs to a language family, that family must have a registered engine that satisfies the security validation (see `RegisterLanguageEngine`). Registration will fail if no secure engine is found for the associated family.
- `YapperAPI:RegisterLanguageEngine(familyId: string, engine: table) → boolean` ([`#L750`](../Src/API.lua#L750))
  Register a language engine. **Security Requirement**: The `engine` table MUST provide a `BlockedHashes` table and a `HashWord` function. Registration is blocked if these are missing.
- `YapperAPI:IsLanguageEngineRegistered(familyId: string) → boolean` ([`#L764`](../Src/API.lua#L764))
- `YapperAPI:RegisterLocaleAddon(locale: string, addonName: string) → boolean` ([`#L783`](../Src/API.lua#L783))

### Queue

- `YapperAPI:GetQueueState() → { active, stalled, chatType, policyClass, pending, inFlight }` ([`#L847`](../Src/API.lua#L847))
- `YapperAPI:CancelQueue() → number` ([`#L860`](../Src/API.lua#L860))
- `YapperAPI:ResolvePost(handle: number) → boolean` ([`#L1036`](../Src/API.lua#L1036))

### Theme

- `YapperAPI:RegisterTheme(name: string, data: table) → boolean` ([`#L876`](../Src/API.lua#L876))
- `YapperAPI:SetTheme(name: string) → boolean` ([`#L886`](../Src/API.lua#L886))
- `YapperAPI:GetRegisteredThemes() → string[]` ([`#L894`](../Src/API.lua#L894))
- `YapperAPI:GetTheme(name?: string) → table|nil` ([`#L902`](../Src/API.lua#L902))

### Utility wrappers

- `YapperAPI:IsChatLockdown() → boolean` ([`#L915`](../Src/API.lua#L915))
- `YapperAPI:IsSecret(value: any) → boolean` ([`#L928`](../Src/API.lua#L928))
- `YapperAPI:GetChatParent() → Frame` ([`#L949`](../Src/API.lua#L949))
- `YapperAPI:MakeFullscreenAware(frame: Frame) → nil` ([`#L959`](../Src/API.lua#L959))

### Icon gallery

- `YapperAPI:ShowIconGallery(editBox: EditBox, anchorFrame?: Frame, query?: string) → nil` ([`#L1058`](../Src/API.lua#L1058))
- `YapperAPI:HideIconGallery() → nil` ([`#L1066`](../Src/API.lua#L1066))
- `YapperAPI:IsIconGalleryShown() → boolean` ([`#L1072`](../Src/API.lua#L1072))
- `YapperAPI:GetRaidIconData() → table[]` ([`#L1079`](../Src/API.lua#L1079))

### Ghost text / autocomplete

- `YapperAPI:GetAutocompleteSuggestion(word: string) → string|nil` ([`#L1094`](../Src/API.lua#L1094)) — returns the best autocomplete suggestion for the given partial word, or `nil`.
- `YapperAPI:GetCaretOffset(editBox: EditBox) → number` ([`#L1104`](../Src/API.lua#L1104)) — returns the current pixel x-offset of the cursor/caret within an EditBox.
- `YapperAPI:GetGhostFrame() → table|nil` ([`#L1121`](../Src/API.lua#L1121)) — returns the shared FontString used for ghost text rendering.
- `YapperAPI:ShowGhostText(text: string, editBox: EditBox, prefix: string, textUpToCursor: string) → nil` ([`#L1133`](../Src/API.lua#L1133)) — manually show ghost text on a specific EditBox.
- `YapperAPI:HideGhostText() → nil` ([`#L1149`](../Src/API.lua#L1149)) — hide the ghost text.
- `YapperAPI:SetGhostTextOffset(offsetX: number, offsetY: number) → nil` ([`#L1158`](../Src/API.lua#L1158)) — set a manual pixel offset for ghost text alignment.
- `YapperAPI:SyncGhostTextFont() → nil` ([`#L1166`](../Src/API.lua#L1166)) — force the ghost text to re-synchronise its font with its current parent EditBox.
- `YapperAPI:SetSpellcheckTooltipOffset(hintX: number, hintY: number, suggestX: number, suggestY: number) → nil` ([`#L1178`](../Src/API.lua#L1178)) — set manual pixel offsets for spellcheck hint and suggestion tooltips.

### State / frames

- `YapperAPI:SetState(stateName: string) → nil` ([`#L559`](../Src/API.lua#L559)) — transition the state machine to a new state. Prefer `State:Transition` internally; use via API for external orchestration.
- `YapperAPI:ListFrames() → table` ([`#L572`](../Src/API.lua#L572)) — returns a table mapping internal frame names to their WoW frame objects.

### Text insertion

- `YapperAPI:InsertText(text: string) → nil` ([`#L824`](../Src/API.lua#L824)) — insert `text` at the current cursor position in the active Yapper editbox.

### Atomic patterns

- `YapperAPI:RegisterAtomicPattern(pattern: string) → nil` ([`#L808`](../Src/API.lua#L808)) — register a custom Lua string pattern that the Yapper chunker should never split across chunk boundaries.
- `YapperAPI:GetRegisteredAtomicPatterns() → string[]` ([`#L815`](../Src/API.lua#L815)) — returns an array of all registered atomic patterns.

### Language engine (public accessor)

- `YapperAPI:GetLanguageEngine(familyId: string) → table|nil` ([`#L772`](../Src/API.lua#L772)) — returns the registered language engine for `familyId`, or `nil` if not found.

## Public API

- Methods:
  - [NEW] `YapperAPI:OpenSettingsCategory(id) → boolean success`: Open Yapper's settings window to a specific category. ([`../Src/API.lua#L1339`](../Src/API.lua#L1339))
  - [NEW] `YapperAPI:GetRegisteredSettingsCategories() → table`: Get a list of registered settings categories (excludes internal ones). ([`../Src/API.lua#L1326`](../Src/API.lua#L1326))
  - [NEW] `YapperAPI:UnregisterSettingsCategory(id) → nil`: Unregister a previously registered settings category. ([`../Src/API.lua#L1308`](../Src/API.lua#L1308))
  - [NEW] `YapperAPI:RegisterSettingsCategory(id, label, options) → boolean success`: Register a settings category in Yapper's settings window. ([`../Src/API.lua#L1268`](../Src/API.lua#L1268))
  - `YapperAPI:Deleet(word) → string`: Convert leetspeak characters back to their base alphabet equivalents. ([`../Src/API.lua#L939`](../Src/API.lua#L939))
  - `YapperAPI:ClearSuggestionCache() → nil`: Clear the spellcheck suggestion cache, forcing re-generation (and re-filtering) ([`../Src/API.lua#L1187`](../Src/API.lua#L1187))
