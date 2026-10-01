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
  - `YapperTable:OverrideYapper(disable: boolean) → nil` ([`../Yapper.lua#L285`](../Yapper.lua#L285)) — toggles runtime ownership between Yapper overlay and Blizzard chat; cancels queue and unregisters events when disabling.

## Core

Initialised on `ADDON_LOADED` by [`Yapper.lua#L105-L110`](../Yapper.lua#L105-L110).

- Description: SavedVariables schema/default/migration authority.
- Fields:
  - `Yapper.Config: table` live config root ([`../Src/Core.lua#L284`](../Src/Core.lua#L284)).
- Methods:
  - `Core:IsLanguageCacheValid() → boolean isValid`: Check if the language cache is still valid for the current character. ([`../Src/Core.lua#L325`](../Src/Core.lua#L325))
  - `Core:RegisterFrame(category, key, frame) → nil`: Register a frame in the central UI registry for external access. ([`../Src/Core.lua#L389`](../Src/Core.lua#L389))
  - `Core:DemoteGlobalToCharacter() → nil`: Unpack stashed local settings when switching away from Global Profile. ([`../Src/Core.lua#L829`](../Src/Core.lua#L829))
  - `Core:RefreshInheritance() → nil`: Initialise inheritance chain (Global vs Local). ([`../Src/Core.lua#L627`](../Src/Core.lua#L627))
  - `Core:GetCharacterLanguage(lang) → number langId`: Get the language or defaults if not present. ([`../Src/Core.lua#L356`](../Src/Core.lua#L356))
  - `Core:BuildLanguageCache() → nil`: No description provided. ([`../Src/Core.lua#L295`](../Src/Core.lua#L295))
  - `Core:InitSavedVars() → nil` ([`../Src/Core.lua#L517`](../Src/Core.lua#L517)) — creates/migrates `YapperDB`, `YapperLocalConf`, `YapperLocalHistory`; mutates metatables for inheritance.
  - `Core:GetVersion() → string` ([`../Src/Core.lua#L650`](../Src/Core.lua#L650))
  - `Core:GetDefaults() → table` ([`../Src/Core.lua#L654`](../Src/Core.lua#L654))
  - `Core:SetVerbose(bool: boolean) → nil` ([`../Src/Core.lua#L658`](../Src/Core.lua#L658))
  - `Core:SaveSetting(category, key, value) → nil` ([`../Src/Core.lua#L671`](../Src/Core.lua#L671)) — delegates to `Interface:SetLocalPath` for profile-aware write routing.
  - `Core:PromoteCharacterToGlobal() → nil` ([`../Src/Core.lua#L736`](../Src/Core.lua#L736)) — wipes local overrides (excluding `MainWindowPosition`) and re-seeds metatable inheritance from `YapperDB`.
  - `Core:PushToGlobal() → nil` ([`../Src/Core.lua#L850`](../Src/Core.lua#L850)) — deep-copies character settings into `YapperDB`. Whitelists `System` keys; excludes `MainWindowPosition`; migrates `_themeOverrides` and `_appliedTheme` markers; no-op when already global.
- Invariants:
  - Must run before feature init (`LoadSavedVariablesFirst: 1`).
  - Metatable chain must remain intact for local fallback/inheritance logic.

## Utils

Loaded at startup; used by most modules.

- Description: Print/debug/fullscreen/chat utility helpers.
- Fields:
  - `_G.YAPPER_UTILS: table` alias for debug access ([`../Src/Utils.lua#L133`](../Src/Utils.lua#L133)).
- Methods:
  - `Utils:Print(...) → nil` ([`../Src/Utils.lua#L19`](../Src/Utils.lua#L19))
  - `Utils:VerbosePrint(...) → nil` ([`../Src/Utils.lua#L43`](../Src/Utils.lua#L43))
  - `Utils:DebugPrint(...) → nil` ([`../Src/Utils.lua#L49`](../Src/Utils.lua#L49))
  - `Utils:GetChatParent() → Frame` ([`../Src/Utils.lua#L58`](../Src/Utils.lua#L58))
  - `Utils:MakeFullscreenAware(frame) → nil` ([`../Src/Utils.lua#L70`](../Src/Utils.lua#L70))
  - `Utils:IsChatLockdown() → boolean` ([`../Src/Utils.lua#L99`](../Src/Utils.lua#L99))
  - `Utils:IsSecret(value) → boolean` ([`../Src/Utils.lua#L189`](../Src/Utils.lua#L189))

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
  - `API:_createClaim(text, chatType, language, target, owner) → number` ([`../Src/API.lua#L1211`](../Src/API.lua#L1211))
  - `API:RunFilter(hookPoint, payload) → table|false` ([`../Src/API.lua#L1385`](../Src/API.lua#L1385))
  - `API:Fire(event, ...) → nil` ([`../Src/API.lua#L1430`](../Src/API.lua#L1430))
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
  - Suggestion state: `SuggestionRows`, `ActiveSuggestions`, `ActiveIndex`, `ActiveWord`, `ActiveRange`, `_debounceTimer` ([`../Src/Spellcheck.lua#L59-L60`](../Src/Spellcheck.lua#L59-L60), [`../Src/Spellcheck.lua#L62-L66`](../Src/Spellcheck.lua#L62-L66), [`../Src/Spellcheck.lua#L76`](../Src/Spellcheck.lua#L76)).
  - Dictionary/user state: `UserDictCache` ([`../Src/Spellcheck.lua#L69`](`../Src/Spellcheck.lua#L69`))
  - Dictionary/user state: `_pendingLocaleLoads` ([`../Src/Spellcheck.lua#L70`](`../Src/Spellcheck.lua#L70`))
  - Dictionary/user state: `DictionaryBuilders` ([`../Src/Spellcheck.lua#L72`](`../Src/Spellcheck.lua#L72`))
  - Edit-distance buffers: `_ed_prev`, `_ed_cur`, `_ed_prev_prev` *private by convention; do not rely on* ([`../Src/Spellcheck.lua#L73-L75`](../Src/Spellcheck.lua#L73-L75)).
  - Tunable constants/helpers: `_SCORE_WEIGHTS`, `_MAX_SUGGESTION_ROWS`, `_RAID_ICONS`, `_KB_LAYOUTS`, `_DICT_CHUNK_SIZE` *private by convention; do not rely on* ([`../Src/Spellcheck.lua#L665-L675`](../Src/Spellcheck.lua#L665-L675)).
- Methods:
  - `Spellcheck:GetNgramTopCandidates() → number`: Return the clamped NgramTopCandidates config value (1-5000, default 500). ([`../Src/Spellcheck.lua#L651`](../Src/Spellcheck.lua#L651))
  - `Spellcheck:GetNgramMaxPosting() → number`: Return the clamped NgramMaxPosting config value (1-5000, default 500). ([`../Src/Spellcheck.lua#L646`](../Src/Spellcheck.lua#L646))
  - `Spellcheck:GetNgramN() → number`: Return the clamped NgramN config value (2-4, default 2). ([`../Src/Spellcheck.lua#L641`](../Src/Spellcheck.lua#L641))
  - `Spellcheck:GetUserDictWordCap() → number`: Returns the maximum number of words in `AddedWords` before oldest entries are FIFO-evicted. Configurable via `UserDictWordCap`; default 2000, min 50, max 10000. ([`../Src/Spellcheck.lua#L661`](../Src/Spellcheck.lua#L661))
  - `Spellcheck:IsWordBlocked(word, locale, ignoreManual) → boolean`: Convenience function for checking a single word (e.g., during YAS learning). ([`../Src/Spellcheck.lua#L541`](../Src/Spellcheck.lua#L541))
  - `Spellcheck:GetBlockData(locale) → table|nil addedSet`: Returns the data needed to check if a word is blocked at runtime. ([`../Src/Spellcheck.lua#L522`](../Src/Spellcheck.lua#L522))
  - `Spellcheck:EvictRandomMeta() → nil`: No description provided. ([`../Src/Spellcheck.lua#L428`](../Src/Spellcheck.lua#L428))
  - `Spellcheck:Init() → nil` ([`../Src/Spellcheck.lua#L188`](../Src/Spellcheck.lua#L188))
  - `Spellcheck:_RegisterLanguageEngine(familyId, engine) → boolean` ([`../Src/Spellcheck.lua#L214`](../Src/Spellcheck.lua#L214)) — **Security Note**: Enforces mandatory `BlockedHashes` table and `HashWord` function. Returns `false` and prints a chat error if missing.
  - `Spellcheck:GetActiveEngine() → table|nil` ([`../Src/Spellcheck.lua#L239`](../Src/Spellcheck.lua#L239))
  - `Spellcheck:GetEngine(familyId) → table|nil` ([`../Src/Spellcheck.lua#L248`](../Src/Spellcheck.lua#L248))
  - `Spellcheck:GetConfig() → table` ([`../Src/Spellcheck.lua#L335`](../Src/Spellcheck.lua#L335))
  - `Spellcheck:IsEnabled() → boolean` ([`../Src/Spellcheck.lua#L339`](../Src/Spellcheck.lua#L339))
  - `Spellcheck:GetLocale() → string` ([`../Src/Spellcheck.lua#L344`](../Src/Spellcheck.lua#L344))
  - `Spellcheck:GetFallbackLocale() → string` ([`../Src/Spellcheck.lua#L372`](../Src/Spellcheck.lua#L372))
  - `Spellcheck:GetDictionary() → table|nil` ([`../Src/Spellcheck.lua#L380`](../Src/Spellcheck.lua#L380))
  - `Spellcheck:GetMeta(dict, word) → table|nil` ([`../Src/Spellcheck.lua#L390`](../Src/Spellcheck.lua#L390))

  - `Spellcheck:GetUserDictStore() → table` ([`../Src/Spellcheck.lua#L448`](../Src/Spellcheck.lua#L448))
  - `Spellcheck:GetUserDict(locale) → table` ([`../Src/Spellcheck.lua#L472`](../Src/Spellcheck.lua#L472))
  - `Spellcheck:TouchUserDict(dict) → nil` ([`../Src/Spellcheck.lua#L482`](../Src/Spellcheck.lua#L482))
  - `Spellcheck:BuildWordSet(list) → table` ([`../Src/Spellcheck.lua#L489`](../Src/Spellcheck.lua#L489))
  - `Spellcheck:GetUserSets(locale) → table, table` ([`../Src/Spellcheck.lua#L503`](../Src/Spellcheck.lua#L503))
  - `Spellcheck:AddUserWord(locale, word) → nil` ([`../Src/Spellcheck.lua#L559`](../Src/Spellcheck.lua#L559)) — adds `word` to `AddedWords`; FIFO-evicts the oldest entry when the list exceeds `GetUserDictWordCap()`.
  - `Spellcheck:IgnoreWord(locale, word) → nil` ([`../Src/Spellcheck.lua#L587`](../Src/Spellcheck.lua#L587))
  - `Spellcheck:ClearSuggestionCache() → nil` ([`../Src/Spellcheck.lua#L611`](../Src/Spellcheck.lua#L611))
  - Accessors: `GetMaxSuggestions` ([`../Src/Spellcheck.lua#L616`](`../Src/Spellcheck.lua#L616`))
  - Accessors: `GetMaxCandidates` ([`../Src/Spellcheck.lua#L621`](`../Src/Spellcheck.lua#L621`))
  - Accessors: `GetSuggestionCacheSize` ([`../Src/Spellcheck.lua#L626`](`../Src/Spellcheck.lua#L626`))
  - Accessors: `GetReshuffleAttempts` ([`../Src/Spellcheck.lua#L631`](`../Src/Spellcheck.lua#L631`))
  - Accessors: `GetMaxWrongLetters` ([`../Src/Spellcheck.lua#L636`](`../Src/Spellcheck.lua#L636`))
  - Accessors: `GetMinWordLength` ([`../Src/Spellcheck.lua#L656`](`../Src/Spellcheck.lua#L656`))
  - Accessors: `GetMisspellingColour` ([`../Src/Spellcheck.lua#L668`](`../Src/Spellcheck.lua#L668`))
  - Accessors: `GetKeyboardLayout` ([`../Src/Spellcheck.lua#L677`](`../Src/Spellcheck.lua#L677`))
  - Accessors: `GetKBDistTable` ([`../Src/Spellcheck.lua#L687`](`../Src/Spellcheck.lua#L687`))
  - Accessors: `_GetKBDistFromLayouts` ([`../Src/Spellcheck.lua#L706`](`../Src/Spellcheck.lua#L706`))
- Callbacks fired:
  - `SPELLCHECK_WORD_ADDED`, `SPELLCHECK_WORD_IGNORED`.

## Spellcheck.Dictionary

Used lazily by `GetDictionary`, locale switches, and LOD registration.

- Description: Dictionary registration/loading, locale availability, async indexing.
- Methods:
  - `Spellcheck:LoadDictionary(locale) → nil` ([`../Src/Spellcheck/Dictionary.lua#L32`](../Src/Spellcheck/Dictionary.lua#L32))
  - `Spellcheck:RegisterDictionary(locale, data) → nil` ([`../Src/Spellcheck/Dictionary.lua#L67`](../Src/Spellcheck/Dictionary.lua#L67)) — **Security Note**: Validates the associated language family engine for `BlockedHashes` before indexing. Blocks registration if the family engine is missing or insecure.
  - `Spellcheck:_OnDictRegistrationComplete(locale) → nil` ([`../Src/Spellcheck/Dictionary.lua#L368`](../Src/Spellcheck/Dictionary.lua#L368))
  - `Spellcheck:GetAvailableLocales() → string[]` ([`../Src/Spellcheck/Dictionary.lua#L411`](../Src/Spellcheck/Dictionary.lua#L411))
  - `Spellcheck:GetLocaleAddon(locale) → string|nil` ([`../Src/Spellcheck/Dictionary.lua#L420`](../Src/Spellcheck/Dictionary.lua#L420))
  - `Spellcheck:HasLocaleAddon(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L425`](../Src/Spellcheck/Dictionary.lua#L425))
  - `Spellcheck:HasAnyDictionary() → boolean` ([`../Src/Spellcheck/Dictionary.lua#L456`](../Src/Spellcheck/Dictionary.lua#L456))
  - `Spellcheck:IsLocaleAvailable(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L468`](../Src/Spellcheck/Dictionary.lua#L468))
  - `Spellcheck:CanLoadLocale(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L482`](../Src/Spellcheck/Dictionary.lua#L482))
  - `Spellcheck:Notify(msg) → nil` ([`../Src/Spellcheck/Dictionary.lua#L497`](../Src/Spellcheck/Dictionary.lua#L497))
  - `Spellcheck:EnsureLocale(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L503`](../Src/Spellcheck/Dictionary.lua#L503))
  - `Spellcheck:ScheduleLocaleRefresh(locale) → nil` ([`../Src/Spellcheck/Dictionary.lua#L570`](../Src/Spellcheck/Dictionary.lua#L570))
  - `dict:Contains(word: string) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L189`](../Src/Spellcheck/Dictionary.lua#L189)) — returns true if the word (normalised) exists in the dictionary, its base, or the user's personal dictionary.
- Side effects:
  - Schedules `C_Timer.After(0, ...)` chunk processing and refresh tickers.

## Spellcheck.Engine

Runs during suggestion/recolour rebuild.

- Description: Tokenisation, misspelling detection, candidate scoring.
- Methods:
  - `Spellcheck:CollectAffixMatches() → nil`: Scans text for words recognized via affix-stripping. ([`../Src/Spellcheck/Engine.lua#L122`](../Src/Spellcheck/Engine.lua#L122))
  - `CollectMisspellings` ([`../Src/Spellcheck/Engine.lua#L77`](`../Src/Spellcheck/Engine.lua#L77`))
  - `ShouldCheckWord` ([`../Src/Spellcheck/Engine.lua#L138`](`../Src/Spellcheck/Engine.lua#L138`))
  - `GetIgnoredRanges` ([`../Src/Spellcheck/Engine.lua#L145`](`../Src/Spellcheck/Engine.lua#L145`))
  - `IsRangeIgnored` ([`../Src/Spellcheck/Engine.lua#L209`](`../Src/Spellcheck/Engine.lua#L209`))
  - `IsWordCorrect` ([`../Src/Spellcheck/Engine.lua#L218`](`../Src/Spellcheck/Engine.lua#L218`))
  - `ResolveImplicitTrace` ([`../Src/Spellcheck/Engine.lua#L255`](`../Src/Spellcheck/Engine.lua#L255`))
  - `UpdateActiveWord` ([`../Src/Spellcheck/Engine.lua#L299`](`../Src/Spellcheck/Engine.lua#L299`))
  - `GetWordAtCursor` ([`../Src/Spellcheck/Engine.lua#L379`](`../Src/Spellcheck/Engine.lua#L379`))
  - `GetSuggestions` ([`../Src/Spellcheck/Engine.lua#L917`](`../Src/Spellcheck/Engine.lua#L917`))
  - `EditDistance` ([`../Src/Spellcheck/Engine.lua#L1223`](`../Src/Spellcheck/Engine.lua#L1223`))
  - `FormatSuggestionLabel` ([`../Src/Spellcheck/Engine.lua#L1295`](`../Src/Spellcheck/Engine.lua#L1295`))
- Filters run:
  - `PRE_SPELLCHECK` via `API:RunFilter`.

## Spellcheck.UI

Bound when overlay exists; reacts to text/cursor updates.

- Description: UI state machine for recolour refresh, hint, and suggestions.
- Methods:
  - `Spellcheck:GetScrollOffset() → number`: Derive the horizontal scroll offset of a single-line EditBox. ([`../Src/Spellcheck/UI.lua#L1225`](../Src/Spellcheck/UI.lua#L1225))
  - `Spellcheck:MeasureText(text) → number`: Measure text width using a FontString matching the editbox's current font and spacing. ([`../Src/Spellcheck/UI.lua#L1199`](../Src/Spellcheck/UI.lua#L1199))
  - `Spellcheck:ApplyOverlayFont(fontString, maxSize) → number`: Apply the editbox's font to a FontString, optionally clamped to maxSize. Returns the effective size. ([`../Src/Spellcheck/UI.lua#L1185`](../Src/Spellcheck/UI.lua#L1185))
  - `Spellcheck:GetCaretXOffset() → number`: Compute the X offset of the caret for tooltip positioning, clamped to the visible text area. ([`../Src/Spellcheck/UI.lua#L1158`](../Src/Spellcheck/UI.lua#L1158))
  - `Spellcheck:SetSpellcheckOffset(hintX, hintY, suggestX, suggestY) → nil`: Set manual pixel offsets for spellcheck tooltips. ([`../Src/Spellcheck/UI.lua#L560`](../Src/Spellcheck/UI.lua#L560))
  - `Bind` ([`../Src/Spellcheck/UI.lua#L28`](`../Src/Spellcheck/UI.lua#L28`))
  - `BindMultiline` ([`../Src/Spellcheck/UI.lua#L65`](`../Src/Spellcheck/UI.lua#L65`))
  - `UnbindMultiline` ([`../Src/Spellcheck/UI.lua#L122`](`../Src/Spellcheck/UI.lua#L122`))
  - `UnloadAllDictionaries` ([`../Src/Spellcheck/UI.lua#L157`](`../Src/Spellcheck/UI.lua#L157`))
  - `ApplyState` ([`../Src/Spellcheck/UI.lua#L199`](`../Src/Spellcheck/UI.lua#L199`))
  - `OnConfigChanged` ([`../Src/Spellcheck/UI.lua#L230`](`../Src/Spellcheck/UI.lua#L230`))
  - `OnTextChanged` ([`../Src/Spellcheck/UI.lua#L234`](`../Src/Spellcheck/UI.lua#L234`))
  - `OnCursorChanged` ([`../Src/Spellcheck/UI.lua#L256`](`../Src/Spellcheck/UI.lua#L256`))
  - `OnOverlayHide` ([`../Src/Spellcheck/UI.lua#L298`](`../Src/Spellcheck/UI.lua#L298`))
  - `ScheduleRefresh` ([`../Src/Spellcheck/UI.lua#L304`](`../Src/Spellcheck/UI.lua#L304`))
  - `Rebuild` ([`../Src/Spellcheck/UI.lua#L327`](`../Src/Spellcheck/UI.lua#L327`))
  - `EnsureMeasureFontString` ([`../Src/Spellcheck/UI.lua#L341`](`../Src/Spellcheck/UI.lua#L341`))
  - `EnsureSuggestionFrame` ([`../Src/Spellcheck/UI.lua#L356`](`../Src/Spellcheck/UI.lua#L356`))
  - `SuggestionsEqual` ([`../Src/Spellcheck/UI.lua#L449`](`../Src/Spellcheck/UI.lua#L449`))
  - `EnsureHintFrame` ([`../Src/Spellcheck/UI.lua#L459`](`../Src/Spellcheck/UI.lua#L459`))
  - `CancelHintTimer` ([`../Src/Spellcheck/UI.lua#L485`](`../Src/Spellcheck/UI.lua#L485`))
  - `ScheduleHintShow` ([`../Src/Spellcheck/UI.lua#L497`](`../Src/Spellcheck/UI.lua#L497`))
  - `ShowHint` ([`../Src/Spellcheck/UI.lua#L575`](`../Src/Spellcheck/UI.lua#L575`))
  - `HideHint` ([`../Src/Spellcheck/UI.lua#L606`](`../Src/Spellcheck/UI.lua#L606`))
  - `UpdateHint` ([`../Src/Spellcheck/UI.lua#L611`](`../Src/Spellcheck/UI.lua#L611`))
  - `IsSuggestionOpen` ([`../Src/Spellcheck/UI.lua#L634`](`../Src/Spellcheck/UI.lua#L634`))
  - `IsSuggestionEligible` ([`../Src/Spellcheck/UI.lua#L638`](`../Src/Spellcheck/UI.lua#L638`))
  - `HandleKeyDown` ([`../Src/Spellcheck/UI.lua#L645`](`../Src/Spellcheck/UI.lua#L645`))
  - `MoveSelection` ([`../Src/Spellcheck/UI.lua#L706`](`../Src/Spellcheck/UI.lua#L706`))
  - `RefreshSuggestionSelection` ([`../Src/Spellcheck/UI.lua#L728`](`../Src/Spellcheck/UI.lua#L728`))
  - `OpenOrCycleSuggestions` ([`../Src/Spellcheck/UI.lua#L760`](`../Src/Spellcheck/UI.lua#L760`))
  - `ShowSuggestions` ([`../Src/Spellcheck/UI.lua#L789`](`../Src/Spellcheck/UI.lua#L789`))
  - `NextSuggestionsPage` ([`../Src/Spellcheck/UI.lua#L921`](`../Src/Spellcheck/UI.lua#L921`))
  - `HideSuggestions` ([`../Src/Spellcheck/UI.lua#L948`](`../Src/Spellcheck/UI.lua#L948`))
  - `ApplySuggestion` ([`../Src/Spellcheck/UI.lua#L972`](`../Src/Spellcheck/UI.lua#L972`))
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
  - `CanonicalText` ([`../Src/Spellcheck/Recolour.lua#L61`](`../Src/Spellcheck/Recolour.lua#L61`))
  - `CanonicalCursorFromText` ([`../Src/Spellcheck/Recolour.lua#L78`](`../Src/Spellcheck/Recolour.lua#L78`))
  - `CanonicalCursor` ([`../Src/Spellcheck/Recolour.lua#L152`](`../Src/Spellcheck/Recolour.lua#L152`))
  - `CanonicalTextAndCursor` ([`../Src/Spellcheck/Recolour.lua#L164`](`../Src/Spellcheck/Recolour.lua#L164`))
  - `ResolveColour` ([`../Src/Spellcheck/Recolour.lua#L186`](`../Src/Spellcheck/Recolour.lua#L186`)) — seam for future visibility adaptation; currently returns the configured `Spellcheck.MisspellingColour` verbatim.
  - `ColourPrefix` ([`../Src/Spellcheck/Recolour.lua#L197`](`../Src/Spellcheck/Recolour.lua#L197`))
  - `BuildDisplayText` ([`../Src/Spellcheck/Recolour.lua#L218`](`../Src/Spellcheck/Recolour.lua#L218`))
  - `ToDisplayCursor` ([`../Src/Spellcheck/Recolour.lua#L250`](`../Src/Spellcheck/Recolour.lua#L250`))
  - `Apply` ([`../Src/Spellcheck/Recolour.lua#L352`](`../Src/Spellcheck/Recolour.lua#L352`)) — diff-before-SetText is the recursion loop-breaker and caret-stability guarantee.
  - `Clear` ([`../Src/Spellcheck/Recolour.lua#L394`](`../Src/Spellcheck/Recolour.lua#L394`))
  - `Invalidate` ([`../Src/Spellcheck/Recolour.lua#L414`](`../Src/Spellcheck/Recolour.lua#L414`))
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
  - `auto[word] = { c, t }` — repeated uncorrected words pending auto-promotion.
  - `autoCount: number` — cached count of `auto` entries (maintained for O(1) cap checks).
  - `negBiasCount: number` — cached count of `negBias` entries.
  - `total: number` — tracked unique vocabulary size for frequency-cap enforcement.
  ([`../Src/Spellcheck/Adaptive.lua#L63-L100`](../Src/Spellcheck/Adaptive.lua#L63-L100)).
- Methods:
  - `YAS:GetAutoCap() → number`: Returns the maximum number of entries tracked in the `auto` table before low-scoring ones are pruned. Configurable via `YASAutoCap`; default 500, min 50, max 5000. ([`../Src/Spellcheck/Adaptive.lua#L149`](../Src/Spellcheck/Adaptive.lua#L149))
  - `YAS:GetNegBiasCap() → number`: Returns the maximum number of `negBias` rejection-pair entries before low-scoring ones are pruned. Configurable via `YASNegBiasCap`; default 500, min 100, max 10000. ([`../Src/Spellcheck/Adaptive.lua#L142`](../Src/Spellcheck/Adaptive.lua#L142))
  - `YAS:Export() → nil`: Export current learned data for a locale as a text block. ([`../Src/Spellcheck/Adaptive.lua#L832`](../Src/Spellcheck/Adaptive.lua#L832))
  - `YAS:GetBiasTargets() → nil`: Returns a list of candidate words that have been learned as corrections for the given typo. ([`../Src/Spellcheck/Adaptive.lua#L665`](../Src/Spellcheck/Adaptive.lua#L665))
  - `YAS:EnsureFreqSorted() → nil`: Ensures the frequency-sorted index is up-to-date, rebuilding if dirty. ([`../Src/Spellcheck/Adaptive.lua#L237`](../Src/Spellcheck/Adaptive.lua#L237))
  - `IsEnabled() → boolean`: Returns true if YAS is enabled in the configuration. ([`../Src/Spellcheck/Adaptive.lua#L112`](../Src/Spellcheck/Adaptive.lua#L112))
  - `GetFreqCap` ([`../Src/Spellcheck/Adaptive.lua#L121`](../Src/Spellcheck/Adaptive.lua#L121))
  - `GetBiasCap` ([`../Src/Spellcheck/Adaptive.lua#L128`](../Src/Spellcheck/Adaptive.lua#L128))
  - `GetAutoThreshold` ([`../Src/Spellcheck/Adaptive.lua#L135`](../Src/Spellcheck/Adaptive.lua#L135))
  - `Init` ([`../Src/Spellcheck/Adaptive.lua#L160`](../Src/Spellcheck/Adaptive.lua#L160))
  - `GetLocaleDB` ([`../Src/Spellcheck/Adaptive.lua#L187`](../Src/Spellcheck/Adaptive.lua#L187))
  - `IsSaneWord` ([`../Src/Spellcheck/Adaptive.lua#L261`](../Src/Spellcheck/Adaptive.lua#L261))
  - `RecordUsage` ([`../Src/Spellcheck/Adaptive.lua#L303`](../Src/Spellcheck/Adaptive.lua#L303))
  - `RecordSelection` ([`../Src/Spellcheck/Adaptive.lua#L350`](../Src/Spellcheck/Adaptive.lua#L350))
  - `RecordImplicitCorrection` ([`../Src/Spellcheck/Adaptive.lua#L432`](../Src/Spellcheck/Adaptive.lua#L432))
  - `RecordRejection` ([`../Src/Spellcheck/Adaptive.lua#L528`](../Src/Spellcheck/Adaptive.lua#L528))
  - `RecordIgnored` ([`../Src/Spellcheck/Adaptive.lua#L562`](../Src/Spellcheck/Adaptive.lua#L562))
  - `GetBonus` ([`../Src/Spellcheck/Adaptive.lua#L610`](../Src/Spellcheck/Adaptive.lua#L610))
  - `Prune` ([`../Src/Spellcheck/Adaptive.lua#L711`](../Src/Spellcheck/Adaptive.lua#L711))
  - `Reset` ([`../Src/Spellcheck/Adaptive.lua#L760`](../Src/Spellcheck/Adaptive.lua#L760))
  - `GetDataSummary` ([`../Src/Spellcheck/Adaptive.lua#L776`](../Src/Spellcheck/Adaptive.lua#L776))
  - `ClearSpecificUsage` ([`../Src/Spellcheck/Adaptive.lua#L869`](../Src/Spellcheck/Adaptive.lua#L869))
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
  - `Hide` ([`../Src/IconGallery.lua#L109`](../Src/IconGallery.lua#L109))
  - `Filter` ([`../Src/IconGallery.lua#L121`](../Src/IconGallery.lua#L121))
  - `Select` ([`../Src/IconGallery.lua#L147`](../Src/IconGallery.lua#L147))
  - `HandleKeyDown` ([`../Src/IconGallery.lua#L172`](../Src/IconGallery.lua#L172))
  - `_GetIconMeta` ([`../Src/IconGallery.lua#L215`](../Src/IconGallery.lua#L215))
  - `OnTextChanged` ([`../Src/IconGallery.lua#L226`](../Src/IconGallery.lua#L226))
- Callbacks fired:
  - `ICON_GALLERY_SHOW`, `ICON_GALLERY_HIDE`, `ICON_GALLERY_SELECT`.

## EditBox
- Methods:
  - `EditBox:ResolveWhisperTarget(chatType, source, fallback) → any target, boolean isSecure`: Source a whisper target directly from Blizzard's secure last-tell state (GetLastTellTarget/GetLastToldTarget), bypassing Yapper-stored copies that may have become tainted. Used by the `/r` and `/r2` send path. Returns `(fallback, false)` when Blizzard has no matching target. ([`../Src/EditBox.lua#L474`](../Src/EditBox.lua#L474))
  - `EditBox:GetActiveEditor() → table|nil`: Return Yapper's currently visible chat editor, preferring multiline while it is open and falling back to the single-line overlay. ([`../Src/EditBox.lua#L96`](../Src/EditBox.lua#L96))
  - `EditBox:IsChatTypeAvailable(chatType) → boolean`: Check if a chat type is currently available (e.g., in a guild, in a raid). ([`../Src/EditBox.lua#L680`](../Src/EditBox.lua#L680))
  - `EditBox:GetResolvedChatType(ct) → string`: Smartly switch from Party/Raid to Instance if the Home group is missing. ([`../Src/EditBox.lua#L658`](../Src/EditBox.lua#L658))
  - `EditBox:RegisterKeybindOverrides() → nil`: Register keybind overrides when timing is safe. ([`../Src/EditBox.lua#L783`](../Src/EditBox.lua#L783))
  - `EditBox:InitKeybinds() → nil`: Initialize keybind override system. ([`../Src/EditBox.lua#L772`](../Src/EditBox.lua#L772))
  - `EditBox:UpdateFocusOverride() → nil`: Centralize focus override updating. Sets/clears CHAT_FOCUS_OVERRIDE ([`../Src/EditBox.lua#L109`](../Src/EditBox.lua#L109))
  - `YapperTable.InstallCompatMethods(box) → nil`: Installs Blizzard chat-box compatibility methods and stubs on the overlay editbox so addons can query `GetChatType`, `GetChannelTarget`, `GetTellTarget`, `GetLanguage`, `GetAttribute`, and parity fields without nil-crashes. ([`../Src/EditBoxCompat.lua#L32`](../Src/EditBoxCompat.lua#L32))
  - `box.UpdateHeader`: no-op stub installed by InstallCompatMethods to prevent nil-method crashes from Blizzard's chat-frame utility. ([`../Src/EditBoxCompat.lua#L75`](../Src/EditBoxCompat.lua#L75))
  - `box.SetFocusRegionsShown`: no-op stub installed by `InstallCompatMethods`. ([`../Src/EditBoxCompat.lua#L32`](../Src/EditBoxCompat.lua#L32))
  - `box.UpdateNewcomerEditBoxHint`: no-op stub installed by `InstallCompatMethods`. ([`../Src/EditBoxCompat.lua#L32`](../Src/EditBoxCompat.lua#L32))
  - `box:ParseText(send) → nil`: Execute slash lines through Yapper's forwarding path while leaving plain text for Blizzard's SendText dispatch. ([`../Src/EditBoxCompat.lua#L95`](../Src/EditBoxCompat.lua#L95))
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
  - Internal helper exports: `IsWhisperSlashPrefill` ([`../Src/EditBox.lua#L607`](`../Src/EditBox.lua#L607`))
  - Internal helper exports: `ExtractRegionalWhisperTarget` — port of Blizzard's `ExtractTellTarget` for `RegionalUniqueNamesEnabled()` clients (WoW: Forever); resolves "First Last"/"First-Last" targets by longest autocomplete-matching prefix and returns nil while the surname is still being typed ([`../Src/EditBox.lua#L280`](`../Src/EditBox.lua#L280`))
  - Internal helper exports: `ParseWhisperSlash` — one-token target on retail; delegates to `ExtractRegionalWhisperTarget` when regional unique names are enabled ([`../Src/EditBox.lua#L608`](`../Src/EditBox.lua#L608`))
  - Internal helper exports: `GetLastTellTargetInfo` — returns chatType and name of the last person who whispered *you* ([`../Src/EditBox.lua#L611`](`../Src/EditBox.lua#L611`))
  - Internal helper exports: `GetLastToldTargetInfo` — returns chatType and name of the last person *you* whispered (outgoing). Uses `ChatFrameUtil.GetLastToldTarget`; stays in sync with both Yapper and Blizzard sends. ([`../Src/EditBox.lua#L391`](`../Src/EditBox.lua#L391`))
  - Internal helper exports: `SetFrameFillColour` ([`../Src/EditBox.lua#L613`](`../Src/EditBox.lua#L613`))
- Methods:
  - `ClearLockdownState` ([`../Src/EditBox.lua#L81`](../Src/EditBox.lua#L81))
  - `AddReplyTarget` ([`../Src/EditBox.lua#L134`](../Src/EditBox.lua#L134))
  - `NextReplyTarget` ([`../Src/EditBox.lua#L164`](../Src/EditBox.lua#L164))
  - `OpenBlizzardChat` ([`../Src/EditBox.lua#L501`](../Src/EditBox.lua#L501))
  - `SetOnSend` ([`../Src/EditBox.lua#L702`](../Src/EditBox.lua#L702))
  - `EditBox:SyncLanguageFromNative(blizzEditBox) → boolean`: Reconcile languageID changes made directly by Blizzard or another addon with Yapper's active and persisted language state. ([`../Src/EditBox.lua#L711`](../Src/EditBox.lua#L711))
  - `SetPreShowCheck` ([`../Src/EditBox.lua#L766`](../Src/EditBox.lua#L766))
- Invariants:
  - Overlay behaviour valid only after `HookAllChatFrames()` has run.

## EditBox.SkinProxy

Attached during overlay show lifecycle.

- Description: Keeps Blizzard's native editbox skin visible underneath the Yapper overlay.
- Methods:
  - `EditBox:EnsureProxyHeaderHidden() → nil`: Re-hide Blizzard header/prompt elements after native header updates. ([`../Src/EditBox/SkinProxy.lua#L24`](../Src/EditBox/SkinProxy.lua#L24))
  - `EditBox:ApplyProxyMode() → nil`: Activate proxy mode and preserve the original editbox state. ([`../Src/EditBox/SkinProxy.lua#L42`](../Src/EditBox/SkinProxy.lua#L42))
  - `EditBox:RestoreProxyMode() → nil`: Restore the original editbox to the state found before proxy mode. ([`../Src/EditBox/SkinProxy.lua#L113`](../Src/EditBox/SkinProxy.lua#L113))

## EditBox.Overlay

Used by `EditBox:Show` to create and refresh frame contents.

- Description: Overlay frame creation and label/font rendering helpers.
- Fields:
  - `_RefreshOverlayVisuals`, `_ApplyShadowTint`, `_ResolveChannelName`, `_BuildLabelText`, `_GetLabelUsableWidth`, `_ResetLabelToBaseFont`, `_TruncateLabelToWidth`, `_FitLabelFontToWidth`, `_UpdateLabelBackgroundForText` *private by convention; do not rely on* ([`../Src/EditBox/Overlay.lua#L829-L837`](../Src/EditBox/Overlay.lua#L829-L837)).
- Methods:
  - `EditBox:ShowMultilineHint() → nil`: Show the onboarding hint once during the current session and let it fade ([`../Src/EditBox/Overlay.lua#L544`](../Src/EditBox/Overlay.lua#L544))
  - `EditBox:CreateMultilineHint() → nil`: Create the non-interactive hint frame lazily, using UIParent as its parent ([`../Src/EditBox/Overlay.lua#L511`](../Src/EditBox/Overlay.lua#L511))
  - `EditBox:HideMultilineHint() → nil`: Cancel and hide the session-only multiline onboarding hint. ([`../Src/EditBox/Overlay.lua#L493`](../Src/EditBox/Overlay.lua#L493))
  - `EditBox:CreateOverlay() → nil` ([`../Src/EditBox/Overlay.lua#L684`](../Src/EditBox/Overlay.lua#L684)).

## EditBox.Handlers

Bound by `SetupOverlayScripts` when overlay is created.

- Description: Input handlers for Enter/Tab/history/channel switching.
- Methods:
  - `SetupOverlayScripts` ([`../Src/EditBox/Handlers.lua#L41`](../Src/EditBox/Handlers.lua#L41)).
  - `ResetLockdownIdleTimer` ([`../Src/EditBox/Handlers.lua#L1155`](../Src/EditBox/Handlers.lua#L1155)).
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
  - `EditBox:RecordFallbackSend(editBox) → nil`: Record a message sent through Blizzard's native editbox during lockdown, bypass, or handoff fallback into persistent history. ([`../Src/Hooks/ShowHide.lua#L1076`](../Src/Hooks/ShowHide.lua#L1076))
  - `EditBox:RetargetOpenWhisper(target, blizzBox, chatType) → boolean`: Retarget the already-open overlay onto an external transient whisper; supports character names and numeric Battle.net account IDs. ([`../Src/Hooks/ShowHide.lua#L1026`](../Src/Hooks/ShowHide.lua#L1026))
  - `EditBox:IsNativeChatEditBox(eb) → boolean`: True only for Blizzard's native ChatFrameN editboxes (never our overlay). ([`../Src/Hooks/ShowHide.lua#L1013`](../Src/Hooks/ShowHide.lua#L1013))
  - `EditBox:Show(origEditBox)` - Present overlay in place of Blizzard editbox.
  - `EditBox:Hide(isHandoff)` - Close overlay, save state.
  - `EditBox:HandoffToBlizzard(silent?, bypassOpen?, isMultiline?)` - Lockdown handoff.
  - `EditBox:ApplyConfigToLiveOverlay(force?)` - Re-apply config to visible overlay.

## Hooks.Label

Channel label and tab cycling.

- Description: RefreshLabel(), CycleChatType(), RecordTabChannel(), PersistLastUsed(), OnTabPressed().
- File: [`../Src/Hooks/Label.lua`](../Src/Hooks/Label.lua)
- Methods:
  - `EditBox:ResyncFromBlizzardAfterLockdown() → boolean`: Pull safe native channel state (chatType, tellTarget, channelTarget, language) back into Yapper from Blizzard's editbox attributes after lockdown recovery. Returns false when attributes are missing or secret-tainted. Called from the lockdown-recovery path in Handlers. ([`../Src/Hooks/Label.lua#L397`](../Src/Hooks/Label.lua#L397))
  - `EditBox:ResetSyncedAttributes() → nil`: Inverse of SyncAttributesToBlizzard: restore the Blizzard editbox to a neutral state and clear cached native attributes. ([`../Src/Hooks/Label.lua#L348`](../Src/Hooks/Label.lua#L348))
  - `EditBox:SyncAttributesToBlizzard(allowLockdown) → nil`: Push Yapper's current chatType, target, channel and language into Blizzard's native editbox when safe. Whisper attributes remain owned by Blizzard to avoid taint. ([`../Src/Hooks/Label.lua#L254`](../Src/Hooks/Label.lua#L254))
  - `EditBox:GetAvailableChatTypes() → table`: Return the subset of TAB_CYCLE entries currently available to the player. ([`../Src/Hooks/Label.lua#L439`](../Src/Hooks/Label.lua#L439))
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
  - `UpdateState` ([`../Src/Bridges/TypingTrackerBridge.lua#L124`](`../Src/Bridges/TypingTrackerBridge.lua#L124`))
  - `OnOverlayFocusGained` ([`../Src/Bridges/TypingTrackerBridge.lua#L160`](`../Src/Bridges/TypingTrackerBridge.lua#L160`))
  - `OnOverlayFocusLost` ([`../Src/Bridges/TypingTrackerBridge.lua#L164`](`../Src/Bridges/TypingTrackerBridge.lua#L164`))
  - `OnChannelChanged` ([`../Src/Bridges/TypingTrackerBridge.lua#L168`](`../Src/Bridges/TypingTrackerBridge.lua#L168`))

## RPPrefixBridge

Initialised by `Chat:Init`.

- Description: Prefixes outgoing RP marker text.
- Methods:
  - `Init` ([`../Src/Bridges/RPPrefixBridge.lua#L61`](`../Src/Bridges/RPPrefixBridge.lua#L61`))
  - `IsActive` ([`../Src/Bridges/RPPrefixBridge.lua#L131`](`../Src/Bridges/RPPrefixBridge.lua#L131`))
  - `ApplyPrefix` ([`../Src/Bridges/RPPrefixBridge.lua#L152`](`../Src/Bridges/RPPrefixBridge.lua#L152`))

## WIMBridge

Initialised by `Chat:Init`.

- Description: Cooperates with WIM focus ownership.
- Methods:
  - `IsFocusActive` ([`../Src/Bridges/WIMBridge.lua#L26`](`../Src/Bridges/WIMBridge.lua#L26`))
  - `IsLoaded` ([`../Src/Bridges/WIMBridge.lua#L43`](`../Src/Bridges/WIMBridge.lua#L43`))
  - `Init` ([`../Src/Bridges/WIMBridge.lua#L51`](`../Src/Bridges/WIMBridge.lua#L51`))

## Policies

Passive rule modules loaded from `Src/Policies/` and invoked by owner modules.

- Description: Policy objects expose decision methods but do not perform startup work or register runtime hooks.
- Modules:
  - `LockdownPolicy:IsChatLockdown() → boolean`: Returns true when chat messaging lockdown is active. ([`../Src/Policies/LockdownPolicy.lua#L53`](../Src/Policies/LockdownPolicy.lua#L53))
  - `LockdownPolicy:IsCombatLockdown() → boolean`: Returns true when protected-frame combat lockdown is active. ([`../Src/Policies/LockdownPolicy.lua#L66`](../Src/Policies/LockdownPolicy.lua#L66))
  - `LockdownPolicy:IsChatOrCombatLockdown() → boolean`: Returns true when either chat or combat lockdown is active. ([`../Src/Policies/LockdownPolicy.lua#L71`](../Src/Policies/LockdownPolicy.lua#L71))
  - `LockdownPolicy:IsProtectedSlashCommand(command) → boolean`: Returns true when a slash command token (e.g. "/m") resolves to an action insecure code cannot run during combat lockdown — secure registry commands via `IsSecureCmd` plus curated non-secure commands that call protected APIs. ([`../Src/Policies/LockdownPolicy.lua#L133`](../Src/Policies/LockdownPolicy.lua#L133))
  - `LockdownPolicy:IsAlwaysForbiddenSlashCommand(command) → boolean`: Returns true for targeting and focus slash commands whose protected Blizzard handlers must never be dispatched through Yapper's tainted forwarding path. ([`../Src/Policies/LockdownPolicy.lua#L150`](../Src/Policies/LockdownPolicy.lua#L150))
  - `LockdownPolicy:HasAddOnRestrictionAPI() → boolean`: Returns true when the client exposes the WoW 12.x `C_RestrictedActions` / `Enum.AddOnRestrictionType` surface. ([`../Src/Policies/LockdownPolicy.lua#L18`](../Src/Policies/LockdownPolicy.lua#L18))
  - `LockdownPolicy:IsAddOnRestrictionActive(restrictionType) → boolean`: Returns true when a single `Enum.AddOnRestrictionType` is enforced. ([`../Src/Policies/LockdownPolicy.lua#L28`](../Src/Policies/LockdownPolicy.lua#L28))
  - `LockdownPolicy:IsAnyAddOnRestrictionActive() → boolean`: Returns true while any addon restriction type is enforced; non-chat restrictions leave messaging usable but poison Blizzard-produced data with secret values, so tainted calls into Blizzard handlers can error on secret comparisons. ([`../Src/Policies/LockdownPolicy.lua#L42`](../Src/Policies/LockdownPolicy.lua#L42))
  - `ChannelPolicy:BuildPersistedLastUsed(...) → table|nil`: Produces the sticky persisted last-used payload while preserving current selection semantics. ([`../Src/Policies/ChannelPolicy.lua#L100`](../Src/Policies/ChannelPolicy.lua#L100))
  - `ChannelPolicy:ResolveOpenSelection(context) → table`: Resolves the open channel selection from the current show/handoff context. ([`../Src/Policies/ChannelPolicy.lua#L186`](../Src/Policies/ChannelPolicy.lua#L186))

## Router

Initialised by `Chat:Init`.

- Description: Resolves concrete WoW send API for chat target.
- Fields:
  - `SendChatMessage`, `BNSendWhisper`, `ClubSendMessage` cached function refs ([`../Src/Router.lua#L26-L28`](../Src/Router.lua#L26-L28)).
- Methods:
  - `ChannelPolicy:SanitizeCommittedSelection(current) → table|nil`: Normalize a runtime channel selection before persistence or commit, removing unusable secret or unavailable targets. ([`../Src/Policies/ChannelPolicy.lua#L169`](../Src/Policies/ChannelPolicy.lua#L169))
  - `ResolveBnetTarget` ([`../Src/Router.lua#L63`](`../Src/Router.lua#L63`))
  - `_ResolveBnetTargetUncached` ([`../Src/Router.lua#L85`](`../Src/Router.lua#L85`))
  - `ResolveBnetDisplay` ([`../Src/Router.lua#L118`](`../Src/Router.lua#L118`))
  - `FlushBnetCache` ([`../Src/Router.lua#L177`](`../Src/Router.lua#L177`))
  - `Init` ([`../Src/Router.lua#L181`](`../Src/Router.lua#L181`))
  - `DetectCommunityChannel` ([`../Src/Router.lua#L199`](`../Src/Router.lua#L199`))
  - `Send` ([`../Src/Router.lua#L217`](`../Src/Router.lua#L217`))
- Side effects:
  - May delegate to `GopherBridge:Send`.

## Chunking

Called from `Chat:SendPosts` for every post, oversized or not, so that `PRE_CHUNK` fires uniformly.

- Description: UTF-8 aware message splitting.
- Methods:
  - `Chunking:Split(text, limit, opts?) → string[]|nil` ([`../Src/Chunking.lua#L378`](../Src/Chunking.lua#L378))
    - `opts`: `{ ignoreParagraphMerging?, useDelineators?, delineator?, chatType?, language? }`
    - Fires the `PRE_CHUNK` filter once per contiguous text unit (after paragraph isolation). Returns `nil` when a filter cancels the send.
    - Honours `payload.continuationPrefix` set by a `PRE_CHUNK` filter, charging it against the byte budget of every chunk after the first.
    - Continuation chunks are assembled as `<delineator><continuationPrefix><text>`, or `<continuationPrefix><delineator><text>` when the filter sets `payload.continuationPrefixFirst`.

## Queue

Initialised by `Chat:Init`; registers many chat confirm events.

- Description: Ordered chunk delivery with ack/stall policy.
- Fields:
  - Queue state: `Entries` ([`../Src/Queue.lua#L184`](`../Src/Queue.lua#L184`))

  - Queue state: `PlayerGUID` ([`../Src/Queue.lua#L185`](`../Src/Queue.lua#L185`))
  - Queue state: `NeedsContinue` ([`../Src/Queue.lua#L189`](`../Src/Queue.lua#L189`))
  - Queue state: `StallTimer` ([`../Src/Queue.lua#L190`](`../Src/Queue.lua#L190`))
  - Queue state: `StallTimeout` ([`../Src/Queue.lua#L191`](`../Src/Queue.lua#L191`))
  - Queue state: `PendingEntry` ([`../Src/Queue.lua#L193`](`../Src/Queue.lua#L193`))
  - Queue state: `PendingAckEntry` ([`../Src/Queue.lua#L194`](`../Src/Queue.lua#L194`))
  - Queue state: `PendingAckText` ([`../Src/Queue.lua#L195`](`../Src/Queue.lua#L195`))
  - Queue state: `PendingAckEvent` ([`../Src/Queue.lua#L196`](`../Src/Queue.lua#L196`))
  - Queue state: `PendingAckPolicyClass` ([`../Src/Queue.lua#L197`](`../Src/Queue.lua#L197`))
  - Queue state: `StrictAckMatching` ([`../Src/Queue.lua#L198`](`../Src/Queue.lua#L198`))
  - Queue state: `_lastEscTime` ([`../Src/Queue.lua#L200`](`../Src/Queue.lua#L200`))
  - Queue state: `ContinueFrame` ([`../Src/Queue.lua#L203`](`../Src/Queue.lua#L203`))
- Methods:
  - `Queue:IsAcceptableAck() → nil`: Check if a received chat event is an acceptable acknowledgement for an expected event. ([`../Src/Queue.lua#L558`](../Src/Queue.lua#L558))
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
  - `RequiresHardwareEvent` ([`../Src/Queue.lua#L423`](../Src/Queue.lua#L423))
  - `SendNext` ([`../Src/Queue.lua#L428`](../Src/Queue.lua#L428))
  - `BeginEntry` ([`../Src/Queue.lua#L464`](../Src/Queue.lua#L464))
  - `HandleAck` ([`../Src/Queue.lua#L501`](../Src/Queue.lua#L501))
  - `AssumeAck` ([`../Src/Queue.lua#L510`](../Src/Queue.lua#L510))
  - `RawSend` ([`../Src/Queue.lua#L520`](../Src/Queue.lua#L520))
  - `Complete` ([`../Src/Queue.lua#L541`](../Src/Queue.lua#L541))
  - `OnChatEvent` ([`../Src/Queue.lua#L568`](../Src/Queue.lua#L568))
  - `OnOpenChat` ([`../Src/Queue.lua#L659`](../Src/Queue.lua#L659))
  - `TryContinue` ([`../Src/Queue.lua#L669`](../Src/Queue.lua#L669))
  - `ResetStallTimer` ([`../Src/Queue.lua#L688`](../Src/Queue.lua#L688))
  - `CancelStallTimer` ([`../Src/Queue.lua#L705`](../Src/Queue.lua#L705))
  - `OnStallTimeout` ([`../Src/Queue.lua#L712`](../Src/Queue.lua#L712))
  - `CreateContinueFrame` ([`../Src/Queue.lua#L732`](../Src/Queue.lua#L732))
  - `ShowContinuePrompt` ([`../Src/Queue.lua#L792`](../Src/Queue.lua#L792))
  - `HideContinuePrompt` ([`../Src/Queue.lua#L829`](../Src/Queue.lua#L829))
  - `EnableEscapeCancel` ([`../Src/Queue.lua#L840`](../Src/Queue.lua#L840))
  - `DisableEscapeCancel` ([`../Src/Queue.lua#L873`](../Src/Queue.lua#L873))
  - `Cancel` ([`../Src/Queue.lua#L880`](../Src/Queue.lua#L880))
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
  - `Chat:SendPosts(posts, chatType, language, target) → boolean, string|nil, number|nil, string|nil` ([`../Src/Chat.lua#L107`](../Src/Chat.lua#L107))
  - `Chat:OnSend(text, chatType, language, target) → boolean` ([`../Src/Chat.lua#L223`](../Src/Chat.lua#L223))
  - `Chat:DirectSend(msg, chatType, language, target) → nil` ([`../Src/Chat.lua#L238`](../Src/Chat.lua#L238))
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
  - `Frame` ([`../Src/Multiline.lua#L57`](`../Src/Multiline.lua#L57`))
  - `ScrollFrame` ([`../Src/Multiline.lua#L58`](`../Src/Multiline.lua#L58`))
  - `EditBox` ([`../Src/Multiline.lua#L59`](`../Src/Multiline.lua#L59`))
  - `LabelFS` ([`../Src/Multiline.lua#L60`](`../Src/Multiline.lua#L60`))
  - `Active` ([`../Src/Multiline.lua#L239`](`../Src/Multiline.lua#L239`))
  - `ChatType` ([`../Src/Multiline.lua#L61`](`../Src/Multiline.lua#L61`))
  - `Language` ([`../Src/Multiline.lua#L62`](`../Src/Multiline.lua#L62`))
  - `Target` ([`../Src/Multiline.lua#L63`](`../Src/Multiline.lua#L63`))
- Methods:
  - `Multiline:OnLockdownEnd() → nil`: Called when combat ends (PLAYER_REGEN_ENABLED). ([`../Src/Multiline.lua#L1104`](../Src/Multiline.lua#L1104))
  - `Multiline:OnLockdownStart() → nil`: Called when combat starts (PLAYER_REGEN_DISABLED). ([`../Src/Multiline.lua#L1063`](../Src/Multiline.lua#L1063))
  - `UpdateLabelGap` ([`../Src/Multiline.lua#L169`](`../Src/Multiline.lua#L169`))
  - `CreateFrame` ([`../Src/Multiline.lua#L200`](`../Src/Multiline.lua#L200`))
  - `Enter` ([`../Src/Multiline.lua#L646`](`../Src/Multiline.lua#L646`))
  - `Exit` ([`../Src/Multiline.lua#L800`](`../Src/Multiline.lua#L800`))
  - `Submit` ([`../Src/Multiline.lua#L928`](`../Src/Multiline.lua#L928`))
  - `Cancel` ([`../Src/Multiline.lua#L1029`](`../Src/Multiline.lua#L1029`))
  - `ApplyTheme` ([`../Src/Multiline.lua#L1123`](`../Src/Multiline.lua#L1123`))
- Invariants:
  - While `Active`, single-line overlay show path should early-return.

## Autocomplete

Binds to overlay (or multiline) editbox when available.

- Description: Ghost-text completion from dictionary + YAS.
- Fields:
  - `GhostFS` ([`../Src/Autocomplete.lua#L59`](`../Src/Autocomplete.lua#L59`))
  - `CurrentSugg` ([`../Src/Autocomplete.lua#L60`](`../Src/Autocomplete.lua#L60`))
  - `CurrentPrefix` ([`../Src/Autocomplete.lua#L61`](`../Src/Autocomplete.lua#L61`))
  - `PrefixText` ([`../Src/Autocomplete.lua#L62`](`../Src/Autocomplete.lua#L62`))
  - `Active` ([`../Src/Autocomplete.lua#L63`](`../Src/Autocomplete.lua#L63`))
  - `Enabled` ([`../Src/Autocomplete.lua#L63`](`../Src/Autocomplete.lua#L63`))
  - `_activeEditBox` ([`../Src/Autocomplete.lua#L65`](`../Src/Autocomplete.lua#L65`))
  - `_isMultiline` ([`../Src/Autocomplete.lua#L66`](`../Src/Autocomplete.lua#L66`))
- Methods:
  - `Autocomplete:SetOffset(x, y) → nil`: Set a manual pixel offset for the ghost-text positioning. ([`../Src/Autocomplete.lua#L611`](../Src/Autocomplete.lua#L611))
  - `IsEnabled`, `ExtractWordAtCursor`, `SearchDictionary`, `GetSuggestion`, `GetGhostFS`, `_InstallCursorHook`, `PositionGhost`, `ShowGhost`, `HideGhost`, `OnTextChanged`, `OnTabPressed`, `OnOverlayHide`, `SyncFont`, `SyncGhostFont`, `BindMultiline`, `UnbindMultiline` ([`../Src/Autocomplete.lua`](../Src/Autocomplete.lua)).

## History

Initialised on `ADDON_LOADED`; hooks overlay on `PLAYER_ENTERING_WORLD`.

- Description: Persistent chat history, draft store, undo/redo snapshots.
- Methods:
  - `History:SaveDraft(editBox, isMultiline) → nil`: Save a draft from any EditBox (overlay or multiline). ([`../Src/History.lua#L196`](../Src/History.lua#L196))
  - `History:GetDraft() → string? text, string? chatType, string? target, boolean? multiline`: Return the saved draft if dirty. ([`../Src/History.lua#L249`](../Src/History.lua#L249))
  - `InitDB` ([`../Src/History.lua#L73`](`../Src/History.lua#L73`))
  - `SaveDB` ([`../Src/History.lua#L114`](`../Src/History.lua#L114`))
  - `AddChatHistory` ([`../Src/History.lua#L135`](`../Src/History.lua#L135`))
  - `GetChatHistory` ([`../Src/History.lua#L172`](`../Src/History.lua#L172`))
  - `GetDraftStore` ([`../Src/History.lua#L183`](`../Src/History.lua#L183`))
  - `MarkDirty` ([`../Src/History.lua#L258`](`../Src/History.lua#L258`))
  - `ClearDraft` ([`../Src/History.lua#L263`](`../Src/History.lua#L263`))
  - `CancelPauseTimer` ([`../Src/History.lua#L283`](`../Src/History.lua#L283`))
  - `AddSnapshot` ([`../Src/History.lua#L313`](`../Src/History.lua#L313`))
  - `Undo` ([`../Src/History.lua#L359`](`../Src/History.lua#L359`))
  - `Redo` ([`../Src/History.lua#L375`](`../Src/History.lua#L375`))
  - `HookOverlayEditBox` ([`../Src/History.lua#L405`](`../Src/History.lua#L405`))
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
  - `LayoutCursor:Pad() → nil`: No description provided. ([`../Src/Interface.lua#L107`](../Src/Interface.lua#L107))
  - `LayoutCursor:Advance() → nil`: No description provided. ([`../Src/Interface.lua#L102`](../Src/Interface.lua#L102))
  - `LayoutCursor:Y() → nil`: No description provided. ([`../Src/Interface.lua#L98`](../Src/Interface.lua#L98))
  - `LayoutCursor:New(startY) → table`: No description provided. ([`../Src/Interface.lua#L94`](../Src/Interface.lua#L94))
  - `InitPopups` ([`../Src/Interface.lua#L306`](`../Src/Interface.lua#L306`))
  - `BuildConfigUI` ([`../Src/Interface.lua#L453`](`../Src/Interface.lua#L453`))
  - `ShowMainWindow` ([`../Src/Interface.lua#L776`](`../Src/Interface.lua#L776`))
  - `OpenToCategory` ([`../Src/Interface.lua#L801`](`../Src/Interface.lua#L801`))
  - `ToggleMainWindow` ([`../Src/Interface.lua#L825`](`../Src/Interface.lua#L825`))
  - `HandleLauncherClick` ([`../Src/Interface.lua#L857`](`../Src/Interface.lua#L857`))
  - `CloseFrame` ([`../Src/Interface.lua#L892`](`../Src/Interface.lua#L892`))
  - `Init` ([`../Src/Interface.lua#L903`](`../Src/Interface.lua#L903`))
  - `CreateLauncher` ([`../Src/Interface.lua#L937`](`../Src/Interface.lua#L937`))
- Global function:
  - `Yapper_FromCompartment(...)` ([`../Src/Interface.lua#L845`](../Src/Interface.lua#L845)).

## Interface.Schema

Build-time render schema module used by window/UI builders.

- Description: Settings schema composition and category metadata.
- Fields:
  - `_COLOUR_KEYS`, `_CHANNEL_OVERRIDE_OPTIONS`, `_CREDITS_BUNDLED`, `_CREDITS_OPTIONAL`, `_FONT_OUTLINE_OPTIONS`, `_SETTING_TOOLTIPS`, `_FRIENDLY_LABELS`, `_CATEGORIES`, `_PATH_TO_CATEGORY` *private by convention; do not rely on* ([`../Src/Interface/Schema.lua#L519-L527`](../Src/Interface/Schema.lua#L512)).
- Methods:
  - `BuildRenderSchema` ([`../Src/Interface/Schema.lua#L345`](`../Src/Interface/Schema.lua#L345`))
  - `GetRenderSchema` ([`../Src/Interface/Schema.lua#L486`](`../Src/Interface/Schema.lua#L486`))
  - `RefreshRenderSchema` ([`../Src/Interface/Schema.lua#L494`](`../Src/Interface/Schema.lua#L494`))
  - `OnWindowClosed` ([`../Src/Interface/Schema.lua#L500`](`../Src/Interface/Schema.lua#L500`))

## Interface.Config

Handles config reads/writes and side-effect fan-out.

- Description: Config root/path helpers, sanitisation, minimap controls.
- Methods:
  - `Interface:FactoryReset() → nil`: TRUE clean slate: wipes all settings, learned dictionary data, and history. ([`../Src/Interface/Config.lua#L75`](../Src/Interface/Config.lua#L75))
  - `Interface:ResetAllSettings() → nil`: Reset all configuration settings to their default values. ([`../Src/Interface/Config.lua#L47`](../Src/Interface/Config.lua#L47))
  - `GetLocalConfigRoot` ([`../Src/Interface/Config.lua#L31`](`../Src/Interface/Config.lua#L31`))
  - `GetDefaultsRoot` ([`../Src/Interface/Config.lua#L38`](`../Src/Interface/Config.lua#L38`))
  - `GetRenderCacheContainer` ([`../Src/Interface/Config.lua#L95`](`../Src/Interface/Config.lua#L95`))
  - `PurgeRenderCache` ([`../Src/Interface/Config.lua#L106`](`../Src/Interface/Config.lua#L106`))
  - `SetDirty` ([`../Src/Interface/Config.lua#L112`](`../Src/Interface/Config.lua#L112`))
  - `IsDirty` ([`../Src/Interface/Config.lua#L117`](`../Src/Interface/Config.lua#L117`))
  - `SetSettingsChanged` ([`../Src/Interface/Config.lua#L122`](`../Src/Interface/Config.lua#L122`))
  - `GetConfigPath` ([`../Src/Interface/Config.lua#L130`](`../Src/Interface/Config.lua#L130`))
  - `GetDefaultPath` ([`../Src/Interface/Config.lua#L138`](`../Src/Interface/Config.lua#L138`))
  - `UpdateOverrideTextColorCheckboxState` ([`../Src/Interface/Config.lua#L142`](`../Src/Interface/Config.lua#L142`))
  - `SetLocalPath` ([`../Src/Interface/Config.lua#L146`](`../Src/Interface/Config.lua#L146`))
  - `GetLauncherTooltipLines` ([`../Src/Interface/Config.lua#L393`](`../Src/Interface/Config.lua#L393`))
  - `GetMinimapButtonSettings` ([`../Src/Interface/Config.lua#L401`](`../Src/Interface/Config.lua#L401`))
  - `GetMinimapButtonOffset` ([`../Src/Interface/Config.lua#L414`](`../Src/Interface/Config.lua#L414`))
  - `PositionMinimapButton` ([`../Src/Interface/Config.lua#L418`](`../Src/Interface/Config.lua#L418`))
  - `UpdateMinimapButtonAngleFromCursor` ([`../Src/Interface/Config.lua#L434`](`../Src/Interface/Config.lua#L434`))
  - `ApplyMinimapButtonVisibility` ([`../Src/Interface/Config.lua#L451`](`../Src/Interface/Config.lua#L451`))
  - `IsPathDisabledByTheme` ([`../Src/Interface/Config.lua#L491`](`../Src/Interface/Config.lua#L491`))
  - `GetFriendlyLabel` ([`../Src/Interface/Config.lua#L531`](`../Src/Interface/Config.lua#L531`))
  - `SanitizeLocalConfig` ([`../Src/Interface/Config.lua#L570`](`../Src/Interface/Config.lua#L570`))
- Non-obvious rationale migrated from old docs:
  - `SetLocalPath` is the **single authoritative write source** for configuration; it handles profile-aware routing, theme-override marking, and automatic `PromoteCharacterToGlobal` triggers during profile toggles.
  - `SetLocalPath` enforces channel marker sync (`Chat.DELINEATOR` and `Chat.PREFIX`) as a single logical setting update.

## Interface.Window

Builds and controls top-level frames.

- Description: Main window, welcome/what's-new flows, UI font scaling.
- Fields:
  - `_activeCategory` *private by convention; do not rely on* ([`../Src/Interface/Window.lua#L175`](../Src/Interface/Window.lua#L175)).
- Methods:
  - `Interface:CreateFullscreenDimmer(alpha) → Frame`: Create a fullscreen modal dimmer shared by welcome and What's New popups. ([`../Src/Interface/Window.lua#L261`](../Src/Interface/Window.lua#L261))
  - `Interface:ForEachWhatsNewVersion(limitToOne, callback) → nil`: Iterate through changelog versions in display order, passing each version and note array to the callback. ([`../Src/Interface/Window.lua#L216`](../Src/Interface/Window.lua#L216))
  - `CompareVersions` — Compares semantic version strings. ([`../Src/Interface/Window.lua#L194`](../Src/Interface/Window.lua#L194))
  - `GetSortedVersions` — Returns WHATS_NEW entries sorted by version. ([`../Src/Interface/Window.lua#L205`](../Src/Interface/Window.lua#L205))
  - `CheckForChangelogUpdate` — Handshake that updates seen records and triggers popups. ([`../Src/Interface/Window.lua#L314`](../Src/Interface/Window.lua#L314))
  - `PopulateWhatsNewContent` — Renders changelog notes into a container. ([`../Src/Interface/Window.lua#L754`](../Src/Interface/Window.lua#L754))
  - `RefreshWhatsNewContent` — Wipes and re-renders the WhatsNew popup. ([`../Src/Interface/Window.lua#L796`](../Src/Interface/Window.lua#L796))
  - `UpdateWhatsNewButtonScale` — Scales the 'Got it' button text. ([`../Src/Interface/Window.lua#L813`](../Src/Interface/Window.lua#L813))
  - `Interface:GetWelcomeVersion() → number`: Returns the target version of the welcome screen content. ([`../Src/Interface/Window.lua#L227`](../Src/Interface/Window.lua#L227))
  - `GetMainWindowPositionStore` ([`../Src/Interface/Window.lua#L29`](`../Src/Interface/Window.lua#L29`))
  - `SaveMainWindowPosition` ([`../Src/Interface/Window.lua#L46`](`../Src/Interface/Window.lua#L46`))
  - `ApplyMainWindowPosition` ([`../Src/Interface/Window.lua#L63`](`../Src/Interface/Window.lua#L63`))
  - `ShouldShowWelcomeChoice` ([`../Src/Interface/Window.lua#L275`](`../Src/Interface/Window.lua#L275`))
  - `MarkWelcomeShown` ([`../Src/Interface/Window.lua#L320`](`../Src/Interface/Window.lua#L320`))
  - `MarkVersionSeen` ([`../Src/Interface/Window.lua#L324`](`../Src/Interface/Window.lua#L324`))
  - `CreateWelcomeChoiceFrame` ([`../Src/Interface/Window.lua#L381`](`../Src/Interface/Window.lua#L381`))
  - `CreateWhatsNewFrame` ([`../Src/Interface/Window.lua#L571`](`../Src/Interface/Window.lua#L571`))
  - `CreateMainWindow` ([`../Src/Interface/Window.lua#L808`](`../Src/Interface/Window.lua#L808`))
  - `UpdateSidebarSelection` ([`../Src/Interface/Window.lua#L1018`](`../Src/Interface/Window.lua#L1018`))
  - `GetUIFontOffset` ([`../Src/Interface/Window.lua#L1037`](`../Src/Interface/Window.lua#L1037`))
  - `SetUIFontOffset` ([`../Src/Interface/Window.lua#L1043`](`../Src/Interface/Window.lua#L1043`))
  - `ScaledRow` ([`../Src/Interface/Window.lua#L1051`](`../Src/Interface/Window.lua#L1051`))
  - `ApplyUIFontScaleToFontString` ([`../Src/Interface/Window.lua#L1056`](`../Src/Interface/Window.lua#L1056`))
  - `ApplyUIFontScale` ([`../Src/Interface/Window.lua#L1071`](`../Src/Interface/Window.lua#L1071`))
  - `RefreshFontScaleLabel` ([`../Src/Interface/Window.lua#L1090`](`../Src/Interface/Window.lua#L1090`))

## Interface.Widgets

Widget factory/pool and reusable setting controls.

- Description: UI control allocator with pooling, tooltip plumbing, common controls.
- Fields:
  - `WidgetPool: table` ([`../Src/Interface/Widgets.lua#L66`](../Src/Interface/Widgets.lua#L66)).
  - `_OpenColorPicker: function` *private by convention; do not rely on* ([`../Src/Interface/Widgets.lua#L891`](../Src/Interface/Widgets.lua#L891)).
- Methods:
  - `ClearConfigControls` ([`../Src/Interface/Widgets.lua#L33`](`../Src/Interface/Widgets.lua#L33`))
  - `AddControl` ([`../Src/Interface/Widgets.lua#L54`](`../Src/Interface/Widgets.lua#L54`))
  - `AcquireWidget` ([`../Src/Interface/Widgets.lua#L75`](`../Src/Interface/Widgets.lua#L75`))
  - `ReleaseWidget` ([`../Src/Interface/Widgets.lua#L112`](`../Src/Interface/Widgets.lua#L112`))
  - `GetTooltip` ([`../Src/Interface/Widgets.lua#L190`](`../Src/Interface/Widgets.lua#L190`))
  - `AttachTooltip` ([`../Src/Interface/Widgets.lua#L201`](`../Src/Interface/Widgets.lua#L201`))
  - `CreateResetButton` ([`../Src/Interface/Widgets.lua#L306`](`../Src/Interface/Widgets.lua#L306`))
  - `CreateLabel` ([`../Src/Interface/Widgets.lua#L319`](`../Src/Interface/Widgets.lua#L319`))
  - `CreateCheckBox` ([`../Src/Interface/Widgets.lua#L521`](`../Src/Interface/Widgets.lua#L521`))
  - `CreateTextInput` ([`../Src/Interface/Widgets.lua#L569`](`../Src/Interface/Widgets.lua#L569`))
  - `CreateColorPickerControl` ([`../Src/Interface/Widgets.lua#L660`](`../Src/Interface/Widgets.lua#L660`))
  - `CreateFontSizeDropdown` ([`../Src/Interface/Widgets.lua#L746`](`../Src/Interface/Widgets.lua#L746`))
  - `CreateFontOutlineDropdown` ([`../Src/Interface/Widgets.lua#L845`](`../Src/Interface/Widgets.lua#L845`))
- Non-obvious rationale migrated from old docs:
  - `CreateResetButton` self-registers with control tracking; do not double-register via `AddControl`.

## Interface.Pages

Per-category page builders called by `BuildConfigUI`.

- Description: Concrete settings page construction routines.
- Methods:
  - `CreateChangelogPage` — Builds the scrollable version history settings tab. ([`../Src/Interface/Pages.lua#L908`](../Src/Interface/Pages.lua#L908))
  - `CreateChannelOverrideControls` ([`../Src/Interface/Pages.lua#L37`](`../Src/Interface/Pages.lua#L37`))
  - `CreateGlobalSyncControls` ([`../Src/Interface/Pages.lua#L338`](`../Src/Interface/Pages.lua#L338`))
  - `CreateYASLearningPage` ([`../Src/Interface/Pages.lua#L397`](`../Src/Interface/Pages.lua#L397`))
  - `CreateQueueDiagnostics` ([`../Src/Interface/Pages.lua#L642`](`../Src/Interface/Pages.lua#L642`))
  - `CreateTutorialPage` ([`../Src/Interface/Pages.lua#L746`](`../Src/Interface/Pages.lua#L746`))
  - `CreateCreditsPage` ([`../Src/Interface/Pages.lua#L845`](`../Src/Interface/Pages.lua#L845`))
  - `CreateSpellcheckLocaleDropdown` ([`../Src/Interface/Pages.lua#L957`](`../Src/Interface/Pages.lua#L957`))
  - `CreateSpellcheckKeyboardLayoutDropdown` ([`../Src/Interface/Pages.lua#L1058`](`../Src/Interface/Pages.lua#L1058`))
  - `CreateSpellcheckUserDictEditor` ([`../Src/Interface/Pages.lua#L1107`](`../Src/Interface/Pages.lua#L1107`))
  - `CreateThemeDropdown` ([`../Src/Interface/Pages.lua#L1293`](`../Src/Interface/Pages.lua#L1293`))
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
  - `Utils:SafeNumber(value, fallback) → number`: Return a sanitized number, or `fallback` when the value is nil/secret/non-numeric. Convenience wrapper around SanitizeNumber. ([`../Src/Utils.lua#L268`](../Src/Utils.lua#L268))
  - `Utils:SanitizeNumber(value) → number|nil`: Return a number only when it is usable from tainted code; secret numbers (which pass `or 0` then fail inside Blizzard arithmetic) return nil. ([`../Src/Utils.lua#L256`](../Src/Utils.lua#L256))
  - `Utils:SanitizeTarget(value) → string|number|nil`: Return a chat target only when it is usable from tainted code. Secret values (and non-string/number types) return nil so callers treat them as "no target" instead of erroring on comparisons. ([`../Src/Utils.lua#L240`](../Src/Utils.lua#L240))
  - `Utils:StripDisplayEscapes(text) → string`: Strip display-only WoW escape sequences from text while preserving complete hyperlinks. ([`../Src/Utils.lua#L396`](../Src/Utils.lua#L396))
  - `Utils:IsUnambiguousBnetTarget(target) → boolean`: Return true when target is an unambiguous Battle.net identifier, such as a numeric ID or BattleTag containing `#`. ([`../Src/Utils.lua#L551`](../Src/Utils.lua#L551))
  - `Utils:SetFontIfChanged(widget, face, size, flags) → boolean`: Set a widget's font only when the target differs from the current font; returns whether SetFont was called. ([`../Src/Utils.lua#L510`](../Src/Utils.lua#L510))
  - `Utils:IsForeverClient() → boolean`: True on the World of Warcraft: Forever client, detected via Forever-only API surfaces first, then flavour/product labels (camelot/forever/classicplus variants), then a 1.6x build-version heuristic. Cached after first call. ([`../Src/Utils.lua#L304`](../Src/Utils.lua#L304))
  - `Utils:HasRegionalUniqueNames() → boolean`: True when the current ruleset has surname-bearing regional-unique player names — Blizzard's own `RegionalUniqueNamesEnabled()` gate; intentionally independent of `IsForeverClient()`. ([`../Src/Utils.lua#L355`](../Src/Utils.lua#L355))
  - `Utils:NormaliseCharName(name) → string|nil`: Canonicalise a character name for comparison — strips the `-Realm` suffix on retail; on regional-unique-names clients (Forever) keeps the surname and canonicalises "First Last"/"First-Last" to a single lowercase space-separated form. ([`../Src/Utils.lua#L374`](../Src/Utils.lua#L374))
  - `Utils:SafeToString(value) → string`: Convert diagnostic values without stringifying secret values; returns `<secret>` for secret values and `<unavailable>` when conversion fails. ([`../Src/Utils.lua#L36`](../Src/Utils.lua#L36))
  - `Utils:IsChatOrCombatLockdown() → boolean`: Return true when either chat-messaging or combat lockdown is active. ([`../Src/Utils.lua#L139`](../Src/Utils.lua#L139))
  - `Utils:IsAnyAddOnRestriction() → boolean`: Return true while any addon restriction type is enforced — secret values may exist in Blizzard code paths, so tainted forwarding can hit illegal secret comparisons. ([`../Src/Utils.lua#L129`](../Src/Utils.lua#L129))
  - `Utils:IsCombatLockdown() → boolean`: Return true when protected-frame combat restrictions are active. ([`../Src/Utils.lua#L111`](../Src/Utils.lua#L111))
  - `Utils:AssertType(value, expectedType, default) → any`: Assert type matches expected, returning the original value or default. ([`../Src/Utils.lua#L183`](../Src/Utils.lua#L183))
  - `Utils:EnsureTablePath(root, ...) → table`: Ensure a table path exists, creating intermediate tables as needed, and return the deepest table. ([`../Src/Utils.lua#L165`](../Src/Utils.lua#L165))
  - `Utils:EnsureTable(t) → table`: Ensure a value is a table, returning it or a new empty table. ([`../Src/Utils.lua#L157`](../Src/Utils.lua#L157))
  - `Utils:Deleet(word) → string`: Convert leetspeak characters back to their base alphabet equivalents. ([`../Src/Utils.lua#L566`](../Src/Utils.lua#L566))

## TotalRP3Bridge

- Methods:
  - `TotalRP3Bridge:GetPlayerDisplayName() → string`: Return the best available RP display name for the player when TRP3 is loaded, falling back to UnitName("player"). ([`../Src/Bridges/TotalRP3Bridge.lua#L91`](../Src/Bridges/TotalRP3Bridge.lua#L91))
  - `TotalRP3Bridge:GetUnitDisplayName(unit) → string`: Return the best available RP display name for a unit, falling back to the unit's Blizzard name or "You". ([`../Src/Bridges/TotalRP3Bridge.lua#L75`](../Src/Bridges/TotalRP3Bridge.lua#L75))

## Hooks.UnitPopup

- Methods:
  - `EditBox:InstallUnitPopupWhisperOverride() → boolean`: Install the Menu.ModifyMenu registrations for character and Battle.net unit-popup Whisper actions. Idempotent; returns false when the Menu API is unavailable. ([`../Src/Hooks/UnitPopup.lua#L255`](../Src/Hooks/UnitPopup.lua#L255))

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
  - `Migrations:MigrateMisspellingColour(configTable, configType) → nil`: Migrate removed underline-style spellcheck rendering settings to the single MisspellingColour key used by the recolour engine. ([`../Src/Migrations.lua#L162`](../Src/Migrations.lua#L162))



## Interface.HelpContent

- Methods:
  - `HelpContent.ForEachItem(callback) → nil`: Iterate the read-only help items through a safe callback-based iterator because Lua 5.1's ipairs bypasses __index proxies. ([`../Src/Interface/HelpContent.lua#L158`](../Src/Interface/HelpContent.lua#L158))

## EditBoxCompat

- Methods:
  - `EditBox:SetChatCompatibilityEnabled(enabled) → nil`: Toggle Blizzard GetActiveWindow/FocusActiveWindow compatibility wrappers on or off during lockdown handoff and recovery. The wrappers route active-window queries to Yapper while safe and fall back to native behavior during lockdown/bypass. ([`../Src/EditBoxCompat.lua#L204`](../Src/EditBoxCompat.lua#L204))

## WhisperMessengerBridge

- Methods:
  - `WhisperMessengerBridge:HookSecureButtonCreation() → nil`: Hook Keybinds.CreateSecureButtons so the bridge re-wraps whenever the secure buttons are recreated. ([`../Src/Bridges/WhisperMessengerBridge.lua#L141`](../Src/Bridges/WhisperMessengerBridge.lua#L141))
  - `WhisperMessengerBridge:WrapReplyKeybind() → nil`: Wrap the REPLYTELL2 secure button's PostClick so the reply/re-whisper keybind is delegated when WhisperMessenger owns its window. ([`../Src/Bridges/WhisperMessengerBridge.lua#L88`](../Src/Bridges/WhisperMessengerBridge.lua#L88))
  - `WhisperMessengerBridge:IsWindowVisible() → boolean`: Check whether the WhisperMessenger window is currently visible. ([`../Src/Bridges/WhisperMessengerBridge.lua#L50`](../Src/Bridges/WhisperMessengerBridge.lua#L50))

## EditBox.Keybinds

- Methods:
  - `Keybinds:SyncContextYields() → nil`: Re-apply override bindings so keys claimed by an active binding context (e.g. housing editor modes) stay yielded; unlike `RefreshOverrides` it intentionally runs during combat/chat lockdown since override set/clear is not a protected operation. Called by binding-context and housing-selection change triggers. ([`../Src/EditBox/Keybinds.lua#L533`](../Src/EditBox/Keybinds.lua#L533))
