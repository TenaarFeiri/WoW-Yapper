# Yapper public API (`_G.YapperAPI`)

Source of truth: [`Src/API.lua`](../Src/API.lua).

## Stability and usage

- Public object is created at [`Src/API.lua#L540-L543`](../Src/API.lua#L540-L543).
- Registrations are sandboxed (`pcall`) so consumer errors do not crash Yapper.
- Filters are cancellable pre-hooks; callbacks are post events.

## Filters

Register/unregister:

- `YapperAPI:RegisterFilter(hookPoint: string, callback: function, priority?: number) → handle|nil` ([`#L557`](../Src/API.lua#L557))
- `YapperAPI:UnregisterFilter(handle: number) → nil` ([`#L610`](../Src/API.lua#L610))

### `PRE_EDITBOX_SHOW`

- Signature: `callback(payload) → payload|false`
- Payload: `{ chatType: string|nil, target: string|nil }`
- Fired from [`Src/EditBox/Hooks.lua#L1256`](../Src/EditBox/Hooks.lua#L1256).
- Return `false` to suppress overlay open.

### `PRE_SEND`

- Payload: `{ text: string, chatType: string, language: any, target: string|number|nil }`
- Fired from [`Src/Chat.lua#L89`](../Src/Chat.lua#L89) and [`Src/Multiline.lua#L740`](../Src/Multiline.lua#L740).
- Return `false` to cancel send.

### `PRE_CHUNK`

- Payload: `{ text: string, limit: number }`
- Fired from [`Src/Chat.lua#L150`](../Src/Chat.lua#L150).
- Return `false` to abort chunking path.

### `PRE_DELIVER`

- Payload: `{ text: string, chatType: string, language: any, target: string|number|nil }`
- Fired from [`Src/Chat.lua#L223`](../Src/Chat.lua#L223).
- Return `false` to claim delivery; this emits `POST_CLAIMED` and starts delegation timeout.

### `PRE_SPELLCHECK`

- Payload: `{ text: string }`
- Fired from [`Src/Spellcheck/Engine.lua#L81`](../Src/Spellcheck/Engine.lua#L81).
- Return `false` to skip spellcheck for that text.

## Callbacks

Register/unregister:

- `YapperAPI:RegisterCallback(event: string, callback: function) → handle|nil` ([`Src/API.lua#L650`](../Src/API.lua#L650))
- `YapperAPI:UnregisterCallback(handle: number) → nil` ([`Src/API.lua#L691`](../Src/API.lua#L691))

### Event list

- `POST_SEND(text, chatType, language, target)`
- `POST_CLAIMED(handle, text, chatType, language, target)`
- `CONFIG_CHANGED(path, value)`
- `STATE_CHANGED(newState, oldState, ...)`
- `EDITBOX_SHOW(chatType, target)`
- `EDITBOX_HIDE()`
- `EDITBOX_CHANNEL_CHANGED(chatType, target)`
- `THEME_CHANGED(themeName)`
- `SPELLCHECK_SUGGESTION(word, suggestions)`
- `SPELLCHECK_APPLIED(original, replacement)`
- `SPELLCHECK_WORD_ADDED(word, locale)`
- `SPELLCHECK_WORD_IGNORED(word, locale)`
- `YALLM_WORD_LEARNED(word, locale)`
- `QUEUE_STALL(chatType, policyClass, chunksRemaining)`
- `QUEUE_COMPLETE()`
- `ICON_GALLERY_SHOW(query)`
- `ICON_GALLERY_HIDE()`
- `ICON_GALLERY_SELECT(index, text, code)`
- `API_ERROR(kind, hook, handlerInfo, errorMessage, data, ...)`

Emission sites: [`Src/Chat.lua`](../Src/Chat.lua), [`Src/Queue.lua`](../Src/Queue.lua), [`Src/Interface/Config.lua`](../Src/Interface/Config.lua), [`Src/EditBox/Hooks.lua`](../Src/EditBox/Hooks.lua), [`Src/Theme.lua`](../Src/Theme.lua), [`Src/IconGallery.lua`](../Src/IconGallery.lua), [`Src/Spellcheck.lua`](../Src/Spellcheck.lua), [`Src/Spellcheck/UI.lua`](../Src/Spellcheck/UI.lua), [`Src/Spellcheck/YALLM.lua`](../Src/Spellcheck/YALLM.lua).

### `API_ERROR` ownership/scoping

When a handler faults, Yapper first attempts to route `API_ERROR` only to handlers owned by the same addon/module (owner captured at registration from source path). If no owner-matched handlers exist, it falls back to broadcasting all `API_ERROR` handlers; if none exist, it emits debug output. See [`Src/API.lua#L334-L355`](../Src/API.lua#L334-L355).

## Methods

### Registration / lifecycle

- `YapperAPI:GetVersion() → string` ([`#L684`](../Src/API.lua#L684))
- `YapperAPI:GetCurrentTheme() → string|nil` ([`#L692`](../Src/API.lua#L692))
- `YapperAPI:IsOverlayShown() → boolean` ([`#L703`](../Src/API.lua#L703))
- `YapperAPI:GetConfig(path: string) → any` ([`#L713`](../Src/API.lua#L713))
- `YapperAPI:GetDelineator() → string|nil` ([`#L739`](../Src/API.lua#L739))
- `YapperAPI:OpenBlizzardChat() → nil` ([`#L731`](../Src/API.lua#L731))
  Force the Yapper overlay to close and open the original Blizzard editbox. Equivalent to the user pressing the "Bypass Yapper" keybind (Shift-Enter).
- `YapperAPI:GetState() → string` ([`#L747`](../Src/API.lua#L747))
- `YapperAPI:IsState(state: string) → boolean` ([`#L756`](../Src/API.lua#L756))
- `YapperAPI:GetStates() → string[]` ([`#L766`](../Src/API.lua#L766))
- `YapperAPI:GetStateLogs() → table` ([`#L1243`](../Src/API.lua#L1243)) — returns the full circular buffer of state transitions (max 200 entries).
- `YapperAPI:GetStateLog(index: number) → table|nil` ([`#L1238`](../Src/API.lua#L1238)) — returns a specific transition entry from the history.
- `YapperAPI:GetStateLogCount() → number` ([`#L1233`](../Src/API.lua#L1233)) — returns the current number of transitions stored in the buffer.

### Spellcheck helpers

- `YapperAPI:IsSpellcheckEnabled() → boolean` ([`#L748`](../Src/API.lua#L748))
- `YapperAPI:CheckWord(word: string) → boolean` ([`#L757`](../Src/API.lua#L757))
- `YapperAPI:GetSuggestions(word: string) → string[]|nil` ([`#L767`](../Src/API.lua#L767))
- `YapperAPI:GetSpellcheckLocale() → string|nil` ([`#L788`](../Src/API.lua#L788))
- `YapperAPI:AddToDictionary(word: string) → boolean` ([`#L798`](../Src/API.lua#L798))
- `YapperAPI:IgnoreWord(word: string) → boolean` ([`#L811`](../Src/API.lua#L811))
- `YapperAPI:FindMisspellings(text: string) → table[]|nil` ([`#L916`](../Src/API.lua#L916))
- `YapperAPI:IsSuggestionOpen() → boolean` ([`#L913`](../Src/API.lua#L913))
- `YapperAPI:HideSuggestions() → boolean` ([`#L922`](../Src/API.lua#L922))
- `YapperAPI:ApplySuggestion(index: number) → boolean` ([`#L932`](../Src/API.lua#L932))

### Dictionary / language engine

- `YapperAPI:RegisterDictionary(locale: string, data: table) → boolean` ([`#L828`](../Src/API.lua#L828))
  Register a dictionary. If the dictionary belongs to a language family, that family must have a registered engine that satisfies the security validation (see `RegisterLanguageEngine`). Registration will fail if no secure engine is found for the associated family.
- `YapperAPI:RegisterLanguageEngine(familyId: string, engine: table) → boolean` ([`#L845`](../Src/API.lua#L845))
  Register a language engine. **Security Requirement**: The `engine` table MUST provide a `BlockedHashes` table and a `HashWord` function. Registration is blocked if these are missing.
- `YapperAPI:IsLanguageEngineRegistered(familyId: string) → boolean` ([`#L859`](../Src/API.lua#L859))
- `YapperAPI:RegisterLocaleAddon(locale: string, addonName: string) → boolean` ([`#L870`](../Src/API.lua#L870))

### Queue

- `YapperAPI:GetQueueState() → { active, stalled, chatType, policyClass, pending, inFlight }` ([`#L891`](../Src/API.lua#L891))
- `YapperAPI:CancelQueue() → number` ([`#L904`](../Src/API.lua#L904))
- `YapperAPI:ResolvePost(handle: number) → boolean` ([`#L1069`](../Src/API.lua#L1069))

### Theme

- `YapperAPI:RegisterTheme(name: string, data: table) → boolean` ([`#L920`](../Src/API.lua#L920))
- `YapperAPI:SetTheme(name: string) → boolean` ([`#L930`](../Src/API.lua#L930))
- `YapperAPI:GetRegisteredThemes() → string[]` ([`#L938`](../Src/API.lua#L938))
- `YapperAPI:GetTheme(name?: string) → table|nil` ([`#L946`](../Src/API.lua#L946))

### Utility wrappers

- `YapperAPI:IsChatLockdown() → boolean` ([`#L959`](../Src/API.lua#L959))
- `YapperAPI:IsSecret(value: any) → boolean` ([`#L972`](../Src/API.lua#L972))
- `YapperAPI:GetChatParent() → Frame` ([`#L982`](../Src/API.lua#L982))
- `YapperAPI:MakeFullscreenAware(frame: Frame) → nil` ([`#L992`](../Src/API.lua#L992))

### Icon gallery

- `YapperAPI:ShowIconGallery(editBox: EditBox, anchorFrame?: Frame, query?: string) → nil` ([`#L1091`](../Src/API.lua#L1091))
- `YapperAPI:HideIconGallery() → nil` ([`#L1099`](../Src/API.lua#L1099))
- `YapperAPI:IsIconGalleryShown() → boolean` ([`#L1105`](../Src/API.lua#L1105))
- `YapperAPI:GetRaidIconData() → table[]` ([`#L1112`](../Src/API.lua#L1112))

## Public API

- Methods:
  - [NEW] `YapperAPI:GetLanguageEngine() → nil`: Returns the language engine for `familyId`, or nil. ([`../Src/API.lua#L321`](../Src/API.lua#L321))
  - [NEW] `API:Fire(event) → nil`: Fire all callbacks for an event.  Arguments are passed through. ([`../Src/API.lua#L1311`](../Src/API.lua#L1311))
  - [NEW] `API:RunFilter(hookPoint, payload) → table|false`: Run all filters for a hook point. ([`../Src/API.lua#L1276`](../Src/API.lua#L1276))
