# Yapper public API (`_G.YapperAPI`)

> `_G.YapperAPI` is the supported integration boundary between other add-ons and Yapper. Prefer this API over internal tables. If an integration needs a missing hook or accessor, request a public API rather than depending on implementation details.
>
> Deprecated API names are retained for compatibility where explicitly documented. Yapper may warn when a deprecated alias is used. The current compatibility aliases are listed below; do not assume that undocumented names are protected.
>
> Explicitly deprecated API is intended to remain protected for up to six months through an alias or replacement wrapper. After that grace period, it may be removed or become unusable. Update integrations when a deprecation notice appears.

Source of truth: [`Src/API.lua`](../Src/API.lua).

## Stability and usage

- The public object is created at [`Src/API.lua#L237-L240`](../Src/API.lua#L237-L240).
- API compatibility is feature-detected; there is no API-version field to branch on.
- External filter and callback handlers are invoked through `pcall`, so handler errors do not propagate into Yapper.
- Filters are pre-operation hooks and may modify or cancel. Callbacks are notification events and cannot modify or cancel the operation.
- A maximum of 50 filters is allowed per hook point and 50 callbacks per event. Registration returns `nil` when validation fails or a cap is reached.
- Filter registrations receive monotonically increasing numeric handles. Callback registrations use the same handle sequence; handles are opaque and should only be passed back to the matching unregister method.

## Filters

### Registration

- `YapperAPI:RegisterFilter(hookPoint: string, callback: function, priority?: number) → number|nil` ([`Src/API.lua#L410`](../Src/API.lua#L419))
- `YapperAPI:UnregisterFilter(handle: number) → nil` ([`Src/API.lua#L481`](../Src/API.lua#L474))

`callback` receives one payload table. A filter may:

- return the payload table, usually the same table after in-place mutation;
- return a replacement table;
- return `false` to cancel a cancellable operation; or
- return `nil` to continue with the current payload unchanged. This is supported for compatibility, but returning the payload explicitly is preferred.

`priority` defaults to `10`; lower values run first. Equal priorities run in registration order. Unknown hook points are rejected. There are currently no filter aliases.

### `PRE_EDITBOX_SHOW`

- Payload: `{ chatType: string|nil, target: string|nil }`
- Return `false` to suppress the overlay opening.
- Fired by the Blizzard editbox hooks and Yapper keybind path before the overlay is shown.

### `PRE_EDITBOX_LABEL`

- Payload: `{ chatType: string|nil, target: string|number|nil, channelName: string|nil, label: string|nil, unit: string|nil }`
- This hook is deliberately non-cancellable. Returning `false` is ignored.
- Mutate `payload.label` to provide custom label text. Yapper falls back to normal label resolution when no non-empty string label is supplied.
- Yapper deep-copies the original payload before filtering and restores it when a filter returns `false`, a non-table, or malformed values.
- Implementation: [`Src/EditBox/Overlay.lua#L231-L280`](../Src/EditBox/Overlay.lua#L231-L280).

### `PRE_SEND`

- Payload: `{ text: string, chatType: string, language: any, target: string|number|nil }`
- Runs once per composed send in `Chat:SendPosts`, after raw input is recorded to history and before chunking.
- `payload.text` may contain newlines. Yapper splits each resulting line into a separate post, so a prefix intended for every line must be applied to every line.
- Filters may rewrite `text`, `chatType`, `language`, or `target`. The resolved routing fields are used for delivery and sticky-channel persistence.
- Return `false` to cancel the send.
- Implementation: [`Src/Chat.lua#L135-L150`](../Src/Chat.lua#L135-L150).

### `PRE_CHUNK`

- Payload: `{ text: string, limit: number, chatType: string|nil, language: any }`
- Runs once per contiguous text unit passed to `Chunking:Split`, after paragraph isolation and even when the text needs no splitting.
- Filters may rewrite `text` or `limit`.
- `payload.continuationPrefix: string`, when supplied, is prepended to every chunk after the first and charged against the byte budget automatically. Do not reduce `limit` separately to reserve space for it.
- By default a continuation chunk is ordered as `<delineator><continuationPrefix><text>`.
- `payload.continuationPrefixFirst: boolean` moves the continuation prefix before the delineator: `<continuationPrefix><delineator><text>`. Use this when the receiving addon requires its marker at the head of the message; the delineator is user-configurable and must not be assumed.
- Return `false` to cancel chunking. `Chunking:Split` returns `nil` and the caller aborts the send.
- Implementation: [`Src/Chunking.lua#L365-L426`](../Src/Chunking.lua#L365-L426).

### `PRE_DELIVER`

- Payload: `{ text: string, chatType: string, language: any, target: string|number|nil }`
- Runs immediately before `Router:Send` for one message.
- A filter may rewrite the payload or return `false` to claim delivery. A claim causes `POST_CLAIMED` to fire and starts a five-second delegation timeout.
- The claiming addon must call `YapperAPI:ResolvePost(handle)` before the timeout. If it does not, Yapper sends the message itself and reports the claiming owner.
- Implementation: [`Src/Chat.lua#L274-L315`](../Src/Chat.lua#L274-L315).

### `PRE_SPELLCHECK`

- Payload: `{ text: string }`
- Runs before spellcheck examines the text.
- Return `false` to skip spellcheck for that operation.
- Implementation: [`Src/Spellcheck/Engine.lua#L83-L91`](../Src/Spellcheck/Engine.lua#L83-L91).

### `PRE_SPELLCHECK_SUGGESTIONS`

- Payload: `{ word: string, suggestions: table[], locale: string }`
- Runs after suggestions are scored, sorted, and formatted, but before the result is cached and shown.
- Entries normally have one of these forms:
  - `{ kind="word", value=string, score=number, baseScore=number }`
  - `{ kind="add", value=string }`
  - `{ kind="ignore", value=string }`
  - `{ kind="split", value=string }`
- Add-ons may reorder, append, remove, or rewrite entries by mutating the `suggestions` array and returning the payload.
- Return `false` to suppress the suggestion result. Call `YapperAPI:ClearSuggestionCache()` after changing plugin state when cached results must be recomputed.
- Implementation: [`Src/Spellcheck/Engine.lua#L1198-L1226`](../Src/Spellcheck/Engine.lua#L1198-L1226).

### `PRE_MULTILINE_SHOW`

- Payload: `{ text: string, chatType: string, language: any, target: string|number|nil }`
- Runs before the expanded multiline editor opens.
- Modify the initial text or routing fields, or return `false` to block opening.
- Implementation: [`Src/Multiline.lua#L624-L644`](../Src/Multiline.lua#L624-L644).

### `PRE_ICON_GALLERY_SHOW`

- Payload: `{ rawEditBox: EditBox, query: string }`
- Runs before the raid-icon gallery opens.
- Filters may rewrite both `rawEditBox` and `query`, or return `false` to suppress the gallery.
- Implementation: [`Src/IconGallery.lua#L78-L107`](../Src/IconGallery.lua#L78-L107).

## Callbacks

### Registration

- `YapperAPI:RegisterCallback(event: string, callback: function) → number|nil` ([`Src/API.lua#L499`](../Src/API.lua#L492))
- `YapperAPI:UnregisterCallback(handle: number) → nil` ([`Src/API.lua#L559`](../Src/API.lua#L538))

Callbacks receive event-specific arguments. Return values are ignored. Unknown event names are rejected. Each event allows at most 50 registered callbacks.

### Event list

- `POST_SEND(text, chatType, language, target)` — fires after the router or WoW chat API accepts the message.
- `POST_CLAIMED(handle, text, chatType, language, target)` — fires when `PRE_DELIVER` claims a message and creates a delegation handle.
- `CONFIG_CHANGED(path, value)` — fires when a Yapper setting changes. `path` is a dot-delimited config path.
- `STATE_CHANGED(newState, oldState, ...)` — fires after a state transition. Trailing values are transition metadata.
- `EDITBOX_SHOW(chatType, target)` — fires when the Yapper overlay becomes visible.
- `EDITBOX_HIDE()` — fires when the Yapper overlay is hidden.
- `EDITBOX_TEXT_CHANGED(text, isUserInput, box)` — fires when a managed editbox's text changes. `box` is the relevant WoW EditBox.
- `EDITBOX_CHANNEL_CHANGED(chatType, target)` — fires when the active chat channel or target changes.
- `EDITBOX_LABEL_UPDATED(label, r, g, b)` — fires after the visible label and its text colour are refreshed.
- `THEME_CHANGED(themeName)` — fires after the active theme changes.
- `SPELLCHECK_SUGGESTION(word, suggestions)` — fires when the suggestion popup is shown. `suggestions` is the displayed array of strings.
- `SPELLCHECK_SUGGESTION_HIGHLIGHTED(text, index, total)` — fires when a suggestion is highlighted. `text` has colour codes stripped; `index` is one-based.
- `SPELLCHECK_APPLIED(original, replacement)` — fires when a suggestion is applied.
- `SPELLCHECK_CLOSED()` — fires when the suggestion popup closes.
- `SPELLCHECK_WORD_ADDED(word, locale)` — fires when a word is added to the current user dictionary.
- `SPELLCHECK_WORD_IGNORED(word, locale)` — fires when a word is marked ignored.
- `YAS_WORD_LEARNED(word, locale)` — fires when YAS automatically promotes a word to the user dictionary.
- `QUEUE_STALL(chatType, policyClass, chunksRemaining)` — fires when the queue acknowledgement timer expires and the Continue prompt is shown. `chunksRemaining` includes the stalled chunk.
- `QUEUE_COMPLETE()` — fires when the delivery queue finishes or is cancelled.
- `ICON_GALLERY_SHOW(query)` — fires when the raid-icon gallery opens. `query` may be empty.
- `ICON_GALLERY_HIDE()` — fires when the gallery closes.
- `ICON_GALLERY_SELECT(index, text, code)` — fires when an icon is selected. `index` is 1-8; `text` is the icon name; `code` is its shorthand such as `rt8`.
- `STRINGS_UPDATED(locale)` — fires when an addon registers or replaces a locale string table via `RegisterStrings`. Widgets that resolve strings at render time pick up the change automatically; listeners can use this to re-render open panels.
- `API_ERROR(kind, hook, handler_info, errorMessage, data, ...)` — reports handler failures, unexpected filter return values, registration-cap failures, delegation timeouts, and other API-level errors.

`YALLM_WORD_LEARNED(word, locale)` is a deprecated alias for `YAS_WORD_LEARNED`. Registering the old name resolves it to the canonical event and emits a deprecation warning. The alias is defined at [`Src/API.lua#L72-L75`](../Src/API.lua#L72-L75).

Callback emission sites include [`Src/Chat.lua`](../Src/Chat.lua), [`Src/Queue.lua`](../Src/Queue.lua), [`Src/Interface/Config.lua`](../Src/Interface/Config.lua), [`Src/Hooks/ShowHide.lua`](../Src/Hooks/ShowHide.lua), [`Src/Hooks/Label.lua`](../Src/Hooks/Label.lua), [`Src/Theme.lua`](../Src/Theme.lua), [`Src/IconGallery.lua`](../Src/IconGallery.lua), [`Src/Spellcheck.lua`](../Src/Spellcheck.lua), [`Src/Spellcheck/UI.lua`](../Src/Spellcheck/UI.lua), [`Src/Spellcheck/Adaptive.lua`](../Src/Spellcheck/Adaptive.lua), [`Src/State.lua`](../Src/State.lua), [`Src/Multiline.lua`](../Src/Multiline.lua), and [`Src/API.lua`](../Src/API.lua).

### `API_ERROR` ownership and payload

When a handler faults, Yapper first attempts to deliver `API_ERROR` only to handlers whose best-effort detected owner matches the failing handler's owner. If no owner-matched handlers exist, it broadcasts to all `API_ERROR` handlers. If none are registered, it emits debug output instead. API_ERROR handlers are themselves protected and do not recursively emit another `API_ERROR` event.

`handler_info` is nil when no registered handler caused the error. Otherwise it contains a snapshot with `handle`, `priority` when applicable, and `owner` when available. `data` and trailing callback arguments are bounded, sanitized snapshots: secret values are replaced with `<secret>` and nested tables are not passed through live. The `kind` value commonly includes `filter`, `callback`, and `filter-return`, but operation-level errors may use values such as `FILTER`, `CALLBACK`, `SETTINGS`, `RegisterDictionary`, `RegisterLanguageEngine`, `deprecated`, or `delegation-timeout`.

Implementation: [`Src/API.lua#L153-L224`](../Src/API.lua#L153-L224).

## Methods

All methods below are members of `_G.YapperAPI` and use colon-call syntax.

### Core, configuration, and lifecycle

- `YapperAPI:GetVersion() → string` ([`Src/API.lua#L554`](../Src/API.lua#L554)) — returns addon metadata version, or `"unknown"` if the core is unavailable.
- `YapperAPI:GetCurrentTheme() → string|nil` ([`Src/API.lua#L583`](../Src/API.lua#L562)) — returns the active theme name.
- `YapperAPI:IsOverlayShown() → boolean` ([`Src/API.lua#L594`](../Src/API.lua#L573)) — reports whether the single-line overlay is visible.
- `YapperAPI:OpenBlizzardChat() → nil` ([`Src/API.lua#L604`](../Src/API.lua#L583)) — requests the Blizzard editbox path, equivalent to the Bypass Yapper keybind.
- `YapperAPI:GetConfig(path: string) → any|nil` ([`Src/API.lua#L612`](../Src/API.lua#L591)) — reads a dot-delimited path. Returned tables are deep copies. `Spellcheck.UnderlineColor` is a deprecated alias for `Spellcheck.MisspellingColour`.
- `YapperAPI:GetDelineator() → string|nil` ([`Src/API.lua#L643`](../Src/API.lua#L619)) — returns `Chat.DELINEATOR`, falling back to the legacy `Chat.PREFIX` key.

### State and frames

- `YapperAPI:GetState() → string` ([`Src/API.lua#L652`](../Src/API.lua#L628))
- `YapperAPI:IsState(state: string) → boolean` ([`Src/API.lua#L661`](../Src/API.lua#L637))
- `YapperAPI:GetStates() → string[]` ([`Src/API.lua#L670`](../Src/API.lua#L646)) — sorted valid states are `INITIALISING`, `IDLE`, `EDITING`, `MULTILINE`, `SENDING`, `STALLED`, `LOCKDOWN`, and `CONFIG`.
- `YapperAPI:GetStateLogs() → table` ([`Src/API.lua#L684`](../Src/API.lua#L660)) — returns a copy of the circular buffer, capped at 200 entries.
- `YapperAPI:GetStateLog(index: number) → table|nil` ([`Src/API.lua#L694`](../Src/API.lua#L670)) — returns a copy of the entry at an index.
- `YapperAPI:GetStateLogCount() → number` ([`Src/API.lua#L703`](../Src/API.lua#L679)).
- `YapperAPI:SetState(stateName: string, ...) → boolean` ([`Src/API.lua#L730`](../Src/API.lua#L706)) — deprecated compatibility escape hatch. It emits a one-time deprecation warning and `API_ERROR` notification when first used. It returns false for an invalid state; otherwise requests the transition and returns true. Extra arguments are forwarded as `STATE_CHANGED` metadata. Avoid new usage because forced transitions can bypass internal safety logic.
- `YapperAPI:ListFrames() → table` ([`Src/API.lua#L752`](../Src/API.lua#L728)) — returns flat keys `Overlay`, `OverlayEdit`, `LabelBg`, `SuggestionFrame`, `HintFrame`, `SuggestionClickCatcher`, `MultilineFrame`, `MultilineEdit`, and `MultilineScroll`, plus `All`, the categorized live frame registry.

State log entries have `{ time, old, new, file, func, line }`. `GetStateLogs` and `GetStateLog` return copied data. `ListFrames` intentionally exposes live frame objects so addons can re-parent or restyle them; callers should not replace or mutate the registry structure itself.

### Spellcheck helpers

- `YapperAPI:IsSpellcheckEnabled() → boolean` ([`Src/API.lua#L785`](../Src/API.lua#L761))
- `YapperAPI:CheckWord(word: string) → boolean` ([`Src/API.lua#L794`](../Src/API.lua#L770))
- `YapperAPI:GetSuggestions(word: string) → string[]|nil` ([`Src/API.lua#L804`](../Src/API.lua#L780)) — unwraps internal suggestion records to public word strings.
- `YapperAPI:GetSpellcheckLocale() → string|nil` ([`Src/API.lua#L825`](../Src/API.lua#L801))
- `YapperAPI:AddToDictionary(word: string) → boolean` ([`Src/API.lua#L835`](../Src/API.lua#L811))
- `YapperAPI:IgnoreWord(word: string) → boolean` ([`Src/API.lua#L848`](../Src/API.lua#L824))
- `YapperAPI:IsSuggestionOpen() → boolean` ([`Src/API.lua#L860`](../Src/API.lua#L836))
- `YapperAPI:HideSuggestions() → boolean` ([`Src/API.lua#L869`](../Src/API.lua#L845)) — true means spellcheck was available and the hide operation was called; it does not necessarily mean a visible popup existed.
- `YapperAPI:ApplySuggestion(index: number) → boolean` ([`Src/API.lua#L880`](../Src/API.lua#L859)) — accepts a one-based suggestion row.
- `YapperAPI:FindMisspellings(text: string) → table[]|nil` ([`Src/API.lua#L893`](../Src/API.lua#L869)) — returns nil when disabled, unavailable, or empty; entries are `{ startPos, endPos, word }`.
- `YapperAPI:ClearSuggestionCache() → boolean` ([`Src/API.lua#L1369`](../Src/API.lua#L1384)) — returns true when the spellcheck service cleared its cache.

These wrappers return false or nil when spellcheck is unavailable or arguments are invalid.

### Dictionary and language engines

- `YapperAPI:RegisterDictionary(locale: string, data: table|function) → boolean` ([`Src/API.lua#L914`](../Src/API.lua#L892)) — accepts a dictionary data table or lazy builder function. Tables may provide `words`, `phonetics`, `extends`, `languageFamily`, `affixRules`, and an optional `engine`. Every dictionary must resolve to a `languageFamily` whose engine is already registered — there is no implicit default. Delta status is inferred from `extends`; an `isDelta` field is not used by the implementation. A true result means dispatch completed without a Lua error; internal contract validation may still reject the data.
- `YapperAPI:RegisterLanguageEngine(familyId: string, engine: table) → boolean` ([`Src/API.lua#L932`](../Src/API.lua#L919)) — registers an engine under a strict contract. Required: `NormaliseWord`, `NormaliseVowels`, `GetPhoneticHash`, `HashWord`, `BlockedHashes`, `WordBytes`, `WordStartBytes`. Optional: `StripAffixes`, `ShouldCheckWord`, `MatchCase`, `IsSaneWord`, `HasVariantRules`, `VariantRules`, `ScoreWeights`, `KBLayouts`, `DefaultLayout`, `Locales`, `DisplayName`. Unknown keys are rejected (`X_`-prefixed keys are allowed as vendor extensions). Engines are owner-locked per family, validated with runtime probes, and purged together with their bound dictionaries if they throw at runtime. Full contract, limits, and examples: [Dictionaries.md](Dictionaries.md).
- `YapperAPI:IsLanguageEngineRegistered(familyId: string) → boolean` ([`Src/API.lua#L947`](../Src/API.lua#L968)).
- `YapperAPI:GetLanguageEngine(familyId: string) → table|nil` ([`Src/API.lua#L955`](../Src/API.lua#L976)) — returns a deep copy of the registered engine; functions remain callable, but nested tables are not live registry data.
- `YapperAPI:RegisterLocaleAddon(locale: string, addonName: string) → boolean` ([`Src/API.lua#L966`](../Src/API.lua#L986)) — maps a load-on-demand dictionary addon to a locale and retries `EnsureLocale` immediately when that locale is active.

### UI strings (localisation)

UI strings resolve against the **client** locale (`GetLocale()`), never the spellcheck dictionary locale. The enUS table in [`Src/Strings.lua`](../Src/Strings.lua) is canonical; addon-registered locales may only override keys that exist there, and missing keys fall back to English.

- `YapperAPI:RegisterStrings(locale: string, tbl: table) → boolean` ([`Src/API.lua`](../Src/API.lua)) — registers a sparse `{ key → translated text }` table for a locale. Owner-captured: re-registering from the same addon replaces that addon's contribution wholesale; when two addons set the same key, the later registration wins. Validated before applying (string keys/values, length caps, keys must exist in the canonical table); a rejected registration changes nothing. `enUS` is core-owned and cannot be overridden. Fires `STRINGS_UPDATED` on success.
- `YapperAPI:GetString(key: string, ...: any) → string` ([`Src/API.lua`](../Src/API.lua)) — resolves a key for the active client locale with enUS fallback; extra arguments feed `string.format`. Never returns nil — an unknown key resolves to the key itself.

Call sites should resolve at render time rather than caching text: dictionary addons are load-on-demand, so translations can arrive after the UI is built.

### Queue, delivery, and text handling

- `YapperAPI:InsertText(text: string) → boolean` ([`Src/API.lua#L1007`](../Src/API.lua#L1027)) — inserts non-empty text into the active Yapper editbox. Multiline has priority; false means no active Yapper editbox.
- `YapperAPI:GetQueueState() → table` ([`Src/API.lua#L1030`](../Src/API.lua#L1049)) — returns `active`, `stalled`, `chatType`, `policyClass`, `pending`, and `inFlight`. `expectedAckEvent` is removed as an internal field. When Queue is unavailable, the fallback contains `active=false`, `stalled=false`, `pending=0`, and `inFlight=0`.
- `YapperAPI:CancelQueue() → number` ([`Src/API.lua#L1043`](../Src/API.lua#L1062)) — cancels the active queue and returns the number of discarded chunks; returns 0 when there is nothing to cancel.
- `YapperAPI:ResolvePost(handle: number) → boolean` ([`Src/API.lua#L1218`](../Src/API.lua#L1235)) — clears an active `POST_CLAIMED` delegation claim before its timeout.
- `YapperAPI:RegisterAtomicPattern(pattern: string) → boolean` ([`Src/API.lua#L991`](../Src/API.lua#L1011)) — registers a non-empty Lua string pattern that the chunker treats as atomic. Duplicate patterns are allowed.
- `YapperAPI:GetRegisteredAtomicPatterns() → string[]` ([`Src/API.lua#L998`](../Src/API.lua#L1018)) — returns a copy of the registry array.

### Themes and utility helpers

- `YapperAPI:RegisterTheme(name: string, data: table) → boolean` ([`Src/API.lua#L1060`](../Src/API.lua#L1079)) — registers a deep copy of a theme table containing fields such as `inputBg`, `labelBg`, `textColor`, `borderColor`, `border`, `allowRoundedCorners`, `allowDropShadow`, `font`, and optional `OnApply`.
- `YapperAPI:SetTheme(name: string) → boolean` ([`Src/API.lua#L1070`](../Src/API.lua#L1089)) — activates and persists a registered theme, updates live UI, and emits `THEME_CHANGED`.
- `YapperAPI:GetRegisteredThemes() → string[]` ([`Src/API.lua#L1078`](../Src/API.lua#L1097)) — returns names sorted alphabetically.
- `YapperAPI:GetTheme(name?: string) → table|nil` ([`Src/API.lua#L1086`](../Src/API.lua#L1105)) — returns a deep copy; nil selects the active theme.
- `YapperAPI:IsChatLockdown() → boolean` ([`Src/API.lua#L1097`](../Src/API.lua#L1116)).
- `YapperAPI:IsSecret(value: any) → boolean` ([`Src/API.lua#L1110`](../Src/API.lua#L1129)) — uses Blizzard secret/accessibility predicates, with `|K` and empty-string fallbacks; nil and false are treated as secret.
- `YapperAPI:Deleet(word: string) → string` ([`Src/API.lua#L1121`](../Src/API.lua#L1140)) — converts common leetspeak substitutions to letters.
- `YapperAPI:GetChatParent() → Frame` ([`Src/API.lua#L1131`](../Src/API.lua#L1150)).
- `YapperAPI:MakeFullscreenAware(frame: Frame) → nil` ([`Src/API.lua#L1141`](../Src/API.lua#L1160)) — hooks reparenting across fullscreen panel changes.

### Icon gallery

- `YapperAPI:ShowIconGallery(editBox: EditBox, anchorFrame?: Frame, query?: string) → nil` ([`Src/API.lua#L1240`](../Src/API.lua#L1256)) — anchors to `anchorFrame` or `editBox`; invalid editbox values are ignored. `PRE_ICON_GALLERY_SHOW` may rewrite the editbox/query or cancel.
- `YapperAPI:HideIconGallery() → nil` ([`Src/API.lua#L1248`](../Src/API.lua#L1264)).
- `YapperAPI:IsIconGalleryShown() → boolean` ([`Src/API.lua#L1254`](../Src/API.lua#L1270)).
- `YapperAPI:GetRaidIconData() → table[]` ([`Src/API.lua#L1261`](../Src/API.lua#L1277)) — returns eight newly-created `{ index, text, code }` metadata tables for `star/rt1` through `skull/rt8`.

### Autocomplete and ghost text

- `YapperAPI:GetAutocompleteSuggestion(word: string) → string|nil` ([`Src/API.lua#L1276`](../Src/API.lua#L1292)).
- `YapperAPI:GetCaretOffset(editBox: EditBox) → number, number, number` ([`Src/API.lua#L1286`](../Src/API.lua#L1302)) — returns logical-pixel `x, y, height`, or `0, 0, 0` when the editbox is not the currently hooked one.
- `YapperAPI:GetGhostFrame() → FontString|nil` ([`Src/API.lua#L1303`](../Src/API.lua#L1319)).
- `YapperAPI:ShowGhostText(text: string, editBox: EditBox, prefix?: string, textUpToCursor?: string) → nil` ([`Src/API.lua#L1315`](../Src/API.lua#L1331)).
- `YapperAPI:HideGhostText() → nil` ([`Src/API.lua#L1331`](../Src/API.lua#L1346)).
- `YapperAPI:SetGhostTextOffset(offsetX: number, offsetY: number) → nil` ([`Src/API.lua#L1340`](../Src/API.lua#L1355)).
- `YapperAPI:SyncGhostTextFont() → nil` ([`Src/API.lua#L1348`](../Src/API.lua#L1363)).
- `YapperAPI:SetSpellcheckTooltipOffset(hintX?: number, hintY?: number, suggestX?: number, suggestY?: number) → nil` ([`Src/API.lua#L1360`](../Src/API.lua#L1375)).

### Settings categories

- `YapperAPI:RegisterSettingsCategory(id: string, label: string, options: table) → boolean` ([`Src/API.lua#L1460`](../Src/API.lua#L1473)) — rejects invalid or duplicate IDs and caps registrations at 20. `options.render` must be a function when present; `options.schema` must be a table when present. At least one of `render`, `schema`, or the internal `_internal` flag is required. `options.internal = true` marks the category hidden from `GetRegisteredSettingsCategories()`.
- `YapperAPI:UnregisterSettingsCategory(id: string) → nil` ([`Src/API.lua#L1500`](../Src/API.lua#L1510)) — ignores invalid or unknown IDs.
- `YapperAPI:GetRegisteredSettingsCategories() → { { id: string, label: string } }` ([`Src/API.lua#L1518`](../Src/API.lua#L1527)) — returns newly-created `{ id, label }` tables for categories not marked `internal`.
- `YapperAPI:OpenSettingsCategory(id: string) → boolean` ([`Src/API.lua#L1531`](../Src/API.lua#L1540)) — returns false for a non-string ID or unavailable Interface module. It passes string IDs to `Interface:OpenToCategory` and does not verify that a category with that ID exists.

## Grouped aliases

The following tables are feature-detection-friendly aliases to the existing flat methods. They reference the same functions and do not introduce separate behavior. Use colon-call syntax; the original flat names remain the compatibility surface.

- `YapperAPI.Filters`: `RegisterFilter`, `UnregisterFilter`
- `YapperAPI.Callbacks`: `RegisterCallback`, `UnregisterCallback`
- `YapperAPI.State`: `GetState`, `IsState`, `GetStates`, `GetStateLogs`, `GetStateLog`, `GetStateLogCount`, `SetState`
- `YapperAPI.Chat`: `GetDelineator`, `InsertText`, `GetQueueState`, `CancelQueue`, `ResolvePost`, `RegisterAtomicPattern`, `GetRegisteredAtomicPatterns`, `OpenBlizzardChat`
- `YapperAPI.Spellcheck`: spellcheck helpers plus dictionary and language-engine registration methods
- `YapperAPI.Themes`: theme accessors and mutators
- `YapperAPI.UI`: overlay, frame, icon-gallery, autocomplete, ghost-text, and fullscreen-parent methods
- `YapperAPI.Settings`: settings-category methods
- `YapperAPI.Utility`: `GetConfig`, `IsChatLockdown`, `IsSecret`, `Deleet`

Example:

```lua
YapperAPI.Spellcheck:CheckWord("hello")
YapperAPI.Filters:RegisterFilter("PRE_SEND", handler)
```

## Compatibility aliases

- Callback alias: `YALLM_WORD_LEARNED` → `YAS_WORD_LEARNED`.
- Config alias: `Spellcheck.UnderlineColor` → `Spellcheck.MisspellingColour`, resolved by `GetConfig()` with a warning.
- There are currently no filter aliases.

## Add-on author notes

- Use colon-call syntax and retain registration handles so handlers can be unregistered.
- `GetStateLogs`, `GetStateLog`, `GetLanguageEngine`, `GetTheme`, `GetConfig`, and `GetRegisteredAtomicPatterns` return copied data. `ListFrames` intentionally exposes live frame objects for addon customization; do not replace the registry structure itself.
- Filter payloads are validated after each handler. Mutate in place and return the payload explicitly; malformed replacements are rejected and reported through `API_ERROR`.
- `API_ERROR` data is sanitized and may contain `<secret>`, bounded table snapshots, or redacted values rather than the original object.
- `PRE_EDITBOX_LABEL` is non-cancellable. `PRE_DELIVER` is the filter that starts external delivery delegation when it returns false.
- Do not depend on `YapperTable` or the internal `API:RunFilter`/`API:Fire` object; those are implementation entry points for Yapper's own modules.
