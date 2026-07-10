# Internals reference (`_G.Yapper` / `YapperTable`)

> ⚠️ Everything documented here is **internal**. Use `YapperAPI` (see `API.md`) when possible.
> By interacting with, using and/or modifying internals directly (e.g. through `_G.Yapper`), you accept that these internals may change or be removed at any time, without notice, and that you are solely responsible for maintenance. Always prefer API over internals, and if you find yourself missing critical surface area for which it makes sense to create API, please reach out.

All sections below follow TOC load order from [`Yapper.toc`](../Yapper.toc).

## YapperTable root (`_G.Yapper`)

Published in [`../Yapper.lua#L64`](../Yapper.lua#L64).

- Description: global namespace alias for the addon-private table.
- Fields:
  - `YapperTable.YAPPER_DISABLED: boolean` set by override toggle ([`../Yapper.lua#L282`](../Yapper.lua#L282)).
- Methods:
  - `YapperTable:OverrideYapper(disable: boolean) → nil` ([`../Yapper.lua#L277`](../Yapper.lua#L277)) — toggles runtime ownership between Yapper overlay and Blizzard chat; cancels queue and unregisters events when disabling.

## Core

Initialised on `ADDON_LOADED` by [`Yapper.lua#L105-L110`](../Yapper.lua#L105-L110).

- Description: SavedVariables schema/default/migration authority.
- Fields:
  - `Yapper.Config: table` live config root ([`../Src/Core.lua#L286`](../Src/Core.lua#L286)).
- Methods:
  - `Core:IsLanguageCacheValid() → boolean isValid`: Check if the language cache is still valid for the current character. ([`../Src/Core.lua#L322`](../Src/Core.lua#L322))
  - `Core:RegisterFrame(category, key, frame) → nil`: Register a frame in the central UI registry for external access. ([`../Src/Core.lua#L386`](../Src/Core.lua#L386))
  - `Core:DemoteGlobalToCharacter() → nil`: Unpack stashed local settings when switching away from Global Profile. ([`../Src/Core.lua#L826`](../Src/Core.lua#L826))
  - `Core:RefreshInheritance() → nil`: Initialise inheritance chain (Global vs Local). ([`../Src/Core.lua#L624`](../Src/Core.lua#L624))
  - `Core:GetCharacterLanguage(lang) → number langId`: Get the language or defaults if not present. ([`../Src/Core.lua#L353`](../Src/Core.lua#L353))
  - `Core:BuildLanguageCache() → nil`: No description provided. ([`../Src/Core.lua#L292`](../Src/Core.lua#L292))
  - `Core:InitSavedVars() → nil` ([`../Src/Core.lua#L514`](../Src/Core.lua#L514)) — creates/migrates `YapperDB`, `YapperLocalConf`, `YapperLocalHistory`; mutates metatables for inheritance.
  - `Core:GetVersion() → string` ([`../Src/Core.lua#L647`](../Src/Core.lua#L647))
  - `Core:GetDefaults() → table` ([`../Src/Core.lua#L651`](../Src/Core.lua#L651))
  - `Core:SetVerbose(bool: boolean) → nil` ([`../Src/Core.lua#L655`](../Src/Core.lua#L655))
  - `Core:SaveSetting(category, key, value) → nil` ([`../Src/Core.lua#L668`](../Src/Core.lua#L668)) — delegates to `Interface:SetLocalPath` for profile-aware write routing.
  - `Core:PromoteCharacterToGlobal() → nil` ([`../Src/Core.lua#L733`](../Src/Core.lua#L733)) — wipes local overrides (excluding `MainWindowPosition`) and re-seeds metatable inheritance from `YapperDB`.
  - `Core:PushToGlobal() → nil` ([`../Src/Core.lua#L847`](../Src/Core.lua#L847)) — deep-copies character settings into `YapperDB`. Whitelists `System` keys; excludes `MainWindowPosition`; migrates `_themeOverrides` and `_appliedTheme` markers; no-op when already global.
- Invariants:
  - Must run before feature init (`LoadSavedVariablesFirst: 1`).
  - Metatable chain must remain intact for local fallback/inheritance logic.

## Utils

Loaded at startup; used by most modules.

- Description: Print/debug/fullscreen/chat utility helpers.
- Fields:
  - `_G.YAPPER_UTILS: table` alias for debug access ([`../Src/Utils.lua#L123`](../Src/Utils.lua#L123)).
- Methods:
  - `Utils:Print(...) → nil` ([`../Src/Utils.lua#L19`](../Src/Utils.lua#L19))
  - `Utils:VerbosePrint(...) → nil` ([`../Src/Utils.lua#L33`](../Src/Utils.lua#L33))
  - `Utils:DebugPrint(...) → nil` ([`../Src/Utils.lua#L39`](../Src/Utils.lua#L39))
  - `Utils:GetChatParent() → Frame` ([`../Src/Utils.lua#L48`](../Src/Utils.lua#L48))
  - `Utils:MakeFullscreenAware(frame) → nil` ([`../Src/Utils.lua#L60`](../Src/Utils.lua#L60))
  - `Utils:IsChatLockdown() → boolean` ([`../Src/Utils.lua#L89`](../Src/Utils.lua#L89))
  - `Utils:IsSecret(value) → boolean` ([`../Src/Utils.lua#L164`](../Src/Utils.lua#L164))

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
  - `_lastCancelOwner: string|nil` *private by convention; do not rely on* ([`../Src/API.lua#L1234`](../Src/API.lua#L1234)).
- Methods:
  - `API:_createClaim(text, chatType, language, target, owner) → number` ([`../Src/API.lua#L1046`](../Src/API.lua#L1046))
  - `API:RunFilter(hookPoint, payload) → table|false` ([`../Src/API.lua#L1220`](../Src/API.lua#L1220))
  - `API:Fire(event, ...) → nil` ([`../Src/API.lua#L1255`](../Src/API.lua#L1255))
  - `API:GetStateLogCount() → number` ([`../Src/API.lua#L536`](../Src/API.lua#L536)) — returns the number of entries in the FSM state history.
  - `API:GetStateLog(index) → table|nil` ([`../Src/API.lua#L527`](../Src/API.lua#L527)) — returns a specific state transition log entry.
  - `API:GetStateLogs() → table` ([`../Src/API.lua#L517`](../Src/API.lua#L517)) — returns the full circular buffer of state transitions.
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
  - `State:ToConfig() → nil`: Transition to CONFIG (settings) state. ([`../Src/State.lua#L276`](../Src/State.lua#L276))
  - `State:IsConfig() → boolean`: Is the settings/interface window open? ([`../Src/State.lua#L225`](../Src/State.lua#L225))
  - `State:IsInitialised() → boolean`: Has the machine completed initialisation (i.e. not in INITIALISING state)? ([`../Src/State.lua#L183`](../Src/State.lua#L183))
  - `State:SetFlag(name, value, persistent) → nil`: Set a state flag value. ([`../Src/State.lua#L75`](../Src/State.lua#L75))
  - `State:GetFlag(name, default) → any`: Get a state flag value. ([`../Src/State.lua#L54`](../Src/State.lua#L54))
  - `State:IsInitialising() → boolean`: Is the machine in INITIALISING state? ([`../Src/State.lua#L177`](../Src/State.lua#L177))
  - `State:ToLockdown() → nil`: Transition to LOCKDOWN state. ([`../Src/State.lua#L271`](../Src/State.lua#L271))
  - `State:ToStalled() → nil`: Transition to STALLED state. ([`../Src/State.lua#L266`](../Src/State.lua#L266))
  - `State:ToSending() → nil`: Transition to SENDING state. ([`../Src/State.lua#L261`](../Src/State.lua#L261))
  - `State:ToMultiline() → nil`: Transition to MULTILINE state. ([`../Src/State.lua#L256`](../Src/State.lua#L256))
  - `State:ToEditing() → nil`: Transition to EDITING state. ([`../Src/State.lua#L251`](../Src/State.lua#L251))
  - `State:ToIdle() → nil`: Transition to IDLE state. ([`../Src/State.lua#L246`](../Src/State.lua#L246))
  - `State:IsInputActive() → boolean`: Helper: is the user currently typing (either overlay or multiline)? ([`../Src/State.lua#L231`](../Src/State.lua#L231))
  - `State:IsLockdown() → boolean`: Is the addon suppressed by combat or manual lockdown? ([`../Src/State.lua#L219`](../Src/State.lua#L219))
  - `State:IsStalled() → boolean`: Is the queue stalled awaiting hardware input? ([`../Src/State.lua#L213`](../Src/State.lua#L213))
  - `State:IsSending() → boolean`: Is a message currently being delivered? ([`../Src/State.lua#L207`](../Src/State.lua#L207))
  - `State:IsMultiline() → boolean`: Is the user typing in the expanded multiline editor? ([`../Src/State.lua#L201`](../Src/State.lua#L201))
  - `State:IsEditing() → boolean`: Is the user typing in the single-line overlay? ([`../Src/State.lua#L195`](../Src/State.lua#L195))
  - `State:IsIdle() → boolean`: Is the machine in IDLE state? ([`../Src/State.lua#L189`](../Src/State.lua#L189))
  - `State:IsInitialising() → boolean`: Is the machine in INITIALISING state? ([`../Src/State.lua#L177`](../Src/State.lua#L177))
  - `State:GetLogCount() → number` ([`../Src/State.lua#L337`](../Src/State.lua#L337)) — returns the number of transitions stored in the history buffer.
  - `State:GetLog(index) → table|nil` ([`../Src/State.lua#L344`](../Src/State.lua#L344)) — returns the transition log at the given index.
  - `State:GetLogs() → table` ([`../Src/State.lua#L350`](../Src/State.lua#L350)) — returns the raw circular buffer table.
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
  - Underline/suggestion state: `UnderlinePool`, `Underlines`, `SuggestionRows`, `ActiveSuggestions`, `ActiveIndex`, `ActiveWord`, `ActiveRange`, `_debounceTimer` ([`../Src/Spellcheck.lua#L59-L60`](../Src/Spellcheck.lua#L59-L60), [`../Src/Spellcheck.lua#L62-L66`](../Src/Spellcheck.lua#L62-L66), [`../Src/Spellcheck.lua#L78`](../Src/Spellcheck.lua#L78)).
  - Dictionary/user state: `UserDictCache` ([`../Src/Spellcheck.lua#L79`](`../Src/Spellcheck.lua#L79`))
  - Dictionary/user state: `_pendingLocaleLoads` ([`../Src/Spellcheck.lua#L80`](`../Src/Spellcheck.lua#L80`))
  - Dictionary/user state: `DictionaryBuilders` ([`../Src/Spellcheck.lua#L82`](`../Src/Spellcheck.lua#L82`))
  - Edit-distance buffers: `_ed_prev`, `_ed_cur`, `_ed_prev_prev` *private by convention; do not rely on* ([`../Src/Spellcheck.lua#L73-L75`](../Src/Spellcheck.lua#L73-L75)).
  - Tunable constants/helpers: `_SCORE_WEIGHTS`, `_MAX_SUGGESTION_ROWS`, `_RAID_ICONS`, `_KB_LAYOUTS`, `_DICT_CHUNK_SIZE` *private by convention; do not rely on* ([`../Src/Spellcheck.lua#L665-L675`](../Src/Spellcheck.lua#L665-L675)).
- Methods:
  - `Spellcheck:GetUserDictWordCap() → number`: Returns the maximum number of words in `AddedWords` before oldest entries are FIFO-evicted. Configurable via `UserDictWordCap`; default 2000, min 50, max 10000. ([`../Src/Spellcheck.lua#L657`](../Src/Spellcheck.lua#L657))
  - `Spellcheck:IsWordBlocked(word, locale, ignoreManual) → boolean`: Convenience function for checking a single word (e.g., during YAS learning). ([`../Src/Spellcheck.lua#L550`](../Src/Spellcheck.lua#L550))
  - `Spellcheck:GetBlockData(locale) → table|nil addedSet`: Returns the data needed to check if a word is blocked at runtime. ([`../Src/Spellcheck.lua#L531`](../Src/Spellcheck.lua#L531))
  - `Spellcheck:EvictRandomMeta() → nil`: No description provided. ([`../Src/Spellcheck.lua#L437`](../Src/Spellcheck.lua#L437))
  - `Spellcheck:Init(threads) → nil` ([`../Src/Spellcheck.lua#L198`](../Src/Spellcheck.lua#L198))
  - `Spellcheck:_RegisterLanguageEngine(familyId, engine) → boolean` ([`../Src/Spellcheck.lua#L223`](../Src/Spellcheck.lua#L223)) — **Security Note**: Enforces mandatory `BlockedHashes` table and `HashWord` function. Returns `false` and prints a chat error if missing.
  - `Spellcheck:GetActiveEngine() → table|nil` ([`../Src/Spellcheck.lua#L248`](../Src/Spellcheck.lua#L248))
  - `Spellcheck:GetEngine(familyId) → table|nil` ([`../Src/Spellcheck.lua#L257`](../Src/Spellcheck.lua#L257))
  - `Spellcheck:GetConfig() → table` ([`../Src/Spellcheck.lua#L344`](../Src/Spellcheck.lua#L344))
  - `Spellcheck:IsEnabled() → boolean` ([`../Src/Spellcheck.lua#L348`](../Src/Spellcheck.lua#L348))
  - `Spellcheck:GetLocale() → string` ([`../Src/Spellcheck.lua#L353`](../Src/Spellcheck.lua#L353))
  - `Spellcheck:GetFallbackLocale() → string` ([`../Src/Spellcheck.lua#L381`](../Src/Spellcheck.lua#L381))
  - `Spellcheck:GetDictionary() → table|nil` ([`../Src/Spellcheck.lua#L389`](../Src/Spellcheck.lua#L389))
  - `Spellcheck:GetMeta(dict, word) → table|nil` ([`../Src/Spellcheck.lua#L399`](../Src/Spellcheck.lua#L399))

  - `Spellcheck:GetUserDictStore() → table` ([`../Src/Spellcheck.lua#L457`](../Src/Spellcheck.lua#L457))
  - `Spellcheck:GetUserDict(locale) → table` ([`../Src/Spellcheck.lua#L481`](../Src/Spellcheck.lua#L481))
  - `Spellcheck:TouchUserDict(dict) → nil` ([`../Src/Spellcheck.lua#L491`](../Src/Spellcheck.lua#L491))
  - `Spellcheck:BuildWordSet(list) → table` ([`../Src/Spellcheck.lua#L498`](../Src/Spellcheck.lua#L498))
  - `Spellcheck:GetUserSets(locale) → table, table` ([`../Src/Spellcheck.lua#L512`](../Src/Spellcheck.lua#L512))
  - `Spellcheck:AddUserWord(locale, word) → nil` ([`../Src/Spellcheck.lua#L568`](../Src/Spellcheck.lua#L568)) — adds `word` to `AddedWords`; FIFO-evicts the oldest entry when the list exceeds `GetUserDictWordCap()`.
  - `Spellcheck:IgnoreWord(locale, word) → nil` ([`../Src/Spellcheck.lua#L596`](../Src/Spellcheck.lua#L596))
  - `Spellcheck:ClearSuggestionCache() → nil` ([`../Src/Spellcheck.lua#L620`](../Src/Spellcheck.lua#L620))
  - Accessors: `GetMaxSuggestions` ([`../Src/Spellcheck.lua#L625`](`../Src/Spellcheck.lua#L625`))
  - Accessors: `GetMaxCandidates` ([`../Src/Spellcheck.lua#L630`](`../Src/Spellcheck.lua#L630`))
  - Accessors: `GetSuggestionCacheSize` ([`../Src/Spellcheck.lua#L635`](`../Src/Spellcheck.lua#L635`))
  - Accessors: `GetReshuffleAttempts` ([`../Src/Spellcheck.lua#L640`](`../Src/Spellcheck.lua#L640`))
  - Accessors: `GetMaxWrongLetters` ([`../Src/Spellcheck.lua#L645`](`../Src/Spellcheck.lua#L645`))
  - Accessors: `GetMinWordLength` ([`../Src/Spellcheck.lua#L650`](`../Src/Spellcheck.lua#L650`))
  - Accessors: `GetUnderlineStyle` ([`../Src/Spellcheck.lua#L660`](`../Src/Spellcheck.lua#L660`))
  - Accessors: `GetKeyboardLayout` ([`../Src/Spellcheck.lua#L668`](`../Src/Spellcheck.lua#L668`))
  - Accessors: `GetKBDistTable` ([`../Src/Spellcheck.lua#L678`](`../Src/Spellcheck.lua#L678`))
  - Accessors: `_GetKBDistFromLayouts` ([`../Src/Spellcheck.lua#L697`](`../Src/Spellcheck.lua#L697`))
- Callbacks fired:
  - `SPELLCHECK_WORD_ADDED`, `SPELLCHECK_WORD_IGNORED`.

## Spellcheck.Dictionary

Used lazily by `GetDictionary`, locale switches, and LOD registration.

- Description: Dictionary registration/loading, locale availability, async indexing.
- Methods:
  - `Spellcheck:LoadDictionary(locale) → nil` ([`../Src/Spellcheck/Dictionary.lua#L36`](../Src/Spellcheck/Dictionary.lua#L36))
  - `Spellcheck:RegisterDictionary(locale, data) → nil` ([`../Src/Spellcheck/Dictionary.lua#L71`](../Src/Spellcheck/Dictionary.lua#L71)) — **Security Note**: Validates the associated language family engine for `BlockedHashes` before indexing. Blocks registration if the family engine is missing or insecure.
  - `Spellcheck:_OnDictRegistrationComplete(locale) → nil` ([`../Src/Spellcheck/Dictionary.lua#L370`](../Src/Spellcheck/Dictionary.lua#L370))
  - `Spellcheck:GetAvailableLocales() → string[]` ([`../Src/Spellcheck/Dictionary.lua#L413`](../Src/Spellcheck/Dictionary.lua#L413))
  - `Spellcheck:GetLocaleAddon(locale) → string|nil` ([`../Src/Spellcheck/Dictionary.lua#L422`](../Src/Spellcheck/Dictionary.lua#L422))
  - `Spellcheck:HasLocaleAddon(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L427`](../Src/Spellcheck/Dictionary.lua#L427))
  - `Spellcheck:HasAnyDictionary() → boolean` ([`../Src/Spellcheck/Dictionary.lua#L458`](../Src/Spellcheck/Dictionary.lua#L458))
  - `Spellcheck:IsLocaleAvailable(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L470`](../Src/Spellcheck/Dictionary.lua#L470))
  - `Spellcheck:CanLoadLocale(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L484`](../Src/Spellcheck/Dictionary.lua#L484))
  - `Spellcheck:Notify(msg) → nil` ([`../Src/Spellcheck/Dictionary.lua#L499`](../Src/Spellcheck/Dictionary.lua#L499))
  - `Spellcheck:EnsureLocale(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L505`](../Src/Spellcheck/Dictionary.lua#L505))
  - `Spellcheck:ScheduleLocaleRefresh(locale) → nil` ([`../Src/Spellcheck/Dictionary.lua#L572`](../Src/Spellcheck/Dictionary.lua#L572))
  - `dict:Contains(word: string) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L193`](../Src/Spellcheck/Dictionary.lua#L193)) — returns true if the word (normalised) exists in the dictionary, its base, or the user's personal dictionary.
- Side effects:
  - Schedules `C_Timer.After(0, ...)` chunk processing and refresh tickers.

## Spellcheck.Engine

Runs during suggestion/underline rebuild.

- Description: Tokenisation, misspelling detection, candidate scoring.
- Methods:
  - `Spellcheck:CollectAffixMatches() → nil`: Scans text for words recognized via affix-stripping. ([`../Src/Spellcheck/Engine.lua#L126`](../Src/Spellcheck/Engine.lua#L126))
  - `CollectMisspellings` ([`../Src/Spellcheck/Engine.lua#L81`](`../Src/Spellcheck/Engine.lua#L81`))
  - `ShouldCheckWord` ([`../Src/Spellcheck/Engine.lua#L142`](`../Src/Spellcheck/Engine.lua#L142`))
  - `GetIgnoredRanges` ([`../Src/Spellcheck/Engine.lua#L149`](`../Src/Spellcheck/Engine.lua#L149`))
  - `IsRangeIgnored` ([`../Src/Spellcheck/Engine.lua#L202`](`../Src/Spellcheck/Engine.lua#L202`))
  - `IsWordCorrect` ([`../Src/Spellcheck/Engine.lua#L211`](`../Src/Spellcheck/Engine.lua#L211`))
  - `ResolveImplicitTrace` ([`../Src/Spellcheck/Engine.lua#L248`](`../Src/Spellcheck/Engine.lua#L248`))
  - `UpdateActiveWord` ([`../Src/Spellcheck/Engine.lua#L293`](`../Src/Spellcheck/Engine.lua#L293`))
  - `GetWordAtCursor` ([`../Src/Spellcheck/Engine.lua#L374`](`../Src/Spellcheck/Engine.lua#L374`))
  - `GetSuggestions` ([`../Src/Spellcheck/Engine.lua#L911`](`../Src/Spellcheck/Engine.lua#L911`))
  - `EditDistance` ([`../Src/Spellcheck/Engine.lua#L1217`](`../Src/Spellcheck/Engine.lua#L1217`))
  - `FormatSuggestionLabel` ([`../Src/Spellcheck/Engine.lua#L1289`](`../Src/Spellcheck/Engine.lua#L1289`))
- Filters run:
  - `PRE_SPELLCHECK` via `API:RunFilter`.

## Spellcheck.UI

Bound when overlay exists; reacts to text/cursor updates.

- Description: UI state machine for underlines, hint, and suggestions.
- Methods:
  - `Spellcheck:SetSpellcheckOffset(hintX, hintY, suggestX, suggestY) → nil`: Set manual pixel offsets for spellcheck tooltips. ([`../Src/Spellcheck/UI.lua#L621`](../Src/Spellcheck/UI.lua#L621))
  - `Bind` ([`../Src/Spellcheck/UI.lua#L30`](`../Src/Spellcheck/UI.lua#L30`))
  - `BindMultiline` ([`../Src/Spellcheck/UI.lua#L65`](`../Src/Spellcheck/UI.lua#L65`))
  - `UnbindMultiline` ([`../Src/Spellcheck/UI.lua#L126`](`../Src/Spellcheck/UI.lua#L126`))
  - `PurgeOtherDictionaries` ([`../Src/Spellcheck/UI.lua#L164`](`../Src/Spellcheck/UI.lua#L164`))
  - `UnloadAllDictionaries` ([`../Src/Spellcheck/UI.lua#L218`](`../Src/Spellcheck/UI.lua#L218`))
  - `ApplyState` ([`../Src/Spellcheck/UI.lua#L260`](`../Src/Spellcheck/UI.lua#L260`))
  - `OnConfigChanged` ([`../Src/Spellcheck/UI.lua#L291`](`../Src/Spellcheck/UI.lua#L291`))
  - `OnTextChanged` ([`../Src/Spellcheck/UI.lua#L295`](`../Src/Spellcheck/UI.lua#L295`))
  - `OnCursorChanged` ([`../Src/Spellcheck/UI.lua#L315`](`../Src/Spellcheck/UI.lua#L315`))
  - `OnOverlayHide` ([`../Src/Spellcheck/UI.lua#L359`](`../Src/Spellcheck/UI.lua#L359`))
  - `ScheduleRefresh` ([`../Src/Spellcheck/UI.lua#L365`](`../Src/Spellcheck/UI.lua#L365`))
  - `Rebuild` ([`../Src/Spellcheck/UI.lua#L388`](`../Src/Spellcheck/UI.lua#L388`))
  - `EnsureMeasureFontString` ([`../Src/Spellcheck/UI.lua#L402`](`../Src/Spellcheck/UI.lua#L402`))
  - `EnsureSuggestionFrame` ([`../Src/Spellcheck/UI.lua#L417`](`../Src/Spellcheck/UI.lua#L417`))
  - `SuggestionsEqual` ([`../Src/Spellcheck/UI.lua#L510`](`../Src/Spellcheck/UI.lua#L510`))
  - `EnsureHintFrame` ([`../Src/Spellcheck/UI.lua#L520`](`../Src/Spellcheck/UI.lua#L520`))
  - `CancelHintTimer` ([`../Src/Spellcheck/UI.lua#L546`](`../Src/Spellcheck/UI.lua#L546`))
  - `ScheduleHintShow` ([`../Src/Spellcheck/UI.lua#L558`](`../Src/Spellcheck/UI.lua#L558`))
  - `ShowHint` ([`../Src/Spellcheck/UI.lua#L636`](`../Src/Spellcheck/UI.lua#L636`))
  - `HideHint` ([`../Src/Spellcheck/UI.lua#L657`](`../Src/Spellcheck/UI.lua#L657`))
  - `UpdateHint` ([`../Src/Spellcheck/UI.lua#L662`](`../Src/Spellcheck/UI.lua#L662`))
  - `IsSuggestionOpen` ([`../Src/Spellcheck/UI.lua#L685`](`../Src/Spellcheck/UI.lua#L685`))
  - `IsSuggestionEligible` ([`../Src/Spellcheck/UI.lua#L689`](`../Src/Spellcheck/UI.lua#L689`))
  - `HandleKeyDown` ([`../Src/Spellcheck/UI.lua#L696`](`../Src/Spellcheck/UI.lua#L696`))
  - `MoveSelection` ([`../Src/Spellcheck/UI.lua#L757`](`../Src/Spellcheck/UI.lua#L757`))
  - `RefreshSuggestionSelection` ([`../Src/Spellcheck/UI.lua#L779`](`../Src/Spellcheck/UI.lua#L779`))
  - `OpenOrCycleSuggestions` ([`../Src/Spellcheck/UI.lua#L811`](`../Src/Spellcheck/UI.lua#L811`))
  - `ShowSuggestions` ([`../Src/Spellcheck/UI.lua#L840`](`../Src/Spellcheck/UI.lua#L840`))
  - `NextSuggestionsPage` ([`../Src/Spellcheck/UI.lua#L961`](`../Src/Spellcheck/UI.lua#L961`))
  - `HideSuggestions` ([`../Src/Spellcheck/UI.lua#L988`](`../Src/Spellcheck/UI.lua#L988`))
  - `ApplySuggestion` ([`../Src/Spellcheck/UI.lua#L1012`](`../Src/Spellcheck/UI.lua#L1012`))
- Fields:
  - `HintDelay: number` ([`../Src/Spellcheck/UI.lua#L556`](../Src/Spellcheck/UI.lua#L556)).
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
  - `auto[word] = { c, t }` — repeated uncorrected words pending auto-promotion.
  - `autoCount: number` — cached count of `auto` entries (maintained for O(1) cap checks).
  - `negBiasCount: number` — cached count of `negBias` entries.
  - `total: number` — tracked unique vocabulary size for frequency-cap enforcement.
  ([`../Src/Spellcheck/Adaptive.lua#L63-L100`](../Src/Spellcheck/Adaptive.lua#L63-L100)).
- Methods:
  - `YAS:GetAutoCap() → number`: Returns the maximum number of entries tracked in the `auto` table before low-scoring ones are pruned. Configurable via `YASAutoCap`; default 500, min 50, max 5000. ([`../Src/Spellcheck/Adaptive.lua#L154`](../Src/Spellcheck/Adaptive.lua#L154))
  - `YAS:GetNegBiasCap() → number`: Returns the maximum number of `negBias` rejection-pair entries before low-scoring ones are pruned. Configurable via `YASNegBiasCap`; default 500, min 100, max 10000. ([`../Src/Spellcheck/Adaptive.lua#L147`](../Src/Spellcheck/Adaptive.lua#L147))
  - `YAS:Export() → nil`: Export current learned data for a locale as a text block. ([`../Src/Spellcheck/Adaptive.lua#L835`](../Src/Spellcheck/Adaptive.lua#L835))
  - `YAS:GetBiasTargets() → nil`: Returns a list of candidate words that have been learned as corrections for the given typo. ([`../Src/Spellcheck/Adaptive.lua#L668`](../Src/Spellcheck/Adaptive.lua#L668))
  - `YAS:EnsureFreqSorted() → nil`: Ensures the frequency-sorted index is up-to-date, rebuilding if dirty. ([`../Src/Spellcheck/Adaptive.lua#L240`](../Src/Spellcheck/Adaptive.lua#L240))
  - `IsEnabled() → boolean`: Returns true if YAS is enabled in the configuration. ([`../Src/Spellcheck/Adaptive.lua#L115`](../Src/Spellcheck/Adaptive.lua#L115))
  - `GetFreqCap` ([`../Src/Spellcheck/Adaptive.lua#L124`](../Src/Spellcheck/Adaptive.lua#L124))
  - `GetBiasCap` ([`../Src/Spellcheck/Adaptive.lua#L131`](../Src/Spellcheck/Adaptive.lua#L131))
  - `GetAutoThreshold` ([`../Src/Spellcheck/Adaptive.lua#L138`](../Src/Spellcheck/Adaptive.lua#L138))
  - `Init` ([`../Src/Spellcheck/Adaptive.lua#L163`](../Src/Spellcheck/Adaptive.lua#L163))
  - `GetLocaleDB` ([`../Src/Spellcheck/Adaptive.lua#L190`](../Src/Spellcheck/Adaptive.lua#L190))
  - `IsSaneWord` ([`../Src/Spellcheck/Adaptive.lua#L264`](../Src/Spellcheck/Adaptive.lua#L264))
  - `RecordUsage` ([`../Src/Spellcheck/Adaptive.lua#L306`](../Src/Spellcheck/Adaptive.lua#L306))
  - `RecordSelection` ([`../Src/Spellcheck/Adaptive.lua#L353`](../Src/Spellcheck/Adaptive.lua#L353))
  - `RecordImplicitCorrection` ([`../Src/Spellcheck/Adaptive.lua#L435`](../Src/Spellcheck/Adaptive.lua#L435))
  - `RecordRejection` ([`../Src/Spellcheck/Adaptive.lua#L531`](../Src/Spellcheck/Adaptive.lua#L531))
  - `RecordIgnored` ([`../Src/Spellcheck/Adaptive.lua#L565`](../Src/Spellcheck/Adaptive.lua#L565))
  - `GetBonus` ([`../Src/Spellcheck/Adaptive.lua#L613`](../Src/Spellcheck/Adaptive.lua#L613))
  - `Prune` ([`../Src/Spellcheck/Adaptive.lua#L714`](../Src/Spellcheck/Adaptive.lua#L714))
  - `Reset` ([`../Src/Spellcheck/Adaptive.lua#L763`](../Src/Spellcheck/Adaptive.lua#L763))
  - `GetDataSummary` ([`../Src/Spellcheck/Adaptive.lua#L779`](../Src/Spellcheck/Adaptive.lua#L779))
  - `ClearSpecificUsage` ([`../Src/Spellcheck/Adaptive.lua#L872`](../Src/Spellcheck/Adaptive.lua#L872))
- Score model:
  - `GetBonus` applies `freqBonus`, `biasBonus`, `phBonus`, and `negBias` penalty and returns an additive score adjustment used in candidate ranking. The `negBias` penalty is time-decayed: `penalty × 1/(ageDays/30 + 1)`, halving roughly every 30 days. ([`../Src/Spellcheck/Adaptive.lua#L660`](../Src/Spellcheck/Adaptive.lua#L660), [`../Src/Spellcheck/Engine.lua#L695-L696`](../Src/Spellcheck/Engine.lua#L695-L696)).
- Learning entry points:
  - `Chat:DirectSend` records usage and ignored-word counts ([`../Src/Chat.lua#L199-L215`](../Src/Chat.lua#L199-L215)).
  - `Spellcheck.UI` records explicit suggestion picks/rejections ([`../Src/Spellcheck/UI.lua#L869-L962`](../Src/Spellcheck/UI.lua#L869-L962)).
  - `Spellcheck.Engine` records implicit corrections from retyped trace words ([`../Src/Spellcheck/Engine.lua#L236-L238`](../Src/Spellcheck/Engine.lua#L236-L238)).
- Invariants / safeguards:
  - `IsSaneWord` gates noisy tokens before learning; pruning preserves highest relevance entries by count/utility/recency score; caps/thresholds are clamped from config (`YASEnabled`, `YASFreqCap`, `YASBiasCap`, `YASNegBiasCap`, `YASAutoThreshold`, `YASAutoCap`) ([`../Src/Spellcheck/Adaptive.lua#L130-L170`](../Src/Spellcheck/Adaptive.lua#L130-L170), [`../Src/Spellcheck/Adaptive.lua#L269-L310`](../Src/Spellcheck/Adaptive.lua#L269-L310), [`../Src/Core.lua#L217-L224`](../Src/Core.lua#L217-L224)).
- Callbacks fired:
  - `YAS_WORD_LEARNED` (deprecated `YALLM_WORD_LEARNED` is automatically aliased to this event).

## IconGallery

Lazy-created; used by spellcheck/autocomplete edit flows and public API.

- Description: Raid icon picker popup and selection callbacks.
- Methods:
  - `Init` ([`../Src/IconGallery.lua#L19`](../Src/IconGallery.lua#L19))
  - `Show` ([`../Src/IconGallery.lua#L78`](../Src/IconGallery.lua#L78))
  - `Hide` ([`../Src/IconGallery.lua#L110`](../Src/IconGallery.lua#L110))
  - `Filter` ([`../Src/IconGallery.lua#L122`](../Src/IconGallery.lua#L122))
  - `Select` ([`../Src/IconGallery.lua#L148`](../Src/IconGallery.lua#L148))
  - `HandleKeyDown` ([`../Src/IconGallery.lua#L174`](../Src/IconGallery.lua#L174))
  - `_GetIconMeta` ([`../Src/IconGallery.lua#L217`](../Src/IconGallery.lua#L217))
  - `OnTextChanged` ([`../Src/IconGallery.lua#L228`](../Src/IconGallery.lua#L228))
- Callbacks fired:
  - `ICON_GALLERY_SHOW`, `ICON_GALLERY_HIDE`, `ICON_GALLERY_SELECT`.

## EditBox
- Methods:
  - [NEW] `EditBox:ApplyProgrammaticPrefill(text, box) → nil`: Apply text prefill to the overlay editbox and mirror any UX side-effects ([`../Src/EditBox.lua#L565`](../Src/EditBox.lua#L565))
  - [NEW] `EditBox:IsChatTypeAvailable() → nil`: Check if a chat type is currently available (e.g., in a guild, in a raid). ([`../Src/EditBox.lua#L535`](../Src/EditBox.lua#L535))
  - [NEW] `EditBox:GetResolvedChatType() → nil`: Smartly switch from Party/Raid to Instance if the Home group is missing. ([`../Src/EditBox.lua#L513`](../Src/EditBox.lua#L513))
  - `EditBox:RegisterKeybindOverrides() → nil`: Register keybind overrides when timing is safe. ([`../Src/EditBox.lua#L599`](../Src/EditBox.lua#L599))
  - `EditBox:InitKeybinds() → nil`: Initialize keybind override system. ([`../Src/EditBox.lua#L588`](../Src/EditBox.lua#L588))
  - `EditBox:UpdateFocusOverride() → nil`: Centralize focus override updating. Sets/clears CHAT_FOCUS_OVERRIDE ([`../Src/EditBox.lua#L90`](../Src/EditBox.lua#L90))
  - `YapperTable.InstallCompatMethods(box) → nil`: Installs Blizzard chat-box compatibility methods and stubs on the overlay editbox so addons can query `GetChatType`, `GetChannelTarget`, `GetTellTarget`, `GetLanguage`, `GetAttribute`, and parity fields without nil-crashes. ([`../Src/EditBoxCompat.lua#L46`](../Src/EditBoxCompat.lua#L46))
  - `box.UpdateHeader`: no-op stub installed by `InstallCompatMethods` to prevent nil-method crashes from `ChatFrameUtil`. ([`../Src/EditBoxCompat.lua#L153`](../Src/EditBoxCompat.lua#L153))
  - `box.SetFocusRegionsShown`: no-op stub installed by `InstallCompatMethods`. ([`../Src/EditBoxCompat.lua#L32`](../Src/EditBoxCompat.lua#L32))
  - `box.UpdateNewcomerEditBoxHint`: no-op stub installed by `InstallCompatMethods`. ([`../Src/EditBoxCompat.lua#L32`](../Src/EditBoxCompat.lua#L32))
  - `box:GetAttribute() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L46`](../Src/EditBoxCompat.lua#L46))
  - `box:GetLanguage() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L44`](../Src/EditBoxCompat.lua#L44))
  - `box:GetTellTarget() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L42`](../Src/EditBoxCompat.lua#L42))
  - `box:GetChannelTarget() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L40`](../Src/EditBoxCompat.lua#L40))
  - `box:GetChatType() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L38`](../Src/EditBoxCompat.lua#L38))

Overlay root; hooked on `PLAYER_ENTERING_WORLD` via `HookAllChatFrames`.

- Description: Core overlay state and high-level editbox operations.
- Fields:
  - Runtime frames/state: `Overlay` ([`../Src/EditBox.lua#L25`](`../Src/EditBox.lua#L25`))
  - Runtime frames/state: `OverlayEdit` ([`../Src/EditBox.lua#L26`](`../Src/EditBox.lua#L26`))
  - Runtime frames/state: `ChannelLabel` ([`../Src/EditBox.lua#L27`](`../Src/EditBox.lua#L27`))
  - Runtime frames/state: `LabelBg` ([`../Src/EditBox.lua#L28`](`../Src/EditBox.lua#L28`))
  - Runtime frames/state: `OrigEditBox` ([`../Src/EditBox.lua#L32`](`../Src/EditBox.lua#L32`))
  - Runtime frames/state: `ChatType` ([`../Src/EditBox.lua#L33`](`../Src/EditBox.lua#L33`))
  - Runtime frames/state: `Language` ([`../Src/EditBox.lua#L34`](`../Src/EditBox.lua#L34`))
  - Runtime frames/state: `Target` ([`../Src/EditBox.lua#L35`](`../Src/EditBox.lua#L35`))
  - Runtime frames/state: `ChannelName` ([`../Src/EditBox.lua#L36`](`../Src/EditBox.lua#L36`))
  - State tables: `HookedBoxes`, `LastUsed`, `ReplyQueue`, `_attrCache` ([`../Src/EditBox.lua#L30-L40`](../Src/EditBox.lua#L30-L40), [`../Src/EditBox.lua#L41`](../Src/EditBox.lua#L41)).
  - History pointers: `HistoryIndex` ([`../Src/EditBox.lua#L38`](`../Src/EditBox.lua#L38`))
  - History pointers: `HistoryCache` ([`../Src/EditBox.lua#L39`](`../Src/EditBox.lua#L39`))
  - `_lockdown`, `_overlayUnfocused` *private by convention; do not rely on* ([`../Src/EditBox.lua#L44-L56`](../Src/EditBox.lua#L44-L56)).
  - Internal constants/closures exported for submodules (`_UserBypassingYapper`, `_SetUserBypassingYapper`, `_BypassEditBox`, `_SetBypassEditBox`, `_SLASH_MAP`, `_TAB_CYCLE`, `_LABEL_PREFIXES`, `_GROUP_CHAT_TYPES`, `_CHATTYPE_TO_OVERRIDE_KEY`, `_REPLY_QUEUE_MAX`) *private by convention; do not rely on* ([`../Src/EditBox.lua#L329-L338`](../Src/EditBox.lua#L329-L338)).
  - Internal helper exports: `IsWhisperSlashPrefill` ([`../Src/EditBox.lua#L504`](`../Src/EditBox.lua#L504`))
  - Internal helper exports: `ParseWhisperSlash` ([`../Src/EditBox.lua#L505`](`../Src/EditBox.lua#L505`))
  - Internal helper exports: `GetLastTellTargetInfo` — returns chatType and name of the last person who whispered *you* ([`../Src/EditBox.lua#L508`](`../Src/EditBox.lua#L508`))
  - Internal helper exports: `GetLastToldTargetInfo` — returns chatType and name of the last person *you* whispered (outgoing). Uses `ChatFrameUtil.GetLastToldTarget`; stays in sync with both Yapper and Blizzard sends. ([`../Src/EditBox.lua#L359`](`../Src/EditBox.lua#L359`))
  - Internal helper exports: `SetFrameFillColour` ([`../Src/EditBox.lua#L510`](`../Src/EditBox.lua#L510`))
- Methods:
  - `ClearLockdownState` ([`../Src/EditBox.lua#L75`](../Src/EditBox.lua#L75))
  - `AddReplyTarget` ([`../Src/EditBox.lua#L116`](../Src/EditBox.lua#L116))
  - `NextReplyTarget` ([`../Src/EditBox.lua#L146`](../Src/EditBox.lua#L146))
  - `OpenBlizzardChat` ([`../Src/EditBox.lua#L389`](../Src/EditBox.lua#L389))
  - `SetOnSend` ([`../Src/EditBox.lua#L557`](../Src/EditBox.lua#L557))
  - `SetPreShowCheck` ([`../Src/EditBox.lua#L582`](../Src/EditBox.lua#L582))
- Invariants:
  - Overlay behaviour valid only after `HookAllChatFrames()` has run.

## EditBox.SkinProxy

Attached during overlay show lifecycle.

- Description: Mirrors Blizzard editbox visual skin.
- Methods:
  - [NEW] `EditBox:EnsureProxyHeaderHidden() → nil`: Re-hide Blizzard header/prompt elements that UpdateHeader may re-show. ([`../Src/EditBox/SkinProxy.lua#L580`](../Src/EditBox/SkinProxy.lua#L580))
  - `EditBox:RestoreProxyMode() → nil`: Restore the original editbox to the state we found it in. ([`../Src/EditBox/SkinProxy.lua#L669`](../Src/EditBox/SkinProxy.lua#L669))
  - `EditBox:ApplyProxyMode() → nil`: Activate wholesale proxy mode: keep the Blizzard editbox visible underneath. ([`../Src/EditBox/SkinProxy.lua#L599`](../Src/EditBox/SkinProxy.lua#L599))
  - `AttachBlizzardSkinProxy` ([`../Src/EditBox/SkinProxy.lua#L18`](`../Src/EditBox/SkinProxy.lua#L18`))
  - `TintSkinProxyTextures` ([`../Src/EditBox/SkinProxy.lua#L506`](`../Src/EditBox/SkinProxy.lua#L506`))
  - `DetachBlizzardSkinProxy` ([`../Src/EditBox/SkinProxy.lua#L541`](`../Src/EditBox/SkinProxy.lua#L541`))

## EditBox.Overlay

Used by `EditBox:Show` to create and refresh frame contents.

- Description: Overlay frame creation and label/font rendering helpers.
- Fields:
  - `_RefreshOverlayVisuals`, `_ResolveChannelName`, `_BuildLabelText`, `_GetLabelUsableWidth`, `_ResetLabelToBaseFont`, `_TruncateLabelToWidth`, `_FitLabelFontToWidth`, `_UpdateLabelBackgroundForText` *private by convention; do not rely on* ([`../Src/EditBox/Overlay.lua#L478-L485`](../Src/EditBox/Overlay.lua#L478-L485)).
- Methods:
  - `EditBox:CreateOverlay() → nil` ([`../Src/EditBox/Overlay.lua#L512`](../Src/EditBox/Overlay.lua#L512)).

## EditBox.Handlers

Bound by `SetupOverlayScripts` when overlay is created.

- Description: Input handlers for Enter/Tab/history/channel switching.
- Methods:
  - `SetupOverlayScripts`, `ResetLockdownIdleTimer` ([`../Src/EditBox/Handlers.lua#L992`](../Src/EditBox/Handlers.lua#L992), [`../Src/EditBox/Handlers.lua#L992`](../Src/EditBox/Handlers.lua#L992)).
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
  - [NEW] `EditBox:RecordFallbackSend() → nil`: Record a message sent through Blizzard's native editbox (lockdown / bypass / ([`../Src/Hooks/ShowHide.lua#L856`](../Src/Hooks/ShowHide.lua#L856))
  - [NEW] `EditBox:RetargetOpenWhisper() → nil`: Retarget the already-open overlay onto an external (transient) whisper. ([`../Src/Hooks/ShowHide.lua#L810`](../Src/Hooks/ShowHide.lua#L810))
  - [NEW] `EditBox:IsNativeChatEditBox() → nil`: True only for Blizzard's native ChatFrameN editboxes (never our overlay). ([`../Src/Hooks/ShowHide.lua#L798`](../Src/Hooks/ShowHide.lua#L798))
  - `EditBox:Show(origEditBox)` - Present overlay in place of Blizzard editbox.
  - `EditBox:Hide(isHandoff)` - Close overlay, save state.
  - `EditBox:HandoffToBlizzard(silent?, bypassOpen?, isMultiline?)` - Lockdown handoff.
  - `EditBox:ApplyConfigToLiveOverlay(force?)` - Re-apply config to visible overlay.

## Hooks.Label

Channel label and tab cycling.

- Description: RefreshLabel(), CycleChatType(), RecordTabChannel(), PersistLastUsed(), OnTabPressed().
- File: [`../Src/Hooks/Label.lua`](../Src/Hooks/Label.lua)
- Methods:
  - [NEW] `EditBox:ResetSyncedAttributes() → nil`: Inverse of SyncAttributesToBlizzard: restore the Blizzard editbox to a neutral ([`../Src/Hooks/Label.lua#L300`](../Src/Hooks/Label.lua#L300))
  - [NEW] `EditBox:SyncAttributesToBlizzard() → nil`: Push Yapper's current chatType, target, channel and language into Blizzard's ([`../Src/Hooks/Label.lua#L234`](../Src/Hooks/Label.lua#L234))
  - [NEW] `EditBox:GetAvailableChatTypes() → nil`: Returns the subset of _TAB_CYCLE entries currently available to the player. ([`../Src/Hooks/Label.lua#L332`](../Src/Hooks/Label.lua#L332))
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
  - `EditBox:NavigateHistory(direction)` - Navigate command history (-1=up, 1=down).

## Hooks.Slash

Slash command forwarding.

- Description: ForwardSlashCommand() to pass unknown slash commands to Blizzard.
- File: [`../Src/Hooks/Slash.lua`](../Src/Hooks/Slash.lua)
- Methods:
  - `EditBox:ForwardSlashCommand(text)` - Forward slash command to Blizzard editbox.

## Hooks.Blizzard

Blizzard editbox hooks (taint-free).

- Description: HookBlizzardEditBox(), HookAllChatFrames(), all secure hooks.
- File: [`../Src/Hooks/BlizzardHookCtl/10_ProxyBackground.lua`](../Src/Hooks/BlizzardHookCtl/10_ProxyBackground.lua), [`../Src/Hooks/BlizzardHookCtl/20_EditBoxHooks.lua`](../Src/Hooks/BlizzardHookCtl/20_EditBoxHooks.lua), [`../Src/Hooks/BlizzardHookCtl/30_ChatFrameHooks.lua`](../Src/Hooks/BlizzardHookCtl/30_ChatFrameHooks.lua), [`../Src/Hooks/BlizzardHookCtl/40_IMWindowMemory.lua`](../Src/Hooks/BlizzardHookCtl/40_IMWindowMemory.lua)
- Methods:
  - [NEW] `EditBox:EnsureProxyBackgroundShown() → nil`: In proxy mode the native editbox is the visible background. A channel link ([`../Src/Hooks/BlizzardHookCtl/10_ProxyBackground.lua#L8`](../Src/Hooks/BlizzardHookCtl/10_ProxyBackground.lua#L8))
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
  - `UpdateState` ([`../Src/Bridges/TypingTrackerBridge.lua#L112`](`../Src/Bridges/TypingTrackerBridge.lua#L112`))
  - `OnOverlayFocusGained` ([`../Src/Bridges/TypingTrackerBridge.lua#L148`](`../Src/Bridges/TypingTrackerBridge.lua#L148`))
  - `OnOverlayFocusLost` ([`../Src/Bridges/TypingTrackerBridge.lua#L152`](`../Src/Bridges/TypingTrackerBridge.lua#L152`))
  - `OnOverlaySent` ([`../Src/Bridges/TypingTrackerBridge.lua#L156`](`../Src/Bridges/TypingTrackerBridge.lua#L156`))
  - `OnChannelChanged` ([`../Src/Bridges/TypingTrackerBridge.lua#L161`](`../Src/Bridges/TypingTrackerBridge.lua#L161`))

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

## Policies

Passive rule modules loaded from `Src/Policies/` and invoked by owner modules.

- Description: Policy objects expose decision methods but do not perform startup work or register runtime hooks.
- Modules:
  - `LockdownPolicy:IsChatLockdown() → boolean`: Returns true when chat messaging lockdown is active. ([`../Src/Policies/LockdownPolicy.lua#L13`](../Src/Policies/LockdownPolicy.lua#L13))
  - `LockdownPolicy:IsCombatLockdown() → boolean`: Returns true when protected-frame combat lockdown is active. ([`../Src/Policies/LockdownPolicy.lua#L19`](../Src/Policies/LockdownPolicy.lua#L19))
  - `LockdownPolicy:IsChatOrCombatLockdown() → boolean`: Returns true when either chat or combat lockdown is active. ([`../Src/Policies/LockdownPolicy.lua#L24`](../Src/Policies/LockdownPolicy.lua#L24))
  - `ChannelPolicy:BuildPersistedLastUsed(...) → table|nil`: Produces the sticky persisted last-used payload while preserving current selection semantics. ([`../Src/Policies/ChannelPolicy.lua#L85`](../Src/Policies/ChannelPolicy.lua#L85))
  - `ChannelPolicy:ResolveOpenSelection(context) → table`: Resolves the open channel selection from the current show/handoff context. ([`../Src/Policies/ChannelPolicy.lua#L170`](../Src/Policies/ChannelPolicy.lua#L170))

## Router

Initialised by `Chat:Init`.

- Description: Resolves concrete WoW send API for chat target.
- Fields:
  - `SendChatMessage`, `BNSendWhisper`, `ClubSendMessage` cached function refs ([`../Src/Router.lua#L26-L28`](../Src/Router.lua#L26-L28)).
- Methods:
  - [NEW] `ChannelPolicy:SanitizeCommittedSelection(current) → table|nil`: Normalize a runtime selection before persistence/commit. ([`../Src/Policies/ChannelPolicy.lua#L153`](../Src/Policies/ChannelPolicy.lua#L153))
  - `ResolveBnetTarget` ([`../Src/Router.lua#L59`](`../Src/Router.lua#L59`))
  - `_ResolveBnetTargetUncached` ([`../Src/Router.lua#L81`](`../Src/Router.lua#L81`))
  - `ResolveBnetDisplay` ([`../Src/Router.lua#L114`](`../Src/Router.lua#L114`))
  - `FlushBnetCache` ([`../Src/Router.lua#L173`](`../Src/Router.lua#L173`))
  - `Init` ([`../Src/Router.lua#L177`](`../Src/Router.lua#L177`))
  - `DetectCommunityChannel` ([`../Src/Router.lua#L196`](`../Src/Router.lua#L196`))
  - `Send` ([`../Src/Router.lua#L214`](`../Src/Router.lua#L214`))
- Side effects:
  - May delegate to `GopherBridge:Send`.

## Chunking

Called from `Chat:OnSend` for oversized messages.

- Description: UTF-8 aware message splitting.
- Methods:
  - `Chunking:Split(text, limit, ignoreParagraphMerging?, useDelineators?, delineator?, prefix?) → string[]` ([`../Src/Chunking.lua#L361`](../Src/Chunking.lua#L361))
  - `Chunking:GetDelineators() → table` ([`../Src/Chunking.lua#L589`](../Src/Chunking.lua#L589))

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
  - `Queue:IsAcceptableAck() → nil`: Check if a received chat event is an acceptable acknowledgement for an expected event. ([`../Src/Queue.lua#L527`](../Src/Queue.lua#L527))
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
  - `HandleAck` ([`../Src/Queue.lua#L470`](../Src/Queue.lua#L470))
  - `AssumeAck` ([`../Src/Queue.lua#L479`](../Src/Queue.lua#L479))
  - `RawSend` ([`../Src/Queue.lua#L489`](../Src/Queue.lua#L489))
  - `Complete` ([`../Src/Queue.lua#L510`](../Src/Queue.lua#L510))
  - `OnChatEvent` ([`../Src/Queue.lua#L537`](../Src/Queue.lua#L537))
  - `OnOpenChat` ([`../Src/Queue.lua#L605`](../Src/Queue.lua#L605))
  - `TryContinue` ([`../Src/Queue.lua#L615`](../Src/Queue.lua#L615))
  - `ResetStallTimer` ([`../Src/Queue.lua#L636`](../Src/Queue.lua#L636))
  - `CancelStallTimer` ([`../Src/Queue.lua#L653`](../Src/Queue.lua#L653))
  - `OnStallTimeout` ([`../Src/Queue.lua#L660`](../Src/Queue.lua#L660))
  - `CreateContinueFrame` ([`../Src/Queue.lua#L680`](../Src/Queue.lua#L680))
  - `ShowContinuePrompt` ([`../Src/Queue.lua#L740`](../Src/Queue.lua#L740))
  - `HideContinuePrompt` ([`../Src/Queue.lua#L777`](../Src/Queue.lua#L777))
  - `EnableEscapeCancel` ([`../Src/Queue.lua#L788`](../Src/Queue.lua#L788))
  - `DisableEscapeCancel` ([`../Src/Queue.lua#L821`](../Src/Queue.lua#L821))
  - `Cancel` ([`../Src/Queue.lua#L828`](../Src/Queue.lua#L828))
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
  - `Chat:OnSend(text, chatType, language, target) → nil` ([`../Src/Chat.lua#L98`](../Src/Chat.lua#L98))
  - `Chat:DirectSend(msg, chatType, language, target) → nil` ([`../Src/Chat.lua#L210`](../Src/Chat.lua#L210))
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
  - `Active` ([`../Src/Multiline.lua#L237`](`../Src/Multiline.lua#L237`))
  - `ChatType` ([`../Src/Multiline.lua#L60`](`../Src/Multiline.lua#L60`))
  - `Language` ([`../Src/Multiline.lua#L61`](`../Src/Multiline.lua#L61`))
  - `Target` ([`../Src/Multiline.lua#L62`](`../Src/Multiline.lua#L62`))
- Methods:
  - `Multiline:OnLockdownEnd() → nil`: Called when combat ends (PLAYER_REGEN_ENABLED). ([`../Src/Multiline.lua#L1089`](../Src/Multiline.lua#L1089))
  - `Multiline:OnLockdownStart() → nil`: Called when combat starts (PLAYER_REGEN_DISABLED). ([`../Src/Multiline.lua#L1074`](../Src/Multiline.lua#L1074))
  - `UpdateLabelGap` ([`../Src/Multiline.lua#L153`](`../Src/Multiline.lua#L153`))
  - `CreateFrame` ([`../Src/Multiline.lua#L184`](`../Src/Multiline.lua#L184`))
  - `Enter` ([`../Src/Multiline.lua#L618`](`../Src/Multiline.lua#L618`))
  - `Exit` ([`../Src/Multiline.lua#L768`](`../Src/Multiline.lua#L768`))
  - `Submit` ([`../Src/Multiline.lua#L891`](`../Src/Multiline.lua#L891`))
  - `Cancel` ([`../Src/Multiline.lua#L1040`](`../Src/Multiline.lua#L1040`))
  - `HandleEscape` ([`../Src/Multiline.lua#L1100`](`../Src/Multiline.lua#L1100`)) — handles the ESC key; returns true to close, false to ignore (e.g. closing sub-UI first).
  - `ApplyTheme` ([`../Src/Multiline.lua#L1109`](`../Src/Multiline.lua#L1109`))
- Invariants:
  - While `Active`, single-line overlay show path should early-return.

## Autocomplete

Binds to overlay (or multiline) editbox when available.

- Description: Ghost-text completion from dictionary + YAS.
- Fields:
  - `GhostFS` ([`../Src/Autocomplete.lua#L58`](`../Src/Autocomplete.lua#L58`))
  - `CurrentSugg` ([`../Src/Autocomplete.lua#L59`](`../Src/Autocomplete.lua#L59`))
  - `CurrentPrefix` ([`../Src/Autocomplete.lua#L60`](`../Src/Autocomplete.lua#L60`))
  - `PrefixText` ([`../Src/Autocomplete.lua#L61`](`../Src/Autocomplete.lua#L61`))
  - `Active` ([`../Src/Autocomplete.lua#L62`](`../Src/Autocomplete.lua#L62`))
  - `Enabled` ([`../Src/Autocomplete.lua#L63`](`../Src/Autocomplete.lua#L63`))
  - `_activeEditBox` ([`../Src/Autocomplete.lua#L64`](`../Src/Autocomplete.lua#L64`))
  - `_isMultiline` ([`../Src/Autocomplete.lua#L65`](`../Src/Autocomplete.lua#L65`))
- Methods:
  - `Autocomplete:SetOffset(x, y) → nil`: Set a manual pixel offset for the ghost-text positioning. ([`../Src/Autocomplete.lua#L611`](../Src/Autocomplete.lua#L611))
  - `IsEnabled`, `ExtractWordAtCursor`, `SearchDictionary`, `GetSuggestion`, `GetGhostFS`, `_InstallCursorHook`, `PositionGhost`, `ShowGhost`, `HideGhost`, `OnTextChanged`, `OnTabPressed`, `OnOverlayHide`, `SyncFont`, `SyncGhostFont`, `BindMultiline`, `UnbindMultiline` ([`../Src/Autocomplete.lua`](../Src/Autocomplete.lua)).

## History

Initialised on `ADDON_LOADED`; hooks overlay on `PLAYER_ENTERING_WORLD`.

- Description: Persistent chat history, draft store, undo/redo snapshots.
- Methods:
  - `History:SaveDraft(editBox, isMultiline) → nil`: Save a draft from any EditBox (overlay or multiline). ([`../Src/History.lua#L195`](../Src/History.lua#L195))
  - `History:GetDraft() → string? text, string? chatType, string? target, boolean? multiline`: Return the saved draft if dirty. ([`../Src/History.lua#L240`](../Src/History.lua#L240))
  - `InitDB` ([`../Src/History.lua#L72`](`../Src/History.lua#L72`))
  - `SaveDB` ([`../Src/History.lua#L113`](`../Src/History.lua#L113`))
  - `AddChatHistory` ([`../Src/History.lua#L134`](`../Src/History.lua#L134`))
  - `GetChatHistory` ([`../Src/History.lua#L171`](`../Src/History.lua#L171`))
  - `GetDraftStore` ([`../Src/History.lua#L182`](`../Src/History.lua#L182`))
  - `MarkDirty` ([`../Src/History.lua#L249`](`../Src/History.lua#L249`))
  - `ClearDraft` ([`../Src/History.lua#L254`](`../Src/History.lua#L254`))
  - `CancelPauseTimer` ([`../Src/History.lua#L274`](`../Src/History.lua#L274`))
  - `AddSnapshot` ([`../Src/History.lua#L304`](`../Src/History.lua#L304`))
  - `Undo` ([`../Src/History.lua#L348`](`../Src/History.lua#L348`))
  - `Redo` ([`../Src/History.lua#L364`](`../Src/History.lua#L364`))
  - `HookOverlayEditBox` ([`../Src/History.lua#L392`](`../Src/History.lua#L392`))
- Global state touched:
  - `_G.YapperLocalHistory`.

## Theme

Loaded with defaults; active theme restored on `ADDON_LOADED`.

- Description: Theme registry, application, persistence, live sync.
- Fields:
  - `_registry`, `_current` *private by convention; do not rely on* ([`../Src/Theme.lua#L16-L17`](../Src/Theme.lua#L16-L17)).
- Methods:
  - `YapperTable:GetRegisteredThemes() → nil`: No description provided. ([`../Src/Theme.lua#L248`](../Src/Theme.lua#L248))
  - `RegisterTheme` ([`../Src/Theme.lua#L26`](`../Src/Theme.lua#L26`))
  - `GetTheme` ([`../Src/Theme.lua#L32`](`../Src/Theme.lua#L32`))
  - `GetRegisteredNames` ([`../Src/Theme.lua#L37`](`../Src/Theme.lua#L37`))
  - `SetTheme` ([`../Src/Theme.lua#L45`](`../Src/Theme.lua#L45`))
  - `ApplyToFrame` ([`../Src/Theme.lua#L121`](`../Src/Theme.lua#L121`))
  - `GetCurrentName` ([`../Src/Theme.lua#L186`](`../Src/Theme.lua#L186`))
  - `SetLiveTheme` ([`../Src/Theme.lua#L197`](`../Src/Theme.lua#L197`))
  - `SetTheme` logic switches between `_G.YapperDB` and `_G.YapperLocalConf` as the root for `_appliedTheme` based on `UseGlobalProfile`.
  - Global wrappers on root table: `Yapper:RegisterTheme` ([`../Src/Theme.lua#L26`](`../Src/Theme.lua#L26`))
  - Global wrappers on root table: `Yapper:SetTheme` ([`../Src/Theme.lua#L45`](`../Src/Theme.lua#L45`))
  - Global wrappers on root table: `Yapper:GetRegisteredThemes` ([`../Src/Theme.lua#L248`](`../Src/Theme.lua#L248`))
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
  - `InitPopups` ([`../Src/Interface.lua#L314`](`../Src/Interface.lua#L314`))
  - `BuildConfigUI` ([`../Src/Interface.lua#L461`](`../Src/Interface.lua#L461`))
  - `ShowMainWindow` ([`../Src/Interface.lua#L748`](`../Src/Interface.lua#L748`))
  - `OpenToCategory` ([`../Src/Interface.lua#L773`](`../Src/Interface.lua#L773`))
  - `ToggleMainWindow` ([`../Src/Interface.lua#L798`](`../Src/Interface.lua#L798`))
  - `HandleLauncherClick` ([`../Src/Interface.lua#L830`](`../Src/Interface.lua#L830`))
  - `CloseFrame` ([`../Src/Interface.lua#L865`](`../Src/Interface.lua#L865`))
  - `Init` ([`../Src/Interface.lua#L876`](`../Src/Interface.lua#L876`))
  - `CreateLauncher` ([`../Src/Interface.lua#L911`](`../Src/Interface.lua#L911`))
- Global function:
  - `Yapper_FromCompartment(...)` ([`../Src/Interface.lua#L852`](../Src/Interface.lua#L852)).

## Interface.Schema

Build-time render schema module used by window/UI builders.

- Description: Settings schema composition and category metadata.
- Fields:
  - `_COLOUR_KEYS`, `_CHANNEL_OVERRIDE_OPTIONS`, `_CREDITS_BUNDLED`, `_CREDITS_OPTIONAL`, `_FONT_OUTLINE_OPTIONS`, `_SETTING_TOOLTIPS`, `_FRIENDLY_LABELS`, `_CATEGORIES`, `_PATH_TO_CATEGORY` *private by convention; do not rely on* ([`../Src/Interface/Schema.lua#L519-L527`](../Src/Interface/Schema.lua#L527)).
- Methods:
  - `BuildRenderSchema` ([`../Src/Interface/Schema.lua#L348`](`../Src/Interface/Schema.lua#L348`))
  - `GetRenderSchema` ([`../Src/Interface/Schema.lua#L493`](`../Src/Interface/Schema.lua#L493`))
  - `RefreshRenderSchema` ([`../Src/Interface/Schema.lua#L501`](`../Src/Interface/Schema.lua#L501`))
  - `OnWindowClosed` ([`../Src/Interface/Schema.lua#L507`](`../Src/Interface/Schema.lua#L507`))

## Interface.Config

Handles config reads/writes and side-effect fan-out.

- Description: Config root/path helpers, sanitisation, minimap controls.
- Methods:
  - `Interface:FactoryReset() → nil`: TRUE clean slate: wipes all settings, learned dictionary data, and history. ([`../Src/Interface/Config.lua#L79`](../Src/Interface/Config.lua#L79))
  - `Interface:ResetAllSettings() → nil`: Reset all configuration settings to their default values. ([`../Src/Interface/Config.lua#L51`](../Src/Interface/Config.lua#L51))
  - `GetLocalConfigRoot` ([`../Src/Interface/Config.lua#L35`](`../Src/Interface/Config.lua#L35`))
  - `GetDefaultsRoot` ([`../Src/Interface/Config.lua#L42`](`../Src/Interface/Config.lua#L42`))
  - `GetRenderCacheContainer` ([`../Src/Interface/Config.lua#L99`](`../Src/Interface/Config.lua#L99`))
  - `PurgeRenderCache` ([`../Src/Interface/Config.lua#L110`](`../Src/Interface/Config.lua#L110`))
  - `SetDirty` ([`../Src/Interface/Config.lua#L116`](`../Src/Interface/Config.lua#L116`))
  - `IsDirty` ([`../Src/Interface/Config.lua#L121`](`../Src/Interface/Config.lua#L121`))
  - `SetSettingsChanged` ([`../Src/Interface/Config.lua#L126`](`../Src/Interface/Config.lua#L126`))
  - `GetConfigPath` ([`../Src/Interface/Config.lua#L134`](`../Src/Interface/Config.lua#L134`))
  - `GetDefaultPath` ([`../Src/Interface/Config.lua#L142`](`../Src/Interface/Config.lua#L142`))
  - `UpdateOverrideTextColorCheckboxState` ([`../Src/Interface/Config.lua#L146`](`../Src/Interface/Config.lua#L146`))
  - `SetLocalPath` ([`../Src/Interface/Config.lua#L150`](`../Src/Interface/Config.lua#L150`))
  - `GetLauncherTooltipLines` ([`../Src/Interface/Config.lua#L397`](`../Src/Interface/Config.lua#L397`))
  - `GetMinimapButtonSettings` ([`../Src/Interface/Config.lua#L405`](`../Src/Interface/Config.lua#L405`))
  - `GetMinimapButtonOffset` ([`../Src/Interface/Config.lua#L418`](`../Src/Interface/Config.lua#L418`))
  - `PositionMinimapButton` ([`../Src/Interface/Config.lua#L422`](`../Src/Interface/Config.lua#L422`))
  - `UpdateMinimapButtonAngleFromCursor` ([`../Src/Interface/Config.lua#L438`](`../Src/Interface/Config.lua#L438`))
  - `ApplyMinimapButtonVisibility` ([`../Src/Interface/Config.lua#L455`](`../Src/Interface/Config.lua#L455`))
  - `IsPathDisabledByTheme` ([`../Src/Interface/Config.lua#L495`](`../Src/Interface/Config.lua#L495`))
  - `GetFriendlyLabel` ([`../Src/Interface/Config.lua#L533`](`../Src/Interface/Config.lua#L533`))
  - `SanitizeLocalConfig` ([`../Src/Interface/Config.lua#L572`](`../Src/Interface/Config.lua#L572`))
- Non-obvious rationale migrated from old docs:
  - `SetLocalPath` is the **single authoritative write source** for configuration; it handles profile-aware routing, theme-override marking, and automatic `PromoteCharacterToGlobal` triggers during profile toggles.
  - `SetLocalPath` enforces channel marker sync (`Chat.DELINEATOR` and `Chat.PREFIX`) as a single logical setting update.

## Interface.Window

Builds and controls top-level frames.

- Description: Main window, welcome/what's-new flows, UI font scaling.
- Fields:
  - `_activeCategory` *private by convention; do not rely on* ([`../Src/Interface/Window.lua#L175`](../Src/Interface/Window.lua#L175)).
- Methods:
  - `CompareVersions` — Compares semantic version strings. ([`../Src/Interface/Window.lua#L194`](../Src/Interface/Window.lua#L194))
  - `GetSortedVersions` — Returns WHATS_NEW entries sorted by version. ([`../Src/Interface/Window.lua#L205`](../Src/Interface/Window.lua#L205))
  - `CheckForChangelogUpdate` — Handshake that updates seen records and triggers popups. ([`../Src/Interface/Window.lua#L288`](../Src/Interface/Window.lua#L288))
  - `PopulateWhatsNewContent` — Renders changelog notes into a container. ([`../Src/Interface/Window.lua#L738`](../Src/Interface/Window.lua#L738))
  - `RefreshWhatsNewContent` — Wipes and re-renders the WhatsNew popup. ([`../Src/Interface/Window.lua#L786`](../Src/Interface/Window.lua#L786))
  - `UpdateWhatsNewButtonScale` — Scales the 'Got it' button text. ([`../Src/Interface/Window.lua#L803`](../Src/Interface/Window.lua#L803))
  - `Interface:GetWelcomeVersion() → number`: Returns the target version of the welcome screen content. ([`../Src/Interface/Window.lua#L216`](../Src/Interface/Window.lua#L216))
  - `GetMainWindowPositionStore` ([`../Src/Interface/Window.lua#L31`](`../Src/Interface/Window.lua#L31`))
  - `SaveMainWindowPosition` ([`../Src/Interface/Window.lua#L48`](`../Src/Interface/Window.lua#L48`))
  - `ApplyMainWindowPosition` ([`../Src/Interface/Window.lua#L65`](`../Src/Interface/Window.lua#L65`))
  - `ShouldShowWelcomeChoice` ([`../Src/Interface/Window.lua#L260`](`../Src/Interface/Window.lua#L260`))
  - `ShouldShowWhatsNew` ([`../Src/Interface/Window.lua#L279`](`../Src/Interface/Window.lua#L279`))
  - `MarkWelcomeShown` ([`../Src/Interface/Window.lua#L314`](`../Src/Interface/Window.lua#L314`))
  - `MarkVersionSeen` ([`../Src/Interface/Window.lua#L318`](`../Src/Interface/Window.lua#L318`))
  - `CreateWelcomeChoiceFrame` ([`../Src/Interface/Window.lua#L375`](`../Src/Interface/Window.lua#L375`))
  - `CreateWhatsNewFrame` ([`../Src/Interface/Window.lua#L570`](`../Src/Interface/Window.lua#L570`))
  - `CreateMainWindow` ([`../Src/Interface/Window.lua#L821`](`../Src/Interface/Window.lua#L821`))
  - `UpdateSidebarSelection` ([`../Src/Interface/Window.lua#L1019`](`../Src/Interface/Window.lua#L1019`))
  - `GetUIFontOffset` ([`../Src/Interface/Window.lua#L1038`](`../Src/Interface/Window.lua#L1038`))
  - `SetUIFontOffset` ([`../Src/Interface/Window.lua#L1044`](`../Src/Interface/Window.lua#L1044`))
  - `ScaledRow` ([`../Src/Interface/Window.lua#L1052`](`../Src/Interface/Window.lua#L1052`))
  - `ApplyUIFontScale` ([`../Src/Interface/Window.lua#L1058`](`../Src/Interface/Window.lua#L1058`))
  - `RefreshFontScaleLabel` ([`../Src/Interface/Window.lua#L1086`](`../Src/Interface/Window.lua#L1086`))

## Interface.Widgets

Widget factory/pool and reusable setting controls.

- Description: UI control allocator with pooling, tooltip plumbing, common controls.
- Fields:
  - `WidgetPool: table` ([`../Src/Interface/Widgets.lua#L66`](../Src/Interface/Widgets.lua#L66)).
  - `_OpenColorPicker: function` *private by convention; do not rely on* ([`../Src/Interface/Widgets.lua#L885`](../Src/Interface/Widgets.lua#L885)).
- Methods:
  - `ClearConfigControls` ([`../Src/Interface/Widgets.lua#L34`](`../Src/Interface/Widgets.lua#L34`))
  - `AddControl` ([`../Src/Interface/Widgets.lua#L55`](`../Src/Interface/Widgets.lua#L55`))
  - `AcquireWidget` ([`../Src/Interface/Widgets.lua#L76`](`../Src/Interface/Widgets.lua#L76`))
  - `ReleaseWidget` ([`../Src/Interface/Widgets.lua#L110`](`../Src/Interface/Widgets.lua#L110`))
  - `GetTooltip` ([`../Src/Interface/Widgets.lua#L188`](`../Src/Interface/Widgets.lua#L188`))
  - `AttachTooltip` ([`../Src/Interface/Widgets.lua#L199`](`../Src/Interface/Widgets.lua#L199`))
  - `CreateResetButton` ([`../Src/Interface/Widgets.lua#L304`](`../Src/Interface/Widgets.lua#L304`))
  - `CreateLabel` ([`../Src/Interface/Widgets.lua#L317`](`../Src/Interface/Widgets.lua#L317`))
  - `CreateCheckBox` ([`../Src/Interface/Widgets.lua#L519`](`../Src/Interface/Widgets.lua#L519`))
  - `CreateTextInput` ([`../Src/Interface/Widgets.lua#L561`](`../Src/Interface/Widgets.lua#L561`))
  - `CreateColorPickerControl` ([`../Src/Interface/Widgets.lua#L652`](`../Src/Interface/Widgets.lua#L652`))
  - `CreateFontSizeDropdown` ([`../Src/Interface/Widgets.lua#L737`](`../Src/Interface/Widgets.lua#L737`))
  - `CreateFontOutlineDropdown` ([`../Src/Interface/Widgets.lua#L836`](`../Src/Interface/Widgets.lua#L836`))
- Non-obvious rationale migrated from old docs:
  - `CreateResetButton` self-registers with control tracking; do not double-register via `AddControl`.

## Interface.Pages

Per-category page builders called by `BuildConfigUI`.

- Description: Concrete settings page construction routines.
- Methods:
  - `CreateChangelogPage` — Builds the scrollable version history settings tab. ([`../Src/Interface/Pages.lua#L955`](../Src/Interface/Pages.lua#L955))
  - `CreateChannelOverrideControls` ([`../Src/Interface/Pages.lua#L42`](`../Src/Interface/Pages.lua#L42`))
  - `CreateGlobalSyncControls` ([`../Src/Interface/Pages.lua#L336`](`../Src/Interface/Pages.lua#L336`))
  - `CreateYASLearningPage` ([`../Src/Interface/Pages.lua#L393`](`../Src/Interface/Pages.lua#L393`))
  - `CreateQueueDiagnostics` ([`../Src/Interface/Pages.lua#L638`](`../Src/Interface/Pages.lua#L638`))
  - `CreateTutorialPage` ([`../Src/Interface/Pages.lua#L742`](`../Src/Interface/Pages.lua#L742`))
  - `CreateCreditsPage` ([`../Src/Interface/Pages.lua#L887`](`../Src/Interface/Pages.lua#L887`))
  - `CreateSpellcheckLocaleDropdown` ([`../Src/Interface/Pages.lua#L995`](`../Src/Interface/Pages.lua#L995`))
  - `CreateSpellcheckKeyboardLayoutDropdown` ([`../Src/Interface/Pages.lua#L1096`](`../Src/Interface/Pages.lua#L1096`))
  - `CreateSpellcheckUnderlineDropdown` ([`../Src/Interface/Pages.lua#L1145`](`../Src/Interface/Pages.lua#L1145`))
  - `CreateSpellcheckUserDictEditor` ([`../Src/Interface/Pages.lua#L1209`](`../Src/Interface/Pages.lua#L1209`))
  - `CreateThemeDropdown` ([`../Src/Interface/Pages.lua#L1375`](`../Src/Interface/Pages.lua#L1375`))
- Invariants:
  - Dropdown handlers assume config roots are initialised.

## Emotes

- Methods:
  - `Emotes:EnsureHintUI() → nil`: Ensures the emote hint UI is created. ([`../Src/Emotes.lua#L185`](../Src/Emotes.lua#L185))
  - `Emotes:EnsureMenuUI() → nil`: Ensures the emote menu UI is created. ([`../Src/Emotes.lua#L55`](../Src/Emotes.lua#L55))
  - `Emotes:InitEmoteList() → nil`: Populates the emote list. Only called when the menu is actually opened. ([`../Src/Emotes.lua#L28`](../Src/Emotes.lua#L28))
  - `Emotes:ApplySelection(index, isEnter) → nil`: Applies the selected emote to the edit box and hides the menu. If `autoSend` is enabled, immediately sends the emote to chat; otherwise, appends a space and refocuses the edit box (suppressing the Enter key if `isEnter` is true). ([`../Src/Emotes.lua#L396`](../Src/Emotes.lua#L396))
  - `Emotes:RefreshSelection() → nil`: Highlights the currently selected row in the emote menu. ([`../Src/Emotes.lua#L381`](../Src/Emotes.lua#L381))
  - `Emotes:FilterAndShow() → nil`: Re-renders the emote menu UI based on the current ActiveFilter. ([`../Src/Emotes.lua#L280`](../Src/Emotes.lua#L280))
  - `Emotes:FilterMenu(query) → nil`: Prepares the search filter state from a raw slash command query. ([`../Src/Emotes.lua#L270`](../Src/Emotes.lua#L270))
  - `Emotes:HideMenu() → nil`: Hides the emote menu. ([`../Src/Emotes.lua#L262`](../Src/Emotes.lua#L262))
  - `Emotes:OpenMenu() → nil`: Opens the emote menu. ([`../Src/Emotes.lua#L242`](../Src/Emotes.lua#L242))

## Utilities

- Methods:
  - [NEW] `Utils:IsUnambiguousBnetTarget(target) → boolean`: Returns true when target is unambiguously a Battle.net identifier ([`../Src/Utils.lua#L240`](../Src/Utils.lua#L240))
  - [NEW] `Utils:SetFontIfChanged(widget, face, size, flags) → boolean changed  True if SetFont was actually called`: SetFont only when the target font differs from the current one. ([`../Src/Utils.lua#L220`](../Src/Utils.lua#L220))
  - [NEW] `Utils:NormaliseCharName(name) → string|nil`: Strip the realm suffix from a character name and lowercase it. ([`../Src/Utils.lua#L201`](../Src/Utils.lua#L201))
  - [NEW] `Utils:IsChatOrCombatLockdown() → nil`: Return true when either chat-messaging or combat lockdown is active. ([`../Src/Utils.lua#L114`](../Src/Utils.lua#L114))
  - [NEW] `Utils:IsCombatLockdown() → nil`: Return true when protected-frame combat restrictions are active. ([`../Src/Utils.lua#L101`](../Src/Utils.lua#L101))
  - [NEW] `Utils:AssertType(value, expectedType, default) → any  Original value if type matches`: Assert type matches expected, return default if not. ([`../Src/Utils.lua#L158`](../Src/Utils.lua#L158))
  - [NEW] `Utils:EnsureTablePath(root) → table  The deepest table in the path`: Ensure a table path exists, creating intermediate tables as needed. ([`../Src/Utils.lua#L140`](../Src/Utils.lua#L140))
  - [NEW] `Utils:EnsureTable(t) → table`: Ensure a value is a table, returning it or a new empty table. ([`../Src/Utils.lua#L132`](../Src/Utils.lua#L132))
  - `Utils:Deleet(word) → string`: Convert leetspeak characters back to their base alphabet equivalents. ([`../Src/Utils.lua#L255`](../Src/Utils.lua#L255))

## TotalRP3Bridge

- Methods:
  - [NEW] `TotalRP3Bridge:GetPlayerDisplayName() → nil`: Returns the best available RP display name for the player when TRP3 is loaded. ([`../Src/Bridges/TotalRP3Bridge.lua#L90`](../Src/Bridges/TotalRP3Bridge.lua#L90))
  - [NEW] `TotalRP3Bridge:GetUnitDisplayName() → nil`: No description provided. ([`../Src/Bridges/TotalRP3Bridge.lua#L74`](../Src/Bridges/TotalRP3Bridge.lua#L74))

## Hooks.UnitPopup

- Methods:
  - [NEW] `EditBox:InstallUnitPopupWhisperOverride() → nil`: Install the Menu.ModifyMenu registrations.  Idempotent; called from ([`../Src/Hooks/UnitPopup.lua#L194`](../Src/Hooks/UnitPopup.lua#L194))

## Bridges\WhisperMessengerBridge

- Methods:
  - [NEW] `Bridge:HookSecureButtonCreation() → nil`: Hook Keybinds.CreateSecureButtons so the bridge re-wraps whenever the ([`../Src/Bridges/WhisperMessengerBridge.lua#L141`](../Src/Bridges/WhisperMessengerBridge.lua#L141))
  - [NEW] `Bridge:WrapReplyKeybind() → nil`: Wrap the REPLYTELL2 secure button's PostClick so the reply/re-whisper ([`../Src/Bridges/WhisperMessengerBridge.lua#L88`](../Src/Bridges/WhisperMessengerBridge.lua#L88))
  - [NEW] `Bridge:IsWindowVisible() → boolean`: Check whether the WM window is currently visible. ([`../Src/Bridges/WhisperMessengerBridge.lua#L50`](../Src/Bridges/WhisperMessengerBridge.lua#L50))
