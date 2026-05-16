# Internals reference (`_G.Yapper` / `YapperTable`)

> ⚠️ Everything documented here is **internal**. Use `YapperAPI` (see `API.md`) when possible. Internals are documented because third-party addons sometimes need them, but they may change without notice. If you find yourself relying on an internal, please open an issue proposing an addition to the public API.

All sections below follow TOC load order from [`Yapper.toc`](../Yapper.toc).

## YapperTable root (`_G.Yapper`)

Published in [`../Yapper.lua#L64`](../Yapper.lua#L64).

- Description: global namespace alias for the addon-private table.
- Fields:
  - `YapperTable.YAPPER_DISABLED: boolean` set by override toggle ([`../Yapper.lua#L226`](../Yapper.lua#L226)).
- Methods:
  - `YapperTable:OverrideYapper(disable: boolean) → nil` ([`../Yapper.lua#L221`](../Yapper.lua#L221)) — toggles runtime ownership between Yapper overlay and Blizzard chat; cancels queue and unregisters events when disabling.

## Core

Initialised on `ADDON_LOADED` by [`Yapper.lua#L105-L110`](../Yapper.lua#L105-L110).

- Description: SavedVariables schema/default/migration authority.
- Fields:
  - `Yapper.Config: table` live config root ([`../Src/Core.lua#L277`](../Src/Core.lua#L277)).
- Methods:
  - [NEW] `Core:RegisterFrame(category, key, frame) → nil`: Register a frame in the central UI registry for external access. ([`../Src/Core.lua#L318`](../Src/Core.lua#L318))
  - `Core:DemoteGlobalToCharacter() → nil`: Unpack stashed local settings when switching away from Global Profile. ([`../Src/Core.lua#L740`](../Src/Core.lua#L740))
  - `Core:RefreshInheritance() → nil`: Initialise inheritance chain (Global vs Local). ([`../Src/Core.lua#L537`](../Src/Core.lua#L537))
  - `Core:GetCharacterLanguage(lang) → number langId`: Get the language or defaults if not present. ([`../Src/Core.lua#L297`](../Src/Core.lua#L297))
  - `Core:BuildLanguageCache() → nil`: No description provided. ([`../Src/Core.lua#L282`](../Src/Core.lua#L282))
  - `Core:InitSavedVars() → nil` ([`../Src/Core.lua#L433`](../Src/Core.lua#L433)) — creates/migrates `YapperDB`, `YapperLocalConf`, `YapperLocalHistory`; mutates metatables for inheritance.
  - `Core:GetVersion() → string` ([`../Src/Core.lua#L560`](../Src/Core.lua#L560))
  - `Core:GetDefaults() → table` ([`../Src/Core.lua#L564`](../Src/Core.lua#L564))
  - `Core:SetVerbose(bool: boolean) → nil` ([`../Src/Core.lua#L568`](../Src/Core.lua#L568))
  - `Core:SaveSetting(category, key, value) → nil` ([`../Src/Core.lua#L581`](../Src/Core.lua#L581)) — delegates to `Interface:SetLocalPath` for profile-aware write routing.
  - `Core:PromoteCharacterToGlobal() → nil` ([`../Src/Core.lua#L647`](../Src/Core.lua#L647)) — wipes local overrides (excluding `MainWindowPosition`) and re-seeds metatable inheritance from `YapperDB`.
  - `Core:PushToGlobal() → nil` ([`../Src/Core.lua#L761`](../Src/Core.lua#L761)) — deep-copies character settings into `YapperDB`. Whitelists `System` keys; excludes `MainWindowPosition`; migrates `_themeOverrides` and `_appliedTheme` markers; no-op when already global.
- Invariants:
  - Must run before feature init (`LoadSavedVariablesFirst: 1`).
  - Metatable chain must remain intact for local fallback/inheritance logic.

## Utils

Loaded at startup; used by most modules.

- Description: Print/debug/fullscreen/chat utility helpers.
- Fields:
  - `_G.YAPPER_UTILS: table` alias for debug access ([`../Src/Utils.lua#L94`](../Src/Utils.lua#L94)).
- Methods:
  - `Utils:Print(...) → nil` ([`../Src/Utils.lua#L19`](../Src/Utils.lua#L19))
  - `Utils:VerbosePrint(...) → nil` ([`../Src/Utils.lua#L33`](../Src/Utils.lua#L33))
  - `Utils:DebugPrint(...) → nil` ([`../Src/Utils.lua#L39`](../Src/Utils.lua#L39))
  - `Utils:GetChatParent() → Frame` ([`../Src/Utils.lua#L48`](../Src/Utils.lua#L48))
  - `Utils:MakeFullscreenAware(frame) → nil` ([`../Src/Utils.lua#L60`](../Src/Utils.lua#L60))
  - `Utils:IsChatLockdown() → boolean` ([`../Src/Utils.lua#L85`](../Src/Utils.lua#L85))
  - `Utils:IsSecret(value) → boolean` ([`../Src/Utils.lua#L98`](../Src/Utils.lua#L98))

## Error

Loaded early; used for warnings and fatal throws.

- Description: Central error code registry and formatting.
- Methods:
  - `Error:PrintError(code, ...) → nil` ([`../Src/Error.lua#L82`](../Src/Error.lua#L82))
  - `Error:Throw(code, ...) → nil` ([`../Src/Error.lua#L92`](../Src/Error.lua#L92)) — halts via `error()` after printing.

## Frame

Created by `Frames.lua`; consumed by event system.

- Description: Marker table for frame container module.
- Fields:
  - `Frame.defined: boolean` ([`../Src/Frames.lua#L8-L10`](../Src/Frames.lua#L8-L10)).

## EventFrames

Initialised from boot entrypoint (`Yapper.lua`).

- Description: Creates and stores event-listening frames.
- Fields:
  - `EventFrames.Container: table` map of frame names to frame objects ([`../Src/Frames.lua#L19`](../Src/Frames.lua#L19)).
- Methods:
  - `EventFrames:Init() → nil` ([`../Src/Frames.lua#L22`](../Src/Frames.lua#L22))
  - `EventFrames:HideParent() → nil` ([`../Src/Frames.lua#L37`](../Src/Frames.lua#L37))

## Events

Starts being used immediately in `Yapper.lua` to register lifecycle handlers.

- Description: Lightweight event bus over Blizzard frame events.
- Methods:
  - `Events:Register(frameName, event, fn, handlerId?) → nil` ([`../Src/Events.lua#L21`](../Src/Events.lua#L21))
  - `Events:Unregister(frameName, event) → nil` ([`../Src/Events.lua#L46`](../Src/Events.lua#L46))
  - `Events:UnregisterAll() → nil` ([`../Src/Events.lua#L55`](../Src/Events.lua#L55))
  - `Events:Dispatch(event, ...) → nil` ([`../Src/Events.lua#L72`](../Src/Events.lua#L72))
- Invariants:
  - `frameName` must exist in `EventFrames.Container`.

## API (internal helper table)

Loaded before all integration hooks.

- Description: Internal dispatch table behind public `_G.YapperAPI`.
- Fields:
  - `Yapper.API: table` internal object ([`../Src/API.lua#L379-L380`](../Src/API.lua#L379-L380)).
  - `_lastCancelOwner: string|nil` *private by convention; do not rely on* ([`../Src/API.lua#L1125`](../Src/API.lua#L1125)).
- Methods:
  - `API:_createClaim(text, chatType, language, target, owner) → number` ([`../Src/API.lua#L948`](../Src/API.lua#L948))
  - `API:RunFilter(hookPoint, payload) → table|false` ([`../Src/API.lua#L1111`](../Src/API.lua#L1111))
  - `API:Fire(event, ...) → nil` ([`../Src/API.lua#L1146`](../Src/API.lua#L1146))
  - `API:GetStateLogCount() → number` ([`../Src/API.lua#L449`](../Src/API.lua#L449)) — returns the number of entries in the FSM state history.
  - `API:GetStateLog(index) → table|nil` ([`../Src/API.lua#L440`](../Src/API.lua#L440)) — returns a specific state transition log entry.
  - `API:GetStateLogs() → table` ([`../Src/API.lua#L430`](../Src/API.lua#L430)) — returns the full circular buffer of state transitions.
- Side effects:
  - Catches external addon errors and emits/targets `API_ERROR`.

## State

Loaded early; central orchestrator for the addon's operational mode.

- Description: Finite state machine managing transitions between idle, editing, and sending states.
- Fields:
  - `STATES: table` enum of valid states (`IDLE`, `EDITING`, `MULTILINE`, `SENDING`, `STALLED`, `LOCKDOWN`).
  - `_current: string` current active state.
- Flags:
  - `SuppressNextEnter`: Session flag used to block the next native `OnEnterPressed` event (e.g. after selecting an emote with auto-send disabled).
- Methods:
  [MISSING] - [NEW] `State:Resume() → nil`: Return from CONFIG or other transient states. ([`../Src/State.lua#L312`](../Src/State.lua#L312))
  - [NEW] `State:ToConfig() → nil`: Transition to CONFIG (settings) state. ([`../Src/State.lua#L288`](../Src/State.lua#L288))
  - [NEW] `State:IsConfig() → boolean`: Is the settings/interface window open? ([`../Src/State.lua#L230`](../Src/State.lua#L230))
  - [NEW] `State:IsInitialised() → boolean`: Has the machine completed initialisation (i.e. not in INITIALISING state)? ([`../Src/State.lua#L188`](../Src/State.lua#L188))
  - [NEW] `State:SetFlag(name, value, persistent) → nil`: Set a state flag value. ([`../Src/State.lua#L75`](../Src/State.lua#L75))
  - [NEW] `State:GetFlag(name, default) → any`: Get a state flag value. ([`../Src/State.lua#L54`](../Src/State.lua#L54))
  - `State:IsInitialising() → boolean`: Is the machine in INITIALISING state? ([`../Src/State.lua#L182`](../Src/State.lua#L182))
  - `State:ToLockdown() → nil`: Transition to LOCKDOWN state. ([`../Src/State.lua#L283`](../Src/State.lua#L283))
  - `State:ToStalled() → nil`: Transition to STALLED state. ([`../Src/State.lua#L278`](../Src/State.lua#L278))
  - `State:ToSending() → nil`: Transition to SENDING state. ([`../Src/State.lua#L273`](../Src/State.lua#L273))
  - `State:ToMultiline() → nil`: Transition to MULTILINE state. ([`../Src/State.lua#L268`](../Src/State.lua#L268))
  - `State:ToEditing() → nil`: Transition to EDITING state. ([`../Src/State.lua#L263`](../Src/State.lua#L263))
  - `State:ToIdle() → nil`: Transition to IDLE state. ([`../Src/State.lua#L258`](../Src/State.lua#L258))
  - `State:IsInputActive() → boolean`: Helper: is the user currently typing (either overlay or multiline)? ([`../Src/State.lua#L236`](../Src/State.lua#L236))
  - `State:IsLockdown() → boolean`: Is the addon suppressed by combat or manual lockdown? ([`../Src/State.lua#L224`](../Src/State.lua#L224))
  - `State:IsStalled() → boolean`: Is the queue stalled awaiting hardware input? ([`../Src/State.lua#L218`](../Src/State.lua#L218))
  - `State:IsSending() → boolean`: Is a message currently being delivered? ([`../Src/State.lua#L212`](../Src/State.lua#L212))
  - `State:IsMultiline() → boolean`: Is the user typing in the expanded multiline editor? ([`../Src/State.lua#L206`](../Src/State.lua#L206))
  - `State:IsEditing() → boolean`: Is the user typing in the single-line overlay? ([`../Src/State.lua#L200`](../Src/State.lua#L200))
  - `State:IsIdle() → boolean`: Is the machine in IDLE state? ([`../Src/State.lua#L194`](../Src/State.lua#L194))
  - `State:IsInitialising() → boolean`: Is the machine in INITIALISING state? ([`../Src/State.lua#L182`](../Src/State.lua#L182))
  - `State:GetLogCount() → number` ([`../Src/State.lua#L349`](../Src/State.lua#L349)) — returns the number of transitions stored in the history buffer.
  - `State:GetLog(index) → table|nil` ([`../Src/State.lua#L356`](../Src/State.lua#L356)) — returns the transition log at the given index.
  - `State:GetLogs() → table` ([`../Src/State.lua#L362`](../Src/State.lua#L362)) — returns the raw circular buffer table.
  - `State:Get() → string`: Returns the current state.
  - `State:Is(state: string) → boolean`: Returns true if the current state matches.
  - `State:Transition(newState: string, ...) → nil`: Transitions to a new state and fires `STATE_CHANGED`.
  - `State:Reset() → nil`: Resets to `IDLE`.
- Callbacks fired:
  - `STATE_CHANGED(newState, oldState, ...)`.

## Spellcheck

Initialised on `ADDON_LOADED` (`Spellcheck:Init`) and rebound to overlay lifecycle.

- Description: Spellchecking runtime hub and shared state.
- Fields:
  - `Dictionaries: table` locale → dictionary state ([`../Src/Spellcheck.lua#L37`](../Src/Spellcheck.lua#L37)).
  - `LanguageEngines: table` family → engine ([`../Src/Spellcheck.lua#L38`](../Src/Spellcheck.lua#L38)).
  - `KnownLocales: string[]` ([`../Src/Spellcheck.lua#L39-L44`](../Src/Spellcheck.lua#L39-L44)).
  - `LocaleAddons: table` locale → addon name ([`../Src/Spellcheck.lua#L49-L55`](../Src/Spellcheck.lua#L49-L55)).
  - Frame references: `EditBox`, `Overlay`, `MeasureFS`, `SuggestionFrame`, `HintFrame` ([`../Src/Spellcheck.lua#L56-L58`](../Src/Spellcheck.lua#L56-L58), [`../Src/Spellcheck.lua#L61-L67`](../Src/Spellcheck.lua#L61-L67)).
  - Underline/suggestion state: `UnderlinePool`, `Underlines`, `SuggestionRows`, `ActiveSuggestions`, `ActiveIndex`, `ActiveWord`, `ActiveRange`, `_debounceTimer` ([`../Src/Spellcheck.lua#L59-L60`](../Src/Spellcheck.lua#L59-L60), [`../Src/Spellcheck.lua#L62-L66`](../Src/Spellcheck.lua#L62-L66), [`../Src/Spellcheck.lua#L68`](../Src/Spellcheck.lua#L68)).
  - Dictionary/user state: `UserDictCache` ([`../Src/Spellcheck.lua#L73`](`../Src/Spellcheck.lua#L73`))
  - Dictionary/user state: `_pendingLocaleLoads` ([`../Src/Spellcheck.lua#L74`](`../Src/Spellcheck.lua#L74`))
  - Dictionary/user state: `DictionaryBuilders` ([`../Src/Spellcheck.lua#L75`](`../Src/Spellcheck.lua#L75`))
  - Edit-distance buffers: `_ed_prev`, `_ed_cur`, `_ed_prev_prev` *private by convention; do not rely on* ([`../Src/Spellcheck.lua#L73-L75`](../Src/Spellcheck.lua#L73-L75)).
  - Tunable constants/helpers: `_SCORE_WEIGHTS`, `_MAX_SUGGESTION_ROWS`, `_RAID_ICONS`, `_KB_LAYOUTS`, `_DICT_CHUNK_SIZE` *private by convention; do not rely on* ([`../Src/Spellcheck.lua#L665-L675`](../Src/Spellcheck.lua#L665-L675)).
- Methods:
  - [NEW] `Spellcheck:IsWordBlocked(word, locale, ignoreManual) → boolean`: Convenience function for checking a single word (e.g., during YALLM learning). ([`../Src/Spellcheck.lua#L551`](../Src/Spellcheck.lua#L551))
  - [NEW] `Spellcheck:GetBlockData(locale) → table|nil addedSet`: Returns the data needed to check if a word is blocked at runtime. ([`../Src/Spellcheck.lua#L532`](../Src/Spellcheck.lua#L532))
  - `Spellcheck:EvictRandomMeta() → nil`: No description provided. ([`../Src/Spellcheck.lua#L436`](../Src/Spellcheck.lua#L436))
  - `Spellcheck:Init(threads) → nil` ([`../Src/Spellcheck.lua#L191`](../Src/Spellcheck.lua#L191))
  - `Spellcheck:_RegisterLanguageEngine(familyId, engine) → boolean` ([`../Src/Spellcheck.lua#L216`](../Src/Spellcheck.lua#L216)) — **Security Note**: Enforces mandatory `BlockedHashes` table and `HashWord` function. Returns `false` and prints a chat error if missing.
  - `Spellcheck:GetActiveEngine() → table|nil` ([`../Src/Spellcheck.lua#L241`](../Src/Spellcheck.lua#L241))
  - `Spellcheck:GetEngine(familyId) → table|nil` ([`../Src/Spellcheck.lua#L250`](../Src/Spellcheck.lua#L250))
  - `Spellcheck:GetConfig() → table` ([`../Src/Spellcheck.lua#L337`](../Src/Spellcheck.lua#L337))
  - `Spellcheck:IsEnabled() → boolean` ([`../Src/Spellcheck.lua#L341`](../Src/Spellcheck.lua#L341))
  - `Spellcheck:GetLocale() → string` ([`../Src/Spellcheck.lua#L346`](../Src/Spellcheck.lua#L346))
  - `Spellcheck:GetFallbackLocale() → string` ([`../Src/Spellcheck.lua#L374`](../Src/Spellcheck.lua#L374))
  - `Spellcheck:GetDictionary() → table|nil` ([`../Src/Spellcheck.lua#L382`](../Src/Spellcheck.lua#L382))
  - `Spellcheck:GetMeta(dict, word) → table|nil` ([`../Src/Spellcheck.lua#L392`](../Src/Spellcheck.lua#L392))

  - `Spellcheck:GetUserDictStore() → table` ([`../Src/Spellcheck.lua#L456`](../Src/Spellcheck.lua#L456))
  - `Spellcheck:GetUserDict(locale) → table` ([`../Src/Spellcheck.lua#L480`](../Src/Spellcheck.lua#L480))
  - `Spellcheck:TouchUserDict(dict) → nil` ([`../Src/Spellcheck.lua#L492`](../Src/Spellcheck.lua#L492))
  - `Spellcheck:BuildWordSet(list) → table` ([`../Src/Spellcheck.lua#L499`](../Src/Spellcheck.lua#L499))
  - `Spellcheck:GetUserSets(locale) → table, table` ([`../Src/Spellcheck.lua#L513`](../Src/Spellcheck.lua#L513))
  - `Spellcheck:AddUserWord(locale, word) → nil` ([`../Src/Spellcheck.lua#L571`](../Src/Spellcheck.lua#L571))
  - `Spellcheck:IgnoreWord(locale, word) → nil` ([`../Src/Spellcheck.lua#L594`](../Src/Spellcheck.lua#L594))
  - `Spellcheck:ClearSuggestionCache() → nil` ([`../Src/Spellcheck.lua#L618`](../Src/Spellcheck.lua#L618))
  - Accessors: `GetMaxSuggestions` ([`../Src/Spellcheck.lua#L623`](`../Src/Spellcheck.lua#L623`))
  - Accessors: `GetMaxCandidates` ([`../Src/Spellcheck.lua#L628`](`../Src/Spellcheck.lua#L628`))
  - Accessors: `GetSuggestionCacheSize` ([`../Src/Spellcheck.lua#L633`](`../Src/Spellcheck.lua#L633`))
  - Accessors: `GetReshuffleAttempts` ([`../Src/Spellcheck.lua#L638`](`../Src/Spellcheck.lua#L638`))
  - Accessors: `GetMaxWrongLetters` ([`../Src/Spellcheck.lua#L643`](`../Src/Spellcheck.lua#L643`))
  - Accessors: `GetMinWordLength` ([`../Src/Spellcheck.lua#L648`](`../Src/Spellcheck.lua#L648`))
  - Accessors: `GetUnderlineStyle` ([`../Src/Spellcheck.lua#L653`](`../Src/Spellcheck.lua#L653`))
  - Accessors: `GetKeyboardLayout` ([`../Src/Spellcheck.lua#L661`](`../Src/Spellcheck.lua#L661`))
  - Accessors: `GetKBDistTable` ([`../Src/Spellcheck.lua#L671`](`../Src/Spellcheck.lua#L671`))
  - Accessors: `_GetKBDistFromLayouts` ([`../Src/Spellcheck.lua#L690`](`../Src/Spellcheck.lua#L690`))
- Callbacks fired:
  - `SPELLCHECK_WORD_ADDED`, `SPELLCHECK_WORD_IGNORED`.

## Spellcheck.Dictionary

Used lazily by `GetDictionary`, locale switches, and LOD registration.

- Description: Dictionary registration/loading, locale availability, async indexing.
- Methods:
  - `Spellcheck:LoadDictionary(locale) → nil` ([`../Src/Spellcheck/Dictionary.lua#L34`](../Src/Spellcheck/Dictionary.lua#L34))
  - `Spellcheck:RegisterDictionary(locale, data) → nil` ([`../Src/Spellcheck/Dictionary.lua#L61`](../Src/Spellcheck/Dictionary.lua#L61)) — **Security Note**: Validates the associated language family engine for `BlockedHashes` before indexing. Blocks registration if the family engine is missing or insecure.
  - `Spellcheck:_OnDictRegistrationComplete(locale) → nil` ([`../Src/Spellcheck/Dictionary.lua#L364`](../Src/Spellcheck/Dictionary.lua#L364))
  - `Spellcheck:GetAvailableLocales() → string[]` ([`../Src/Spellcheck/Dictionary.lua#L409`](../Src/Spellcheck/Dictionary.lua#L409))
  - `Spellcheck:GetLocaleAddon(locale) → string|nil` ([`../Src/Spellcheck/Dictionary.lua#L418`](../Src/Spellcheck/Dictionary.lua#L418))
  - `Spellcheck:HasLocaleAddon(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L423`](../Src/Spellcheck/Dictionary.lua#L423))
  - `Spellcheck:HasAnyDictionary() → boolean` ([`../Src/Spellcheck/Dictionary.lua#L454`](../Src/Spellcheck/Dictionary.lua#L454))
  - `Spellcheck:IsLocaleAvailable(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L466`](../Src/Spellcheck/Dictionary.lua#L466))
  - `Spellcheck:CanLoadLocale(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L480`](../Src/Spellcheck/Dictionary.lua#L480))
  - `Spellcheck:Notify(msg) → nil` ([`../Src/Spellcheck/Dictionary.lua#L495`](../Src/Spellcheck/Dictionary.lua#L495))
  - `Spellcheck:EnsureLocale(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L501`](../Src/Spellcheck/Dictionary.lua#L501))
  - `Spellcheck:ScheduleLocaleRefresh(locale) → nil` ([`../Src/Spellcheck/Dictionary.lua#L557`](../Src/Spellcheck/Dictionary.lua#L557))
  - `dict:Contains(word: string) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L186`](../Src/Spellcheck/Dictionary.lua#L186)) — returns true if the word (normalised) exists in the dictionary, its base, or the user's personal dictionary.
- Side effects:
  - Schedules `C_Timer.After(0, ...)` chunk processing and refresh tickers.

## Spellcheck.Engine

Runs during suggestion/underline rebuild.

- Description: Tokenisation, misspelling detection, candidate scoring.
- Methods:
  - [NEW] `Spellcheck:CollectAffixMatches() → nil`: Scans text for words recognized via affix-stripping. ([`../Src/Spellcheck/Engine.lua#L158`](../Src/Spellcheck/Engine.lua#L158))
  - `CollectMisspellings` ([`../Src/Spellcheck/Engine.lua#L94`](`../Src/Spellcheck/Engine.lua#L94`))
  - `ShouldCheckWord` ([`../Src/Spellcheck/Engine.lua#L192`](`../Src/Spellcheck/Engine.lua#L192`))
  - `GetIgnoredRanges` ([`../Src/Spellcheck/Engine.lua#L199`](`../Src/Spellcheck/Engine.lua#L199`))
  - `IsRangeIgnored` ([`../Src/Spellcheck/Engine.lua#L242`](`../Src/Spellcheck/Engine.lua#L242`))
  - `IsWordCorrect` ([`../Src/Spellcheck/Engine.lua#L251`](`../Src/Spellcheck/Engine.lua#L251`))
  - `ResolveImplicitTrace` ([`../Src/Spellcheck/Engine.lua#L288`](`../Src/Spellcheck/Engine.lua#L288`))
  - `UpdateActiveWord` ([`../Src/Spellcheck/Engine.lua#L333`](`../Src/Spellcheck/Engine.lua#L333`))
  - `GetWordAtCursor` ([`../Src/Spellcheck/Engine.lua#L414`](`../Src/Spellcheck/Engine.lua#L414`))
  - `GetSuggestions` ([`../Src/Spellcheck/Engine.lua#L968`](`../Src/Spellcheck/Engine.lua#L968`))
  - `EditDistance` ([`../Src/Spellcheck/Engine.lua#L1263`](`../Src/Spellcheck/Engine.lua#L1263`))
  - `FormatSuggestionLabel` ([`../Src/Spellcheck/Engine.lua#L1335`](`../Src/Spellcheck/Engine.lua#L1335`))
- Filters run:
  - `PRE_SPELLCHECK` via `API:RunFilter`.

## Spellcheck.UI

Bound when overlay exists; reacts to text/cursor updates.

- Description: UI state machine for underlines, hint, and suggestions.
- Methods:
  - [NEW] `Spellcheck:SetSpellcheckOffset(hintX, hintY, suggestX, suggestY) → nil`: Set manual pixel offsets for spellcheck tooltips. ([`../Src/Spellcheck/UI.lua#L619`](../Src/Spellcheck/UI.lua#L619))
  - `Bind` ([`../Src/Spellcheck/UI.lua#L29`](`../Src/Spellcheck/UI.lua#L29`))
  - `BindMultiline` ([`../Src/Spellcheck/UI.lua#L64`](`../Src/Spellcheck/UI.lua#L64`))
  - `UnbindMultiline` ([`../Src/Spellcheck/UI.lua#L125`](`../Src/Spellcheck/UI.lua#L125`))
  - `PurgeOtherDictionaries` ([`../Src/Spellcheck/UI.lua#L163`](`../Src/Spellcheck/UI.lua#L163`))
  - `UnloadAllDictionaries` ([`../Src/Spellcheck/UI.lua#L217`](`../Src/Spellcheck/UI.lua#L217`))
  - `ApplyState` ([`../Src/Spellcheck/UI.lua#L259`](`../Src/Spellcheck/UI.lua#L259`))
  - `OnConfigChanged` ([`../Src/Spellcheck/UI.lua#L289`](`../Src/Spellcheck/UI.lua#L289`))
  - `OnTextChanged` ([`../Src/Spellcheck/UI.lua#L293`](`../Src/Spellcheck/UI.lua#L293`))
  - `OnCursorChanged` ([`../Src/Spellcheck/UI.lua#L313`](`../Src/Spellcheck/UI.lua#L313`))
  - `OnOverlayHide` ([`../Src/Spellcheck/UI.lua#L357`](`../Src/Spellcheck/UI.lua#L357`))
  - `ScheduleRefresh` ([`../Src/Spellcheck/UI.lua#L363`](`../Src/Spellcheck/UI.lua#L363`))
  - `Rebuild` ([`../Src/Spellcheck/UI.lua#L386`](`../Src/Spellcheck/UI.lua#L386`))
  - `EnsureMeasureFontString` ([`../Src/Spellcheck/UI.lua#L400`](`../Src/Spellcheck/UI.lua#L400`))
  - `EnsureSuggestionFrame` ([`../Src/Spellcheck/UI.lua#L415`](`../Src/Spellcheck/UI.lua#L415`))
  - `SuggestionsEqual` ([`../Src/Spellcheck/UI.lua#L508`](`../Src/Spellcheck/UI.lua#L508`))
  - `EnsureHintFrame` ([`../Src/Spellcheck/UI.lua#L518`](`../Src/Spellcheck/UI.lua#L518`))
  - `CancelHintTimer` ([`../Src/Spellcheck/UI.lua#L544`](`../Src/Spellcheck/UI.lua#L544`))
  - `ScheduleHintShow` ([`../Src/Spellcheck/UI.lua#L556`](`../Src/Spellcheck/UI.lua#L556`))
  - `ShowHint` ([`../Src/Spellcheck/UI.lua#L634`](`../Src/Spellcheck/UI.lua#L634`))
  - `HideHint` ([`../Src/Spellcheck/UI.lua#L655`](`../Src/Spellcheck/UI.lua#L655`))
  - `UpdateHint` ([`../Src/Spellcheck/UI.lua#L660`](`../Src/Spellcheck/UI.lua#L660`))
  - `IsSuggestionOpen` ([`../Src/Spellcheck/UI.lua#L683`](`../Src/Spellcheck/UI.lua#L683`))
  - `IsSuggestionEligible` ([`../Src/Spellcheck/UI.lua#L687`](`../Src/Spellcheck/UI.lua#L687`))
  - `HandleKeyDown` ([`../Src/Spellcheck/UI.lua#L694`](`../Src/Spellcheck/UI.lua#L694`))
  - `MoveSelection` ([`../Src/Spellcheck/UI.lua#L755`](`../Src/Spellcheck/UI.lua#L755`))
  - `RefreshSuggestionSelection` ([`../Src/Spellcheck/UI.lua#L777`](`../Src/Spellcheck/UI.lua#L777`))
  - `OpenOrCycleSuggestions` ([`../Src/Spellcheck/UI.lua#L809`](`../Src/Spellcheck/UI.lua#L809`))
  - `ShowSuggestions` ([`../Src/Spellcheck/UI.lua#L838`](`../Src/Spellcheck/UI.lua#L838`))
  - `NextSuggestionsPage` ([`../Src/Spellcheck/UI.lua#L959`](`../Src/Spellcheck/UI.lua#L959`))
  - `HideSuggestions` ([`../Src/Spellcheck/UI.lua#L986`](`../Src/Spellcheck/UI.lua#L986`))
  - `ApplySuggestion` ([`../Src/Spellcheck/UI.lua#L1010`](`../Src/Spellcheck/UI.lua#L1010`))
- Fields:
  - `HintDelay: number` ([`../Src/Spellcheck/UI.lua#L554`](../Src/Spellcheck/UI.lua#L554)).
- Callbacks fired:
  - `SPELLCHECK_SUGGESTION`, `SPELLCHECK_APPLIED`.

## Spellcheck.Underline

Used by `Rebuild` and cursor movement.

- Description: Underline geometry and draw-pool management.
- Methods:
  - `GetCaretXOffset` ([`../Src/Spellcheck/Underline.lua#L23`](`../Src/Spellcheck/Underline.lua#L23`))
  - `ApplyOverlayFont` ([`../Src/Spellcheck/Underline.lua#L49`](`../Src/Spellcheck/Underline.lua#L49`))
  - `MeasureText` ([`../Src/Spellcheck/Underline.lua#L63`](`../Src/Spellcheck/Underline.lua#L63`))
  - `GetScrollOffset` ([`../Src/Spellcheck/Underline.lua#L89`](`../Src/Spellcheck/Underline.lua#L89`))
  - `UpdateUnderlines` ([`../Src/Spellcheck/Underline.lua#L123`](`../Src/Spellcheck/Underline.lua#L123`))
  - `RedrawUnderlines` ([`../Src/Spellcheck/Underline.lua#L231`](`../Src/Spellcheck/Underline.lua#L231`))
  - `DrawUnderline` ([`../Src/Spellcheck/Underline.lua#L249`](`../Src/Spellcheck/Underline.lua#L249`))
  - `EnsureUnderlineLayer` ([`../Src/Spellcheck/Underline.lua#L331`](`../Src/Spellcheck/Underline.lua#L331`))
  - `AcquireUnderline` ([`../Src/Spellcheck/Underline.lua#L338`](`../Src/Spellcheck/Underline.lua#L338`))
  - `ClearUnderlines` ([`../Src/Spellcheck/Underline.lua#L345`](`../Src/Spellcheck/Underline.lua#L345`))
  - `EnsureMLMeasureFS` ([`../Src/Spellcheck/Underline.lua#L361`](`../Src/Spellcheck/Underline.lua#L361`))
  - `SyncMLMeasureFont` ([`../Src/Spellcheck/Underline.lua#L376`](`../Src/Spellcheck/Underline.lua#L376`))
  - `MeasureMLWord` ([`../Src/Spellcheck/Underline.lua#L405`](`../Src/Spellcheck/Underline.lua#L405`))
  - `GetVerticalScroll` ([`../Src/Spellcheck/Underline.lua#L480`](`../Src/Spellcheck/Underline.lua#L480`))
  - `RedrawUnderlines_ML` ([`../Src/Spellcheck/Underline.lua#L490`](`../Src/Spellcheck/Underline.lua#L490`))
  - `DrawUnderline_ML` ([`../Src/Spellcheck/Underline.lua#L509`](`../Src/Spellcheck/Underline.lua#L509`))
- Invariants:
  - Valid only while bound to active overlay/multiline editbox.

## Spellcheck.YALLM

Initialised from `Spellcheck:Init` when present.

- Description: Adaptive learning model for frequency/bias and auto-promote.
- Fields:
  - `Spellcheck.YALLM: table` ([`../Src/Spellcheck/YALLM.lua#L8`](../Src/Spellcheck/YALLM.lua#L8)).
- Locale store shape (`_G.YapperDB.SpellcheckLearned[locale]`):
  - `freq[word] = { c, t }`
  - `bias["typo:correction"] = { c, t, u }`
  - `phBias["phoneticHash:correction"] = { c, t }`
  - `negBias["typo:word"] = { c, t, u }`
  - `auto[word] = { c, t }`
  - `total: number`
  ([`../Src/Spellcheck/YALLM.lua#L63-L100`](../Src/Spellcheck/YALLM.lua#L63-L100)).
- Methods:
  - [NEW] `YALLM:GetNegBiasCap() → nil`: No description provided. ([`../Src/Spellcheck/YALLM.lua#L156`](../Src/Spellcheck/YALLM.lua#L156))
  - `YALLM:Export() → nil`: Export current learned data for a locale as a text block. ([`../Src/Spellcheck/YALLM.lua#L822`](../Src/Spellcheck/YALLM.lua#L822))
  - `YALLM:GetBiasTargets() → nil`: Returns a list of candidate words that have been learned as corrections for the given typo. ([`../Src/Spellcheck/YALLM.lua#L648`](../Src/Spellcheck/YALLM.lua#L648))
  - `YALLM:EnsureFreqSorted() → nil`: No description provided. ([`../Src/Spellcheck/YALLM.lua#L231`](../Src/Spellcheck/YALLM.lua#L231))
  - `IsEnabled() → boolean`: Returns true if YALLM is enabled in the configuration. ([`../Src/Spellcheck/YALLM.lua#L133`](../Src/Spellcheck/YALLM.lua#L133))
  - `GetFreqCap` ([`../Src/Spellcheck/YALLM.lua#L138`](`../Src/Spellcheck/YALLM.lua#L138`))
  - `GetBiasCap` ([`../Src/Spellcheck/YALLM.lua#L144`](`../Src/Spellcheck/YALLM.lua#L144`))
  - `GetAutoThreshold` ([`../Src/Spellcheck/YALLM.lua#L150`](`../Src/Spellcheck/YALLM.lua#L150`))
  - `Init` ([`../Src/Spellcheck/YALLM.lua#L166`](`../Src/Spellcheck/YALLM.lua#L166`))
  - `GetLocaleDB` ([`../Src/Spellcheck/YALLM.lua#L192`](`../Src/Spellcheck/YALLM.lua#L192`))
  - `IsSaneWord` ([`../Src/Spellcheck/YALLM.lua#L251`](`../Src/Spellcheck/YALLM.lua#L251`))
  - `RecordUsage` ([`../Src/Spellcheck/YALLM.lua#L293`](`../Src/Spellcheck/YALLM.lua#L293`))
  - `RecordSelection` ([`../Src/Spellcheck/YALLM.lua#L340`](`../Src/Spellcheck/YALLM.lua#L340`))
  - `RecordImplicitCorrection` ([`../Src/Spellcheck/YALLM.lua#L422`](`../Src/Spellcheck/YALLM.lua#L422`))
  - `RecordRejection` ([`../Src/Spellcheck/YALLM.lua#L518`](`../Src/Spellcheck/YALLM.lua#L518`))
  - `RecordIgnored` ([`../Src/Spellcheck/YALLM.lua#L552`](`../Src/Spellcheck/YALLM.lua#L552`))
  - `GetBonus` ([`../Src/Spellcheck/YALLM.lua#L595`](`../Src/Spellcheck/YALLM.lua#L595`))
  - `Prune` ([`../Src/Spellcheck/YALLM.lua#L694`](`../Src/Spellcheck/YALLM.lua#L694`))
  - `Reset` ([`../Src/Spellcheck/YALLM.lua#L753`](`../Src/Spellcheck/YALLM.lua#L753`))
  - `GetDataSummary` ([`../Src/Spellcheck/YALLM.lua#L766`](`../Src/Spellcheck/YALLM.lua#L766`))
  - `ClearSpecificUsage` ([`../Src/Spellcheck/YALLM.lua#L855`](`../Src/Spellcheck/YALLM.lua#L855`))
- Score model:
  - `GetBonus` applies `freqBonus`, `biasBonus`, `phBonus`, and `negBias` penalty (weighted, capped by repeat count) and returns an additive score adjustment used in candidate ranking ([`../Src/Spellcheck/YALLM.lua#L381-L419`](../Src/Spellcheck/YALLM.lua#L381-L419), [`../Src/Spellcheck/Engine.lua#L695-L696`](../Src/Spellcheck/Engine.lua#L695-L696)).
- Learning entry points:
  - `Chat:DirectSend` records usage and ignored-word counts ([`../Src/Chat.lua#L199-L215`](../Src/Chat.lua#L199-L215)).
  - `Spellcheck.UI` records explicit suggestion picks/rejections ([`../Src/Spellcheck/UI.lua#L869-L962`](../Src/Spellcheck/UI.lua#L869-L962)).
  - `Spellcheck.Engine` records implicit corrections from retyped trace words ([`../Src/Spellcheck/Engine.lua#L236-L238`](../Src/Spellcheck/Engine.lua#L236-L238)).
- Invariants / safeguards:
  - `IsSaneWord` gates noisy tokens before learning; pruning preserves highest relevance entries by count/utility/recency score; caps/thresholds are clamped from config (`YALLMEnabled`, `YALLMFreqCap`, `YALLMBiasCap`, `YALLMAutoThreshold`) ([`../Src/Spellcheck/YALLM.lua#L38-L54`](../Src/Spellcheck/YALLM.lua#L38-L54), [`../Src/Spellcheck/YALLM.lua#L113-L147`](../Src/Spellcheck/YALLM.lua#L113-L147), [`../Src/Spellcheck/YALLM.lua#L427-L468`](../Src/Spellcheck/YALLM.lua#L427-L468), [`../Src/Core.lua#L209-L212`](../Src/Core.lua#L209-L212)).
- Callbacks fired:
  - `YALLM_WORD_LEARNED`.

## IconGallery

Lazy-created; used by spellcheck/autocomplete edit flows and public API.

- Description: Raid icon picker popup and selection callbacks.
- Methods:
  - `Init` ([`../Src/IconGallery.lua#L19`](../Src/IconGallery.lua#L19))
  - `Show` ([`../Src/IconGallery.lua#L78`](../Src/IconGallery.lua#L78))
  - `Hide` ([`../Src/IconGallery.lua#L99`](../Src/IconGallery.lua#L99))
  - `Filter` ([`../Src/IconGallery.lua#L111`](../Src/IconGallery.lua#L111))
  - `Select` ([`../Src/IconGallery.lua#L137`](../Src/IconGallery.lua#L137))
  - `HandleKeyDown` ([`../Src/IconGallery.lua#L163`](../Src/IconGallery.lua#L163))
  - `_GetIconMeta` ([`../Src/IconGallery.lua#L206`](../Src/IconGallery.lua#L206))
  - `OnTextChanged` ([`../Src/IconGallery.lua#L217`](../Src/IconGallery.lua#L217))
- Callbacks fired:
  - `ICON_GALLERY_SHOW`, `ICON_GALLERY_HIDE`, `ICON_GALLERY_SELECT`.

## EditBox
- Methods:
  [MISSING] - [NEW] `EditBox:HardRefocus() → nil`: If the user has triggered a panic condition, ([`../Src/EditBoxCompat.lua#L125`](../Src/EditBoxCompat.lua#L125))
  - [NEW] `YapperTable:InstallCompatMethods() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L32`](../Src/EditBoxCompat.lua#L32))
  - [NEW] `box:UpdateNewcomerEditBoxHint() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L66`](../Src/EditBoxCompat.lua#L66))
  - [NEW] `box:SetFocusRegionsShown() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L65`](../Src/EditBoxCompat.lua#L65))
  [MISSING] - [NEW] `Multiline:Create() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L73`](../Src/EditBoxCompat.lua#L73))
  - [NEW] `box:UpdateHeader() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L64`](../Src/EditBoxCompat.lua#L64))
  - `box:GetAttribute() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L46`](../Src/EditBoxCompat.lua#L46))
  - `box:GetLanguage() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L44`](../Src/EditBoxCompat.lua#L44))
  - `box:GetTellTarget() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L42`](../Src/EditBoxCompat.lua#L42))
  - `box:GetChannelTarget() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L40`](../Src/EditBoxCompat.lua#L40))
  - `box:GetChatType() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L38`](../Src/EditBoxCompat.lua#L38))

Overlay root; hooked on `PLAYER_ENTERING_WORLD` via `HookAllChatFrames`.

- Description: Core overlay state and high-level editbox operations.
- Fields:
  - Runtime frames/state: `Overlay` ([`../Src/EditBox.lua#L24`](`../Src/EditBox.lua#L24`))
  - Runtime frames/state: `OverlayEdit` ([`../Src/EditBox.lua#L25`](`../Src/EditBox.lua#L25`))
  - Runtime frames/state: `ChannelLabel` ([`../Src/EditBox.lua#L26`](`../Src/EditBox.lua#L26`))
  - Runtime frames/state: `LabelBg` ([`../Src/EditBox.lua#L27`](`../Src/EditBox.lua#L27`))
  - Runtime frames/state: `OrigEditBox` ([`../Src/EditBox.lua#L31`](`../Src/EditBox.lua#L31`))
  - Runtime frames/state: `ChatType` ([`../Src/EditBox.lua#L32`](`../Src/EditBox.lua#L32`))
  - Runtime frames/state: `Language` ([`../Src/EditBox.lua#L33`](`../Src/EditBox.lua#L33`))
  - Runtime frames/state: `Target` ([`../Src/EditBox.lua#L34`](`../Src/EditBox.lua#L34`))
  - Runtime frames/state: `ChannelName` ([`../Src/EditBox.lua#L35`](`../Src/EditBox.lua#L35`))
  - State tables: `HookedBoxes`, `LastUsed`, `ReplyQueue`, `_attrCache` ([`../Src/EditBox.lua#L30-L40`](../Src/EditBox.lua#L30-L40), [`../Src/EditBox.lua#L59`](../Src/EditBox.lua#L59)).
  - History pointers: `HistoryIndex` ([`../Src/EditBox.lua#L37`](`../Src/EditBox.lua#L37`))
  - History pointers: `HistoryCache` ([`../Src/EditBox.lua#L38`](`../Src/EditBox.lua#L38`))
  - `_lockdown`, `_overlayUnfocused` *private by convention; do not rely on* ([`../Src/EditBox.lua#L44-L56`](../Src/EditBox.lua#L44-L56)).
  - Internal constants/closures exported for submodules (`_UserBypassingYapper`, `_SetUserBypassingYapper`, `_BypassEditBox`, `_SetBypassEditBox`, `_SLASH_MAP`, `_TAB_CYCLE`, `_LABEL_PREFIXES`, `_GROUP_CHAT_TYPES`, `_CHATTYPE_TO_OVERRIDE_KEY`, `_REPLY_QUEUE_MAX`) *private by convention; do not rely on* ([`../Src/EditBox.lua#L329-L338`](../Src/EditBox.lua#L329-L338)).
  - Internal helper exports: `IsWhisperSlashPrefill` ([`../Src/EditBox.lua#L376`](`../Src/EditBox.lua#L376`))
  - Internal helper exports: `ParseWhisperSlash` ([`../Src/EditBox.lua#L377`](`../Src/EditBox.lua#L377`))
  - Internal helper exports: `GetLastTellTargetInfo` — returns chatType and name of the last person who whispered *you* ([`../Src/EditBox.lua#L378`](`../Src/EditBox.lua#L378`))
  - Internal helper exports: `GetLastToldTargetInfo` — returns chatType and name of the last person *you* whispered (outgoing). Uses `ChatFrameUtil.GetLastToldTarget`; stays in sync with both Yapper and Blizzard sends. ([`../Src/EditBox.lua#L270`](`../Src/EditBox.lua#L270`))
  - Internal helper exports: `SetFrameFillColour` ([`../Src/EditBox.lua#L380`](`../Src/EditBox.lua#L380`))
- Methods:
  - `ClearLockdownState` ([`../Src/EditBox.lua#L65`](../Src/EditBox.lua#L65))
  - `AddReplyTarget` ([`../Src/EditBox.lua#L81`](../Src/EditBox.lua#L81))
  - `NextReplyTarget` ([`../Src/EditBox.lua#L112`](../Src/EditBox.lua#L112))
  - `OpenBlizzardChat` ([`../Src/EditBox.lua#L299`](../Src/EditBox.lua#L299))
  - `SetOnSend` ([`../Src/EditBox.lua#L382`](../Src/EditBox.lua#L382))
  - `SetPreShowCheck` ([`../Src/EditBox.lua#L388`](../Src/EditBox.lua#L388))
- Invariants:
  - Overlay behaviour valid only after `HookAllChatFrames()` has run.

## EditBox.SkinProxy

Attached during overlay show lifecycle.

- Description: Mirrors Blizzard editbox visual skin.
- Methods:
  - `AttachBlizzardSkinProxy` ([`../Src/EditBox/SkinProxy.lua#L17`](`../Src/EditBox/SkinProxy.lua#L17`))
  - `TintSkinProxyTextures` ([`../Src/EditBox/SkinProxy.lua#L175`](`../Src/EditBox/SkinProxy.lua#L175`))
  - `DetachBlizzardSkinProxy` ([`../Src/EditBox/SkinProxy.lua#L210`](`../Src/EditBox/SkinProxy.lua#L210`))

## EditBox.Overlay

Used by `EditBox:Show` to create and refresh frame contents.

- Description: Overlay frame creation and label/font rendering helpers.
- Fields:
  - `_RefreshOverlayVisuals`, `_ResolveChannelName`, `_BuildLabelText`, `_GetLabelUsableWidth`, `_ResetLabelToBaseFont`, `_TruncateLabelToWidth`, `_FitLabelFontToWidth`, `_UpdateLabelBackgroundForText` *private by convention; do not rely on* ([`../Src/EditBox/Overlay.lua#L478-L485`](../Src/EditBox/Overlay.lua#L478-L485)).
- Methods:
  - `EditBox:CreateOverlay() → nil` ([`../Src/EditBox/Overlay.lua#L350`](../Src/EditBox/Overlay.lua#L350)).

## EditBox.Handlers

Bound by `SetupOverlayScripts` when overlay is created.

- Description: Input handlers for Enter/Tab/history/channel switching.
- Methods:
  - `SetupOverlayScripts`, `ResetLockdownIdleTimer` ([`../Src/EditBox/Handlers.lua#L35`](../Src/EditBox/Handlers.lua#L35), [`../Src/EditBox/Handlers.lua#L733`](../Src/EditBox/Handlers.lua#L733)).
- Callbacks fired:
  - `EDITBOX_CHANNEL_CHANGED` (via downstream hooks).

## EditBox.Hooks

Hooked into Blizzard editboxes during `HookAllChatFrames`.

- Description: Show/hide lifecycle, handoff, hook glue, open guards.
- Methods:
  - `Show` ([`../Src/EditBox/Hooks.lua#L61`](`../Src/EditBox/Hooks.lua#L61`))
  - `Hide` ([`../Src/EditBox/Hooks.lua#L423`](`../Src/EditBox/Hooks.lua#L423`))
  - `HandoffToBlizzard` ([`../Src/EditBox/Hooks.lua#L472`](`../Src/EditBox/Hooks.lua#L472`))
  - `ApplyConfigToLiveOverlay` ([`../Src/EditBox/Hooks.lua#L512`](`../Src/EditBox/Hooks.lua#L512`))
  - `RefreshLabel` ([`../Src/EditBox/Hooks.lua#L606`](`../Src/EditBox/Hooks.lua#L606`))
  - `PersistLastUsed` ([`../Src/EditBox/Hooks.lua#L779`](`../Src/EditBox/Hooks.lua#L779`))
  - `CycleChat` ([`../Src/EditBox/Hooks.lua#L817`](`../Src/EditBox/Hooks.lua#L817`))
  - `IsChatTypeAvailable` ([`../Src/EditBox/Hooks.lua#L865`](`../Src/EditBox/Hooks.lua#L865`))
  - `GetResolvedChatType` ([`../Src/EditBox/Hooks.lua#L887`](`../Src/EditBox/Hooks.lua#L887`))
  - `NavigateHistory` ([`../Src/EditBox/Hooks.lua#L912`](`../Src/EditBox/Hooks.lua#L912`))
  - `ForwardSlashCommand` ([`../Src/EditBox/Hooks.lua#L987`](`../Src/EditBox/Hooks.lua#L987`))
  - `HookBlizzardEditBox` ([`../Src/EditBox/Hooks.lua#L1054`](`../Src/EditBox/Hooks.lua#L1054`))
  - `HookAllChatFrames` ([`../Src/EditBox/Hooks.lua#L1455`](`../Src/EditBox/Hooks.lua#L1455`))
- Filters run:
  - `PRE_EDITBOX_SHOW`.
- Callbacks fired:
  - `EDITBOX_SHOW`, `EDITBOX_HIDE`, `EDITBOX_CHANNEL_CHANGED`.
- Invariants:
  - `_inBlizzShowHook` and deferred focus handoff guard reentrancy (issue #21 fix).

## GopherBridge

Initialised by `Chat:Init`.

- Description: LibGopher delivery bridge.
- Fields:
  - `active: boolean` ([`../Src/Bridges/GopherBridge.lua#L25`](`../Src/Bridges/GopherBridge.lua#L25`))
  - `_gopher: table|nil` ([`../Src/Bridges/GopherBridge.lua#L26`](`../Src/Bridges/GopherBridge.lua#L26`))
- Methods:
  - `Init` ([`../Src/Bridges/GopherBridge.lua#L54`](`../Src/Bridges/GopherBridge.lua#L54`))
  - `UpdateState` ([`../Src/Bridges/GopherBridge.lua#L76`](`../Src/Bridges/GopherBridge.lua#L76`))
  - `Send` ([`../Src/Bridges/GopherBridge.lua#L104`](`../Src/Bridges/GopherBridge.lua#L104`))
  - `IsActive` ([`../Src/Bridges/GopherBridge.lua#L148`](`../Src/Bridges/GopherBridge.lua#L148`))
  - `IsBusy` ([`../Src/Bridges/GopherBridge.lua#L155`](`../Src/Bridges/GopherBridge.lua#L155`))

## TypingTrackerBridge

Initialised by `Chat:Init` (state refresh), then driven by overlay callbacks.

- Description: Signals external typing tracker addon.  Correctly snapshots/restores configuration from the active profile root (global or per-character) during activation/deactivation.
- Methods:
  - `UpdateState` ([`../Src/Bridges/TypingTrackerBridge.lua#L377`](`../Src/Bridges/TypingTrackerBridge.lua#L377`))
  - `OnOverlayFocusGained` ([`../Src/Bridges/TypingTrackerBridge.lua#L415`](`../Src/Bridges/TypingTrackerBridge.lua#L415`))
  - `OnOverlayFocusLost` ([`../Src/Bridges/TypingTrackerBridge.lua#L419`](`../Src/Bridges/TypingTrackerBridge.lua#L419`))
  - `OnOverlaySent` ([`../Src/Bridges/TypingTrackerBridge.lua#L423`](`../Src/Bridges/TypingTrackerBridge.lua#L423`))
  - `OnChannelChanged` ([`../Src/Bridges/TypingTrackerBridge.lua#L428`](`../Src/Bridges/TypingTrackerBridge.lua#L428`))

## RPPrefixBridge

Initialised by `Chat:Init`.

- Description: Prefixes outgoing RP marker text.
- Methods:
  - `Init` ([`../Src/Bridges/RPPrefixBridge.lua#L62`](`../Src/Bridges/RPPrefixBridge.lua#L62`))
  - `IsActive` ([`../Src/Bridges/RPPrefixBridge.lua#L117`](`../Src/Bridges/RPPrefixBridge.lua#L117`))
  - `ApplyPrefix` ([`../Src/Bridges/RPPrefixBridge.lua#L138`](`../Src/Bridges/RPPrefixBridge.lua#L138`))

## WIMBridge

Initialised by `Chat:Init`.

- Description: Cooperates with WIM focus ownership.
- Methods:
  - `IsFocusActive` ([`../Src/Bridges/WIMBridge.lua#L25`](`../Src/Bridges/WIMBridge.lua#L25`))
  - `IsLoaded` ([`../Src/Bridges/WIMBridge.lua#L42`](`../Src/Bridges/WIMBridge.lua#L42`))
  - `Init` ([`../Src/Bridges/WIMBridge.lua#L50`](`../Src/Bridges/WIMBridge.lua#L50`))

## ElvUIBridge

Syncs theme colours based on ElvUI state when enabled.

- Description: Optional ElvUI theme adaptation bridge.
- Fields:
  - `active: boolean` ([`../Src/Bridges/ElvUIBridge.lua#L110`](../Src/Bridges/ElvUIBridge.lua#L110)).
- Methods:
  - `Activate` ([`../Src/Bridges/ElvUIBridge.lua#L115`](`../Src/Bridges/ElvUIBridge.lua#L115`))
  - `Deactivate` ([`../Src/Bridges/ElvUIBridge.lua#L159`](`../Src/Bridges/ElvUIBridge.lua#L159`))
  - `RefreshColors` ([`../Src/Bridges/ElvUIBridge.lua#L218`](`../Src/Bridges/ElvUIBridge.lua#L218`))
  - `Sync` ([`../Src/Bridges/ElvUIBridge.lua#L238`](`../Src/Bridges/ElvUIBridge.lua#L238`))

## Router

Initialised by `Chat:Init`.

- Description: Resolves concrete WoW send API for chat target.
- Fields:
  - `SendChatMessage`, `BNSendWhisper`, `ClubSendMessage` cached function refs ([`../Src/Router.lua#L26-L28`](../Src/Router.lua#L26-L28)).
- Methods:
  - `ResolveBnetTarget` ([`../Src/Router.lua#L63`](`../Src/Router.lua#L63`))
  - `_ResolveBnetTargetUncached` ([`../Src/Router.lua#L85`](`../Src/Router.lua#L85`))
  - `ResolveBnetDisplay` ([`../Src/Router.lua#L118`](`../Src/Router.lua#L118`))
  - `FlushBnetCache` ([`../Src/Router.lua#L177`](`../Src/Router.lua#L177`))
  - `Init` ([`../Src/Router.lua#L181`](`../Src/Router.lua#L181`))
  - `DetectCommunityChannel` ([`../Src/Router.lua#L215`](`../Src/Router.lua#L215`))
  - `Send` ([`../Src/Router.lua#L234`](`../Src/Router.lua#L234`))
- Side effects:
  - May delegate to `GopherBridge:Send`.

## Chunking

Called from `Chat:OnSend` for oversized messages.

- Description: UTF-8 aware message splitting.
- Methods:
  - `Chunking:Split(text, limit, ignoreParagraphMerging?, useDelineators?, delineator?, prefix?) → string[]` ([`../Src/Chunking.lua#L351`](../Src/Chunking.lua#L351))
  - `Chunking:GetDelineators() → table` ([`../Src/Chunking.lua#L579`](../Src/Chunking.lua#L579))

## Queue

Initialised by `Chat:Init`; registers many chat confirm events.

- Description: Ordered chunk delivery with ack/stall policy.
- Fields:
  - Queue state: `Entries` ([`../Src/Queue.lua#L168`](`../Src/Queue.lua#L168`))

  - Queue state: `PlayerGUID` ([`../Src/Queue.lua#L169`](`../Src/Queue.lua#L169`))
  - Queue state: `NeedsContinue` ([`../Src/Queue.lua#L173`](`../Src/Queue.lua#L173`))
  - Queue state: `StallTimer` ([`../Src/Queue.lua#L174`](`../Src/Queue.lua#L174`))
  - Queue state: `StallTimeout` ([`../Src/Queue.lua#L175`](`../Src/Queue.lua#L175`))
  - Queue state: `PendingEntry` ([`../Src/Queue.lua#L177`](`../Src/Queue.lua#L177`))
  - Queue state: `PendingAckEntry` ([`../Src/Queue.lua#L178`](`../Src/Queue.lua#L178`))
  - Queue state: `PendingAckText` ([`../Src/Queue.lua#L179`](`../Src/Queue.lua#L179`))
  - Queue state: `PendingAckEvent` ([`../Src/Queue.lua#L180`](`../Src/Queue.lua#L180`))
  - Queue state: `PendingAckPolicyClass` ([`../Src/Queue.lua#L181`](`../Src/Queue.lua#L181`))
  - Queue state: `StrictAckMatching` ([`../Src/Queue.lua#L182`](`../Src/Queue.lua#L182`))
  - Queue state: `_lastEscTime` ([`../Src/Queue.lua#L184`](`../Src/Queue.lua#L184`))
  - Queue state: `ContinueFrame` ([`../Src/Queue.lua#L187`](`../Src/Queue.lua#L187`))
- Methods:
  - [NEW] `Queue:IsAcceptableAck() → nil`: No description provided. ([`../Src/Queue.lua#L510`](../Src/Queue.lua#L510))
  - `Init` ([`../Src/Queue.lua#L193`](../Src/Queue.lua#L193))
  - `Reset` ([`../Src/Queue.lua#L212`](../Src/Queue.lua#L212))
  - `IsOpenWorld` ([`../Src/Queue.lua#L229`](../Src/Queue.lua#L229))
  - `IsCommunityChannelEntry` ([`../Src/Queue.lua#L237`](../Src/Queue.lua#L237))
  - `ClassifyEntry` ([`../Src/Queue.lua#L251`](../Src/Queue.lua#L251))
  - `GetPolicy` ([`../Src/Queue.lua#L294`](../Src/Queue.lua#L294))
  - `GetConfirmEventForEntry` ([`../Src/Queue.lua#L309`](../Src/Queue.lua#L309))
  - `TrackPendingAck` ([`../Src/Queue.lua#L324`](../Src/Queue.lua#L324))
  - `GetActivePolicySnapshot` ([`../Src/Queue.lua#L332`](../Src/Queue.lua#L332))
  - `ClearPendingAck` ([`../Src/Queue.lua#L346`](../Src/Queue.lua#L346))
  - `Enqueue` ([`../Src/Queue.lua#L357`](../Src/Queue.lua#L357))
  - `Flush` ([`../Src/Queue.lua#L369`](../Src/Queue.lua#L369))
  - `RequiresHardwareEvent` ([`../Src/Queue.lua#L392`](../Src/Queue.lua#L392))
  - `SendNext` ([`../Src/Queue.lua#L397`](../Src/Queue.lua#L397))
  - `BeginEntry` ([`../Src/Queue.lua#L433`](../Src/Queue.lua#L433))
  - `HandleAck` ([`../Src/Queue.lua#L459`](../Src/Queue.lua#L459))
  - `AssumeAck` ([`../Src/Queue.lua#L467`](../Src/Queue.lua#L467))
  - `RawSend` ([`../Src/Queue.lua#L477`](../Src/Queue.lua#L477))
  - `Complete` ([`../Src/Queue.lua#L498`](../Src/Queue.lua#L498))
  - `OnChatEvent` ([`../Src/Queue.lua#L520`](../Src/Queue.lua#L520))
  - `OnOpenChat` ([`../Src/Queue.lua#L596`](../Src/Queue.lua#L596))
  - `TryContinue` ([`../Src/Queue.lua#L606`](../Src/Queue.lua#L606))
  - `ResetStallTimer` ([`../Src/Queue.lua#L624`](../Src/Queue.lua#L624))
  - `CancelStallTimer` ([`../Src/Queue.lua#L642`](../Src/Queue.lua#L642))
  - `OnStallTimeout` ([`../Src/Queue.lua#L649`](../Src/Queue.lua#L649))
  - `CreateContinueFrame` ([`../Src/Queue.lua#L671`](../Src/Queue.lua#L671))
  - `ShowContinuePrompt` ([`../Src/Queue.lua#L731`](../Src/Queue.lua#L731))
  - `HideContinuePrompt` ([`../Src/Queue.lua#L768`](../Src/Queue.lua#L768))
  - `EnableEscapeCancel` ([`../Src/Queue.lua#L779`](../Src/Queue.lua#L779))
  - `DisableEscapeCancel` ([`../Src/Queue.lua#L812`](../Src/Queue.lua#L812))
  - `Cancel` ([`../Src/Queue.lua#L819`](../Src/Queue.lua#L819))
- Events registered:
  - `CHAT_MSG_SAY`, `CHAT_MSG_YELL`, `CHAT_MSG_EMOTE`, `CHAT_MSG_WHISPER_INFORM`, `CHAT_MSG_BN_WHISPER_INFORM`, `CHAT_MSG_CHANNEL`, `CHAT_MSG_COMMUNITIES_CHANNEL`, `CHAT_MSG_PARTY`, `CHAT_MSG_PARTY_LEADER`, `CHAT_MSG_RAID`, `CHAT_MSG_RAID_LEADER`, `CHAT_MSG_RAID_WARNING`, `CHAT_MSG_INSTANCE_CHAT`, `CHAT_MSG_INSTANCE_CHAT_LEADER`, `CHAT_MSG_GUILD`, `CHAT_MSG_OFFICER` (registered from `ALL_CONFIRM_EVENTS`) ([`../Src/Queue.lua#L130-L156`](../Src/Queue.lua#L130-L156), [`../Src/Queue.lua#L190-L194`](../Src/Queue.lua#L190-L194)).
  - Hook to `ChatFrameUtil.OpenChat` for continue flow.
- Callbacks fired:
  - `QUEUE_STALL`, `QUEUE_COMPLETE`.
- Invariants:
  - `TryContinue()` only meaningful when `NeedsContinue == true`.

## Chat

Initialised on `PLAYER_ENTERING_WORLD` by `Yapper.lua`.

- Description: Send orchestrator (`EditBox -> Chunking -> Queue -> Router`).
- Methods:
  - `Chat:Init() → nil` ([`../Src/Chat.lua#L41`](../Src/Chat.lua#L41))
  - `Chat:OnSend(text, chatType, language, target) → nil` ([`../Src/Chat.lua#L100`](../Src/Chat.lua#L100))
  - `Chat:DirectSend(msg, chatType, language, target) → nil` ([`../Src/Chat.lua#L218`](../Src/Chat.lua#L218))
- Filters run:
  - `PRE_SEND`, `PRE_CHUNK`, `PRE_DELIVER`.
- Callbacks fired:
  - `POST_SEND`, `POST_CLAIMED`.

## Multiline

Lazy frame creation; active only when user enters multiline mode.

- Description: Expanded multiline editor that bypasses single-line overlay.
- Fields:
  - `Frame` ([`../Src/Multiline.lua#L56`](`../Src/Multiline.lua#L56`))
  - `ScrollFrame` ([`../Src/Multiline.lua#L57`](`../Src/Multiline.lua#L57`))
  - `EditBox` ([`../Src/Multiline.lua#L58`](`../Src/Multiline.lua#L58`))
  - `LabelFS` ([`../Src/Multiline.lua#L59`](`../Src/Multiline.lua#L59`))
  - `Active` ([`../Src/Multiline.lua#L198`](`../Src/Multiline.lua#L198`))
  - `ChatType` ([`../Src/Multiline.lua#L60`](`../Src/Multiline.lua#L60`))
  - `Language` ([`../Src/Multiline.lua#L61`](`../Src/Multiline.lua#L61`))
  - `Target` ([`../Src/Multiline.lua#L62`](`../Src/Multiline.lua#L62`))
- Methods:
  - `UpdateLabelGap` ([`../Src/Multiline.lua#L112`](`../Src/Multiline.lua#L112`))
  - `CreateFrame` ([`../Src/Multiline.lua#L145`](`../Src/Multiline.lua#L145`))
  - `Enter` ([`../Src/Multiline.lua#L547`](`../Src/Multiline.lua#L547`))
  - `Exit` ([`../Src/Multiline.lua#L677`](`../Src/Multiline.lua#L677`))
  - `Submit` ([`../Src/Multiline.lua#L793`](`../Src/Multiline.lua#L793`))
  - `Cancel` ([`../Src/Multiline.lua#L930`](`../Src/Multiline.lua#L930`))
  - `HandleEscape` ([`../Src/Multiline.lua#L956`](`../Src/Multiline.lua#L956`)) — handles the ESC key; returns true to close, false to ignore (e.g. closing sub-UI first).
  - `ShouldAutoExpand` ([`../Src/Multiline.lua#L943`](`../Src/Multiline.lua#L943`))
  - `ApplyTheme` ([`../Src/Multiline.lua#L965`](`../Src/Multiline.lua#L965`))
- Invariants:
  - While `Active`, single-line overlay show path should early-return.

## Autocomplete

Binds to overlay (or multiline) editbox when available.

- Description: Ghost-text completion from dictionary + YALLM.
- Fields:
  - `GhostFS` ([`../Src/Autocomplete.lua#L74`](`../Src/Autocomplete.lua#L74`))
  - `CurrentSugg` ([`../Src/Autocomplete.lua#L75`](`../Src/Autocomplete.lua#L75`))
  - `CurrentPrefix` ([`../Src/Autocomplete.lua#L76`](`../Src/Autocomplete.lua#L76`))
  - `PrefixText` ([`../Src/Autocomplete.lua#L77`](`../Src/Autocomplete.lua#L77`))
  - `Active` ([`../Src/Autocomplete.lua#L78`](`../Src/Autocomplete.lua#L78`))
  - `Enabled` ([`../Src/Autocomplete.lua#L79`](`../Src/Autocomplete.lua#L79`))
  - `_activeEditBox` ([`../Src/Autocomplete.lua#L80`](`../Src/Autocomplete.lua#L80`))
  - `_isMultiline` ([`../Src/Autocomplete.lua#L81`](`../Src/Autocomplete.lua#L81`))
- Methods:
  - [NEW] `Autocomplete:SetOffset(x, y) → nil`: Set a manual pixel offset for the ghost-text positioning. ([`../Src/Autocomplete.lua#L623`](../Src/Autocomplete.lua#L623))
  - `IsEnabled`, `ExtractWordAtCursor`, `SearchDictionary`, `GetSuggestion`, `GetGhostFS`, `_InstallCursorHook`, `PositionGhost`, `ShowGhost`, `HideGhost`, `OnTextChanged`, `OnTabPressed`, `OnOverlayHide`, `SyncFont`, `SyncGhostFont`, `BindMultiline`, `UnbindMultiline` ([`../Src/Autocomplete.lua`](../Src/Autocomplete.lua)).

## History

Initialised on `ADDON_LOADED`; hooks overlay on `PLAYER_ENTERING_WORLD`.

- Description: Persistent chat history, draft store, undo/redo snapshots.
- Methods:
  - `History:SaveDraft(editBox, isMultiline) → nil`: Save a draft from any EditBox (overlay or multiline). ([`../Src/History.lua#L195`](../Src/History.lua#L195))
  - `History:GetDraft() → string? text, string? chatType, string? target, boolean? multiline`: Return the saved draft if dirty. ([`../Src/History.lua#L225`](../Src/History.lua#L225))
  - `InitDB` ([`../Src/History.lua#L72`](`../Src/History.lua#L72`))
  - `SaveDB` ([`../Src/History.lua#L113`](`../Src/History.lua#L113`))
  - `AddChatHistory` ([`../Src/History.lua#L134`](`../Src/History.lua#L134`))
  - `GetChatHistory` ([`../Src/History.lua#L171`](`../Src/History.lua#L171`))
  - `GetDraftStore` ([`../Src/History.lua#L182`](`../Src/History.lua#L182`))
  - `MarkDirty` ([`../Src/History.lua#L234`](`../Src/History.lua#L234`))
  - `ClearDraft` ([`../Src/History.lua#L239`](`../Src/History.lua#L239`))
  - `CancelPauseTimer` ([`../Src/History.lua#L259`](`../Src/History.lua#L259`))
  - `AddSnapshot` ([`../Src/History.lua#L289`](`../Src/History.lua#L289`))
  - `Undo` ([`../Src/History.lua#L333`](`../Src/History.lua#L333`))
  - `Redo` ([`../Src/History.lua#L349`](`../Src/History.lua#L349`))
  - `HookOverlayEditBox` ([`../Src/History.lua#L377`](`../Src/History.lua#L377`))
- Global state touched:
  - `_G.YapperLocalHistory`.

## Theme

Loaded with defaults; active theme restored on `ADDON_LOADED`.

- Description: Theme registry, application, persistence, live sync.
- Fields:
  - `_registry`, `_current` *private by convention; do not rely on* ([`../Src/Theme.lua#L16-L17`](../Src/Theme.lua#L16-L17)).
- Methods:
  - `YapperTable:GetRegisteredThemes() → nil`: No description provided. ([`../Src/Theme.lua#L272`](../Src/Theme.lua#L272))
  - `RegisterTheme` ([`../Src/Theme.lua#L25`](`../Src/Theme.lua#L25`))
  - `GetTheme` ([`../Src/Theme.lua#L31`](`../Src/Theme.lua#L31`))
  - `GetRegisteredNames` ([`../Src/Theme.lua#L36`](`../Src/Theme.lua#L36`))
  - `SetTheme` ([`../Src/Theme.lua#L44`](`../Src/Theme.lua#L44`))
  - `ApplyToFrame` ([`../Src/Theme.lua#L129`](`../Src/Theme.lua#L129`))
  - `GetCurrentName` ([`../Src/Theme.lua#L205`](`../Src/Theme.lua#L205`))
  - `SetLiveTheme` ([`../Src/Theme.lua#L216`](`../Src/Theme.lua#L216`))
  - `SetTheme` logic switches between `_G.YapperDB` and `_G.YapperLocalConf` as the root for `_appliedTheme` based on `UseGlobalProfile`.
  - Global wrappers on root table: `Yapper:RegisterTheme` ([`../Src/Theme.lua#L25`](`../Src/Theme.lua#L25`))
  - Global wrappers on root table: `Yapper:SetTheme` ([`../Src/Theme.lua#L44`](`../Src/Theme.lua#L44`))
  - Global wrappers on root table: `Yapper:GetRegisteredThemes` ([`../Src/Theme.lua#L272`](`../Src/Theme.lua#L272`))
- Callbacks fired:
  - `THEME_CHANGED`.

## Interface

Created during `ADDON_LOADED` startup path and owns settings UI lifecycle.

- Description: Main settings shell, launcher integration, category navigation.
- Fields:
  - `MouseWheelStepRate` ([`../Src/Interface.lua#L8`](`../Src/Interface.lua#L8`))
  - `IsVisible` ([`../Src/Interface.lua#L9`](`../Src/Interface.lua#L9`))
  - `DICTIONARY_DOWNLOAD_URL` ([`../Src/Interface.lua#L12`](`../Src/Interface.lua#L12`))
  - Helpers/constants exported as underscored fields (`_LAYOUT`, `_LayoutCursor`, `_UI_FONT_*`) *private by convention; do not rely on* ([`../Src/Interface.lua#L120-L124`](../Src/Interface.lua#L120-L124)).
- Methods:
  - `LayoutCursor:Pad() → nil`: No description provided. ([`../Src/Interface.lua#L115`](../Src/Interface.lua#L115))
  - `LayoutCursor:Advance() → nil`: No description provided. ([`../Src/Interface.lua#L110`](../Src/Interface.lua#L110))
  - `LayoutCursor:Y() → nil`: No description provided. ([`../Src/Interface.lua#L106`](../Src/Interface.lua#L106))
  - `LayoutCursor:New(startY) → table`: No description provided. ([`../Src/Interface.lua#L102`](../Src/Interface.lua#L102))
  - `InitPopups` ([`../Src/Interface.lua#L308`](`../Src/Interface.lua#L308`))
  - `BuildConfigUI` ([`../Src/Interface.lua#L455`](`../Src/Interface.lua#L455`))
  - `ShowMainWindow` ([`../Src/Interface.lua#L750`](`../Src/Interface.lua#L750`))
  - `OpenToCategory` ([`../Src/Interface.lua#L775`](`../Src/Interface.lua#L775`))
  - `ToggleMainWindow` ([`../Src/Interface.lua#L800`](`../Src/Interface.lua#L800`))
  - `HandleLauncherClick` ([`../Src/Interface.lua#L832`](`../Src/Interface.lua#L832`))
  - `CloseFrame` ([`../Src/Interface.lua#L867`](`../Src/Interface.lua#L867`))
  - `Init` ([`../Src/Interface.lua#L878`](`../Src/Interface.lua#L878`))
  - `CreateLauncher` ([`../Src/Interface.lua#L913`](`../Src/Interface.lua#L913`))
- Global function:
  - `Yapper_FromCompartment(...)` ([`../Src/Interface.lua#L854`](../Src/Interface.lua#L854)).

## Interface.Schema

Build-time render schema module used by window/UI builders.

- Description: Settings schema composition and category metadata.
- Fields:
  - `_COLOUR_KEYS`, `_CHANNEL_OVERRIDE_OPTIONS`, `_CREDITS_BUNDLED`, `_CREDITS_OPTIONAL`, `_FONT_OUTLINE_OPTIONS`, `_SETTING_TOOLTIPS`, `_FRIENDLY_LABELS`, `_CATEGORIES`, `_PATH_TO_CATEGORY` *private by convention; do not rely on* ([`../Src/Interface/Schema.lua#L506-L514`](../Src/Interface/Schema.lua#L514)).
- Methods:
  - `BuildRenderSchema` ([`../Src/Interface/Schema.lua#L346`](`../Src/Interface/Schema.lua#L346`))
  - `GetRenderSchema` ([`../Src/Interface/Schema.lua#L493`](`../Src/Interface/Schema.lua#L493`))
  - `RefreshRenderSchema` ([`../Src/Interface/Schema.lua#L501`](`../Src/Interface/Schema.lua#L501`))
  - `OnWindowClosed` ([`../Src/Interface/Schema.lua#L507`](`../Src/Interface/Schema.lua#L507`))

## Interface.Config

Handles config reads/writes and side-effect fan-out.

- Description: Config root/path helpers, sanitisation, minimap controls.
- Methods:
  - [NEW] `Interface:FactoryReset() → nil`: TRUE clean slate: wipes all settings, learned dictionary data, and history. ([`../Src/Interface/Config.lua#L78`](../Src/Interface/Config.lua#L78))
  - `Interface:ResetAllSettings() → nil`: Reset all configuration settings to their default values. ([`../Src/Interface/Config.lua#L50`](../Src/Interface/Config.lua#L50))
  - `GetLocalConfigRoot` ([`../Src/Interface/Config.lua#L34`](`../Src/Interface/Config.lua#L34`))
  - `GetDefaultsRoot` ([`../Src/Interface/Config.lua#L41`](`../Src/Interface/Config.lua#L41`))
  - `GetRenderCacheContainer` ([`../Src/Interface/Config.lua#L92`](`../Src/Interface/Config.lua#L92`))
  - `PurgeRenderCache` ([`../Src/Interface/Config.lua#L103`](`../Src/Interface/Config.lua#L103`))
  - `SetDirty` ([`../Src/Interface/Config.lua#L109`](`../Src/Interface/Config.lua#L109`))
  - `IsDirty` ([`../Src/Interface/Config.lua#L114`](`../Src/Interface/Config.lua#L114`))
  - `SetSettingsChanged` ([`../Src/Interface/Config.lua#L119`](`../Src/Interface/Config.lua#L119`))
  - `GetConfigPath` ([`../Src/Interface/Config.lua#L127`](`../Src/Interface/Config.lua#L127`))
  - `GetDefaultPath` ([`../Src/Interface/Config.lua#L135`](`../Src/Interface/Config.lua#L135`))
  - `UpdateOverrideTextColorCheckboxState` ([`../Src/Interface/Config.lua#L139`](`../Src/Interface/Config.lua#L139`))
  - `SetLocalPath` ([`../Src/Interface/Config.lua#L143`](`../Src/Interface/Config.lua#L143`))
  - `GetLauncherTooltipLines` ([`../Src/Interface/Config.lua#L339`](`../Src/Interface/Config.lua#L339`))
  - `GetMinimapButtonSettings` ([`../Src/Interface/Config.lua#L347`](`../Src/Interface/Config.lua#L347`))
  - `GetMinimapButtonOffset` ([`../Src/Interface/Config.lua#L360`](`../Src/Interface/Config.lua#L360`))
  - `PositionMinimapButton` ([`../Src/Interface/Config.lua#L364`](`../Src/Interface/Config.lua#L364`))
  - `UpdateMinimapButtonAngleFromCursor` ([`../Src/Interface/Config.lua#L380`](`../Src/Interface/Config.lua#L380`))
  - `ApplyMinimapButtonVisibility` ([`../Src/Interface/Config.lua#L397`](`../Src/Interface/Config.lua#L397`))
  - `IsPathDisabledByTheme` ([`../Src/Interface/Config.lua#L437`](`../Src/Interface/Config.lua#L437`))
  - `GetFriendlyLabel` ([`../Src/Interface/Config.lua#L462`](`../Src/Interface/Config.lua#L462`))
  - `SanitizeLocalConfig` ([`../Src/Interface/Config.lua#L491`](`../Src/Interface/Config.lua#L491`))
- Non-obvious rationale migrated from old docs:
  - `SetLocalPath` is the **single authoritative write source** for configuration; it handles profile-aware routing, theme-override marking, and automatic `PromoteCharacterToGlobal` triggers during profile toggles.
  - `SetLocalPath` enforces channel marker sync (`Chat.DELINEATOR` and `Chat.PREFIX`) as a single logical setting update.

## Interface.Window

Builds and controls top-level frames.

- Description: Main window, welcome/what's-new flows, UI font scaling.
- Fields:
  - `_activeCategory` *private by convention; do not rely on* ([`../Src/Interface/Window.lua#L175`](../Src/Interface/Window.lua#L175)).
- Methods:
  - `CompareVersions` — Compares semantic version strings. ([`../Src/Interface/Window.lua#L301`](../Src/Interface/Window.lua#L301))
  - `GetSortedVersions` — Returns WHATS_NEW entries sorted by version. ([`../Src/Interface/Window.lua#L312`](../Src/Interface/Window.lua#L312))
  - `CheckForChangelogUpdate` — Handshake that updates seen records and triggers popups. ([`../Src/Interface/Window.lua#L388`](../Src/Interface/Window.lua#L388))
  - `PopulateWhatsNewContent` — Renders changelog notes into a container. ([`../Src/Interface/Window.lua#L836`](../Src/Interface/Window.lua#L836))
  - `RefreshWhatsNewContent` — Wipes and re-renders the WhatsNew popup. ([`../Src/Interface/Window.lua#L884`](../Src/Interface/Window.lua#L884))
  - `UpdateWhatsNewButtonScale` — Scales the 'Got it' button text. ([`../Src/Interface/Window.lua#L901`](../Src/Interface/Window.lua#L901))
  - [NEW] `Interface:GetWelcomeVersion() → number`: Returns the target version of the welcome screen content. ([`../Src/Interface/Window.lua#L323`](../Src/Interface/Window.lua#L323))
  - `GetMainWindowPositionStore` ([`../Src/Interface/Window.lua#L31`](`../Src/Interface/Window.lua#L31`))
  - `SaveMainWindowPosition` ([`../Src/Interface/Window.lua#L48`](`../Src/Interface/Window.lua#L48`))
  - `ApplyMainWindowPosition` ([`../Src/Interface/Window.lua#L65`](`../Src/Interface/Window.lua#L65`))
  - `ShouldShowWelcomeChoice` ([`../Src/Interface/Window.lua#L367`](`../Src/Interface/Window.lua#L367`))
  - `ShouldShowWhatsNew` ([`../Src/Interface/Window.lua#L379`](`../Src/Interface/Window.lua#L379`))
  - `MarkWelcomeShown` ([`../Src/Interface/Window.lua#L414`](`../Src/Interface/Window.lua#L414`))
  - `MarkVersionSeen` ([`../Src/Interface/Window.lua#L418`](`../Src/Interface/Window.lua#L418`))
  - `CreateWelcomeChoiceFrame` ([`../Src/Interface/Window.lua#L473`](`../Src/Interface/Window.lua#L473`))
  - `CreateWhatsNewFrame` ([`../Src/Interface/Window.lua#L668`](`../Src/Interface/Window.lua#L668`))
  - `CreateMainWindow` ([`../Src/Interface/Window.lua#L919`](`../Src/Interface/Window.lua#L919`))
  - `UpdateSidebarSelection` ([`../Src/Interface/Window.lua#L1104`](`../Src/Interface/Window.lua#L1104`))
  - `GetUIFontOffset` ([`../Src/Interface/Window.lua#L1123`](`../Src/Interface/Window.lua#L1123`))
  - `SetUIFontOffset` ([`../Src/Interface/Window.lua#L1129`](`../Src/Interface/Window.lua#L1129`))
  - `ScaledRow` ([`../Src/Interface/Window.lua#L1137`](`../Src/Interface/Window.lua#L1137`))
  - `ApplyUIFontScale` ([`../Src/Interface/Window.lua#L1143`](`../Src/Interface/Window.lua#L1143`))
  - `RefreshFontScaleLabel` ([`../Src/Interface/Window.lua#L1171`](`../Src/Interface/Window.lua#L1171`))

## Interface.Widgets

Widget factory/pool and reusable setting controls.

- Description: UI control allocator with pooling, tooltip plumbing, common controls.
- Fields:
  - `WidgetPool: table` ([`../Src/Interface/Widgets.lua#L56`](../Src/Interface/Widgets.lua#L56)).
  - `_OpenColorPicker: function` *private by convention; do not rely on* ([`../Src/Interface/Widgets.lua#L886`](../Src/Interface/Widgets.lua#L886)).
- Methods:
  - `ClearConfigControls` ([`../Src/Interface/Widgets.lua#L34`](`../Src/Interface/Widgets.lua#L34`))
  - `AddControl` ([`../Src/Interface/Widgets.lua#L45`](`../Src/Interface/Widgets.lua#L45`))
  - `AcquireWidget` ([`../Src/Interface/Widgets.lua#L66`](`../Src/Interface/Widgets.lua#L66`))
  - `ReleaseWidget` ([`../Src/Interface/Widgets.lua#L100`](`../Src/Interface/Widgets.lua#L100`))
  - `GetTooltip` ([`../Src/Interface/Widgets.lua#L178`](`../Src/Interface/Widgets.lua#L178`))
  - `AttachTooltip` ([`../Src/Interface/Widgets.lua#L189`](`../Src/Interface/Widgets.lua#L189`))
  - `CreateResetButton` ([`../Src/Interface/Widgets.lua#L294`](`../Src/Interface/Widgets.lua#L294`))
  - `CreateLabel` ([`../Src/Interface/Widgets.lua#L307`](`../Src/Interface/Widgets.lua#L307`))
  - `CreateCheckBox` ([`../Src/Interface/Widgets.lua#L509`](`../Src/Interface/Widgets.lua#L509`))
  - `CreateTextInput` ([`../Src/Interface/Widgets.lua#L562`](`../Src/Interface/Widgets.lua#L562`))
  - `CreateColorPickerControl` ([`../Src/Interface/Widgets.lua#L653`](`../Src/Interface/Widgets.lua#L653`))
  - `CreateFontSizeDropdown` ([`../Src/Interface/Widgets.lua#L738`](`../Src/Interface/Widgets.lua#L738`))
  - `CreateFontOutlineDropdown` ([`../Src/Interface/Widgets.lua#L837`](`../Src/Interface/Widgets.lua#L837`))
- Non-obvious rationale migrated from old docs:
  - `CreateResetButton` self-registers with control tracking; do not double-register via `AddControl`.

## Interface.Pages

Per-category page builders called by `BuildConfigUI`.

- Description: Concrete settings page construction routines.
- Methods:
  - `CreateChangelogPage` — Builds the scrollable version history settings tab. ([`../Src/Interface/Pages.lua#L951`](../Src/Interface/Pages.lua#L951))
  - `CreateChannelOverrideControls` ([`../Src/Interface/Pages.lua#L41`](`../Src/Interface/Pages.lua#L41`))
  - `CreateGlobalSyncControls` ([`../Src/Interface/Pages.lua#L332`](`../Src/Interface/Pages.lua#L332`))
  - `CreateYALLMLearningPage` ([`../Src/Interface/Pages.lua#L389`](`../Src/Interface/Pages.lua#L389`))
  - `CreateQueueDiagnostics` ([`../Src/Interface/Pages.lua#L634`](`../Src/Interface/Pages.lua#L634`))
  - `CreateTutorialPage` ([`../Src/Interface/Pages.lua#L738`](`../Src/Interface/Pages.lua#L738`))
  - `CreateCreditsPage` ([`../Src/Interface/Pages.lua#L883`](`../Src/Interface/Pages.lua#L883`))
  - `CreateSpellcheckLocaleDropdown` ([`../Src/Interface/Pages.lua#L991`](`../Src/Interface/Pages.lua#L991`))
  - `CreateSpellcheckKeyboardLayoutDropdown` ([`../Src/Interface/Pages.lua#L1092`](`../Src/Interface/Pages.lua#L1092`))
  - `CreateSpellcheckUnderlineDropdown` ([`../Src/Interface/Pages.lua#L1141`](`../Src/Interface/Pages.lua#L1141`))
  - `CreateSpellcheckUserDictEditor` ([`../Src/Interface/Pages.lua#L1205`](`../Src/Interface/Pages.lua#L1205`))
  - `CreateThemeDropdown` ([`../Src/Interface/Pages.lua#L1371`](`../Src/Interface/Pages.lua#L1371`))
- Invariants:
  - Dropdown handlers assume config roots are initialised.

## Emotes

- Methods:
  - [NEW] `Emotes:EnsureHintUI() → nil`: Ensures the emote hint UI is created. ([`../Src/Emotes.lua#L185`](../Src/Emotes.lua#L185))
  - [NEW] `Emotes:EnsureMenuUI() → nil`: Ensures the emote menu UI is created. ([`../Src/Emotes.lua#L55`](../Src/Emotes.lua#L55))
  - [NEW] `Emotes:InitEmoteList() → nil`: Populates the emote list. Only called when the menu is actually opened. ([`../Src/Emotes.lua#L28`](../Src/Emotes.lua#L28))
  - [NEW] `Emotes:ApplySelection(index, isEnter) → nil`: Applies the selected emote to the edit box and hides the menu. If `autoSend` is enabled, immediately sends the emote to chat; otherwise, appends a space and refocuses the edit box (suppressing the Enter key if `isEnter` is true). ([`../Src/Emotes.lua#L389`](../Src/Emotes.lua#L389))
  - [NEW] `Emotes:RefreshSelection() → nil`: Highlights the currently selected row in the emote menu. ([`../Src/Emotes.lua#L374`](../Src/Emotes.lua#L374))
  - [NEW] `Emotes:FilterAndShow() → nil`: Re-renders the emote menu UI based on the current ActiveFilter. ([`../Src/Emotes.lua#L273`](../Src/Emotes.lua#L273))
  - [NEW] `Emotes:FilterMenu(query) → nil`: Prepares the search filter state from a raw slash command query. ([`../Src/Emotes.lua#L263`](../Src/Emotes.lua#L263))
  - [NEW] `Emotes:HideMenu() → nil`: Hides the emote menu. ([`../Src/Emotes.lua#L255`](../Src/Emotes.lua#L255))
  - [NEW] `Emotes:OpenMenu() → nil`: Opens the emote menu. ([`../Src/Emotes.lua#L235`](../Src/Emotes.lua#L235))
