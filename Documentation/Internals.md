# Internals reference (`_G.Yapper` / `YapperTable`)

> ⚠️ Everything documented here is **internal**. Use `YapperAPI` (see `API.md`) when possible.
> By interacting with, using and/or modifying internals directly (e.g. through `_G.Yapper`), you accept that these internals may change or be removed at any time, without notice, and that you are solely responsible for maintenance. Always prefer API over internals, and if you find yourself missing critical surface area for which it makes sense to create API, please reach out.

All sections below follow TOC load order from [`Yapper.toc`](../Yapper.toc).

## YapperTable root (`_G.Yapper`)

Published in [`../Yapper.lua#L64`](../Yapper.lua#L64).

- Description: global namespace alias for the addon-private table.
- Fields:
  - `YapperTable.YAPPER_DISABLED: boolean` set by override toggle ([`../Yapper.lua#L290`](../Yapper.lua#L290)).
- Methods:
  - `YapperTable:OverrideYapper(disable: boolean) → nil` ([`../Yapper.lua#L282`](../Yapper.lua#L282)) — toggles runtime ownership between Yapper overlay and Blizzard chat; cancels queue and unregisters events when disabling.

## Core

Initialised on `ADDON_LOADED` by [`Yapper.lua#L105-L110`](../Yapper.lua#L105-L110).

- Description: SavedVariables schema/default/migration authority.
- Fields:
  - `Yapper.Config: table` live config root ([`../Src/Core.lua#L284`](../Src/Core.lua#L284)).
- Methods:
  - `Core:IsLanguageCacheValid() → boolean isValid`: Check if the language cache is still valid for the current character. ([`../Src/Core.lua#L314`](../Src/Core.lua#L314))
  - `Core:RegisterFrame(category, key, frame) → nil`: Register a frame in the central UI registry for external access. ([`../Src/Core.lua#L372`](../Src/Core.lua#L372))
  - `Core:DemoteGlobalToCharacter() → nil`: Unpack stashed local settings when switching away from Global Profile. ([`../Src/Core.lua#L807`](../Src/Core.lua#L807))
  - `Core:RefreshInheritance() → nil`: Initialise inheritance chain (Global vs Local). ([`../Src/Core.lua#L608`](../Src/Core.lua#L608))
  - `Core:GetCharacterLanguage(lang) → number langId`: Get the language or defaults if not present. ([`../Src/Core.lua#L343`](../Src/Core.lua#L343))
  - `Core:BuildLanguageCache() → nil`: No description provided. ([`../Src/Core.lua#L286`](../Src/Core.lua#L286))
  - `Core:InitSavedVars() → nil` ([`../Src/Core.lua#L499`](../Src/Core.lua#L499)) — creates/migrates `YapperDB`, `YapperLocalConf`, `YapperLocalHistory`; mutates metatables for inheritance.
  - `Core:GetVersion() → string` ([`../Src/Core.lua#L629`](../Src/Core.lua#L629))
  - `Core:GetDefaults() → table` ([`../Src/Core.lua#L633`](../Src/Core.lua#L633))
  - `Core:SetVerbose(bool: boolean) → nil` ([`../Src/Core.lua#L637`](../Src/Core.lua#L637))
  - `Core:SaveSetting(category, key, value) → nil` ([`../Src/Core.lua#L650`](../Src/Core.lua#L650)) — delegates to `Interface:SetLocalPath` for profile-aware write routing.
  - `Core:PromoteCharacterToGlobal() → nil` ([`../Src/Core.lua#L714`](../Src/Core.lua#L714)) — wipes local overrides (excluding `MainWindowPosition`) and re-seeds metatable inheritance from `YapperDB`.
  - `Core:PushToGlobal() → nil` ([`../Src/Core.lua#L828`](../Src/Core.lua#L828)) — deep-copies character settings into `YapperDB`. Whitelists `System` keys; excludes `MainWindowPosition`; migrates `_themeOverrides` and `_appliedTheme` markers; no-op when already global.
- Invariants:
  - Must run before feature init (`LoadSavedVariablesFirst: 1`).
  - Metatable chain must remain intact for local fallback/inheritance logic.

## Utils

Loaded at startup; used by most modules.

- Description: Print/debug/fullscreen/chat utility helpers.
- Fields:
  - `_G.YAPPER_UTILS: table` alias for debug access ([`../Src/Utils.lua#L133`](../Src/Utils.lua#L133)).
- Methods:
  - `Utils:Print(...) → nil` ([`../Src/Utils.lua#L17`](../Src/Utils.lua#L17))
  - `Utils:VerbosePrint(...) → nil` ([`../Src/Utils.lua#L41`](../Src/Utils.lua#L41))
  - `Utils:DebugPrint(...) → nil` ([`../Src/Utils.lua#L47`](../Src/Utils.lua#L47))
  - `Utils:GetChatParent() → Frame` ([`../Src/Utils.lua#L56`](../Src/Utils.lua#L56))
  - `Utils:MakeFullscreenAware(frame) → nil` ([`../Src/Utils.lua#L68`](../Src/Utils.lua#L68))
  - `Utils:IsChatLockdown() → boolean` ([`../Src/Utils.lua#L97`](../Src/Utils.lua#L97))
  - `Utils:IsSecret(value) → boolean` ([`../Src/Utils.lua#L184`](../Src/Utils.lua#L184))

## Error

Loaded early; used for warnings and fatal throws.

- Description: Central error code registry and formatting.
- Methods:
  - `Error:PrintError(code, ...) → nil` ([`../Src/Error.lua#L102`](../Src/Error.lua#L102))
  - `Error:Throw(code, ...) → nil` ([`../Src/Error.lua#L112`](../Src/Error.lua#L112)) — halts via `error()` after printing.

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
  - `_lastCancelOwner: string|nil` *private by convention; do not rely on* ([`../Src/API.lua#L1217`](../Src/API.lua#L1217)).
- Methods:
  - `API:_createClaim(text, chatType, language, target, owner) → number` ([`../Src/API.lua#L1229`](../Src/API.lua#L1229))
  - `API:RunFilter(hookPoint, payload) → table|false` ([`../Src/API.lua#L1403`](../Src/API.lua#L1403))
  - `API:Fire(event, ...) → nil` ([`../Src/API.lua#L1447`](../Src/API.lua#L1447))
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
  - `State:ToConfig() → nil`: Transition to CONFIG (settings) state. ([`../Src/State.lua#L255`](../Src/State.lua#L255))
  - `State:IsConfig() → boolean`: Is the settings/interface window open? ([`../Src/State.lua#L211`](../Src/State.lua#L211))
  - `State:IsInitialised() → boolean`: Has the machine completed initialisation (i.e. not in INITIALISING state)? ([`../Src/State.lua#L176`](../Src/State.lua#L176))
  - `State:SetFlag(name, value, persistent) → nil`: Set a state flag value. ([`../Src/State.lua#L72`](../Src/State.lua#L72))
  - `State:GetFlag(name, default) → any`: Get a state flag value. ([`../Src/State.lua#L52`](../Src/State.lua#L52))
  - `State:IsInitialising() → boolean`: Is the machine in INITIALISING state? ([`../Src/State.lua#L170`](../Src/State.lua#L170))
  - `State:ToLockdown() → nil`: Transition to LOCKDOWN state. ([`../Src/State.lua#L251`](../Src/State.lua#L251))
  - `State:ToStalled() → nil`: Transition to STALLED state. ([`../Src/State.lua#L247`](../Src/State.lua#L247))
  - `State:ToSending() → nil`: Transition to SENDING state. ([`../Src/State.lua#L243`](../Src/State.lua#L243))
  - `State:ToMultiline() → nil`: Transition to MULTILINE state. ([`../Src/State.lua#L239`](../Src/State.lua#L239))
  - `State:ToEditing() → nil`: Transition to EDITING state. ([`../Src/State.lua#L235`](../Src/State.lua#L235))
  - `State:ToIdle() → nil`: Transition to IDLE state. ([`../Src/State.lua#L231`](../Src/State.lua#L231))
  - `State:IsInputActive() → boolean`: Helper: is the user currently typing (either overlay or multiline)? ([`../Src/State.lua#L217`](../Src/State.lua#L217))
  - `State:IsLockdown() → boolean`: Is the addon suppressed by combat or manual lockdown? ([`../Src/State.lua#L206`](../Src/State.lua#L206))
  - `State:IsStalled() → boolean`: Is the queue stalled awaiting hardware input? ([`../Src/State.lua#L201`](../Src/State.lua#L201))
  - `State:IsSending() → boolean`: Is a message currently being delivered? ([`../Src/State.lua#L196`](../Src/State.lua#L196))
  - `State:IsMultiline() → boolean`: Is the user typing in the expanded multiline editor? ([`../Src/State.lua#L191`](../Src/State.lua#L191))
  - `State:IsEditing() → boolean`: Is the user typing in the single-line overlay? ([`../Src/State.lua#L186`](../Src/State.lua#L186))
  - `State:IsIdle() → boolean`: Is the machine in IDLE state? ([`../Src/State.lua#L181`](../Src/State.lua#L181))
  - `State:IsInitialising() → boolean`: Is the machine in INITIALISING state? ([`../Src/State.lua#L170`](../Src/State.lua#L170))
  - `State:GetLogCount() → number` ([`../Src/State.lua#L312`](../Src/State.lua#L312)) — returns the number of transitions stored in the history buffer.
  - `State:GetLog(index) → table|nil` ([`../Src/State.lua#L319`](../Src/State.lua#L319)) — returns the transition log at the given index.
  - `State:GetLogs() → table` ([`../Src/State.lua#L325`](../Src/State.lua#L325)) — returns the raw circular buffer table.
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
  - `Dictionaries: table` locale → dictionary state ([`../Src/Spellcheck.lua#L43`](../Src/Spellcheck.lua#L43)).
  - `LanguageEngines: table` family → engine ([`../Src/Spellcheck.lua#L44`](../Src/Spellcheck.lua#L44)).
  - `KnownLocales: string[]` ([`../Src/Spellcheck.lua#L39-L44`](../Src/Spellcheck.lua#L39-L44)).
  - `LocaleAddons: table` locale → addon name ([`../Src/Spellcheck.lua#L49-L55`](../Src/Spellcheck.lua#L49-L55)).
  - Frame references: `EditBox`, `Overlay`, `MeasureFS`, `SuggestionFrame`, `HintFrame` ([`../Src/Spellcheck.lua#L56-L58`](../Src/Spellcheck.lua#L56-L58), [`../Src/Spellcheck.lua#L61-L67`](../Src/Spellcheck.lua#L61-L67)).
  - Suggestion state: `SuggestionRows`, `ActiveSuggestions`, `ActiveIndex`, `ActiveWord`, `ActiveRange`, `_debounceTimer` ([`../Src/Spellcheck.lua#L59-L60`](../Src/Spellcheck.lua#L59-L60), [`../Src/Spellcheck.lua#L62-L66`](../Src/Spellcheck.lua#L62-L66), [`../Src/Spellcheck.lua#L76`](../Src/Spellcheck.lua#L76)).
  - Dictionary/user state: `UserDictCache` [`../Src/Spellcheck.lua#L71`](../Src/Spellcheck.lua#L71)
  - Dictionary/user state: `_pendingLocaleLoads` [`../Src/Spellcheck.lua#L72`](../Src/Spellcheck.lua#L72)
  - Dictionary/user state: `DictionaryBuilders` [`../Src/Spellcheck.lua#L74`](../Src/Spellcheck.lua#L74)
  - Edit-distance buffers: `_ed_prev`, `_ed_cur`, `_ed_prev_prev` *private by convention; do not rely on* ([`../Src/Spellcheck.lua#L73-L75`](../Src/Spellcheck.lua#L73-L75)).
  - Tunable constants/helpers: `_SCORE_WEIGHTS`, `_MAX_SUGGESTION_ROWS`, `_RAID_ICONS`, `_DICT_CHUNK_SIZE` *private by convention; do not rely on* ([`../Src/Spellcheck.lua`](../Src/Spellcheck.lua)).
- Methods:
  - `Spellcheck:GetNgramTopCandidates() → number`: Return the clamped NgramTopCandidates config value (1-5000, default 500). ([`../Src/Spellcheck.lua#L1173`](../Src/Spellcheck.lua#L1173))
  - `Spellcheck:GetNgramMaxPosting() → number`: Return the clamped NgramMaxPosting config value (1-5000, default 500). ([`../Src/Spellcheck.lua#L1168`](../Src/Spellcheck.lua#L1168))
  - `Spellcheck:GetNgramN() → number`: Return the clamped NgramN config value (2-4, default 2). ([`../Src/Spellcheck.lua#L1163`](../Src/Spellcheck.lua#L1163))
  - `Spellcheck:GetUserDictWordCap() → number`: Returns the maximum number of words in `AddedWords` before oldest entries are FIFO-evicted. Configurable via `UserDictWordCap`; default 2000, min 50, max 10000. ([`../Src/Spellcheck.lua#L1183`](../Src/Spellcheck.lua#L1183))
  - `Spellcheck:IsWordBlocked(word, locale, ignoreManual) → boolean`: Convenience function for checking a single word (e.g., during YAS learning). ([`../Src/Spellcheck.lua#L1037`](../Src/Spellcheck.lua#L1037))
  - `Spellcheck:GetBlockData(locale) → table|nil addedSet`: Returns the data needed to check if a word is blocked at runtime. ([`../Src/Spellcheck.lua#L1018`](../Src/Spellcheck.lua#L1018))
  - `Spellcheck:EvictRandomMeta() → nil`: No description provided. ([`../Src/Spellcheck.lua#L887`](../Src/Spellcheck.lua#L887))
  - `Spellcheck:Init() → nil` ([`../Src/Spellcheck.lua#L210`](../Src/Spellcheck.lua#L210))
  - `Spellcheck:_RegisterLanguageEngine(familyId, engine, owner) → boolean` ([`../Src/Spellcheck.lua`](../Src/Spellcheck.lua)) — **Contract**: strict whitelist + type checks + runtime probes (see `Documentation/Dictionaries.md`); required fields include `NormaliseWord`, `NormaliseVowels`, `GetPhoneticHash`, `HashWord`, `BlockedHashes`, `WordBytes`, `WordStartBytes`. Owner-locks the family to the registering addon. Returns `false` and prints a chat error on any violation.
  - `Spellcheck:_ValidateEngineContract(familyId, engine) → boolean, string|nil` — the contract checker used at registration.
  - `Spellcheck:_PurgeEngine(familyId, reason) → nil` — removes a faulting engine, every dictionary bound to its family, and all derived caches; marks locales `ENGINE_PURGED`.
  - `Spellcheck:_PurgeEngineCaches(familyId) → nil` — wipes suggestion/KB/user-dict/meta caches derived from an engine.
  - `Spellcheck:_SafeEngineCall(engine, key, passSelf, ...) → any` — pcall boundary for engine entry points; purges on error.
  - `Spellcheck:_FamilyForLocale(locale) → string|nil`, `Spellcheck:_EngineForLocale(locale) → table|nil, string|nil`, `Spellcheck:_NormForLocale(locale) → function` — locale → family/engine/normaliser resolution.
  - `Spellcheck:GetActiveEngine() → table|nil` ([`../Src/Spellcheck.lua`](../Src/Spellcheck.lua)) — engine of the active locale; **nil** when none is registered (no silent fallback).
  - `Spellcheck:GetEngine(familyId) → table|nil` ([`../Src/Spellcheck.lua`](../Src/Spellcheck.lua))
  - Engine delegates (dot-call): `Spellcheck.NormaliseWord`, `Spellcheck.NormaliseVowels`, `Spellcheck.GetPhoneticHash`, `Spellcheck.IsWordByte`, `Spellcheck.IsWordStartByte` — dispatch to the active engine, neutral fallback only when no engine is loaded.
  - `Spellcheck:GetConfig() → table` ([`../Src/Spellcheck.lua#L794`](../Src/Spellcheck.lua#L794))
  - `Spellcheck:IsEnabled() → boolean` ([`../Src/Spellcheck.lua#L798`](../Src/Spellcheck.lua#L798))
  - `Spellcheck:GetLocale() → string` ([`../Src/Spellcheck.lua#L803`](../Src/Spellcheck.lua#L803))
  - `Spellcheck:GetFallbackLocale() → string` ([`../Src/Spellcheck.lua#L831`](../Src/Spellcheck.lua#L831))
  - `Spellcheck:GetDictionary() → table|nil` ([`../Src/Spellcheck.lua#L839`](../Src/Spellcheck.lua#L839))
  - `Spellcheck:GetMeta(dict, word) → table|nil` ([`../Src/Spellcheck.lua#L849`](../Src/Spellcheck.lua#L849))

  - `Spellcheck:GetUserDictStore() → table` ([`../Src/Spellcheck.lua#L925`](../Src/Spellcheck.lua#L925))
  - `Spellcheck:GetUserDict(locale) → table` ([`../Src/Spellcheck.lua#L948`](../Src/Spellcheck.lua#L948))
  - `Spellcheck:TouchUserDict(dict) → nil` ([`../Src/Spellcheck.lua#L974`](../Src/Spellcheck.lua#L974))
  - `Spellcheck:BuildWordSet(list) → table` ([`../Src/Spellcheck.lua#L983`](../Src/Spellcheck.lua#L983))
  - `Spellcheck:GetUserSets(locale) → table, table` ([`../Src/Spellcheck.lua#L998`](../Src/Spellcheck.lua#L998))
  - `Spellcheck:AddUserWord(locale, word) → nil` ([`../Src/Spellcheck.lua#L1054`](../Src/Spellcheck.lua#L1054)) — adds `word` to `AddedWords`; FIFO-evicts the oldest entry when the list exceeds `GetUserDictWordCap()`. An explicit add also lifts any YAS `rejected` re-learn block (`YAS:ClearReject`).
  - `Spellcheck:IgnoreWord(locale, word) → nil` ([`../Src/Spellcheck.lua#L1088`](../Src/Spellcheck.lua#L1088))
  - `Spellcheck:RemoveUserWord(locale, word) → nil` ([`../Src/Spellcheck.lua#L1114`](../Src/Spellcheck.lua#L1114)) — removes `word` from `AddedWords` (normalised match, all duplicates); used by the learned-word toast's Unlearn action.
  - `Spellcheck:ClearSuggestionCache() → nil` ([`../Src/Spellcheck.lua#L1133`](../Src/Spellcheck.lua#L1133))
  - Accessors: `GetMaxSuggestions` [`../Src/Spellcheck.lua#L1138`](../Src/Spellcheck.lua#L1138)
  - Accessors: `GetMaxCandidates` [`../Src/Spellcheck.lua#L1143`](../Src/Spellcheck.lua#L1143)
  - Accessors: `GetSuggestionCacheSize` [`../Src/Spellcheck.lua#L1148`](../Src/Spellcheck.lua#L1148)
  - Accessors: `GetReshuffleAttempts` [`../Src/Spellcheck.lua#L1153`](../Src/Spellcheck.lua#L1153)
  - Accessors: `GetMaxWrongLetters` [`../Src/Spellcheck.lua#L1158`](../Src/Spellcheck.lua#L1158)
  - Accessors: `GetMinWordLength` [`../Src/Spellcheck.lua#L1178`](../Src/Spellcheck.lua#L1178)
  - Accessors: `GetMisspellingColour` [`../Src/Spellcheck.lua#L1190`](../Src/Spellcheck.lua#L1190)
  - Accessors: `GetKeyboardLayout` ([`../Src/Spellcheck.lua`](../Src/Spellcheck.lua)) — resolves against the active engine's `KBLayouts`/`DefaultLayout`; nil without an engine.
  - Accessors: `GetKeyboardLayoutNames` ([`../Src/Spellcheck.lua`](../Src/Spellcheck.lua)) — sorted layout names offered by the active engine.
  - Accessors: `_GetKBDistFromLayouts` ([`../Src/Spellcheck.lua`](../Src/Spellcheck.lua)) — builds/caches a distance table from an engine's `KBLayouts`; nil when the layout is unknown.
- Callbacks fired:
  - `SPELLCHECK_WORD_ADDED`, `SPELLCHECK_WORD_IGNORED`.

## Spellcheck.Dictionary

Used lazily by `GetDictionary`, locale switches, and LOD registration.

- Description: Dictionary registration/loading, locale availability, async indexing.
- Methods:
  - `Spellcheck:LoadDictionary(locale) → nil` ([`../Src/Spellcheck/Dictionary.lua#L32`](../Src/Spellcheck/Dictionary.lua#L32))
  - `Spellcheck:RegisterDictionary(locale, data, owner) → nil` ([`../Src/Spellcheck/Dictionary.lua`](../Src/Spellcheck/Dictionary.lua)) — **Contract**: rejects dictionaries that don't resolve to a `languageFamily` with a registered, contract-valid engine (no implicit `"en"` default); indexes words through the family's engine normalisers. `owner` is the registering addon name used for the engine owner-lock.
  - `Spellcheck:_OnDictRegistrationComplete(locale) → nil` ([`../Src/Spellcheck/Dictionary.lua#L421`](../Src/Spellcheck/Dictionary.lua#L421))
  - `Spellcheck:GetAvailableLocales() → string[]` ([`../Src/Spellcheck/Dictionary.lua#L462`](../Src/Spellcheck/Dictionary.lua#L462))
  - `Spellcheck:GetLocaleAddon(locale) → string|nil` ([`../Src/Spellcheck/Dictionary.lua#L471`](../Src/Spellcheck/Dictionary.lua#L471))
  - `Spellcheck:HasLocaleAddon(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L476`](../Src/Spellcheck/Dictionary.lua#L476))
  - `Spellcheck:HasAnyDictionary() → boolean` ([`../Src/Spellcheck/Dictionary.lua#L506`](../Src/Spellcheck/Dictionary.lua#L506))
  - `Spellcheck:IsLocaleAvailable(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L518`](../Src/Spellcheck/Dictionary.lua#L518))
  - `Spellcheck:CanLoadLocale(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L532`](../Src/Spellcheck/Dictionary.lua#L532))
  - `Spellcheck:Notify(msg) → nil` ([`../Src/Spellcheck/Dictionary.lua#L547`](../Src/Spellcheck/Dictionary.lua#L547))
  - `Spellcheck:EnsureLocale(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L553`](../Src/Spellcheck/Dictionary.lua#L553))
  - `Spellcheck:ScheduleLocaleRefresh(locale) → nil` ([`../Src/Spellcheck/Dictionary.lua#L619`](../Src/Spellcheck/Dictionary.lua#L619))
  - `dict:Contains(word: string) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L237`](../Src/Spellcheck/Dictionary.lua#L237)) — returns true if the word (normalised) exists in the dictionary, its base, or the user's personal dictionary.
- Side effects:
  - Schedules `C_Timer.After(0, ...)` chunk processing and refresh tickers.

## Spellcheck.Engine

Runs during suggestion/recolour rebuild.

- Description: Tokenisation, misspelling detection, candidate scoring.
- Methods:
  - `Spellcheck:CollectAffixMatches() → nil`: Scans text for words recognized via affix-stripping. ([`../Src/Spellcheck/Engine.lua#L98`](../Src/Spellcheck/Engine.lua#L98))
  - `CollectMisspellings` [`../Src/Spellcheck/Engine.lua#L51`](../Src/Spellcheck/Engine.lua#L51)
  - `ShouldCheckWord` [`../Src/Spellcheck/Engine.lua#L119`](../Src/Spellcheck/Engine.lua#L119)
  - `ClassifyBoundary` [`../Src/Spellcheck/Engine.lua#L157`](../Src/Spellcheck/Engine.lua#L157) — boundary classification for a byte in canonical text; consults the engine's optional `ClassifyBoundary` override, then falls back to the core default (space/newline commit; `.,!?;:` and a parity-closing `"` close; an opening `"` opens). Drives autocorrect commits and autocomplete snap-back.
  - `GetIgnoredRanges` [`../Src/Spellcheck/Engine.lua#L182`](../Src/Spellcheck/Engine.lua#L182)
  - `IsRangeIgnored` [`../Src/Spellcheck/Engine.lua#L245`](../Src/Spellcheck/Engine.lua#L245)
  - `IsWordCorrect` [`../Src/Spellcheck/Engine.lua#L254`](../Src/Spellcheck/Engine.lua#L254)
  - `ResolveImplicitTrace` [`../Src/Spellcheck/Engine.lua#L293`](../Src/Spellcheck/Engine.lua#L293)
  - `UpdateActiveWord` [`../Src/Spellcheck/Engine.lua#L334`](../Src/Spellcheck/Engine.lua#L334)
  - `GetWordAtCursor` [`../Src/Spellcheck/Engine.lua#L437`](../Src/Spellcheck/Engine.lua#L437)
  - `GetSuggestions` [`../Src/Spellcheck/Engine.lua#L989`](../Src/Spellcheck/Engine.lua#L989)
  - `EditDistance` [`../Src/Spellcheck/Engine.lua#L1330`](../Src/Spellcheck/Engine.lua#L1330)
  - `FormatSuggestionLabel` [`../Src/Spellcheck/Engine.lua#L1401`](../Src/Spellcheck/Engine.lua#L1401)
- Filters run:
  - `PRE_SPELLCHECK` via `API:RunFilter`.

## Spellcheck.UI

Bound when overlay exists; reacts to text/cursor updates.

- Description: UI state machine for recolour refresh, hint, and suggestions.
- Methods:
  - `Spellcheck:GetScrollOffset() → number`: Derive the horizontal scroll offset of a single-line EditBox. ([`../Src/Spellcheck/UI.lua#L1269`](../Src/Spellcheck/UI.lua#L1269))
  - `Spellcheck:MeasureText(text) → number`: Measure text width using a FontString matching the editbox's current font and spacing. ([`../Src/Spellcheck/UI.lua#L1243`](../Src/Spellcheck/UI.lua#L1243))
  - `Spellcheck:ApplyOverlayFont(fontString, maxSize) → number`: Apply the editbox's font to a FontString, optionally clamped to maxSize. Returns the effective size. ([`../Src/Spellcheck/UI.lua#L1229`](../Src/Spellcheck/UI.lua#L1229))
  - `Spellcheck:GetCaretXOffset() → number`: Compute the X offset of the caret for tooltip positioning, clamped to the visible text area. ([`../Src/Spellcheck/UI.lua#L1202`](../Src/Spellcheck/UI.lua#L1202))
  - `Spellcheck:SetSpellcheckOffset(hintX, hintY, suggestX, suggestY) → nil`: Set manual pixel offsets for spellcheck tooltips. ([`../Src/Spellcheck/UI.lua#L578`](../Src/Spellcheck/UI.lua#L578))
  - `Bind` [`../Src/Spellcheck/UI.lua#L35`](../Src/Spellcheck/UI.lua#L35)
  - `BindMultiline` [`../Src/Spellcheck/UI.lua#L72`](../Src/Spellcheck/UI.lua#L72)
  - `UnbindMultiline` [`../Src/Spellcheck/UI.lua#L127`](../Src/Spellcheck/UI.lua#L127)
  - `UnloadAllDictionaries` [`../Src/Spellcheck/UI.lua#L162`](../Src/Spellcheck/UI.lua#L162)
  - `ApplyState` [`../Src/Spellcheck/UI.lua#L201`](../Src/Spellcheck/UI.lua#L201)
  - `OnConfigChanged` [`../Src/Spellcheck/UI.lua#L232`](../Src/Spellcheck/UI.lua#L232)
  - `OnTextChanged` [`../Src/Spellcheck/UI.lua#L236`](../Src/Spellcheck/UI.lua#L236)
  - `OnCursorChanged` [`../Src/Spellcheck/UI.lua#L277`](../Src/Spellcheck/UI.lua#L277)
  - `OnOverlayHide` [`../Src/Spellcheck/UI.lua#L315`](../Src/Spellcheck/UI.lua#L315)
  - `ScheduleRefresh` [`../Src/Spellcheck/UI.lua#L323`](../Src/Spellcheck/UI.lua#L323)
  - `Rebuild` [`../Src/Spellcheck/UI.lua#L346`](../Src/Spellcheck/UI.lua#L346)
  - `EnsureMeasureFontString` [`../Src/Spellcheck/UI.lua#L360`](../Src/Spellcheck/UI.lua#L360)
  - `EnsureSuggestionFrame` [`../Src/Spellcheck/UI.lua#L375`](../Src/Spellcheck/UI.lua#L375)
  - `SuggestionsEqual` [`../Src/Spellcheck/UI.lua#L467`](../Src/Spellcheck/UI.lua#L467)
  - `EnsureHintFrame` [`../Src/Spellcheck/UI.lua#L477`](../Src/Spellcheck/UI.lua#L477)
  - `CancelHintTimer` [`../Src/Spellcheck/UI.lua#L503`](../Src/Spellcheck/UI.lua#L503)
  - `ScheduleHintShow` [`../Src/Spellcheck/UI.lua#L515`](../Src/Spellcheck/UI.lua#L515)
  - `ShowHint` [`../Src/Spellcheck/UI.lua#L593`](../Src/Spellcheck/UI.lua#L593)
  - `HideHint` [`../Src/Spellcheck/UI.lua#L624`](../Src/Spellcheck/UI.lua#L624)
  - `UpdateHint` [`../Src/Spellcheck/UI.lua#L629`](../Src/Spellcheck/UI.lua#L629)
  - `IsSuggestionOpen` [`../Src/Spellcheck/UI.lua#L652`](../Src/Spellcheck/UI.lua#L652)
  - `IsSuggestionEligible` [`../Src/Spellcheck/UI.lua#L656`](../Src/Spellcheck/UI.lua#L656)
  - `HandleKeyDown` [`../Src/Spellcheck/UI.lua#L663`](../Src/Spellcheck/UI.lua#L663)
  - `MoveSelection` [`../Src/Spellcheck/UI.lua#L724`](../Src/Spellcheck/UI.lua#L724)
  - `RefreshSuggestionSelection` [`../Src/Spellcheck/UI.lua#L746`](../Src/Spellcheck/UI.lua#L746)
  - `OpenOrCycleSuggestions` [`../Src/Spellcheck/UI.lua#L778`](../Src/Spellcheck/UI.lua#L778)
  - `ShowSuggestions` [`../Src/Spellcheck/UI.lua#L809`](../Src/Spellcheck/UI.lua#L809)
  - `NextSuggestionsPage` [`../Src/Spellcheck/UI.lua#L944`](../Src/Spellcheck/UI.lua#L944)
  - `HideSuggestions` [`../Src/Spellcheck/UI.lua#L971`](../Src/Spellcheck/UI.lua#L971)
  - `ApplySuggestion` [`../Src/Spellcheck/UI.lua#L995`](../Src/Spellcheck/UI.lua#L995)
- Fields:
  - `HintDelay: number` ([`../Src/Spellcheck/UI.lua#L551`](../Src/Spellcheck/UI.lua#L551)).
- Callbacks fired:
  - `SPELLCHECK_SUGGESTION`, `SPELLCHECK_APPLIED`.

## Spellcheck.Recolour

Runs during `Rebuild` (same debounce cadence the old underline refresh used).

- Description: canonical-text invariant and misspelling recolour engine.
  Misspelled words are wrapped in `|cffrrggbb … |r` escapes inside the
  EditBox's own text, so the renderer owns layout (immune to scroll, resize,
  and word-wrap inaccuracy). All module logic operates on canonical
  (escape-free) text and canonical byte offsets; escapes exist only at rest
  inside the widget and `Recolour:Apply` is their sole writer.
- Methods:
  - `CanonicalText` [`../Src/Spellcheck/Recolour.lua#L60`](../Src/Spellcheck/Recolour.lua#L60)
  - `CanonicalCursorFromText` [`../Src/Spellcheck/Recolour.lua#L77`](../Src/Spellcheck/Recolour.lua#L77)
  - `CanonicalCursor` [`../Src/Spellcheck/Recolour.lua#L150`](../Src/Spellcheck/Recolour.lua#L150)
  - `CanonicalTextAndCursor` [`../Src/Spellcheck/Recolour.lua#L162`](../Src/Spellcheck/Recolour.lua#L162)
  - `ResolveColour` [`../Src/Spellcheck/Recolour.lua#L184`](../Src/Spellcheck/Recolour.lua#L184) — seam for future visibility adaptation; currently returns the configured `Spellcheck.MisspellingColour` verbatim.
  - `ColourPrefix` [`../Src/Spellcheck/Recolour.lua#L195`](../Src/Spellcheck/Recolour.lua#L195)
  - `BuildDisplayText` [`../Src/Spellcheck/Recolour.lua#L216`](../Src/Spellcheck/Recolour.lua#L216)
  - `ToDisplayCursor` [`../Src/Spellcheck/Recolour.lua#L248`](../Src/Spellcheck/Recolour.lua#L248)
  - `Apply` [`../Src/Spellcheck/Recolour.lua#L350`](../Src/Spellcheck/Recolour.lua#L350) — diff-before-SetText is the recursion loop-breaker and caret-stability guarantee.
  - `Clear` [`../Src/Spellcheck/Recolour.lua#L392`](../Src/Spellcheck/Recolour.lua#L392)
  - `Invalidate` [`../Src/Spellcheck/Recolour.lua#L412`](../Src/Spellcheck/Recolour.lua#L412)
- Invariants:
  - Outgoing text is stripped at `Chat:SendPosts` entry and at Blizzard
    handoff writes; drafts/history are always stored canonical.

## Spellcheck.YAS

Initialised from `Spellcheck:Init` when present.

- Description: Adaptive learning model for frequency/bias and auto-promote.
- Fields:
  - `Spellcheck.YAS: table` ([`../Src/Spellcheck/Adaptive.lua#L8`](../Src/Spellcheck/Adaptive.lua#L8)).
- Locale store shape (`_G.YapperDB.SpellcheckLearned[locale]`):
  - `freq[word] = { c, t }` — usage count and last-seen timestamp.
  - `bias["typo:correction"] = { c, t, u }` — direct correction preference, count, timestamp, utility weight.
  - `phBias["phoneticHash:correction"] = { c, t }` — generalised phonetic correction memory.
  - `negBias["typo:word"] = { c, t, u }` — rejected suggestion penalties; penalty decays exponentially with age (~30-day half-life).
  - `rejected[word] = { t }` — words the user unlearned via the toast; blocks organic auto-promotion for ~30 days (`REJECT_BLOCK_AGE`). Explicit Add-to-Dictionary lifts it via `YAS:ClearReject`.
  - `auto[word] = { c, t }` — repeated uncorrected words pending auto-promotion.
  - `intent[token] = { c, t, sentUnchanged, waived, accepted, corrected, lastSeen, pinned? }` — per-token intent evidence. `pinned` is set by explicit user actions (Add to Dictionary → `INTENTIONAL`, Ignore Word → `WAIVER`) and by auto-promotion; pinned records are immune to pruning.
  - `intentCount: number` — cached count of `intent` entries.
  - `bigram[prev][next] = { c, t }` — context transitions between sane tokens; sentence-initial words use the `"<s>"` pseudo-token.
  - `bigramCount: number` — cached total transition count.
  - `errProfile = { ops, conf }` — habitual error classes (`transpose`/`substitute`/`insert`/`delete`/`other` counts) plus byte-level confusion pairs (`"o>a"`).
  - `autoCount: number` — cached count of `auto` entries (maintained for O(1) cap checks).
  - `negBiasCount: number` — cached count of `negBias` entries.
  - `total: number` — tracked unique vocabulary size for frequency-cap enforcement.
  ([`../Src/Spellcheck/Adaptive.lua#L63-L100`](../Src/Spellcheck/Adaptive.lua#L63-L100)).
- Methods:
  - `YAS:GetAutoCap() → number`: Returns the maximum number of entries tracked in the `auto` table before low-scoring ones are pruned. Configurable via `YASAutoCap`; default 500, min 50, max 5000. ([`../Src/Spellcheck/Adaptive.lua#L169`](../Src/Spellcheck/Adaptive.lua#L169))
  - `YAS:GetNegBiasCap() → number`: Returns the maximum number of `negBias` rejection-pair entries before low-scoring ones are pruned. Configurable via `YASNegBiasCap`; default 500, min 100, max 10000. ([`../Src/Spellcheck/Adaptive.lua#L162`](../Src/Spellcheck/Adaptive.lua#L162))
  - `YAS:Export() → nil`: Export current learned data for a locale as a text block. ([`../Src/Spellcheck/Adaptive.lua#L2132`](../Src/Spellcheck/Adaptive.lua#L2132))
  - `YAS:GetBiasTargets() → nil`: Returns a list of candidate words that have been learned as corrections for the given typo. ([`../Src/Spellcheck/Adaptive.lua#L1370`](../Src/Spellcheck/Adaptive.lua#L1370))
  - `YAS:EnsureFreqSorted() → nil`: Ensures the frequency-sorted index is up-to-date, rebuilding if dirty. ([`../Src/Spellcheck/Adaptive.lua#L520`](../Src/Spellcheck/Adaptive.lua#L520))
  - `IsEnabled() → boolean`: Returns true if YAS is enabled in the configuration. ([`../Src/Spellcheck/Adaptive.lua#L132`](../Src/Spellcheck/Adaptive.lua#L132))
  - `YAS:GetFreqCap()` ([`../Src/Spellcheck/Adaptive.lua#L122`](../Src/Spellcheck/Adaptive.lua#L122))
  - `YAS:GetBiasCap()` ([`../Src/Spellcheck/Adaptive.lua#L129`](../Src/Spellcheck/Adaptive.lua#L129))
  - `YAS:GetAutoThreshold()` ([`../Src/Spellcheck/Adaptive.lua#L136`](../Src/Spellcheck/Adaptive.lua#L136))
  - `YAS:GetIntentCap() → number` ([`../Src/Spellcheck/Adaptive.lua#L176`](../Src/Spellcheck/Adaptive.lua#L176)) — cap on `intent` records; configurable via `YASIntentCap`, default 1000, min 100, max 10000.
  - `YAS:GetBigramCap() → number` ([`../Src/Spellcheck/Adaptive.lua#L184`](../Src/Spellcheck/Adaptive.lua#L184)) — cap on bigram transitions; configurable via `YASBigramCap`, default 2000, min 200, max 20000.
  - `YAS:RecordExposure(word, locale)` ([`../Src/Spellcheck/Adaptive.lua#L699`](../Src/Spellcheck/Adaptive.lua#L699)) — session-only exposure credit: the suggestion popup is visible for this token now. Consumed by the next `RecordIgnored` for the same token; stale entries (>30s or >200 tracked) are dropped opportunistically.
  - `YAS:GetIntent(word, locale) → "ACCIDENT"|"WAIVER"|"INTENTIONAL"|nil` ([`../Src/Spellcheck/Adaptive.lua#L910`](../Src/Spellcheck/Adaptive.lua#L910)) — classify a token. Order: pin → any correction evidence (ACCIDENT) → ≥3 consistent unchanged sends (INTENTIONAL) → seen-and-sent-unchanged (WAIVER) → unclassified.
  - `YAS:PinIntent(word, class, locale)` ([`../Src/Spellcheck/Adaptive.lua#L734`](../Src/Spellcheck/Adaptive.lua#L734)) — permanent intent pin from explicit user actions.
  - `YAS:PruneBigrams(limit, locale)` ([`../Src/Spellcheck/Adaptive.lua#L1258`](../Src/Spellcheck/Adaptive.lua#L1258)) — evicts lowest-scored transitions to ~90% of the cap; empty buckets are dropped.
  - `YAS:StartConsolidation(locale)` / `YAS:_ConsolidationStep()` ([`../Src/Spellcheck/Adaptive.lua#L1305`](../Src/Spellcheck/Adaptive.lua#L1305)) — chunked background maintenance (≤200 entries/tick): halves cold counts (30d+), evicts stale unclassified intent (60d+), prunes bigrams/confusion pairs to cap. `C_Timer`-driven in-game; `_ConsolidationStep` is directly callable for deterministic tests.
  - `YAS:Init()` ([`../Src/Spellcheck/Adaptive.lua#L212`](../Src/Spellcheck/Adaptive.lua#L212)) — parks flat pre-partition data under `_legacy`; the first real locale partition folds it in via merge.
  - `YAS:GetLocaleDB(locale, noCreate)` ([`../Src/Spellcheck/Adaptive.lua#L245`](../Src/Spellcheck/Adaptive.lua#L245)) — nil locale resolves to the active spellcheck locale; pre-locale writes park under `_pending`. Read hot paths pass `noCreate=true` so lookups never allocate SavedVars tables. Stranded partitions (`_legacy`, `enBASE`, `enBase`, `_pending`) merge into the first real locale that asks.
  - `YAS:EnsureFreqSorted(locale)` ([`../Src/Spellcheck/Adaptive.lua#L306`](../Src/Spellcheck/Adaptive.lua#L306))
  - `YAS:IsSaneWord(w, locale)` ([`../Src/Spellcheck/Adaptive.lua#L338`](../Src/Spellcheck/Adaptive.lua#L338)) — consonant-cluster, keyboard-smash, engine veto, then an n-gram anchor against `"ngramIndex" .. GetNgramN()` (dynamic index name; check skipped while the index is absent during LOD).
  - `YAS:RecordUsage(text, locale)` ([`../Src/Spellcheck/Adaptive.lua#L563`](../Src/Spellcheck/Adaptive.lua#L563)) — records freq plus `prev→next` bigram transitions (only between sane tokens; `<s>` marks openers); bumps `db._rev` on any scoring-relevant write.
  - `YAS:RecordSelection(typo, correction, utilityGain, locale)` ([`../Src/Spellcheck/Adaptive.lua#L460`](../Src/Spellcheck/Adaptive.lua#L460))
  - `YAS:RecordImplicitCorrection(typo, correction, candidates, locale)` ([`../Src/Spellcheck/Adaptive.lua#L539`](../Src/Spellcheck/Adaptive.lua#L539))
  - `YAS:RecordRejection(typo, candidates, locale)` ([`../Src/Spellcheck/Adaptive.lua#L628`](../Src/Spellcheck/Adaptive.lua#L628)) — bumps `db._rev` on negBias writes. On an `INTENTIONAL` token the rejection is waiver evidence only — no `negBias` is written ("stop suggesting" semantics).
  - `YAS:RecordIgnored(word, locale)` ([`../Src/Spellcheck/Adaptive.lua#L664`](../Src/Spellcheck/Adaptive.lua#L664)) — gated by `IsEnabled()` like every other entry point; decrements `autoCount` on promotion. Auto-promotion additionally requires the token to classify `INTENTIONAL` — a correction event anywhere in the token's history blocks promotion permanently.
  - `YAS:GetBonus(cand, typo, typoPhHash, locale, prevWord)` ([`../Src/Spellcheck/Adaptive.lua#L1090`](../Src/Spellcheck/Adaptive.lua#L1090))
  - `YAS:Prune(tableName, limit, locale)` ([`../Src/Spellcheck/Adaptive.lua#L816`](../Src/Spellcheck/Adaptive.lua#L816))
  - `YAS:Reset(locale)` ([`../Src/Spellcheck/Adaptive.lua#L861`](../Src/Spellcheck/Adaptive.lua#L861))
  - `YAS:GetDataSummary(locale)` ([`../Src/Spellcheck/Adaptive.lua#L877`](../Src/Spellcheck/Adaptive.lua#L877))
  - `YAS:ClearSpecificUsage(usageType, key, locale)` ([`../Src/Spellcheck/Adaptive.lua#L970`](../Src/Spellcheck/Adaptive.lua#L970)) — supports `freq`/`bias`/`auto`/`phBias`/`negBias`; maintains cached counters and bumps `_rev` for scoring-relevant tables.
- Score model:
  - `GetBonus` sums six feature terms — `freqBonus`, `biasBonus`, `phBonus`, `negBias` penalty, `bigramBonus` (context: candidate follows the observed prev→next transition), `errAffinity` (candidate's required edit matches the user's habitual error class) — each as `WEIGHT_i * f_i * m_i`. The `negBias` penalty is time-decayed: `penalty × 1/(ageDays/30 + 1)`, halving roughly every 30 days. The suggestion cache key includes the normalised `prevWord` so context-sensitive scoring cannot collide across contexts.
  - Learned scorer (`db.model`): the per-feature multipliers `m_i` start at 1.0 (= frozen WEIGHTS behaviour) and get bounded perceptron updates — `RecordSelection` reinforces the accepted candidate's feature vector, `RecordRejection` dampens rejected candidates (≤5 per call). `lr = 0.02 / (1 + updates/500)`, multipliers clamped to [0.25, 4.0]. `FeatureVector` is shared between scoring and updates so both paths agree exactly.
  - Self-eval: a YAS-surfaced pick (`utilityGain > 0`) is remembered in the session-only `YAS._lastPromoted` map; if the same token is later manually re-corrected to a *different* word it counts as `retypeAfterPromoted`. Once ≥20 promoted picks have a ≥40% re-correction ratio, all multipliers regress halfway toward 1.0 and the eval counters reset — the model's own circuit breaker against overreach.
- Autocorrect decision machinery:
  - `YAS:ClassifySuggestion(typo, candidate, locale, prevWord)` returns `{ suggestion, confidence, tier, vetoReasons }`. Tiers: `AUTO` (≥0.8 conf, no vetoes), `SUGGEST` (≥0.4), `OFFER`, `SUPPRESS` (INTENTIONAL/WAIVER intent is a permanent hard veto). Confidence mixes learned evidence (bias/freq/phonetic/bigram, minus a decaying `negBias` rejection penalty) with `MechanicalTypoPrior` — a cold-start prior that pushes clean single-op edits (adjacent transposition, single insert/delete/substitute on 4+ char words) to AUTO with no history. When the engine ships `KBLayouts`, the substitution prior is gated on key adjacency under the active layout: adjacent swapped keys keep the full prior, distant keys get a weaker signal instead (doign->doing stays AUTO; doign->deign does not). Engine `Autocorrect.AutocorrectVeto`/`MaxConfidence` are honoured; a hot re-correction ratio suspends AUTO. `Spellcheck.Autocorrect` applies only `AUTO`-tier results.
  - `YAS:ShadowClassify(typo, candidate, locale, prevWord)` — opt-in via `Config.Spellcheck.YASAutocorrectShadow`; classifies and appends to a bounded `db.autocorrLog` ring (50 entries). Called for the top candidate in `Spellcheck.Engine`'s suggestion path.
  - `YAS:PushUndo(entry)`/`YAS:PopUndo()`/`YAS:PeekUndo()` — session-only LIFO ring (50) of revertable applied corrections; `PeekUndo` lets a toast validate it still targets the newest correction before reverting. ([`../Src/Spellcheck/Adaptive.lua#L1485`](../Src/Spellcheck/Adaptive.lua#L1485), [`../Src/Spellcheck/Adaptive.lua#L1516`](../Src/Spellcheck/Adaptive.lua#L1516)).
  - `YAS:RecordAutoReject(typo, correction, locale)` ([`../Src/Spellcheck/Adaptive.lua#L1532`](../Src/Spellcheck/Adaptive.lua#L1532)) — the user reverted an applied autocorrection: intent `corrected` bump on the typo (halves that pair's future confidence via `veto.recentRecorrect`), `negBias` on the pair, `retypeAfterPromoted` self-eval credit, and a negative model update. A later manual pick of the same pair via `RecordSelection` (suggestion click or implicit retype) clears the `negBias` entry and the session suppression — the pair returns to AUTO eligibility.
  - `YAS:UnlearnWord(word, locale)` ([`../Src/Spellcheck/Adaptive.lua#L1590`](../Src/Spellcheck/Adaptive.lua#L1590)) — forget a learned word entirely: removes it from `AddedWords`, `freq` and `auto`, then stamps `db.rejected` so organic learning can't re-promote it for ~30 days.
  - `YAS:ClearReject(word, locale)` ([`../Src/Spellcheck/Adaptive.lua#L1625`](../Src/Spellcheck/Adaptive.lua#L1625)) — lifts an Unlearn block; called by `Spellcheck:AddUserWord`.
- Learning entry points:
  - `Chat:DirectSend` records usage and ignored-word counts ([`../Src/Chat.lua#L199-L215`](../Src/Chat.lua#L199-L215)).
  - `Spellcheck.UI` records explicit suggestion picks/rejections ([`../Src/Spellcheck/UI.lua#L869-L962`](../Src/Spellcheck/UI.lua#L869-L962)).
  - `Spellcheck.Engine` records implicit corrections from retyped trace words ([`../Src/Spellcheck/Engine.lua#L236-L238`](../Src/Spellcheck/Engine.lua#L236-L238)).
- Invariants / safeguards:
  - `IsSaneWord` gates noisy tokens before learning; pruning preserves highest relevance entries by count/utility/recency score; caps/thresholds are clamped from config (`YASEnabled`, `YASFreqCap`, `YASBiasCap`, `YASNegBiasCap`, `YASAutoThreshold`, `YASAutoCap`) ([`../Src/Spellcheck/Adaptive.lua#L130-L170`](../Src/Spellcheck/Adaptive.lua#L130-L170), [`../Src/Spellcheck/Adaptive.lua#L269-L310`](../Src/Spellcheck/Adaptive.lua#L269-L310), [`../Src/Core.lua#L217-L224`](../Src/Core.lua#L217-L224)).
- Callbacks fired:
  - `YAS_WORD_LEARNED` (deprecated `YALLM_WORD_LEARNED` is automatically aliased to this event).

## Spellcheck.Autocorrect

Editing-stage autocorrect; opt-in via `Config.Spellcheck.AutocorrectEnabled` (requires spellcheck + YAS). Driven from `Spellcheck:OnTextChanged` — works identically in the single-line overlay and the multiline editor because both rebind `Spellcheck.EditBox`.

- Description: Applies `AUTO`-tier corrections the moment a word is completed by a commit/close boundary; tracks every applied correction for reversion.
- Methods:
  - `Autocorrect:IsEnabled()` [`../Src/Spellcheck/Autocorrect.lua#L55`](../Src/Spellcheck/Autocorrect.lua#L55) — config flag + spellcheck + YAS enabled.
  - `Autocorrect:OnUserTextChanged(editBox, text, cursor) → boolean` [`../Src/Spellcheck/Autocorrect.lua#L92`](../Src/Spellcheck/Autocorrect.lua#L92) — runs before the boundary check on every user edit. Stateless backspace-revert detection: recognises "the stored post-apply text minus its boundary byte, caret at `eApplied`" rather than an armed flag, so WoW's `OnCursorChanged`/`OnTextChanged` ordering cannot break it.
  - `Autocorrect:OnBoundaryCommit(editBox, text, cursor)` [`../Src/Spellcheck/Autocorrect.lua#L113`](../Src/Spellcheck/Autocorrect.lua#L113) — evaluates the word before a `"commit"`/`"close"` boundary through `GetSuggestions` + `YAS:ClassifySuggestion` over the top five candidates, applying the highest-confidence AUTO (ties keep dictionary rank). Guards: slash commands, mid-word boundaries (the byte after the boundary must be non-word/EOL), already-correct words, ignored words, suppressed pairs (skipped per-candidate). Temporarily lends `Spellcheck.ActiveRange`/`EditBox` to the call so bigram context and the suggestion-cache key match the panel's.
  - `Autocorrect:LiveCorrectionAt(editBox, s, e) → corr|nil` [`../Src/Spellcheck/Autocorrect.lua#L65`](../Src/Spellcheck/Autocorrect.lua#L65) — newest un-reverted correction overlapping a word range; lets `UpdateActiveWord` keep a corrected word "active" so the suggestion popup can offer `Restore "<original>"` (entry `kind = "revert"`).
  - `Autocorrect:RevertCorrection(editBox, corr, source) → boolean` [`../Src/Spellcheck/Autocorrect.lua#L273`](../Src/Spellcheck/Autocorrect.lua#L273) — validates the applied word still sits at its recorded range (a drifted edit refuses), splices the original back, preserves the caret when it sat past the correction, then `_FlagReverted` (session pair suppression + `YAS:RecordAutoReject`).
  - `Autocorrect:OnUndo(editBox, prevText, restoredText)` [`../Src/Spellcheck/Autocorrect.lua#L314`](../Src/Spellcheck/Autocorrect.lua#L314) — called by `History:Undo`; an exact `after → before` transition flags the correction reverted.
  - `Autocorrect:UndoByToast(entry) → boolean` [`../Src/Spellcheck/Autocorrect.lua#L350`](../Src/Spellcheck/Autocorrect.lua#L350) — toast Undo; refuses unless `YAS:PeekUndo()` still returns this entry, so a stale card can't pop a newer correction.
  - `Autocorrect:ClearSuppression(typo, correction)` [`../Src/Spellcheck/Autocorrect.lua#L305`](../Src/Spellcheck/Autocorrect.lua#L305) — lifts the session suppression for a pair; called by `YAS:RecordSelection` when the user manually re-corrects a reverted pair.
- Fields:
  - `_corrections` — session ring (cap 20) of live corrections `{box, s, eApplied, original, applied, before, after, undoEntry, reverted, time}`.
  - `_suppressed` — `"typo\0correction"` set; a reverted pair never re-applies for the rest of the session unless the user manually picks the same correction again (which also clears the `negBias` entry).
- Callbacks fired:
  - `AUTOCORRECT_APPLIED`.

## IconGallery

Lazy-created; used by spellcheck/autocomplete edit flows and public API.

- Description: Raid icon picker popup and selection callbacks.
- Methods:
  - `Init` ([`../Src/IconGallery.lua#L18`](../Src/IconGallery.lua#L18))
  - `Show` ([`../Src/IconGallery.lua#L77`](../Src/IconGallery.lua#L77))
  - `Hide` ([`../Src/IconGallery.lua#L107`](../Src/IconGallery.lua#L107))
  - `Filter` ([`../Src/IconGallery.lua#L119`](../Src/IconGallery.lua#L119))
  - `Select` ([`../Src/IconGallery.lua#L145`](../Src/IconGallery.lua#L145))
  - `HandleKeyDown` ([`../Src/IconGallery.lua#L170`](../Src/IconGallery.lua#L170))
  - `_GetIconMeta` ([`../Src/IconGallery.lua#L213`](../Src/IconGallery.lua#L213))
  - `OnTextChanged` ([`../Src/IconGallery.lua#L224`](../Src/IconGallery.lua#L224))
- Callbacks fired:
  - `ICON_GALLERY_SHOW`, `ICON_GALLERY_HIDE`, `ICON_GALLERY_SELECT`.

## EditBox
- Methods:
  - `EditBox:ResolveWhisperTarget(chatType, source, fallback) → any target, boolean isSecure`: Source a whisper target directly from Blizzard's secure last-tell state (GetLastTellTarget/GetLastToldTarget), bypassing Yapper-stored copies that may have become tainted. Used by the `/r` and `/r2` send path. Returns `(fallback, false)` when Blizzard has no matching target. ([`../Src/EditBox.lua#L463`](../Src/EditBox.lua#L463))
  - `EditBox:GetActiveEditor() → table|nil`: Return Yapper's currently visible chat editor, preferring multiline while it is open and falling back to the single-line overlay. ([`../Src/EditBox.lua#L95`](../Src/EditBox.lua#L95))
  - `EditBox:IsChatTypeAvailable(chatType) → boolean`: Check if a chat type is currently available (e.g., in a guild, in a raid). ([`../Src/EditBox.lua#L661`](../Src/EditBox.lua#L661))
  - `EditBox:GetResolvedChatType(ct) → string`: Smartly switch from Party/Raid to Instance if the Home group is missing. ([`../Src/EditBox.lua#L639`](../Src/EditBox.lua#L639))
  - `EditBox:RegisterKeybindOverrides() → nil`: Register keybind overrides when timing is safe. ([`../Src/EditBox.lua#L760`](../Src/EditBox.lua#L760))
  - `EditBox:InitKeybinds() → nil`: Initialize keybind override system. ([`../Src/EditBox.lua#L750`](../Src/EditBox.lua#L750))
  - `EditBox:UpdateFocusOverride() → nil`: Centralize focus override updating. Sets/clears CHAT_FOCUS_OVERRIDE ([`../Src/EditBox.lua#L108`](../Src/EditBox.lua#L108))
  - `YapperTable.InstallCompatMethods(box) → nil`: Installs Blizzard chat-box compatibility methods and stubs on the overlay editbox so addons can query `GetChatType`, `GetChannelTarget`, `GetTellTarget`, `GetLanguage`, `GetAttribute`, and parity fields without nil-crashes. ([`../Src/EditBoxCompat.lua#L32`](../Src/EditBoxCompat.lua#L32))
  - `box.UpdateHeader`: no-op stub installed by InstallCompatMethods to prevent nil-method crashes from Blizzard's chat-frame utility. ([`../Src/EditBoxCompat.lua#L75`](../Src/EditBoxCompat.lua#L75))
  - `box.SetFocusRegionsShown`: no-op stub installed by `InstallCompatMethods`. ([`../Src/EditBoxCompat.lua#L32`](../Src/EditBoxCompat.lua#L32))
  - `box.UpdateNewcomerEditBoxHint`: no-op stub installed by `InstallCompatMethods`. ([`../Src/EditBoxCompat.lua#L32`](../Src/EditBoxCompat.lua#L32))
  - `box:ParseText(send) → nil`: Execute slash lines through Yapper's forwarding path while leaving plain text for Blizzard's SendText dispatch. ([`../Src/EditBoxCompat.lua#L91`](../Src/EditBoxCompat.lua#L91))
  - `box:GetAttribute() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L46`](../Src/EditBoxCompat.lua#L46))
  - `box:GetLanguage() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L44`](../Src/EditBoxCompat.lua#L44))
  - `box:GetTellTarget() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L42`](../Src/EditBoxCompat.lua#L42))
  - `box:GetChannelTarget() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L40`](../Src/EditBoxCompat.lua#L40))
  - `box:GetChatType() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L38`](../Src/EditBoxCompat.lua#L38))

Overlay root; hooked on `PLAYER_ENTERING_WORLD` via `HookAllChatFrames`.

- Description: Core overlay state and high-level editbox operations.
- Fields:
  - Runtime frames/state: `Overlay` [`../Src/EditBox.lua#L25`](../Src/EditBox.lua#L25)
  - Runtime frames/state: `OverlayEdit` [`../Src/EditBox.lua#L26`](../Src/EditBox.lua#L26)
  - Runtime frames/state: `ChannelLabel` [`../Src/EditBox.lua#L27`](../Src/EditBox.lua#L27)
  - Runtime frames/state: `LabelBg` [`../Src/EditBox.lua#L28`](../Src/EditBox.lua#L28)
  - Runtime frames/state: `OrigEditBox` [`../Src/EditBox.lua#L32`](../Src/EditBox.lua#L32)
  - Runtime frames/state: `ChatType` [`../Src/EditBox.lua#L33`](../Src/EditBox.lua#L33)
  - Runtime frames/state: `Language` [`../Src/EditBox.lua#L34`](../Src/EditBox.lua#L34)
  - Runtime frames/state: `Target` [`../Src/EditBox.lua#L35`](../Src/EditBox.lua#L35)
  - Runtime frames/state: `ChannelName` [`../Src/EditBox.lua#L36`](../Src/EditBox.lua#L36)
  - State tables: `HookedBoxes`, `LastUsed`, `ReplyQueue`, `_attrCache` ([`../Src/EditBox.lua#L30-L40`](../Src/EditBox.lua#L30-L40), [`../Src/EditBox.lua#L41`](../Src/EditBox.lua#L41)).
  - History pointers: `HistoryIndex` [`../Src/EditBox.lua#L38`](../Src/EditBox.lua#L38)
  - History pointers: `HistoryCache` [`../Src/EditBox.lua#L39`](../Src/EditBox.lua#L39)
  - History pointers: `HistoryDraft` [`../Src/EditBox.lua#L40`](../Src/EditBox.lua#L40) — stashed in-progress text, restored when navigating back past the newest entry
  - `_lockdown`, `_overlayUnfocused` *private by convention; do not rely on* ([`../Src/EditBox.lua#L44-L56`](../Src/EditBox.lua#L44-L56)).
  - Internal constants/closures exported for submodules (`_UserBypassingYapper`, `_SetUserBypassingYapper`, `_BypassEditBox`, `_SetBypassEditBox`, `_SLASH_MAP`, `_TAB_CYCLE`, `_LABEL_PREFIXES`, `_GROUP_CHAT_TYPES`, `_CHATTYPE_TO_OVERRIDE_KEY`, `_REPLY_QUEUE_MAX`) *private by convention; do not rely on* ([`../Src/EditBox.lua#L329-L338`](../Src/EditBox.lua#L329-L338)).
  - Internal helper exports: `IsWhisperSlashPrefill` [`../Src/EditBox.lua#L607`](../Src/EditBox.lua#L607)
  - Internal helper exports: `ExtractRegionalWhisperTarget` — port of Blizzard's `ExtractTellTarget` for `RegionalUniqueNamesEnabled()` clients (WoW: Forever); resolves "First Last"/"First-Last" targets by longest autocomplete-matching prefix and returns nil while the surname is still being typed [`../Src/EditBox.lua#L280`](../Src/EditBox.lua#L280)
  - Internal helper exports: `ParseWhisperSlash` — one-token target on retail; delegates to `ExtractRegionalWhisperTarget` when regional unique names are enabled [`../Src/EditBox.lua#L608`](../Src/EditBox.lua#L608)
  - Internal helper exports: `GetLastTellTargetInfo` — returns chatType and name of the last person who whispered *you* [`../Src/EditBox.lua#L611`](../Src/EditBox.lua#L611)
  - Internal helper exports: `GetLastToldTargetInfo` — returns chatType and name of the last person *you* whispered (outgoing). Uses `ChatFrameUtil.GetLastToldTarget`; stays in sync with both Yapper and Blizzard sends. [`../Src/EditBox.lua#L391`](../Src/EditBox.lua#L391)
  - Internal helper exports: `SetFrameFillColour` [`../Src/EditBox.lua#L613`](../Src/EditBox.lua#L613)
- Methods:
  - `ClearLockdownState` ([`../Src/EditBox.lua#L80`](../Src/EditBox.lua#L80))
  - `AddReplyTarget` ([`../Src/EditBox.lua#L133`](../Src/EditBox.lua#L133))
  - `NextReplyTarget` ([`../Src/EditBox.lua#L158`](../Src/EditBox.lua#L158))
  - `OpenBlizzardChat` ([`../Src/EditBox.lua#L488`](../Src/EditBox.lua#L488))
  - `SetOnSend` ([`../Src/EditBox.lua#L683`](../Src/EditBox.lua#L683))
  - `EditBox:SyncLanguageFromNative(blizzEditBox) → boolean`: Reconcile languageID changes made directly by Blizzard or another addon with Yapper's active and persisted language state. ([`../Src/EditBox.lua#L691`](../Src/EditBox.lua#L691))
  - `SetPreShowCheck` ([`../Src/EditBox.lua#L745`](../Src/EditBox.lua#L745))
- Invariants:
  - Overlay behaviour valid only after `HookAllChatFrames()` has run.

## EditBox.SkinProxy

Attached during overlay show lifecycle.

- Description: Keeps Blizzard's native editbox skin visible underneath the Yapper overlay.
- Methods:
  - `EditBox:EnsureProxyHeaderHidden() → nil`: Re-hide Blizzard header/prompt elements after native header updates. ([`../Src/EditBox/SkinProxy.lua#L24`](../Src/EditBox/SkinProxy.lua#L24))
  - `EditBox:ApplyProxyMode() → nil`: Activate proxy mode and preserve the original editbox state. ([`../Src/EditBox/SkinProxy.lua#L42`](../Src/EditBox/SkinProxy.lua#L42))
  - `EditBox:RestoreProxyMode() → nil`: Restore the original editbox to the state found before proxy mode. ([`../Src/EditBox/SkinProxy.lua#L110`](../Src/EditBox/SkinProxy.lua#L110))

## EditBox.Overlay

Used by `EditBox:Show` to create and refresh frame contents.

- Description: Overlay frame creation and label/font rendering helpers.
- Fields:
  - `_RefreshOverlayVisuals`, `_ApplyShadowTint`, `_ResolveChannelName`, `_BuildLabelText`, `_GetLabelUsableWidth`, `_ResetLabelToBaseFont`, `_TruncateLabelToWidth`, `_FitLabelFontToWidth`, `_UpdateLabelBackgroundForText` *private by convention; do not rely on* ([`../Src/EditBox/Overlay.lua#L812-L820`](../Src/EditBox/Overlay.lua#L812-L820)).
- Methods:
  - `EditBox:ShowMultilineHint() → nil`: Show the onboarding hint once during the current session and let it fade ([`../Src/EditBox/Overlay.lua#L534`](../Src/EditBox/Overlay.lua#L534))
  - `EditBox:CreateMultilineHint() → nil`: Create the non-interactive hint frame lazily, using UIParent as its parent ([`../Src/EditBox/Overlay.lua#L501`](../Src/EditBox/Overlay.lua#L501))
  - `EditBox:HideMultilineHint() → nil`: Cancel and hide the session-only multiline onboarding hint. ([`../Src/EditBox/Overlay.lua#L483`](../Src/EditBox/Overlay.lua#L483))
  - `EditBox:CreateOverlay() → nil` ([`../Src/EditBox/Overlay.lua#L671`](../Src/EditBox/Overlay.lua#L671)).

## EditBox.Handlers

Bound by `SetupOverlayScripts` when overlay is created.

- Description: Input handlers for Enter/Tab/history/channel switching.
- Methods:
  - `SetupOverlayScripts` ([`../Src/EditBox/Handlers.lua#L41`](../Src/EditBox/Handlers.lua#L41)).
  - `ResetLockdownIdleTimer` ([`../Src/EditBox/Handlers.lua#L1132`](../Src/EditBox/Handlers.lua#L1132)).
- Callbacks fired:
  - `EDITBOX_CHANNEL_CHANGED` (via downstream hooks).

## Hooks.Hub

Shared locals hub for all EditBox hook modules.

- Description: Centralizes shared locals pattern via `YapperTable.EditBoxHooksCore`.
- File: [`../Src/Hooks/Hub.lua`](../Src/Hooks/Hub.lua)

## Hooks.ShowHide

Show/hide lifecycle and overlay management.

- Description: Show(), Hide(), HandoffToBlizzard(), ApplyConfigToLiveOverlay().
- File: [`../Src/Hooks/ShowHide.lua`](../Src/Hooks/ShowHide.lua)
- Methods:
  - `EditBox:RecordFallbackSend(editBox) → nil`: Record a message sent through Blizzard's native editbox during lockdown, bypass, or handoff fallback into persistent history. ([`../Src/Hooks/ShowHide.lua#L1049`](../Src/Hooks/ShowHide.lua#L1049))
  - `EditBox:RetargetOpenWhisper(target, blizzBox, chatType) → boolean`: Retarget the already-open overlay onto an external transient whisper; supports character names and numeric Battle.net account IDs. ([`../Src/Hooks/ShowHide.lua#L1000`](../Src/Hooks/ShowHide.lua#L1000))
  - `EditBox:IsNativeChatEditBox(eb) → boolean`: True only for Blizzard's native ChatFrameN editboxes (never our overlay). ([`../Src/Hooks/ShowHide.lua#L987`](../Src/Hooks/ShowHide.lua#L987))
  - `EditBox:Show(origEditBox)` - Present overlay in place of Blizzard editbox.
  - `EditBox:Hide(isHandoff)` - Close overlay, save state.
  - `EditBox:HandoffToBlizzard(silent?, bypassOpen?, isMultiline?)` - Lockdown handoff.
  - `EditBox:ApplyConfigToLiveOverlay(force?)` - Re-apply config to visible overlay.

## Hooks.Label

Channel label and tab cycling.

- Description: RefreshLabel(), CycleChatType(), RecordTabChannel(), PersistLastUsed(), OnTabPressed().
- File: [`../Src/Hooks/Label.lua`](../Src/Hooks/Label.lua)
- Methods:
  - `EditBox:ResyncFromBlizzardAfterLockdown() → boolean`: Pull safe native channel state (chatType, tellTarget, channelTarget, language) back into Yapper from Blizzard's editbox attributes after lockdown recovery. Returns false when attributes are missing or secret-tainted. Called from the lockdown-recovery path in Handlers. ([`../Src/Hooks/Label.lua#L380`](../Src/Hooks/Label.lua#L380))
  - `EditBox:ResetSyncedAttributes() → nil`: Inverse of SyncAttributesToBlizzard: restore the Blizzard editbox to a neutral state and clear cached native attributes. ([`../Src/Hooks/Label.lua#L335`](../Src/Hooks/Label.lua#L335))
  - `EditBox:SyncAttributesToBlizzard(allowLockdown) → nil`: Push Yapper's current chatType, target, channel and language into Blizzard's native editbox when safe. Whisper attributes remain owned by Blizzard to avoid taint. ([`../Src/Hooks/Label.lua#L245`](../Src/Hooks/Label.lua#L245))
  - `EditBox:GetAvailableChatTypes() → table`: Return the subset of TAB_CYCLE entries currently available to the player. ([`../Src/Hooks/Label.lua#L422`](../Src/Hooks/Label.lua#L422))
  - `EditBox:RefreshLabel()` - Update channel label text/color.
  - `EditBox:CycleChatType(direction)` - Cycle through available chat types.
  - `EditBox:RecordTabChannel(entry?)` - Store per-tab channel memory.
  - `EditBox:PersistLastUsed()` - Save current chat selection (type, target, language) for stickiness across show/hide operations and record per-tab channel memory.
  - `EditBox:OnTabPressed()` - Handle Tab key (cycle or autocomplete).

## Hooks.History

Up/down arrow history navigation.

- Description: NavigateHistory() for overlay text history.
- File: [`../Src/Hooks/History.lua`](../Src/Hooks/History.lua)
- Methods:
  - `EditBox:NavigateHistory(direction)` - Navigate command history (-1=up, 1=down). Leaving the bottom (draft) slot stashes the current text into `HistoryDraft`; returning to it restores the draft and puts the caret at the end.

## Hooks.Slash

Slash command forwarding.

- Description: ForwardSlashCommand() to pass unknown slash commands to Blizzard.
- File: [`../Src/Hooks/Slash.lua`](../Src/Hooks/Slash.lua)
- Methods:
  - `EditBox:ForwardSlashCommand(text)` - Forward slash command to Blizzard editbox.
  - `EditBox:ForwardJoinChannel(text)` - Emulate `/join` via `JoinPermanentChannel` so Blizzard's slash handler never writes Yapper-tainted values into `channelList`/`zoneChannelList` (iterated by `MessageEventHandler` for every channel event; tainted entries re-taint the dispatch and error on secret compares under restrictions).

## Hooks.Blizzard

Blizzard editbox hooks (taint-free).

- Description: HookBlizzardEditBox(), HookAllChatFrames(), all secure hooks.
- File: [`../Src/Hooks/BlizzardHookCtl/10_ProxyBackground.lua`](../Src/Hooks/BlizzardHookCtl/10_ProxyBackground.lua), [`../Src/Hooks/BlizzardHookCtl/20_EditBoxHooks.lua`](../Src/Hooks/BlizzardHookCtl/20_EditBoxHooks.lua), [`../Src/Hooks/BlizzardHookCtl/30_ChatFrameHooks.lua`](../Src/Hooks/BlizzardHookCtl/30_ChatFrameHooks.lua), [`../Src/Hooks/BlizzardHookCtl/40_IMWindowMemory.lua`](../Src/Hooks/BlizzardHookCtl/40_IMWindowMemory.lua)
- Methods:
  - `EditBox:EnsureProxyBackgroundShown() → nil`: In proxy mode the native editbox is the visible background; re-show it after deferred Blizzard activation and keep its visual text empty while Yapper is open. ([`../Src/Hooks/BlizzardHookCtl/10_ProxyBackground.lua#L8`](../Src/Hooks/BlizzardHookCtl/10_ProxyBackground.lua#L8))
  - `EditBox:HookBlizzardEditBox(blizzEditBox)` - Hook a single Blizzard editbox.
  - `EditBox:HookAllChatFrames()` - Hook all NUM_CHAT_WINDOWS editboxes.
- Filters run:
  - `PRE_EDITBOX_SHOW`.
- Callbacks fired:
  - `EDITBOX_SHOW`, `EDITBOX_HIDE`, `EDITBOX_CHANNEL_CHANGED`.
- Invariants:
  - `_inBlizzShowHook` and deferred focus handoff guard reentrancy (issue #21 fix).

## GopherBridge

Self-initialising on `ADDON_LOADED`. Deprecation notifier only: LibGopher/CrossRP
send delegation was intentionally removed ("Gopher deletion prep", `1a28302`).
The former send-path surface (`active`, `_gopher`, `Send`, `NeedsHardwareEvent`,
`IsActive`, `IsBusy`) is gone with it.

- Description: Detects LibGopher, identifies the addon that likely owns it,
  warns the user about breakage, and offers to disable that addon (with reload).
- Fields:
  - `present: boolean` ([`../Src/Bridges/GopherBridge.lua#L22`](../Src/Bridges/GopherBridge.lua#L22))
  - `ownerAddon: string|nil` ([`../Src/Bridges/GopherBridge.lua#L23`](../Src/Bridges/GopherBridge.lua#L23))
- Methods:
  - `GopherBridge:IsPresent() → boolean`: True when LibGopher was detected this session. ([`../Src/Bridges/GopherBridge.lua#L177`](../Src/Bridges/GopherBridge.lua#L177))
  - `GopherBridge:GetOwnerAddon() → string|nil`: Best guess at the addon embedding LibGopher. ([`../Src/Bridges/GopherBridge.lua#L181`](../Src/Bridges/GopherBridge.lua#L181))

## TypingTrackerBridge

Initialised by `Chat:Init` (state refresh), then driven by overlay callbacks.

- Description: Signals external typing tracker addon.  Correctly snapshots/restores configuration from the active profile root (global or per-character) during activation/deactivation.
- Methods:
  - `TypingTrackerBridge:IsExternallyOwned() → boolean`: Return whether an external integration currently owns the typing-tracker signal. ([`../Src/Bridges/TypingTrackerBridge.lua#L93`](../Src/Bridges/TypingTrackerBridge.lua#L93))
  - `TypingTrackerBridge:SetExternalOwner(owner) → nil`: Let an integration own the tracker signal while it is active; passing nil resumes Yapper ownership. ([`../Src/Bridges/TypingTrackerBridge.lua#L85`](../Src/Bridges/TypingTrackerBridge.lua#L85))
  - `UpdateState` [`../Src/Bridges/TypingTrackerBridge.lua#L124`](../Src/Bridges/TypingTrackerBridge.lua#L124)
  - `OnOverlayFocusGained` [`../Src/Bridges/TypingTrackerBridge.lua#L160`](../Src/Bridges/TypingTrackerBridge.lua#L160)
  - `OnOverlayFocusLost` [`../Src/Bridges/TypingTrackerBridge.lua#L164`](../Src/Bridges/TypingTrackerBridge.lua#L164)
  - `OnChannelChanged` [`../Src/Bridges/TypingTrackerBridge.lua#L168`](../Src/Bridges/TypingTrackerBridge.lua#L168)

## RPPrefixBridge

Initialised by `Chat:Init`.

- Description: Prefixes outgoing RP marker text.
- Methods:
  - `Init` [`../Src/Bridges/RPPrefixBridge.lua#L61`](../Src/Bridges/RPPrefixBridge.lua#L61)
  - `IsActive` [`../Src/Bridges/RPPrefixBridge.lua#L127`](../Src/Bridges/RPPrefixBridge.lua#L127)
  - `ApplyPrefix` [`../Src/Bridges/RPPrefixBridge.lua#L148`](../Src/Bridges/RPPrefixBridge.lua#L148)

## WIMBridge

Initialised by `Chat:Init`.

- Description: Cooperates with WIM focus ownership.
- Methods:
  - `IsFocusActive` [`../Src/Bridges/WIMBridge.lua#L26`](../Src/Bridges/WIMBridge.lua#L26)
  - `IsLoaded` [`../Src/Bridges/WIMBridge.lua#L43`](../Src/Bridges/WIMBridge.lua#L43)
  - `Init` [`../Src/Bridges/WIMBridge.lua#L51`](../Src/Bridges/WIMBridge.lua#L51)

## Policies

Passive rule modules loaded from `Src/Policies/` and invoked by owner modules.

- Description: Policy objects expose decision methods but do not perform startup work or register runtime hooks.
- Modules:
  - `LockdownPolicy:IsChatLockdown() → boolean`: Returns true when chat messaging lockdown is active. ([`../Src/Policies/LockdownPolicy.lua#L53`](../Src/Policies/LockdownPolicy.lua#L53))
  - `LockdownPolicy:IsCombatLockdown() → boolean`: Returns true when protected-frame combat lockdown is active. ([`../Src/Policies/LockdownPolicy.lua#L66`](../Src/Policies/LockdownPolicy.lua#L66))
  - `LockdownPolicy:IsChatOrCombatLockdown() → boolean`: Returns true when either chat or combat lockdown is active. ([`../Src/Policies/LockdownPolicy.lua#L71`](../Src/Policies/LockdownPolicy.lua#L71))
  - `LockdownPolicy:IsProtectedSlashCommand(command) → boolean`: Returns true when a slash command token (e.g. "/m") resolves to an action insecure code cannot run during combat lockdown — secure registry commands via `IsSecureCmd` plus curated non-secure commands that call protected APIs. ([`../Src/Policies/LockdownPolicy.lua#L143`](../Src/Policies/LockdownPolicy.lua#L143))
  - `LockdownPolicy:IsAlwaysForbiddenSlashCommand(command) → boolean`: Returns true for targeting and focus slash commands whose protected Blizzard handlers must never be dispatched through Yapper's tainted forwarding path. ([`../Src/Policies/LockdownPolicy.lua#L160`](../Src/Policies/LockdownPolicy.lua#L160))
  - `LockdownPolicy:IsEmulatedSlashCommand(command) → boolean`: Returns true for slash commands (e.g. "/join") Yapper emulates locally instead of forwarding through Blizzard's `SendText` dispatch, because the Blizzard handler would write tainted values into persistent chat-frame state (`channelList`) that re-taints later chat-event dispatches. ([`../Src/Policies/LockdownPolicy.lua#L172`](../Src/Policies/LockdownPolicy.lua#L172))
  - `LockdownPolicy:HasAddOnRestrictionAPI() → boolean`: Returns true when the client exposes the WoW 12.x `C_RestrictedActions` / `Enum.AddOnRestrictionType` surface. ([`../Src/Policies/LockdownPolicy.lua#L18`](../Src/Policies/LockdownPolicy.lua#L18))
  - `LockdownPolicy:IsAddOnRestrictionActive(restrictionType) → boolean`: Returns true when a single `Enum.AddOnRestrictionType` is enforced. ([`../Src/Policies/LockdownPolicy.lua#L28`](../Src/Policies/LockdownPolicy.lua#L28))
  - `LockdownPolicy:IsAnyAddOnRestrictionActive() → boolean`: Returns true while any addon restriction type is enforced; non-chat restrictions leave messaging usable but poison Blizzard-produced data with secret values, so tainted calls into Blizzard handlers can error on secret comparisons. ([`../Src/Policies/LockdownPolicy.lua#L42`](../Src/Policies/LockdownPolicy.lua#L42))
  - `ChannelPolicy:BuildPersistedLastUsed(...) → table|nil`: Produces the sticky persisted last-used payload while preserving current selection semantics. ([`../Src/Policies/ChannelPolicy.lua#L100`](../Src/Policies/ChannelPolicy.lua#L100))
  - `ChannelPolicy:ResolveOpenSelection(context) → table`: Resolves the open channel selection from the current show/handoff context. ([`../Src/Policies/ChannelPolicy.lua#L182`](../Src/Policies/ChannelPolicy.lua#L182))

## Router

Initialised by `Chat:Init`.

- Description: Resolves concrete WoW send API for chat target.
- Fields:
  - `SendChatMessage`, `BNSendWhisper`, `ClubSendMessage` cached function refs ([`../Src/Router.lua#L26-L28`](../Src/Router.lua#L26-L28)).
- Methods:
  - `ChannelPolicy:SanitizeCommittedSelection(current) → table|nil`: Normalize a runtime channel selection before persistence or commit, removing unusable secret or unavailable targets. ([`../Src/Policies/ChannelPolicy.lua#L165`](../Src/Policies/ChannelPolicy.lua#L165))
  - `ResolveBnetTarget` [`../Src/Router.lua#L63`](../Src/Router.lua#L63)
  - `_ResolveBnetTargetUncached` [`../Src/Router.lua#L84`](../Src/Router.lua#L84)
  - `ResolveBnetDisplay` [`../Src/Router.lua#L117`](../Src/Router.lua#L117)
  - `FlushBnetCache` [`../Src/Router.lua#L176`](../Src/Router.lua#L176)
  - `Init` [`../Src/Router.lua#L180`](../Src/Router.lua#L180)
  - `DetectCommunityChannel` [`../Src/Router.lua#L197`](../Src/Router.lua#L197)
  - `Send` [`../Src/Router.lua#L215`](../Src/Router.lua#L215)
- Side effects:
  - May delegate to `GopherBridge:Send`.

## Chunking

Called from `Chat:SendPosts` for every post, oversized or not, so that `PRE_CHUNK` fires uniformly.

- Description: UTF-8 aware message splitting.
- Methods:
  - `Chunking:Split(text, limit, opts?) → string[]|nil` ([`../Src/Chunking.lua#L373`](../Src/Chunking.lua#L373))
    - `opts`: `{ ignoreParagraphMerging?, useDelineators?, delineator?, chatType?, language? }`
    - Fires the `PRE_CHUNK` filter once per contiguous text unit (after paragraph isolation). Returns `nil` when a filter cancels the send.
    - Honours `payload.continuationPrefix` set by a `PRE_CHUNK` filter, charging it against the byte budget of every chunk after the first.
    - Continuation chunks are assembled as `<delineator><continuationPrefix><text>`, or `<continuationPrefix><delineator><text>` when the filter sets `payload.continuationPrefixFirst`.

## Queue

Initialised by `Chat:Init`; registers many chat confirm events.

- Description: Ordered chunk delivery with ack/stall policy.
- Fields:
  - Queue state: `Entries` [`../Src/Queue.lua#L184`](../Src/Queue.lua#L184)

  - Queue state: `PlayerGUID` [`../Src/Queue.lua#L185`](../Src/Queue.lua#L185)
  - Queue state: `NeedsContinue` [`../Src/Queue.lua#L189`](../Src/Queue.lua#L189)
  - Queue state: `StallTimer` [`../Src/Queue.lua#L190`](../Src/Queue.lua#L190)
  - Queue state: `StallTimeout` [`../Src/Queue.lua#L191`](../Src/Queue.lua#L191)
  - Queue state: `PendingEntry` [`../Src/Queue.lua#L193`](../Src/Queue.lua#L193)
  - Queue state: `PendingAckEntry` [`../Src/Queue.lua#L194`](../Src/Queue.lua#L194)
  - Queue state: `PendingAckText` [`../Src/Queue.lua#L195`](../Src/Queue.lua#L195)
  - Queue state: `PendingAckEvent` [`../Src/Queue.lua#L196`](../Src/Queue.lua#L196)
  - Queue state: `PendingAckPolicyClass` [`../Src/Queue.lua#L197`](../Src/Queue.lua#L197)
  - Queue state: `StrictAckMatching` [`../Src/Queue.lua#L198`](../Src/Queue.lua#L198)
  - Queue state: `_lastEscTime` [`../Src/Queue.lua#L200`](../Src/Queue.lua#L200)
  - Queue state: `ContinueFrame` [`../Src/Queue.lua#L203`](../Src/Queue.lua#L203)
- Methods:
  - `Queue:IsAcceptableAck() → nil`: Check if a received chat event is an acceptable acknowledgement for an expected event. ([`../Src/Queue.lua#L556`](../Src/Queue.lua#L556))
  - `Init` ([`../Src/Queue.lua#L209`](../Src/Queue.lua#L209))
  - `Reset` ([`../Src/Queue.lua#L228`](../Src/Queue.lua#L228))
  - `IsOpenWorld` ([`../Src/Queue.lua#L245`](../Src/Queue.lua#L245))
  - `IsCommunityChannelEntry` ([`../Src/Queue.lua#L253`](../Src/Queue.lua#L253))
  - `ClassifyEntry` ([`../Src/Queue.lua#L267`](../Src/Queue.lua#L267))
  - `GetPolicy` ([`../Src/Queue.lua#L318`](../Src/Queue.lua#L318))
  - `GetConfirmEventForEntry` ([`../Src/Queue.lua#L333`](../Src/Queue.lua#L333))
  - `TrackPendingAck` ([`../Src/Queue.lua#L348`](../Src/Queue.lua#L348))
  - `GetActivePolicySnapshot` ([`../Src/Queue.lua#L356`](../Src/Queue.lua#L356))
  - `IsActive` ([`../Src/Queue.lua#L371`](../Src/Queue.lua#L371))
  - `ClearPendingAck` ([`../Src/Queue.lua#L377`](../Src/Queue.lua#L377))
  - `Enqueue` ([`../Src/Queue.lua#L388`](../Src/Queue.lua#L388))
  - `Flush` ([`../Src/Queue.lua#L400`](../Src/Queue.lua#L400))
  - `RequiresHardwareEvent` ([`../Src/Queue.lua#L422`](../Src/Queue.lua#L422))
  - `SendNext` ([`../Src/Queue.lua#L427`](../Src/Queue.lua#L427))
  - `BeginEntry` ([`../Src/Queue.lua#L462`](../Src/Queue.lua#L462))
  - `HandleAck` ([`../Src/Queue.lua#L499`](../Src/Queue.lua#L499))
  - `AssumeAck` ([`../Src/Queue.lua#L508`](../Src/Queue.lua#L508))
  - `RawSend` ([`../Src/Queue.lua#L518`](../Src/Queue.lua#L518))
  - `Complete` ([`../Src/Queue.lua#L539`](../Src/Queue.lua#L539))
  - `OnChatEvent` ([`../Src/Queue.lua#L566`](../Src/Queue.lua#L566))
  - `OnOpenChat` ([`../Src/Queue.lua#L655`](../Src/Queue.lua#L655))
  - `TryContinue` ([`../Src/Queue.lua#L665`](../Src/Queue.lua#L665))
  - `ResetStallTimer` ([`../Src/Queue.lua#L683`](../Src/Queue.lua#L683))
  - `CancelStallTimer` ([`../Src/Queue.lua#L700`](../Src/Queue.lua#L700))
  - `OnStallTimeout` ([`../Src/Queue.lua#L707`](../Src/Queue.lua#L707))
  - `CreateContinueFrame` ([`../Src/Queue.lua#L727`](../Src/Queue.lua#L727))
  - `ShowContinuePrompt` ([`../Src/Queue.lua#L787`](../Src/Queue.lua#L787))
  - `HideContinuePrompt` ([`../Src/Queue.lua#L823`](../Src/Queue.lua#L823))
  - `EnableEscapeCancel` ([`../Src/Queue.lua#L834`](../Src/Queue.lua#L834))
  - `DisableEscapeCancel` ([`../Src/Queue.lua#L866`](../Src/Queue.lua#L866))
  - `Cancel` ([`../Src/Queue.lua#L873`](../Src/Queue.lua#L873))
- Events registered:
  - `CHAT_MSG_SAY`, `CHAT_MSG_YELL`, `CHAT_MSG_EMOTE`, `CHAT_MSG_WHISPER_INFORM`, `CHAT_MSG_BN_WHISPER_INFORM`, `CHAT_MSG_CHANNEL`, `CHAT_MSG_COMMUNITIES_CHANNEL`, `CHAT_MSG_PARTY`, `CHAT_MSG_PARTY_LEADER`, `CHAT_MSG_RAID`, `CHAT_MSG_RAID_LEADER`, `CHAT_MSG_RAID_WARNING`, `CHAT_MSG_INSTANCE_CHAT`, `CHAT_MSG_INSTANCE_CHAT_LEADER`, `CHAT_MSG_GUILD`, `CHAT_MSG_OFFICER`, `CHAT_MSG_GUILD_DISCORD` (registered from `ALL_CONFIRM_EVENTS`) ([`../Src/Queue.lua#L146-L173`](../Src/Queue.lua#L146-L173), [`../Src/Queue.lua#L199-L203`](../Src/Queue.lua#L199-L203)).
  - Hook to `ChatFrameUtil.OpenChat` for continue flow.
- Callbacks fired:
  - `QUEUE_STALL`, `QUEUE_COMPLETE`.
- Invariants:
  - `TryContinue()` only meaningful when `NeedsContinue == true`.

## Chat

Initialised on `PLAYER_ENTERING_WORLD` by `Yapper.lua`.

- Description: Send orchestrator (`EditBox -> Chunking -> Queue -> Router`).
- Methods:
  - `Chat:Init() → nil` ([`../Src/Chat.lua#L55`](../Src/Chat.lua#L55))
  - `Chat:SendPosts(posts, chatType, language, target) → boolean, string|nil, number|nil, string|nil` ([`../Src/Chat.lua#L144`](../Src/Chat.lua#L144))
  - `Chat:OnSend(text, chatType, language, target) → boolean` ([`../Src/Chat.lua#L258`](../Src/Chat.lua#L258))
  - `Chat:DirectSend(msg, chatType, language, target) → nil` ([`../Src/Chat.lua#L273`](../Src/Chat.lua#L273))
- Invariants:
  - `Chat:SendPosts` is the only send pipeline. `Chat:OnSend` (single-line overlay) and `Multiline:Submit` both funnel into it, so history, `PRE_SEND`, chunking, `PRE_CHUNK`, lockdown checks and stalled-queue recovery behave identically in both modes.
  - Every post is chunked, then the whole composition is enqueued as **one** ordered sequence so ack tracking cannot interleave.
  - History records the user's raw input *before* `PRE_SEND`, so recall returns what was typed and re-sending a recalled message cannot compound an addon's prefix.
- Filters run:
  - `PRE_SEND`, `PRE_DELIVER`. (`PRE_CHUNK` is fired by `Chunking:Split`.)
- Callbacks fired:
  - `POST_SEND`, `POST_CLAIMED`.

## Multiline

Lazy frame creation; active only when user enters multiline mode.

- Description: Expanded multiline editor that bypasses single-line overlay.
- Fields:
  - `Frame` [`../Src/Multiline.lua#L57`](../Src/Multiline.lua#L57)
  - `ScrollFrame` [`../Src/Multiline.lua#L58`](../Src/Multiline.lua#L58)
  - `EditBox` [`../Src/Multiline.lua#L59`](../Src/Multiline.lua#L59)
  - `LabelFS` [`../Src/Multiline.lua#L60`](../Src/Multiline.lua#L60)
  - `Active` [`../Src/Multiline.lua#L239`](../Src/Multiline.lua#L239)
  - `ChatType` [`../Src/Multiline.lua#L61`](../Src/Multiline.lua#L61)
  - `Language` [`../Src/Multiline.lua#L62`](../Src/Multiline.lua#L62)
  - `Target` [`../Src/Multiline.lua#L63`](../Src/Multiline.lua#L63)
- Methods:
  - `Multiline:OnLockdownEnd() → nil`: Called when combat ends (PLAYER_REGEN_ENABLED). ([`../Src/Multiline.lua#L1082`](../Src/Multiline.lua#L1082))
  - `Multiline:OnLockdownStart() → nil`: Called when combat starts (PLAYER_REGEN_DISABLED). ([`../Src/Multiline.lua#L1041`](../Src/Multiline.lua#L1041))
  - `UpdateLabelGap` [`../Src/Multiline.lua#L168`](../Src/Multiline.lua#L168)
  - `CreateFrame` [`../Src/Multiline.lua#L199`](../Src/Multiline.lua#L199)
  - `Enter` [`../Src/Multiline.lua#L637`](../Src/Multiline.lua#L637)
  - `Exit` [`../Src/Multiline.lua#L783`](../Src/Multiline.lua#L783)
  - `Submit` [`../Src/Multiline.lua#L907`](../Src/Multiline.lua#L907)
  - `Cancel` [`../Src/Multiline.lua#L1008`](../Src/Multiline.lua#L1008)
  - `ApplyTheme` [`../Src/Multiline.lua#L1101`](../Src/Multiline.lua#L1101)
- Invariants:
  - While `Active`, single-line overlay show path should early-return.

## Autocomplete

Binds to overlay (or multiline) editbox when available.

- Description: Ghost-text completion from dictionary + YAS. Candidates are ranked by prefix fit and length, then adjusted by YAS signals: personal `freq` bonus, `negBias` dismissal penalty, and a `bigram` context bonus (the completed word before the caret resolves the `bigram[prev]` bucket; text start uses `"<s>"`).
- Fields:
  - `GhostFS` [`../Src/Autocomplete.lua#L59`](../Src/Autocomplete.lua#L59)
  - `CurrentSugg` [`../Src/Autocomplete.lua#L60`](../Src/Autocomplete.lua#L60)
  - `CurrentPrefix` [`../Src/Autocomplete.lua#L61`](../Src/Autocomplete.lua#L61)
  - `PrefixText` [`../Src/Autocomplete.lua#L62`](../Src/Autocomplete.lua#L62)
  - `Active` [`../Src/Autocomplete.lua#L63`](../Src/Autocomplete.lua#L63)
  - `Enabled` [`../Src/Autocomplete.lua#L80`](../Src/Autocomplete.lua#L80)
  - `_activeEditBox` [`../Src/Autocomplete.lua#L65`](../Src/Autocomplete.lua#L65)
  - `_isMultiline` [`../Src/Autocomplete.lua#L66`](../Src/Autocomplete.lua#L66)
- Methods:
  - `Autocomplete:SetOffset(x, y) → nil`: Set a manual pixel offset for the ghost-text positioning. ([`../Src/Autocomplete.lua#L667`](../Src/Autocomplete.lua#L667))
  - `IsEnabled`, `ExtractWordAtCursor`, `SearchDictionary`, `GetSuggestion`, `GetGhostFS`, `_InstallCursorHook`, `PositionGhost`, `ShowGhost`, `HideGhost`, `OnTextChanged`, `OnTabPressed`, `OnOverlayHide`, `SyncFont`, `SyncGhostFont`, `BindMultiline`, `UnbindMultiline` ([`../Src/Autocomplete.lua`](../Src/Autocomplete.lua)).
- Notes:
  - Accepting a completion only appends a space when the next byte is a word byte or end-of-text; when it does, the space position is remembered in `_pendingSnap`. If the very next keystroke is a `"close"` boundary (see `Spellcheck:ClassifyBoundary`), the space hops after the punctuation (`"hello "` + `.` → `"hello. "`) — the mobile-keyboard behaviour. The marker self-invalidates by position match, so caret moves can't trigger a stray snap.
  - Ghost text is suppressed while the caret sits mid-word (a word byte directly after the caret).

## Toast

Shared transient notification card (UIParent child, `TOOLTIP` strata — same pattern as the multiline onboarding hint). Used for the autocorrect Undo card and the YAS learned-word card. Initialised from `Chat:Init`, which subscribes it to `YAS_WORD_LEARNED`.

- Description: One card at a time; further shows queue (cap 3, oldest dropped). Hold duration pauses while hovered so action buttons stay reachable; dismiss fades out then pumps the queue.
- Methods:
  - `Toast:Show(opts)` [`../Src/Toast.lua#L276`](../Src/Toast.lua#L276) — `{ title, body, buttons = { {label, onClick} }, duration }`.
  - `Toast:ShowCorrection(corr)` [`../Src/Toast.lua#L359`](../Src/Toast.lua#L359) — the "Autocorrected" card; its Undo routes through `Autocorrect:UndoByToast` for stale-entry validation.
  - `Toast:ShowLearned(word, locale)` [`../Src/Toast.lua#L377`](../Src/Toast.lua#L377) — the learned-word card with Keep / Unlearn (`YAS:UnlearnWord`) / Ignore (`Spellcheck:IgnoreWord` + WAIVER pin).
  - `Toast:_PickPosition(w, h)` [`../Src/Toast.lua#L194`](../Src/Toast.lua#L194) — placement solver: collects the screen rects of the overlay, overlay editbox, multiline frame, suggestion popup, hint frame and default chat frame, then walks candidate zones (beside/above the input, above chat, then screen corners) until one overlaps nothing; always clamped to the screen.
- Fields:
  - `Toast.Frame` — lazily built card frame, registered via `Core:RegisterFrame`.
  - `Toast._queue` — pending toast opts.

## History

Initialised on `ADDON_LOADED`; hooks overlay on `PLAYER_ENTERING_WORLD`.

- Description: Persistent chat history, draft store, undo/redo snapshots.
- Methods:
  - `History:SaveDraft(editBox, isMultiline) → nil`: Save a draft from any EditBox (overlay or multiline). ([`../Src/History.lua#L194`](../Src/History.lua#L194))
  - `History:GetDraft() → string? text, string? chatType, string? target, boolean? multiline`: Return the saved draft if dirty. ([`../Src/History.lua#L246`](../Src/History.lua#L246))
  - `InitDB` [`../Src/History.lua#L73`](../Src/History.lua#L73)
  - `SaveDB` [`../Src/History.lua#L113`](../Src/History.lua#L113)
  - `AddChatHistory` [`../Src/History.lua#L134`](../Src/History.lua#L134)
  - `GetChatHistory` [`../Src/History.lua#L170`](../Src/History.lua#L170)
  - `GetDraftStore` [`../Src/History.lua#L181`](../Src/History.lua#L181)
  - `MarkDirty` [`../Src/History.lua#L255`](../Src/History.lua#L255)
  - `ClearDraft` [`../Src/History.lua#L260`](../Src/History.lua#L260)
  - `CancelPauseTimer` [`../Src/History.lua#L280`](../Src/History.lua#L280)
  - `AddSnapshot` [`../Src/History.lua#L310`](../Src/History.lua#L310)
  - `Undo` [`../Src/History.lua#L356`](../Src/History.lua#L356)
  - `Redo` [`../Src/History.lua#L382`](../Src/History.lua#L382)
  - `HookOverlayEditBox` [`../Src/History.lua#L412`](../Src/History.lua#L412)
- Global state touched:
  - `_G.YapperLocalHistory`.

## Theme

Loaded with defaults; active theme restored on `ADDON_LOADED`.

- Description: Theme registry, application, persistence, live sync.
- Fields:
  - `_registry`, `_current` *private by convention; do not rely on* ([`../Src/Theme.lua#L16-L17`](../Src/Theme.lua#L16-L17)).
- Methods:
  - `YapperTable:GetRegisteredThemes() → nil`: No description provided. ([`../Src/Theme.lua#L237`](../Src/Theme.lua#L237))
  - `RegisterTheme` [`../Src/Theme.lua#L26`](../Src/Theme.lua#L26)
  - `GetTheme` [`../Src/Theme.lua#L32`](../Src/Theme.lua#L32)
  - `GetRegisteredNames` [`../Src/Theme.lua#L37`](../Src/Theme.lua#L37)
  - `SetTheme` [`../Src/Theme.lua#L45`](../Src/Theme.lua#L45)
  - `ApplyToFrame` [`../Src/Theme.lua#L121`](../Src/Theme.lua#L121)
  - `GetCurrentName` [`../Src/Theme.lua#L176`](../Src/Theme.lua#L176)
  - `SetLiveTheme` [`../Src/Theme.lua#L187`](../Src/Theme.lua#L187)
  - `SetTheme` logic switches between `_G.YapperDB` and `_G.YapperLocalConf` as the root for `_appliedTheme` based on `UseGlobalProfile`.
  - Global wrappers on root table: `Yapper:RegisterTheme` [`../Src/Theme.lua#L26`](../Src/Theme.lua#L26)
  - Global wrappers on root table: `Yapper:SetTheme` [`../Src/Theme.lua#L45`](../Src/Theme.lua#L45)
  - Global wrappers on root table: `Yapper:GetRegisteredThemes` [`../Src/Theme.lua#L237`](../Src/Theme.lua#L237)
- Callbacks fired:
  - `THEME_CHANGED`.

## Interface

Created during `ADDON_LOADED` startup path and owns settings UI lifecycle.

- Description: Main settings shell, launcher integration, category navigation.
- Fields:
  - `MouseWheelStepRate` [`../Src/Interface.lua#L8`](../Src/Interface.lua#L8)
  - `IsVisible` [`../Src/Interface.lua#L9`](../Src/Interface.lua#L9)
  - `DICTIONARY_DOWNLOAD_URL` [`../Src/Interface.lua#L12`](../Src/Interface.lua#L12)
  - Helpers/constants exported as underscored fields (`_LAYOUT`, `_LayoutCursor`, `_UI_FONT_*`) *private by convention; do not rely on* ([`../Src/Interface.lua#L120-L124`](../Src/Interface.lua#L120-L124)).
- Methods:
  - `LayoutCursor:Pad() → nil`: No description provided. ([`../Src/Interface.lua#L103`](../Src/Interface.lua#L103))
  - `LayoutCursor:Advance() → nil`: No description provided. ([`../Src/Interface.lua#L98`](../Src/Interface.lua#L98))
  - `LayoutCursor:Y() → nil`: No description provided. ([`../Src/Interface.lua#L94`](../Src/Interface.lua#L94))
  - `LayoutCursor:New(startY) → table`: No description provided. ([`../Src/Interface.lua#L90`](../Src/Interface.lua#L90))
  - `InitPopups` [`../Src/Interface.lua#L302`](../Src/Interface.lua#L302)
  - `BuildConfigUI` [`../Src/Interface.lua#L449`](../Src/Interface.lua#L449)
  - `ShowMainWindow` [`../Src/Interface.lua#L771`](../Src/Interface.lua#L771)
  - `OpenToCategory` [`../Src/Interface.lua#L796`](../Src/Interface.lua#L796)
  - `ToggleMainWindow` [`../Src/Interface.lua#L820`](../Src/Interface.lua#L820)
  - `HandleLauncherClick` [`../Src/Interface.lua#L852`](../Src/Interface.lua#L852)
  - `CloseFrame` [`../Src/Interface.lua#L887`](../Src/Interface.lua#L887)
  - `Init` [`../Src/Interface.lua#L898`](../Src/Interface.lua#L898)
  - `CreateLauncher` [`../Src/Interface.lua#L932`](../Src/Interface.lua#L932)
- Global function:
  - `Yapper_FromCompartment(...)` ([`../Src/Interface.lua#L845`](../Src/Interface.lua#L845)).

## Interface.Schema

Build-time render schema module used by window/UI builders.

- Description: Settings schema composition and category metadata.
- Fields:
  - `_COLOUR_KEYS`, `_CHANNEL_OVERRIDE_OPTIONS`, `_CREDITS_BUNDLED`, `_CREDITS_OPTIONAL`, `_FONT_OUTLINE_OPTIONS`, `_SETTING_TOOLTIPS`, `_FRIENDLY_LABELS`, `_CATEGORIES`, `_PATH_TO_CATEGORY` *private by convention; do not rely on* ([`../Src/Interface/Schema.lua#L519-L527`](../Src/Interface/Schema.lua#L512)).
- Methods:
  - `BuildRenderSchema` [`../Src/Interface/Schema.lua#L369`](../Src/Interface/Schema.lua#L369)
  - `GetRenderSchema` [`../Src/Interface/Schema.lua#L510`](../Src/Interface/Schema.lua#L510)
  - `RefreshRenderSchema` [`../Src/Interface/Schema.lua#L518`](../Src/Interface/Schema.lua#L518)
  - `OnWindowClosed` [`../Src/Interface/Schema.lua#L524`](../Src/Interface/Schema.lua#L524)

## Interface.Config

Handles config reads/writes and side-effect fan-out.

- Description: Config root/path helpers, sanitisation, minimap controls.
- Methods:
  - `Interface:FactoryReset() → nil`: TRUE clean slate: wipes all settings, learned dictionary data, and history. ([`../Src/Interface/Config.lua#L74`](../Src/Interface/Config.lua#L74))
  - `Interface:ResetAllSettings() → nil`: Reset all configuration settings to their default values. ([`../Src/Interface/Config.lua#L46`](../Src/Interface/Config.lua#L46))
  - `GetLocalConfigRoot` [`../Src/Interface/Config.lua#L30`](../Src/Interface/Config.lua#L30)
  - `GetDefaultsRoot` [`../Src/Interface/Config.lua#L37`](../Src/Interface/Config.lua#L37)
  - `GetRenderCacheContainer` [`../Src/Interface/Config.lua#L94`](../Src/Interface/Config.lua#L94)
  - `PurgeRenderCache` [`../Src/Interface/Config.lua#L105`](../Src/Interface/Config.lua#L105)
  - `SetDirty` [`../Src/Interface/Config.lua#L111`](../Src/Interface/Config.lua#L111)
  - `IsDirty` [`../Src/Interface/Config.lua#L116`](../Src/Interface/Config.lua#L116)
  - `SetSettingsChanged` [`../Src/Interface/Config.lua#L121`](../Src/Interface/Config.lua#L121)
  - `GetConfigPath` [`../Src/Interface/Config.lua#L129`](../Src/Interface/Config.lua#L129)
  - `GetDefaultPath` [`../Src/Interface/Config.lua#L137`](../Src/Interface/Config.lua#L137)
  - `UpdateOverrideTextColorCheckboxState` [`../Src/Interface/Config.lua#L141`](../Src/Interface/Config.lua#L141)
  - `SetLocalPath` [`../Src/Interface/Config.lua#L145`](../Src/Interface/Config.lua#L145)
  - `GetLauncherTooltipLines` [`../Src/Interface/Config.lua#L390`](../Src/Interface/Config.lua#L390)
  - `GetMinimapButtonSettings` [`../Src/Interface/Config.lua#L398`](../Src/Interface/Config.lua#L398)
  - `GetMinimapButtonOffset` [`../Src/Interface/Config.lua#L411`](../Src/Interface/Config.lua#L411)
  - `PositionMinimapButton` [`../Src/Interface/Config.lua#L415`](../Src/Interface/Config.lua#L415)
  - `UpdateMinimapButtonAngleFromCursor` [`../Src/Interface/Config.lua#L431`](../Src/Interface/Config.lua#L431)
  - `ApplyMinimapButtonVisibility` [`../Src/Interface/Config.lua#L448`](../Src/Interface/Config.lua#L448)
  - `IsPathDependencyDisabled` [`../Src/Interface/Config.lua#L490`](../Src/Interface/Config.lua#L490) — greys out settings whose prerequisites are off (autocorrect needs spellcheck + adaptive learning, its toast needs autocorrect, learn-toast needs adaptive learning)
  - `IsPathDisabledByTheme` [`../Src/Interface/Config.lua#L513`](../Src/Interface/Config.lua#L513)
  - `GetFriendlyLabel` [`../Src/Interface/Config.lua#L552`](../Src/Interface/Config.lua#L552)
  - `SanitizeLocalConfig` [`../Src/Interface/Config.lua#L591`](../Src/Interface/Config.lua#L591)
- Non-obvious rationale migrated from old docs:
  - `SetLocalPath` is the **single authoritative write source** for configuration; it handles profile-aware routing, theme-override marking, and automatic `PromoteCharacterToGlobal` triggers during profile toggles.
  - `SetLocalPath` enforces channel marker sync (`Chat.DELINEATOR` and `Chat.PREFIX`) as a single logical setting update.

## Interface.Window

Builds and controls top-level frames.

- Description: Main window, welcome/what's-new flows, UI font scaling.
- Fields:
  - `_activeCategory` *private by convention; do not rely on* ([`../Src/Interface/Window.lua#L175`](../Src/Interface/Window.lua#L175)).
- Methods:
  - `Interface:CreateFullscreenDimmer(alpha) → Frame`: Create a fullscreen modal dimmer shared by welcome and What's New popups. ([`../Src/Interface/Window.lua#L259`](../Src/Interface/Window.lua#L259))
  - `Interface:ForEachWhatsNewVersion(limitToOne, callback) → nil`: Iterate through changelog versions in display order, passing each version and note array to the callback. ([`../Src/Interface/Window.lua#L214`](../Src/Interface/Window.lua#L214))
  - `CompareVersions` — Compares semantic version strings. ([`../Src/Interface/Window.lua#L194`](../Src/Interface/Window.lua#L194))
  - `GetSortedVersions` — Returns WHATS_NEW entries sorted by version. ([`../Src/Interface/Window.lua#L205`](../Src/Interface/Window.lua#L205))
  - `CheckForChangelogUpdate` — Handshake that updates seen records and triggers popups. ([`../Src/Interface/Window.lua#L314`](../Src/Interface/Window.lua#L314))
  - `PopulateWhatsNewContent` — Renders changelog notes into a container. ([`../Src/Interface/Window.lua#L754`](../Src/Interface/Window.lua#L754))
  - `RefreshWhatsNewContent` — Wipes and re-renders the WhatsNew popup. ([`../Src/Interface/Window.lua#L796`](../Src/Interface/Window.lua#L796))
  - `UpdateWhatsNewButtonScale` — Scales the 'Got it' button text. ([`../Src/Interface/Window.lua#L813`](../Src/Interface/Window.lua#L813))
  - `Interface:GetWelcomeVersion() → number`: Returns the target version of the welcome screen content. ([`../Src/Interface/Window.lua#L225`](../Src/Interface/Window.lua#L225))
  - `GetMainWindowPositionStore` [`../Src/Interface/Window.lua#L28`](../Src/Interface/Window.lua#L28)
  - `SaveMainWindowPosition` [`../Src/Interface/Window.lua#L45`](../Src/Interface/Window.lua#L45)
  - `ApplyMainWindowPosition` [`../Src/Interface/Window.lua#L62`](../Src/Interface/Window.lua#L62)
  - `ShouldShowWelcomeChoice` [`../Src/Interface/Window.lua#L273`](../Src/Interface/Window.lua#L273)
  - `MarkWelcomeShown` [`../Src/Interface/Window.lua#L315`](../Src/Interface/Window.lua#L315)
  - `MarkVersionSeen` [`../Src/Interface/Window.lua#L319`](../Src/Interface/Window.lua#L319)
  - `CreateWelcomeChoiceFrame` [`../Src/Interface/Window.lua#L471`](../Src/Interface/Window.lua#L471)
  - `CreateWhatsNewFrame` [`../Src/Interface/Window.lua#L678`](../Src/Interface/Window.lua#L678)
  - `ShowSpellcheckLocalePrompt(parent, onDone)` [`../Src/Interface/Window.lua#L385`](../Src/Interface/Window.lua#L385) — language chooser shown when spellcheck is enabled from a popup; writes `Spellcheck.Locale` before `Spellcheck.Enabled` so `ApplyState` loads exactly the picked dictionary
  - `CreateMainWindow` [`../Src/Interface/Window.lua#L934`](../Src/Interface/Window.lua#L934)
  - `UpdateSidebarSelection` [`../Src/Interface/Window.lua#L1136`](../Src/Interface/Window.lua#L1136)
  - `GetUIFontOffset` [`../Src/Interface/Window.lua#L1155`](../Src/Interface/Window.lua#L1155)
  - `SetUIFontOffset` [`../Src/Interface/Window.lua#L1161`](../Src/Interface/Window.lua#L1161)
  - `ScaledRow` [`../Src/Interface/Window.lua#L1169`](../Src/Interface/Window.lua#L1169)
  - `ApplyUIFontScaleToFontString` [`../Src/Interface/Window.lua#L1174`](../Src/Interface/Window.lua#L1174)
  - `ApplyUIFontScale` [`../Src/Interface/Window.lua#L1189`](../Src/Interface/Window.lua#L1189)
  - `RefreshFontScaleLabel` [`../Src/Interface/Window.lua#L1208`](../Src/Interface/Window.lua#L1208)

## Interface.Widgets

Widget factory/pool and reusable setting controls.

- Description: UI control allocator with pooling, tooltip plumbing, common controls.
- Fields:
  - `WidgetPool: table` ([`../Src/Interface/Widgets.lua#L66`](../Src/Interface/Widgets.lua#L66)).
  - `_OpenColorPicker: function` *private by convention; do not rely on* ([`../Src/Interface/Widgets.lua#L884`](../Src/Interface/Widgets.lua#L884)).
- Methods:
  - `ClearConfigControls` [`../Src/Interface/Widgets.lua#L32`](../Src/Interface/Widgets.lua#L32)
  - `AddControl` [`../Src/Interface/Widgets.lua#L53`](../Src/Interface/Widgets.lua#L53)
  - `AcquireWidget` [`../Src/Interface/Widgets.lua#L74`](../Src/Interface/Widgets.lua#L74)
  - `ReleaseWidget` [`../Src/Interface/Widgets.lua#L109`](../Src/Interface/Widgets.lua#L109)
  - `GetTooltip` [`../Src/Interface/Widgets.lua#L184`](../Src/Interface/Widgets.lua#L184)
  - `AttachTooltip` [`../Src/Interface/Widgets.lua#L195`](../Src/Interface/Widgets.lua#L195)
  - `CreateResetButton` [`../Src/Interface/Widgets.lua#L300`](../Src/Interface/Widgets.lua#L300)
  - `CreateLabel` [`../Src/Interface/Widgets.lua#L313`](../Src/Interface/Widgets.lua#L313)
  - `CreateCheckBox` [`../Src/Interface/Widgets.lua#L511`](../Src/Interface/Widgets.lua#L511)
  - `CreateTextInput` [`../Src/Interface/Widgets.lua#L567`](../Src/Interface/Widgets.lua#L567)
  - `CreateColorPickerControl` [`../Src/Interface/Widgets.lua#L658`](../Src/Interface/Widgets.lua#L658)
  - `CreateFontSizeDropdown` [`../Src/Interface/Widgets.lua#L744`](../Src/Interface/Widgets.lua#L744)
  - `CreateFontOutlineDropdown` [`../Src/Interface/Widgets.lua#L843`](../Src/Interface/Widgets.lua#L843)
- Non-obvious rationale migrated from old docs:
  - `CreateResetButton` self-registers with control tracking; do not double-register via `AddControl`.

## Interface.Pages

Per-category page builders called by `BuildConfigUI`.

- Description: Concrete settings page construction routines.
- Methods:
  - `CreateChangelogPage` — Builds the scrollable version history settings tab. ([`../Src/Interface/Pages.lua#L908`](../Src/Interface/Pages.lua#L908))
  - `CreateChannelOverrideControls` [`../Src/Interface/Pages.lua#L36`](../Src/Interface/Pages.lua#L36)
  - `CreateGlobalSyncControls` [`../Src/Interface/Pages.lua#L330`](../Src/Interface/Pages.lua#L330)
  - `CreateYASLearningPage` [`../Src/Interface/Pages.lua#L389`](../Src/Interface/Pages.lua#L389)
  - `CreateQueueDiagnostics` [`../Src/Interface/Pages.lua#L737`](../Src/Interface/Pages.lua#L737)
  - `CreateTutorialPage` [`../Src/Interface/Pages.lua#L841`](../Src/Interface/Pages.lua#L841)
  - `CreateCreditsPage` [`../Src/Interface/Pages.lua#L939`](../Src/Interface/Pages.lua#L939)
  - `CreateSpellcheckLocaleDropdown` [`../Src/Interface/Pages.lua#L1051`](../Src/Interface/Pages.lua#L1051)
  - `CreateSpellcheckKeyboardLayoutDropdown` [`../Src/Interface/Pages.lua#L1151`](../Src/Interface/Pages.lua#L1151)
  - `CreateSpellcheckUserDictEditor` [`../Src/Interface/Pages.lua#L1216`](../Src/Interface/Pages.lua#L1216)
  - `CreateThemeDropdown` [`../Src/Interface/Pages.lua#L1402`](../Src/Interface/Pages.lua#L1402)
- Invariants:
  - Dropdown handlers assume config roots are initialised.

## Emotes

- Methods:
  - `Emotes:EnsureHintUI() → nil`: Ensures the emote hint UI is created. ([`../Src/Emotes.lua#L182`](../Src/Emotes.lua#L182))
  - `Emotes:EnsureMenuUI() → nil`: Ensures the emote menu UI is created. ([`../Src/Emotes.lua#L54`](../Src/Emotes.lua#L54))
  - `Emotes:InitEmoteList() → nil`: Populates the emote list. Only called when the menu is actually opened. ([`../Src/Emotes.lua#L28`](../Src/Emotes.lua#L28))
  - `Emotes:ApplySelection(index, isEnter) → nil`: Applies the selected emote to the edit box and hides the menu. If `autoSend` is enabled, immediately sends the emote to chat; otherwise, appends a space and refocuses the edit box (suppressing the Enter key if `isEnter` is true). ([`../Src/Emotes.lua#L396`](../Src/Emotes.lua#L396))
  - `Emotes:RefreshSelection() → nil`: Highlights the currently selected row in the emote menu. ([`../Src/Emotes.lua#L381`](../Src/Emotes.lua#L381))
  - `Emotes:FilterAndShow() → nil`: Re-renders the emote menu UI based on the current ActiveFilter. ([`../Src/Emotes.lua#L280`](../Src/Emotes.lua#L280))
  - `Emotes:FilterMenu(query) → nil`: Prepares the search filter state from a raw slash command query. ([`../Src/Emotes.lua#L270`](../Src/Emotes.lua#L270))
  - `Emotes:HideMenu() → nil`: Hides the emote menu. ([`../Src/Emotes.lua#L262`](../Src/Emotes.lua#L262))
  - `Emotes:OpenMenu() → nil`: Opens the emote menu. ([`../Src/Emotes.lua#L242`](../Src/Emotes.lua#L242))

## Utilities

- Methods:
  - `Utils:SafeNumber(value, fallback) → number`: Return a sanitized number, or `fallback` when the value is nil/secret/non-numeric. Convenience wrapper around SanitizeNumber. ([`../Src/Utils.lua#L262`](../Src/Utils.lua#L262))
  - `Utils:SanitizeNumber(value) → number|nil`: Return a number only when it is usable from tainted code; secret numbers (which pass `or 0` then fail inside Blizzard arithmetic) return nil. ([`../Src/Utils.lua#L251`](../Src/Utils.lua#L251))
  - `Utils:SanitizeTarget(value) → string|number|nil`: Return a chat target only when it is usable from tainted code. Secret values (and non-string/number types) return nil so callers treat them as "no target" instead of erroring on comparisons. ([`../Src/Utils.lua#L235`](../Src/Utils.lua#L235))
  - `Utils:StripDisplayEscapes(text) → string`: Strip display-only WoW escape sequences from text while preserving complete hyperlinks. ([`../Src/Utils.lua#L387`](../Src/Utils.lua#L387))
  - `Utils:IsUnambiguousBnetTarget(target) → boolean`: Return true when target is an unambiguous Battle.net identifier, such as a numeric ID or BattleTag containing `#`. ([`../Src/Utils.lua#L542`](../Src/Utils.lua#L542))
  - `Utils:SetFontIfChanged(widget, face, size, flags) → boolean`: Set a widget's font only when the target differs from the current font; returns whether SetFont was called. ([`../Src/Utils.lua#L501`](../Src/Utils.lua#L501))
  - `Utils:IsForeverClient() → boolean`: True on the World of Warcraft: Forever client, detected via Forever-only API surfaces first, then flavour/product labels (camelot/forever/classicplus variants), then a 1.6x build-version heuristic. Cached after first call. ([`../Src/Utils.lua#L296`](../Src/Utils.lua#L296))
  - `Utils:HasRegionalUniqueNames() → boolean`: True when the current ruleset has surname-bearing regional-unique player names — Blizzard's own `RegionalUniqueNamesEnabled()` gate; intentionally independent of `IsForeverClient()`. ([`../Src/Utils.lua#L346`](../Src/Utils.lua#L346))
  - `Utils:NormaliseCharName(name) → string|nil`: Canonicalise a character name for comparison — strips the `-Realm` suffix on retail; on regional-unique-names clients (Forever) keeps the surname and canonicalises "First Last"/"First-Last" to a single lowercase space-separated form. ([`../Src/Utils.lua#L365`](../Src/Utils.lua#L365))
  - `Utils:SafeToString(value) → string`: Convert diagnostic values without stringifying secret values; returns `<secret>` for secret values and `<unavailable>` when conversion fails. ([`../Src/Utils.lua#L34`](../Src/Utils.lua#L34))
  - `Utils:IsChatOrCombatLockdown() → boolean`: Return true when either chat-messaging or combat lockdown is active. ([`../Src/Utils.lua#L137`](../Src/Utils.lua#L137))
  - `Utils:IsAnyAddOnRestriction() → boolean`: Return true while any addon restriction type is enforced — secret values may exist in Blizzard code paths, so tainted forwarding can hit illegal secret comparisons. ([`../Src/Utils.lua#L127`](../Src/Utils.lua#L127))
  - `Utils:IsCombatLockdown() → boolean`: Return true when protected-frame combat restrictions are active. ([`../Src/Utils.lua#L109`](../Src/Utils.lua#L109))
  - `Utils:AssertType(value, expectedType, default) → any`: Assert type matches expected, returning the original value or default. ([`../Src/Utils.lua#L178`](../Src/Utils.lua#L178))
  - `Utils:EnsureTablePath(root, ...) → table`: Ensure a table path exists, creating intermediate tables as needed, and return the deepest table. ([`../Src/Utils.lua#L162`](../Src/Utils.lua#L162))
  - `Utils:EnsureTable(t) → table`: Ensure a value is a table, returning it or a new empty table. ([`../Src/Utils.lua#L154`](../Src/Utils.lua#L154))
  - `Utils:Deleet(word) → string`: Convert leetspeak characters back to their base alphabet equivalents. ([`../Src/Utils.lua#L557`](../Src/Utils.lua#L557))

## TotalRP3Bridge

- Methods:
  - `TotalRP3Bridge:GetPlayerDisplayName() → string`: Return the best available RP display name for the player when TRP3 is loaded, falling back to UnitName("player"). ([`../Src/Bridges/TotalRP3Bridge.lua#L91`](../Src/Bridges/TotalRP3Bridge.lua#L91))
  - `TotalRP3Bridge:GetUnitDisplayName(unit) → string`: Return the best available RP display name for a unit, falling back to the unit's Blizzard name or "You". ([`../Src/Bridges/TotalRP3Bridge.lua#L75`](../Src/Bridges/TotalRP3Bridge.lua#L75))

## Hooks.UnitPopup

- Methods:
  - `EditBox:InstallUnitPopupWhisperOverride() → boolean`: Install the Menu.ModifyMenu registrations for character and Battle.net unit-popup Whisper actions. Idempotent; returns false when the Menu API is unavailable. ([`../Src/Hooks/UnitPopup.lua#L245`](../Src/Hooks/UnitPopup.lua#L245))

## Bridges\WhisperMessengerBridge

- Methods:
  - `WhisperMessengerBridge:HookSecureButtonCreation() → nil`: Hook Keybinds.CreateSecureButtons so the bridge re-wraps whenever the secure buttons are recreated. ([`../Src/Bridges/WhisperMessengerBridge.lua#L141`](../Src/Bridges/WhisperMessengerBridge.lua#L141))
  - `WhisperMessengerBridge:WrapReplyKeybind() → nil`: Wrap the REPLYTELL2 secure button's PostClick so the reply/re-whisper keybind is delegated when WhisperMessenger owns its window. ([`../Src/Bridges/WhisperMessengerBridge.lua#L88`](../Src/Bridges/WhisperMessengerBridge.lua#L88))
  - `WhisperMessengerBridge:IsWindowVisible() → boolean`: Check whether the WhisperMessenger window is currently visible. ([`../Src/Bridges/WhisperMessengerBridge.lua#L50`](../Src/Bridges/WhisperMessengerBridge.lua#L50))

## LanguagesBridge

Self-bootstrapping (own `ADDON_LOADED` / `PLAYER_LOGIN` frame); not initialised by core.

- Description: Reproduces Languages' outgoing dialect substitution and `[Language]` tag from `LanguagesAPI` alone. Registers no LibChatFilter mutator and captures none.
- Methods:
  - `LanguagesBridge:Init() → nil`: Register the PRE_SEND and PRE_CHUNK filters at priority 20. Idempotent; a no-op until both LanguagesAPI and YapperAPI exist. ([`../Src/Bridges/LanguagesBridge.lua#L193`](../Src/Bridges/LanguagesBridge.lua#L193))
  - `LanguagesBridge:Shutdown() → nil`: Unregister the filters and go dormant. ([`../Src/Bridges/LanguagesBridge.lua#L234`](../Src/Bridges/LanguagesBridge.lua#L234))
  - `LanguagesBridge:IsActive() → boolean`: Return whether the language filters are currently registered. ([`../Src/Bridges/LanguagesBridge.lua#L247`](../Src/Bridges/LanguagesBridge.lua#L247))
- Invariants:
  - `PRE_SEND` mutates `payload.text` only; `PRE_CHUNK` sets `payload.continuationPrefix` only. Both derive from one resolver, so the head chunk and continuation chunks can never disagree.
  - The dialect gate and the tag gate are independent, matching upstream: a faction-suppressed tag does not suppress the dialect.
- Diagnostics: `/lyb`.

## Migrations

- Methods:
  - `Migrations:MigrateMisspellingColour(configTable, configType) → nil`: Migrate removed underline-style spellcheck rendering settings to the single MisspellingColour key used by the recolour engine. ([`../Src/Migrations.lua#L149`](../Src/Migrations.lua#L149))



## Interface.HelpContent

- Methods:
  - `HelpContent.ForEachItem(callback) → nil`: Iterate the read-only help items through a safe callback-based iterator because Lua 5.1's ipairs bypasses __index proxies. ([`../Src/Interface/HelpContent.lua#L158`](../Src/Interface/HelpContent.lua#L158))

## EditBoxCompat

- Methods:
  - `EditBox:SetChatCompatibilityEnabled(enabled) → nil`: Toggle Blizzard GetActiveWindow/FocusActiveWindow compatibility wrappers on or off during lockdown handoff and recovery. The wrappers route active-window queries to Yapper while safe and fall back to native behavior during lockdown/bypass. ([`../Src/EditBoxCompat.lua#L197`](../Src/EditBoxCompat.lua#L197))

## WhisperMessengerBridge

- Methods:
  - `WhisperMessengerBridge:HookSecureButtonCreation() → nil`: Hook Keybinds.CreateSecureButtons so the bridge re-wraps whenever the secure buttons are recreated. ([`../Src/Bridges/WhisperMessengerBridge.lua#L141`](../Src/Bridges/WhisperMessengerBridge.lua#L141))
  - `WhisperMessengerBridge:WrapReplyKeybind() → nil`: Wrap the REPLYTELL2 secure button's PostClick so the reply/re-whisper keybind is delegated when WhisperMessenger owns its window. ([`../Src/Bridges/WhisperMessengerBridge.lua#L88`](../Src/Bridges/WhisperMessengerBridge.lua#L88))
  - `WhisperMessengerBridge:IsWindowVisible() → boolean`: Check whether the WhisperMessenger window is currently visible. ([`../Src/Bridges/WhisperMessengerBridge.lua#L50`](../Src/Bridges/WhisperMessengerBridge.lua#L50))

## EditBox.Keybinds

- Methods:
  - `Keybinds:SyncContextYields() → nil`: Re-apply override bindings so keys claimed by an active binding context (e.g. housing editor modes) stay yielded; unlike `RefreshOverrides` it intentionally runs during combat/chat lockdown since override set/clear is not a protected operation. Called by binding-context and housing-selection change triggers. ([`../Src/EditBox/Keybinds.lua#L503`](../Src/EditBox/Keybinds.lua#L503))

## Strings

Localisation resolver: canonical `enUS` table plus owner-captured sparse
locale overrides contributed by dictionary addons via
`YapperAPI:RegisterStrings`. Resolution follows the **client** UI locale
(never the spellcheck dictionary locale) → `enUS` fallback → the key itself.
UI resolves strings at render/show time; a `STRINGS_UPDATED` event fires
when registrations arrive so visible widgets can relabel.

- Methods:
  - `Strings:Get(key, ...) → string`: Resolve a key for the active client locale with enUS fallback; trailing args are `string.format` parameters. ([`../Src/Strings.lua#L103`](../Src/Strings.lua#L103))
  - `Strings:Register(locale, tbl, owner) → boolean ok`: Register a sparse locale string table; keys must already exist in the canonical enUS table, `enUS` cannot be overridden, values are length-bounded, and owner-captured re-registration replaces that owner's contribution. ([`../Src/Strings.lua#L128`](../Src/Strings.lua#L128))
  - `Strings:CanonicalKeys() → table`: Enumerate canonical keys — used by `tools/check_string_refs.py` and tests. ([`../Src/Strings.lua#L201`](../Src/Strings.lua#L201))
