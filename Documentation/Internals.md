# Internals reference (`_G.Yapper` / `YapperTable`)

> ⚠️ Everything documented here is **internal**. Use `YapperAPI` (see `API.md`) when possible. Internals are documented because third-party addons sometimes need them, but they may change without notice. If you find yourself relying on an internal, please open an issue proposing an addition to the public API.

All sections below follow TOC load order from [`Yapper.toc`](../Yapper.toc).

## YapperTable root (`_G.Yapper`)

Published in [`../Yapper.lua#L64`](../Yapper.lua#L64).

- Description: global namespace alias for the addon-private table.
- Fields:
  - `YapperTable.YAPPER_DISABLED: boolean` set by override toggle ([`../Yapper.lua#L217`](../Yapper.lua#L217)).
- Methods:
  - `YapperTable:OverrideYapper(disable: boolean) → nil` ([`../Yapper.lua#L212`](../Yapper.lua#L212)) — toggles runtime ownership between Yapper overlay and Blizzard chat; cancels queue and unregisters events when disabling.

## Core

Initialised on `ADDON_LOADED` by [`Yapper.lua#L105-L110`](../Yapper.lua#L105-L110).

- Description: SavedVariables schema/default/migration authority.
- Fields:
  - `Yapper.Config: table` live config root ([`../Src/Core.lua#L268`](../Src/Core.lua#L268)).
- Methods:
  - [TODO] `Core:DemoteGlobalToCharacter() → nil`: Unpack stashed local settings when switching away from Global Profile. ([`../Src/Core.lua#L721`](../Src/Core.lua#L721))
  - [TODO] `Core:RefreshInheritance() → nil`: Initialise inheritance chain (Global vs Local). ([`../Src/Core.lua#L518`](../Src/Core.lua#L518))
  - [TODO] `Core:GetCharacterLanguage(lang) → number langId`: Get the language or defaults if not present. ([`../Src/Core.lua#L290`](../Src/Core.lua#L290))
  - [TODO] `Core:BuildLanguageCache() → nil`: No description provided. ([`../Src/Core.lua#L273`](../Src/Core.lua#L273))
  - `Core:InitSavedVars() → nil` ([`../Src/Core.lua#L416`](../Src/Core.lua#L416)) — creates/migrates `YapperDB`, `YapperLocalConf`, `YapperLocalHistory`; mutates metatables for inheritance.
  - `Core:GetVersion() → string` ([`../Src/Core.lua#L541`](../Src/Core.lua#L541))
  - `Core:GetDefaults() → table` ([`../Src/Core.lua#L545`](../Src/Core.lua#L545))
  - `Core:SetVerbose(bool: boolean) → nil` ([`../Src/Core.lua#L549`](../Src/Core.lua#L549))
  - `Core:SaveSetting(category, key, value) → nil` ([`../Src/Core.lua#L562`](../Src/Core.lua#L562)) — delegates to `Interface:SetLocalPath` for profile-aware write routing.
  - `Core:PromoteCharacterToGlobal() → nil` ([`../Src/Core.lua#L628`](../Src/Core.lua#L628)) — wipes local overrides (excluding `MainWindowPosition`) and re-seeds metatable inheritance from `YapperDB`.
  - `Core:PushToGlobal() → nil` ([`../Src/Core.lua#L742`](../Src/Core.lua#L742)) — deep-copies character settings into `YapperDB`. Whitelists `System` keys; excludes `MainWindowPosition`; migrates `_themeOverrides` and `_appliedTheme` markers; no-op when already global.
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
  - `EventFrames:HideParent() → nil` ([`../Src/Frames.lua#L32`](../Src/Frames.lua#L32))

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
  - `_lastCancelOwner: string|nil` *private by convention; do not rely on* ([`../Src/API.lua#L1143`](../Src/API.lua#L1143)).
- Methods:
  - `API:_createClaim(text, chatType, language, target, owner) → number` ([`../Src/API.lua#L1062`](../Src/API.lua#L1062))
  - `API:RunFilter(hookPoint, payload) → table|false` ([`../Src/API.lua#L1129`](../Src/API.lua#L1129))
  - `API:Fire(event, ...) → nil` ([`../Src/API.lua#L1164`](../Src/API.lua#L1164))
- Side effects:
  - Catches external addon errors and emits/targets `API_ERROR`.

## State

Loaded early; central orchestrator for the addon's operational mode.

- Description: Finite state machine managing transitions between idle, editing, and sending states.
- Fields:
  - `STATES: table` enum of valid states (`IDLE`, `EDITING`, `MULTILINE`, `SENDING`, `STALLED`, `LOCKDOWN`).
  - `_current: string` current active state.
- Methods:
  - `State:ToLockdown() → nil`: Transition to LOCKDOWN state. ([`../Src/State.lua#L161`](../Src/State.lua#L161))
  - `State:ToStalled() → nil`: Transition to STALLED state. ([`../Src/State.lua#L156`](../Src/State.lua#L156))
  - `State:ToSending() → nil`: Transition to SENDING state. ([`../Src/State.lua#L151`](../Src/State.lua#L151))
  - `State:ToMultiline() → nil`: Transition to MULTILINE state. ([`../Src/State.lua#L146`](../Src/State.lua#L146))
  - `State:ToEditing() → nil`: Transition to EDITING state. ([`../Src/State.lua#L141`](../Src/State.lua#L141))
  - `State:ToIdle() → nil`: Transition to IDLE state. ([`../Src/State.lua#L136`](../Src/State.lua#L136))
  - `State:IsInputActive() → boolean`: Helper: is the user currently typing (either overlay or multiline)? ([`../Src/State.lua#L121`](../Src/State.lua#L121))
  - `State:IsLockdown() → boolean`: Is the addon suppressed by combat or manual lockdown? ([`../Src/State.lua#L115`](../Src/State.lua#L115))
  - `State:IsStalled() → boolean`: Is the queue stalled awaiting hardware input? ([`../Src/State.lua#L109`](../Src/State.lua#L109))
  - `State:IsSending() → boolean`: Is a message currently being delivered? ([`../Src/State.lua#L103`](../Src/State.lua#L103))
  - `State:IsMultiline() → boolean`: Is the user typing in the expanded multiline editor? ([`../Src/State.lua#L97`](../Src/State.lua#L97))
  - `State:IsEditing() → boolean`: Is the user typing in the single-line overlay? ([`../Src/State.lua#L91`](../Src/State.lua#L91))
  - `State:IsIdle() → boolean`: Is the machine in IDLE state? ([`../Src/State.lua#L85`](../Src/State.lua#L85))
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
  - Dictionary/user state: `UserDictCache` ([`../Src/Spellcheck.lua#L69`](`../Src/Spellcheck.lua#L69`))
  - Dictionary/user state: `_pendingLocaleLoads` ([`../Src/Spellcheck.lua#L70`](`../Src/Spellcheck.lua#L70`))
  - Dictionary/user state: `DictionaryBuilders` ([`../Src/Spellcheck.lua#L71`](`../Src/Spellcheck.lua#L71`))
  - Edit-distance buffers: `_ed_prev`, `_ed_cur`, `_ed_prev_prev` *private by convention; do not rely on* ([`../Src/Spellcheck.lua#L73-L75`](../Src/Spellcheck.lua#L73-L75)).
  - Tunable constants/helpers: `_SCORE_WEIGHTS`, `_MAX_SUGGESTION_ROWS`, `_RAID_ICONS`, `_KB_LAYOUTS`, `_DICT_CHUNK_SIZE` *private by convention; do not rely on* ([`../Src/Spellcheck.lua#L665-L675`](../Src/Spellcheck.lua#L665-L675)).
- Methods:
  - `Spellcheck:EvictRandomMeta() → nil`: No description provided. ([`../Src/Spellcheck.lua#L425`](../Src/Spellcheck.lua#L425))
  - `Spellcheck:Init(threads) → nil` ([`../Src/Spellcheck.lua#L187`](../Src/Spellcheck.lua#L187))
  - `Spellcheck:_RegisterLanguageEngine(familyId, engine) → boolean` ([`../Src/Spellcheck.lua#L212`](../Src/Spellcheck.lua#L212))
  - `Spellcheck:GetActiveEngine() → table|nil` ([`../Src/Spellcheck.lua#L228`](../Src/Spellcheck.lua#L228))
  - `Spellcheck:GetEngine(familyId) → table|nil` ([`../Src/Spellcheck.lua#L237`](../Src/Spellcheck.lua#L237))
  - `Spellcheck:GetConfig() → table` ([`../Src/Spellcheck.lua#L324`](../Src/Spellcheck.lua#L324))
  - `Spellcheck:IsEnabled() → boolean` ([`../Src/Spellcheck.lua#L328`](../Src/Spellcheck.lua#L328))
  - `Spellcheck:GetLocale() → string` ([`../Src/Spellcheck.lua#L333`](../Src/Spellcheck.lua#L333))
  - `Spellcheck:GetFallbackLocale() → string` ([`../Src/Spellcheck.lua#L363`](../Src/Spellcheck.lua#L363))
  - `Spellcheck:GetDictionary() → table|nil` ([`../Src/Spellcheck.lua#L371`](../Src/Spellcheck.lua#L371))
  - `Spellcheck:GetMeta(dict, word) → table|nil` ([`../Src/Spellcheck.lua#L381`](../Src/Spellcheck.lua#L381))
  [MISSING] - `Spellcheck:EvictOldestMeta(dict, count) → nil` ([`../Src/Spellcheck.lua#L2`](../Src/Spellcheck.lua#L2))
  - `Spellcheck:GetUserDictStore() → table` ([`../Src/Spellcheck.lua#L445`](../Src/Spellcheck.lua#L445))
  - `Spellcheck:GetUserDict(locale) → table` ([`../Src/Spellcheck.lua#L469`](../Src/Spellcheck.lua#L469))
  - `Spellcheck:TouchUserDict(dict) → nil` ([`../Src/Spellcheck.lua#L480`](../Src/Spellcheck.lua#L480))
  - `Spellcheck:BuildWordSet(list) → table` ([`../Src/Spellcheck.lua#L484`](../Src/Spellcheck.lua#L484))
  - `Spellcheck:GetUserSets(locale) → table, table` ([`../Src/Spellcheck.lua#L495`](../Src/Spellcheck.lua#L495))
  - `Spellcheck:AddUserWord(locale, word) → nil` ([`../Src/Spellcheck.lua#L510`](../Src/Spellcheck.lua#L510))
  - `Spellcheck:IgnoreWord(locale, word) → nil` ([`../Src/Spellcheck.lua#L533`](../Src/Spellcheck.lua#L533))
  - `Spellcheck:ClearSuggestionCache() → nil` ([`../Src/Spellcheck.lua#L557`](../Src/Spellcheck.lua#L557))
  - Accessors: `GetMaxSuggestions` ([`../Src/Spellcheck.lua#L562`](`../Src/Spellcheck.lua#L562`))
  - Accessors: `GetMaxCandidates` ([`../Src/Spellcheck.lua#L567`](`../Src/Spellcheck.lua#L567`))
  - Accessors: `GetSuggestionCacheSize` ([`../Src/Spellcheck.lua#L572`](`../Src/Spellcheck.lua#L572`))
  - Accessors: `GetReshuffleAttempts` ([`../Src/Spellcheck.lua#L577`](`../Src/Spellcheck.lua#L577`))
  - Accessors: `GetMaxWrongLetters` ([`../Src/Spellcheck.lua#L582`](`../Src/Spellcheck.lua#L582`))
  - Accessors: `GetMinWordLength` ([`../Src/Spellcheck.lua#L587`](`../Src/Spellcheck.lua#L587`))
  - Accessors: `GetUnderlineStyle` ([`../Src/Spellcheck.lua#L592`](`../Src/Spellcheck.lua#L592`))
  - Accessors: `GetKeyboardLayout` ([`../Src/Spellcheck.lua#L600`](`../Src/Spellcheck.lua#L600`))
  - Accessors: `GetKBDistTable` ([`../Src/Spellcheck.lua#L610`](`../Src/Spellcheck.lua#L610`))
  - Accessors: `_GetKBDistFromLayouts` ([`../Src/Spellcheck.lua#L629`](`../Src/Spellcheck.lua#L629`))
- Callbacks fired:
  - `SPELLCHECK_WORD_ADDED`, `SPELLCHECK_WORD_IGNORED`.

## Spellcheck.Dictionary

Used lazily by `GetDictionary`, locale switches, and LOD registration.

- Description: Dictionary registration/loading, locale availability, async indexing.
- Methods:
  - `Spellcheck:LoadDictionary(locale) → nil` ([`../Src/Spellcheck/Dictionary.lua#L34`](../Src/Spellcheck/Dictionary.lua#L34))
  - `Spellcheck:RegisterDictionary(locale, data) → nil` ([`../Src/Spellcheck/Dictionary.lua#L61`](../Src/Spellcheck/Dictionary.lua#L61))
  - `Spellcheck:_OnDictRegistrationComplete(locale) → nil` ([`../Src/Spellcheck/Dictionary.lua#L308`](../Src/Spellcheck/Dictionary.lua#L308))
  - `Spellcheck:GetAvailableLocales() → string[]` ([`../Src/Spellcheck/Dictionary.lua#L353`](../Src/Spellcheck/Dictionary.lua#L353))
  - `Spellcheck:GetLocaleAddon(locale) → string|nil` ([`../Src/Spellcheck/Dictionary.lua#L362`](../Src/Spellcheck/Dictionary.lua#L362))
  - `Spellcheck:HasLocaleAddon(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L367`](../Src/Spellcheck/Dictionary.lua#L367))
  - `Spellcheck:HasAnyDictionary() → boolean` ([`../Src/Spellcheck/Dictionary.lua#L398`](../Src/Spellcheck/Dictionary.lua#L398))
  - `Spellcheck:IsLocaleAvailable(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L410`](../Src/Spellcheck/Dictionary.lua#L410))
  - `Spellcheck:CanLoadLocale(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L424`](../Src/Spellcheck/Dictionary.lua#L424))
  - `Spellcheck:Notify(msg) → nil` ([`../Src/Spellcheck/Dictionary.lua#L439`](../Src/Spellcheck/Dictionary.lua#L439))
  - `Spellcheck:EnsureLocale(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L445`](../Src/Spellcheck/Dictionary.lua#L445))
  - `Spellcheck:ScheduleLocaleRefresh(locale) → nil` ([`../Src/Spellcheck/Dictionary.lua#L488`](../Src/Spellcheck/Dictionary.lua#L488))
- Side effects:
  - Schedules `C_Timer.After(0, ...)` chunk processing and refresh tickers.

## Spellcheck.Engine

Runs during suggestion/underline rebuild.

- Description: Tokenisation, misspelling detection, candidate scoring.
- Methods:
  - `CollectMisspellings` ([`../Src/Spellcheck/Engine.lua#L77`](`../Src/Spellcheck/Engine.lua#L77`))
  - `ShouldCheckWord` ([`../Src/Spellcheck/Engine.lua#L123`](`../Src/Spellcheck/Engine.lua#L123`))
  - `GetIgnoredRanges` ([`../Src/Spellcheck/Engine.lua#L130`](`../Src/Spellcheck/Engine.lua#L130`))
  - `IsRangeIgnored` ([`../Src/Spellcheck/Engine.lua#L173`](`../Src/Spellcheck/Engine.lua#L173`))
  - `IsWordCorrect` ([`../Src/Spellcheck/Engine.lua#L182`](`../Src/Spellcheck/Engine.lua#L182`))
  - `ResolveImplicitTrace` ([`../Src/Spellcheck/Engine.lua#L202`](`../Src/Spellcheck/Engine.lua#L202`))
  - `UpdateActiveWord` ([`../Src/Spellcheck/Engine.lua#L247`](`../Src/Spellcheck/Engine.lua#L247`))
  - `GetWordAtCursor` ([`../Src/Spellcheck/Engine.lua#L328`](`../Src/Spellcheck/Engine.lua#L328`))
  - `GetSuggestions` ([`../Src/Spellcheck/Engine.lua#L811`](`../Src/Spellcheck/Engine.lua#L811`))
  - `EditDistance` ([`../Src/Spellcheck/Engine.lua#L1087`](`../Src/Spellcheck/Engine.lua#L1087`))
  - `FormatSuggestionLabel` ([`../Src/Spellcheck/Engine.lua#L1157`](`../Src/Spellcheck/Engine.lua#L1157`))
- Filters run:
  - `PRE_SPELLCHECK` via `API:RunFilter`.

## Spellcheck.UI

Bound when overlay exists; reacts to text/cursor updates.

- Description: UI state machine for underlines, hint, and suggestions.
- Methods:
  - `Bind` ([`../Src/Spellcheck/UI.lua#L29`](`../Src/Spellcheck/UI.lua#L29`))
  - `BindMultiline` ([`../Src/Spellcheck/UI.lua#L64`](`../Src/Spellcheck/UI.lua#L64`))
  - `UnbindMultiline` ([`../Src/Spellcheck/UI.lua#L125`](`../Src/Spellcheck/UI.lua#L125`))
  - `PurgeOtherDictionaries` ([`../Src/Spellcheck/UI.lua#L163`](`../Src/Spellcheck/UI.lua#L163`))
  - `UnloadAllDictionaries` ([`../Src/Spellcheck/UI.lua#L217`](`../Src/Spellcheck/UI.lua#L217`))
  - `ApplyState` ([`../Src/Spellcheck/UI.lua#L259`](`../Src/Spellcheck/UI.lua#L259`))
  - `OnConfigChanged` ([`../Src/Spellcheck/UI.lua#L288`](`../Src/Spellcheck/UI.lua#L288`))
  - `OnTextChanged` ([`../Src/Spellcheck/UI.lua#L292`](`../Src/Spellcheck/UI.lua#L292`))
  - `OnCursorChanged` ([`../Src/Spellcheck/UI.lua#L312`](`../Src/Spellcheck/UI.lua#L312`))
  - `OnOverlayHide` ([`../Src/Spellcheck/UI.lua#L356`](`../Src/Spellcheck/UI.lua#L356`))
  - `ScheduleRefresh` ([`../Src/Spellcheck/UI.lua#L362`](`../Src/Spellcheck/UI.lua#L362`))
  - `Rebuild` ([`../Src/Spellcheck/UI.lua#L385`](`../Src/Spellcheck/UI.lua#L385`))
  - `EnsureMeasureFontString` ([`../Src/Spellcheck/UI.lua#L399`](`../Src/Spellcheck/UI.lua#L399`))
  - `EnsureSuggestionFrame` ([`../Src/Spellcheck/UI.lua#L414`](`../Src/Spellcheck/UI.lua#L414`))
  - `SuggestionsEqual` ([`../Src/Spellcheck/UI.lua#L502`](`../Src/Spellcheck/UI.lua#L502`))
  - `EnsureHintFrame` ([`../Src/Spellcheck/UI.lua#L512`](`../Src/Spellcheck/UI.lua#L512`))
  - `CancelHintTimer` ([`../Src/Spellcheck/UI.lua#L534`](`../Src/Spellcheck/UI.lua#L534`))
  - `ScheduleHintShow` ([`../Src/Spellcheck/UI.lua#L546`](`../Src/Spellcheck/UI.lua#L546`))
  - `ShowHint` ([`../Src/Spellcheck/UI.lua#L604`](`../Src/Spellcheck/UI.lua#L604`))
  - `HideHint` ([`../Src/Spellcheck/UI.lua#L625`](`../Src/Spellcheck/UI.lua#L625`))
  - `UpdateHint` ([`../Src/Spellcheck/UI.lua#L630`](`../Src/Spellcheck/UI.lua#L630`))
  - `IsSuggestionOpen` ([`../Src/Spellcheck/UI.lua#L653`](`../Src/Spellcheck/UI.lua#L653`))
  - `IsSuggestionEligible` ([`../Src/Spellcheck/UI.lua#L657`](`../Src/Spellcheck/UI.lua#L657`))
  - `HandleKeyDown` ([`../Src/Spellcheck/UI.lua#L664`](`../Src/Spellcheck/UI.lua#L664`))
  - `MoveSelection` ([`../Src/Spellcheck/UI.lua#L721`](`../Src/Spellcheck/UI.lua#L721`))
  - `RefreshSuggestionSelection` ([`../Src/Spellcheck/UI.lua#L731`](`../Src/Spellcheck/UI.lua#L731`))
  - `OpenOrCycleSuggestions` ([`../Src/Spellcheck/UI.lua#L749`](`../Src/Spellcheck/UI.lua#L749`))
  - `ShowSuggestions` ([`../Src/Spellcheck/UI.lua#L778`](`../Src/Spellcheck/UI.lua#L778`))
  - `NextSuggestionsPage` ([`../Src/Spellcheck/UI.lua#L895`](`../Src/Spellcheck/UI.lua#L895`))
  - `HideSuggestions` ([`../Src/Spellcheck/UI.lua#L918`](`../Src/Spellcheck/UI.lua#L918`))
  - `ApplySuggestion` ([`../Src/Spellcheck/UI.lua#L939`](`../Src/Spellcheck/UI.lua#L939`))
- Fields:
  - `HintDelay: number` ([`../Src/Spellcheck/UI.lua#L544`](../Src/Spellcheck/UI.lua#L544)).
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
  - [TODO] `YALLM:Export() → nil`: Export current learned data for a locale as a text block. ([`../Src/Spellcheck/YALLM.lua#L724`](../Src/Spellcheck/YALLM.lua#L724))
  - [TODO] `YALLM:GetBiasTargets() → nil`: Returns a list of candidate words that have been learned as corrections for the given typo. ([`../Src/Spellcheck/YALLM.lua#L566`](../Src/Spellcheck/YALLM.lua#L566))
  - [TODO] `YALLM:EnsureFreqSorted() → nil`: No description provided. ([`../Src/Spellcheck/YALLM.lua#L192`](../Src/Spellcheck/YALLM.lua#L192))
  - `GetFreqCap` ([`../Src/Spellcheck/YALLM.lua#L112`](`../Src/Spellcheck/YALLM.lua#L112`))
  - `GetBiasCap` ([`../Src/Spellcheck/YALLM.lua#L118`](`../Src/Spellcheck/YALLM.lua#L118`))
  - `GetAutoThreshold` ([`../Src/Spellcheck/YALLM.lua#L124`](`../Src/Spellcheck/YALLM.lua#L124`))
  - `Init` ([`../Src/Spellcheck/YALLM.lua#L134`](`../Src/Spellcheck/YALLM.lua#L134`))
  - `GetLocaleDB` ([`../Src/Spellcheck/YALLM.lua#L160`](`../Src/Spellcheck/YALLM.lua#L160`))
  - `IsSaneWord` ([`../Src/Spellcheck/YALLM.lua#L212`](`../Src/Spellcheck/YALLM.lua#L212`))
  - `RecordUsage` ([`../Src/Spellcheck/YALLM.lua#L250`](`../Src/Spellcheck/YALLM.lua#L250`))
  - `RecordSelection` ([`../Src/Spellcheck/YALLM.lua#L283`](`../Src/Spellcheck/YALLM.lua#L283`))
  - `RecordImplicitCorrection` ([`../Src/Spellcheck/YALLM.lua#L360`](`../Src/Spellcheck/YALLM.lua#L360`))
  - `RecordRejection` ([`../Src/Spellcheck/YALLM.lua#L452`](`../Src/Spellcheck/YALLM.lua#L452`))
  - `RecordIgnored` ([`../Src/Spellcheck/YALLM.lua#L477`](`../Src/Spellcheck/YALLM.lua#L477`))
  - `GetBonus` ([`../Src/Spellcheck/YALLM.lua#L516`](`../Src/Spellcheck/YALLM.lua#L516`))
  - `Prune` ([`../Src/Spellcheck/YALLM.lua#L608`](`../Src/Spellcheck/YALLM.lua#L608`))
  - `Reset` ([`../Src/Spellcheck/YALLM.lua#L655`](`../Src/Spellcheck/YALLM.lua#L655`))
  - `GetDataSummary` ([`../Src/Spellcheck/YALLM.lua#L668`](`../Src/Spellcheck/YALLM.lua#L668`))
  - `ClearSpecificUsage` ([`../Src/Spellcheck/YALLM.lua#L755`](`../Src/Spellcheck/YALLM.lua#L755`))
- Score model:
  - `GetBonus` applies `freqBonus`, `biasBonus`, `phBonus`, and `negBias` penalty (weighted, capped by repeat count) and returns an additive score adjustment used in candidate ranking ([`../Src/Spellcheck/YALLM.lua#L381-L419`](../Src/Spellcheck/YALLM.lua#L381-L419), [`../Src/Spellcheck/Engine.lua#L695-L696`](../Src/Spellcheck/Engine.lua#L695-L696)).
- Learning entry points:
  - `Chat:DirectSend` records usage and ignored-word counts ([`../Src/Chat.lua#L199-L215`](../Src/Chat.lua#L199-L215)).
  - `Spellcheck.UI` records explicit suggestion picks/rejections ([`../Src/Spellcheck/UI.lua#L869-L962`](../Src/Spellcheck/UI.lua#L869-L962)).
  - `Spellcheck.Engine` records implicit corrections from retyped trace words ([`../Src/Spellcheck/Engine.lua#L236-L238`](../Src/Spellcheck/Engine.lua#L236-L238)).
- Invariants / safeguards:
  - `IsSaneWord` gates noisy tokens before learning; pruning preserves highest relevance entries by count/utility/recency score; caps/thresholds are clamped from config (`YALLMFreqCap`, `YALLMBiasCap`, `YALLMAutoThreshold`) ([`../Src/Spellcheck/YALLM.lua#L38-L54`](../Src/Spellcheck/YALLM.lua#L38-L54), [`../Src/Spellcheck/YALLM.lua#L113-L147`](../Src/Spellcheck/YALLM.lua#L113-L147), [`../Src/Spellcheck/YALLM.lua#L427-L468`](../Src/Spellcheck/YALLM.lua#L427-L468), [`../Src/Core.lua#L209-L212`](../Src/Core.lua#L209-L212)).
- Callbacks fired:
  - `YALLM_WORD_LEARNED`.

## IconGallery

Lazy-created; used by spellcheck/autocomplete edit flows and public API.

- Description: Raid icon picker popup and selection callbacks.
- Methods:
  - `Init` ([`../Src/IconGallery.lua#L19`](../Src/IconGallery.lua#L19))
  - `Show` ([`../Src/IconGallery.lua#L73`](../Src/IconGallery.lua#L73))
  - `Hide` ([`../Src/IconGallery.lua#L94`](../Src/IconGallery.lua#L94))
  - `Filter` ([`../Src/IconGallery.lua#L106`](../Src/IconGallery.lua#L106))
  - `Select` ([`../Src/IconGallery.lua#L132`](../Src/IconGallery.lua#L132))
  - `HandleKeyDown` ([`../Src/IconGallery.lua#L158`](../Src/IconGallery.lua#L158))
  - `_GetIconMeta` ([`../Src/IconGallery.lua#L201`](../Src/IconGallery.lua#L201))
  - `OnTextChanged` ([`../Src/IconGallery.lua#L212`](../Src/IconGallery.lua#L212))
- Callbacks fired:
  - `ICON_GALLERY_SHOW`, `ICON_GALLERY_HIDE`, `ICON_GALLERY_SELECT`.

## EditBox
- Methods:
  - [TODO] `box:GetAttribute() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L48`](../Src/EditBoxCompat.lua#L48))
  - [TODO] `box:GetLanguage() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L46`](../Src/EditBoxCompat.lua#L46))
  - [TODO] `box:GetTellTarget() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L44`](../Src/EditBoxCompat.lua#L44))
  - [TODO] `box:GetChannelTarget() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L42`](../Src/EditBoxCompat.lua#L42))
  - [TODO] `box:GetChatType() → nil`: No description provided. ([`../Src/EditBoxCompat.lua#L40`](../Src/EditBoxCompat.lua#L40))

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
  - Internal helper exports: `IsWhisperSlashPrefill` ([`../Src/EditBox.lua#L339`](`../Src/EditBox.lua#L339`))
  - Internal helper exports: `ParseWhisperSlash` ([`../Src/EditBox.lua#L340`](`../Src/EditBox.lua#L340`))
  - Internal helper exports: `GetLastTellTargetInfo` ([`../Src/EditBox.lua#L341`](`../Src/EditBox.lua#L341`))
  - Internal helper exports: `SetFrameFillColour` ([`../Src/EditBox.lua#L342`](`../Src/EditBox.lua#L342`))
- Methods:
  - `ClearLockdownState` ([`../Src/EditBox.lua#L65`](../Src/EditBox.lua#L65))
  - `AddReplyTarget` ([`../Src/EditBox.lua#L81`](../Src/EditBox.lua#L81))
  - `NextReplyTarget` ([`../Src/EditBox.lua#L112`](../Src/EditBox.lua#L112))
  - `OpenBlizzardChat` ([`../Src/EditBox.lua#L262`](../Src/EditBox.lua#L262))
  - `SetOnSend` ([`../Src/EditBox.lua#L344`](../Src/EditBox.lua#L344))
  - `SetPreShowCheck` ([`../Src/EditBox.lua#L350`](../Src/EditBox.lua#L350))
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
  - `Show` ([`../Src/EditBox/Hooks.lua#L60`](`../Src/EditBox/Hooks.lua#L60`))
  - `Hide` ([`../Src/EditBox/Hooks.lua#L373`](`../Src/EditBox/Hooks.lua#L373`))
  - `HandoffToBlizzard` ([`../Src/EditBox/Hooks.lua#L423`](`../Src/EditBox/Hooks.lua#L423`))
  - `ApplyConfigToLiveOverlay` ([`../Src/EditBox/Hooks.lua#L465`](`../Src/EditBox/Hooks.lua#L465`))
  - `RefreshLabel` ([`../Src/EditBox/Hooks.lua#L559`](`../Src/EditBox/Hooks.lua#L559`))
  - `PersistLastUsed` ([`../Src/EditBox/Hooks.lua#L728`](`../Src/EditBox/Hooks.lua#L728`))
  - `CycleChat` ([`../Src/EditBox/Hooks.lua#L766`](`../Src/EditBox/Hooks.lua#L766`))
  - `IsChatTypeAvailable` ([`../Src/EditBox/Hooks.lua#L814`](`../Src/EditBox/Hooks.lua#L814`))
  - `GetResolvedChatType` ([`../Src/EditBox/Hooks.lua#L836`](`../Src/EditBox/Hooks.lua#L836`))
  - `NavigateHistory` ([`../Src/EditBox/Hooks.lua#L861`](`../Src/EditBox/Hooks.lua#L861`))
  - `ForwardSlashCommand` ([`../Src/EditBox/Hooks.lua#L936`](`../Src/EditBox/Hooks.lua#L936`))
  - `HookBlizzardEditBox` ([`../Src/EditBox/Hooks.lua#L1003`](`../Src/EditBox/Hooks.lua#L1003`))
  - `HookAllChatFrames` ([`../Src/EditBox/Hooks.lua#L1356`](`../Src/EditBox/Hooks.lua#L1356`))
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
  - `UpdateState` ([`../Src/Bridges/TypingTrackerBridge.lua#L276`](`../Src/Bridges/TypingTrackerBridge.lua#L276`))
  - `OnOverlayFocusGained` ([`../Src/Bridges/TypingTrackerBridge.lua#L314`](`../Src/Bridges/TypingTrackerBridge.lua#L314`))
  - `OnOverlayFocusLost` ([`../Src/Bridges/TypingTrackerBridge.lua#L318`](`../Src/Bridges/TypingTrackerBridge.lua#L318`))
  - `OnOverlaySent` ([`../Src/Bridges/TypingTrackerBridge.lua#L322`](`../Src/Bridges/TypingTrackerBridge.lua#L322`))
  - `OnChannelChanged` ([`../Src/Bridges/TypingTrackerBridge.lua#L327`](`../Src/Bridges/TypingTrackerBridge.lua#L327`))

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
  - `active: boolean` ([`../Src/Bridges/ElvUIBridge.lua#L107`](../Src/Bridges/ElvUIBridge.lua#L107)).
- Methods:
  - `Activate` ([`../Src/Bridges/ElvUIBridge.lua#L112`](`../Src/Bridges/ElvUIBridge.lua#L112`))
  - `Deactivate` ([`../Src/Bridges/ElvUIBridge.lua#L156`](`../Src/Bridges/ElvUIBridge.lua#L156`))
  - `RefreshColors` ([`../Src/Bridges/ElvUIBridge.lua#L215`](`../Src/Bridges/ElvUIBridge.lua#L215`))
  - `Sync` ([`../Src/Bridges/ElvUIBridge.lua#L235`](`../Src/Bridges/ElvUIBridge.lua#L235`))

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
  - `Chunking:Split(text, limit, ignoreParagraphMerging?, useDelineators?, delineator?, prefix?) → string[]` ([`../Src/Chunking.lua#L315`](../Src/Chunking.lua#L315))
  - `Chunking:GetDelineators() → table` ([`../Src/Chunking.lua#L533`](../Src/Chunking.lua#L533))

## Queue

Initialised by `Chat:Init`; registers many chat confirm events.

- Description: Ordered chunk delivery with ack/stall policy.
- Fields:
  - Queue state: `Entries` ([`../Src/Queue.lua#L160`](`../Src/Queue.lua#L160`))
  - Queue state: `Active` ([`../Src/Queue.lua#L161`](`../Src/Queue.lua#L161`))
  - Queue state: `PlayerGUID` ([`../Src/Queue.lua#L162`](`../Src/Queue.lua#L162`))
  - Queue state: `NeedsContinue` ([`../Src/Queue.lua#L166`](`../Src/Queue.lua#L166`))
  - Queue state: `StallTimer` ([`../Src/Queue.lua#L167`](`../Src/Queue.lua#L167`))
  - Queue state: `StallTimeout` ([`../Src/Queue.lua#L168`](`../Src/Queue.lua#L168`))
  - Queue state: `PendingEntry` ([`../Src/Queue.lua#L170`](`../Src/Queue.lua#L170`))
  - Queue state: `PendingAckEntry` ([`../Src/Queue.lua#L171`](`../Src/Queue.lua#L171`))
  - Queue state: `PendingAckText` ([`../Src/Queue.lua#L172`](`../Src/Queue.lua#L172`))
  - Queue state: `PendingAckEvent` ([`../Src/Queue.lua#L173`](`../Src/Queue.lua#L173`))
  - Queue state: `PendingAckPolicyClass` ([`../Src/Queue.lua#L174`](`../Src/Queue.lua#L174`))
  - Queue state: `StrictAckMatching` ([`../Src/Queue.lua#L175`](`../Src/Queue.lua#L175`))
  - Queue state: `_lastEscTime` ([`../Src/Queue.lua#L177`](`../Src/Queue.lua#L177`))
  - Queue state: `ContinueFrame` ([`../Src/Queue.lua#L180`](`../Src/Queue.lua#L180`))
- Methods:
  - `Init` ([`../Src/Queue.lua#L186`](../Src/Queue.lua#L186))
  - `Reset` ([`../Src/Queue.lua#L205`](../Src/Queue.lua#L205))
  - `IsOpenWorld` ([`../Src/Queue.lua#L221`](../Src/Queue.lua#L221))
  - `IsCommunityChannelEntry` ([`../Src/Queue.lua#L229`](../Src/Queue.lua#L229))
  - `ClassifyEntry` ([`../Src/Queue.lua#L243`](../Src/Queue.lua#L243))
  - `GetPolicy` ([`../Src/Queue.lua#L286`](../Src/Queue.lua#L286))
  - `GetConfirmEventForEntry` ([`../Src/Queue.lua#L301`](../Src/Queue.lua#L301))
  - `TrackPendingAck` ([`../Src/Queue.lua#L316`](../Src/Queue.lua#L316))
  - `GetActivePolicySnapshot` ([`../Src/Queue.lua#L324`](../Src/Queue.lua#L324))
  - `ClearPendingAck` ([`../Src/Queue.lua#L338`](../Src/Queue.lua#L338))
  - `Enqueue` ([`../Src/Queue.lua#L349`](../Src/Queue.lua#L349))
  - `Flush` ([`../Src/Queue.lua#L361`](../Src/Queue.lua#L361))
  - `RequiresHardwareEvent` ([`../Src/Queue.lua#L385`](../Src/Queue.lua#L385))
  - `SendNext` ([`../Src/Queue.lua#L390`](../Src/Queue.lua#L390))
  - `BeginEntry` ([`../Src/Queue.lua#L418`](../Src/Queue.lua#L418))
  - `HandleAck` ([`../Src/Queue.lua#L444`](../Src/Queue.lua#L444))
  - `AssumeAck` ([`../Src/Queue.lua#L452`](../Src/Queue.lua#L452))
  - `RawSend` ([`../Src/Queue.lua#L462`](../Src/Queue.lua#L462))
  - `Complete` ([`../Src/Queue.lua#L486`](../Src/Queue.lua#L486))
  - `OnChatEvent` ([`../Src/Queue.lua#L500`](../Src/Queue.lua#L500))
  - `OnOpenChat` ([`../Src/Queue.lua#L547`](../Src/Queue.lua#L547))
  - `TryContinue` ([`../Src/Queue.lua#L559`](../Src/Queue.lua#L559))
  - `ResetStallTimer` ([`../Src/Queue.lua#L577`](../Src/Queue.lua#L577))
  - `CancelStallTimer` ([`../Src/Queue.lua#L595`](../Src/Queue.lua#L595))
  - `OnStallTimeout` ([`../Src/Queue.lua#L602`](../Src/Queue.lua#L602))
  - `CreateContinueFrame` ([`../Src/Queue.lua#L626`](../Src/Queue.lua#L626))
  - `ShowContinuePrompt` ([`../Src/Queue.lua#L686`](../Src/Queue.lua#L686))
  - `HideContinuePrompt` ([`../Src/Queue.lua#L723`](../Src/Queue.lua#L723))
  - `EnableEscapeCancel` ([`../Src/Queue.lua#L734`](../Src/Queue.lua#L734))
  - `DisableEscapeCancel` ([`../Src/Queue.lua#L767`](../Src/Queue.lua#L767))
  - `Cancel` ([`../Src/Queue.lua#L774`](../Src/Queue.lua#L774))
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
  - `Chat:OnSend(text, chatType, language, target) → nil` ([`../Src/Chat.lua#L86`](../Src/Chat.lua#L86))
  - `Chat:DirectSend(msg, chatType, language, target) → nil` ([`../Src/Chat.lua#L204`](../Src/Chat.lua#L204))
- Filters run:
  - `PRE_SEND`, `PRE_CHUNK`, `PRE_DELIVER`.
- Callbacks fired:
  - `POST_SEND`, `POST_CLAIMED`.

## Multiline

Lazy frame creation; active only when user enters multiline mode.

- Description: Expanded multiline editor that bypasses single-line overlay.
- Fields:
  - `Frame` ([`../Src/Multiline.lua#L50`](`../Src/Multiline.lua#L50`))
  - `ScrollFrame` ([`../Src/Multiline.lua#L51`](`../Src/Multiline.lua#L51`))
  - `EditBox` ([`../Src/Multiline.lua#L52`](`../Src/Multiline.lua#L52`))
  - `LabelFS` ([`../Src/Multiline.lua#L53`](`../Src/Multiline.lua#L53`))
  - `Active` ([`../Src/Multiline.lua#L54`](`../Src/Multiline.lua#L54`))
  - `ChatType` ([`../Src/Multiline.lua#L55`](`../Src/Multiline.lua#L55`))
  - `Language` ([`../Src/Multiline.lua#L56`](`../Src/Multiline.lua#L56`))
  - `Target` ([`../Src/Multiline.lua#L57`](`../Src/Multiline.lua#L57`))
- Methods:
  - `UpdateLabelGap` ([`../Src/Multiline.lua#L107`](`../Src/Multiline.lua#L107`))
  - `CreateFrame` ([`../Src/Multiline.lua#L141`](`../Src/Multiline.lua#L141`))
  - `Enter` ([`../Src/Multiline.lua#L497`](`../Src/Multiline.lua#L497`))
  - `Exit` ([`../Src/Multiline.lua#L615`](`../Src/Multiline.lua#L615`))
  - `Submit` ([`../Src/Multiline.lua#L732`](`../Src/Multiline.lua#L732`))
  - `Cancel` ([`../Src/Multiline.lua#L866`](`../Src/Multiline.lua#L866`))
  - `ShouldAutoExpand` ([`../Src/Multiline.lua#L879`](`../Src/Multiline.lua#L879`))
  - `ApplyTheme` ([`../Src/Multiline.lua#L896`](`../Src/Multiline.lua#L896`))
- Invariants:
  - While `Active`, single-line overlay show path should early-return.

## Autocomplete

Binds to overlay (or multiline) editbox when available.

- Description: Ghost-text completion from dictionary + YALLM.
- Fields:
  - `GhostFS` ([`../Src/Autocomplete.lua#L57`](`../Src/Autocomplete.lua#L57`))
  - `CurrentSugg` ([`../Src/Autocomplete.lua#L58`](`../Src/Autocomplete.lua#L58`))
  - `CurrentPrefix` ([`../Src/Autocomplete.lua#L59`](`../Src/Autocomplete.lua#L59`))
  - `PrefixText` ([`../Src/Autocomplete.lua#L60`](`../Src/Autocomplete.lua#L60`))
  - `Active` ([`../Src/Autocomplete.lua#L61`](`../Src/Autocomplete.lua#L61`))
  - `Enabled` ([`../Src/Autocomplete.lua#L62`](`../Src/Autocomplete.lua#L62`))
  - `_activeEditBox` ([`../Src/Autocomplete.lua#L63`](`../Src/Autocomplete.lua#L63`))
  - `_isMultiline` ([`../Src/Autocomplete.lua#L64`](`../Src/Autocomplete.lua#L64`))
- Methods:
  - `IsEnabled`, `ExtractWordAtCursor`, `SearchDictionary`, `GetSuggestion`, `GetGhostFS`, `_InstallCursorHook`, `PositionGhost`, `ShowGhost`, `HideGhost`, `OnTextChanged`, `OnTabPressed`, `OnOverlayHide`, `SyncFont`, `SyncGhostFont`, `BindMultiline`, `UnbindMultiline` ([`../Src/Autocomplete.lua`](../Src/Autocomplete.lua)).

## History

Initialised on `ADDON_LOADED`; hooks overlay on `PLAYER_ENTERING_WORLD`.

- Description: Persistent chat history, draft store, undo/redo snapshots.
- Methods:
  - `History:SaveDraft(editBox, isMultiline) → nil`: Save a draft from any EditBox (overlay or multiline). ([`../Src/History.lua#L192`](../Src/History.lua#L192))
  - `History:GetDraft() → string? text, string? chatType, string? target, boolean? multiline`: Return the saved draft if dirty. ([`../Src/History.lua#L222`](../Src/History.lua#L222))
  - `InitDB` ([`../Src/History.lua#L69`](`../Src/History.lua#L69`))
  - `SaveDB` ([`../Src/History.lua#L110`](`../Src/History.lua#L110`))
  - `AddChatHistory` ([`../Src/History.lua#L131`](`../Src/History.lua#L131`))
  - `GetChatHistory` ([`../Src/History.lua#L168`](`../Src/History.lua#L168`))
  - `GetDraftStore` ([`../Src/History.lua#L179`](`../Src/History.lua#L179`))
  - `MarkDirty` ([`../Src/History.lua#L231`](`../Src/History.lua#L231`))
  - `ClearDraft` ([`../Src/History.lua#L236`](`../Src/History.lua#L236`))
  - `CancelPauseTimer` ([`../Src/History.lua#L256`](`../Src/History.lua#L256`))
  - `AddSnapshot` ([`../Src/History.lua#L286`](`../Src/History.lua#L286`))
  - `Undo` ([`../Src/History.lua#L330`](`../Src/History.lua#L330`))
  - `Redo` ([`../Src/History.lua#L346`](`../Src/History.lua#L346`))
  - `HookOverlayEditBox` ([`../Src/History.lua#L374`](`../Src/History.lua#L374`))
- Global state touched:
  - `_G.YapperLocalHistory`.

## Theme

Loaded with defaults; active theme restored on `ADDON_LOADED`.

- Description: Theme registry, application, persistence, live sync.
- Fields:
  - `_registry`, `_current` *private by convention; do not rely on* ([`../Src/Theme.lua#L16-L17`](../Src/Theme.lua#L16-L17)).
- Methods:
  - [TODO] `YapperTable:GetRegisteredThemes() → nil`: No description provided. ([`../Src/Theme.lua#L250`](../Src/Theme.lua#L250))
  - `RegisterTheme` ([`../Src/Theme.lua#L24`](`../Src/Theme.lua#L24`))
  - `GetTheme` ([`../Src/Theme.lua#L30`](`../Src/Theme.lua#L30`))
  - `GetRegisteredNames` ([`../Src/Theme.lua#L35`](`../Src/Theme.lua#L35`))
  - `SetTheme` ([`../Src/Theme.lua#L43`](`../Src/Theme.lua#L43`))
  - `ApplyToFrame` ([`../Src/Theme.lua#L107`](`../Src/Theme.lua#L107`))
  - `GetCurrentName` ([`../Src/Theme.lua#L183`](`../Src/Theme.lua#L183`))
  - `SetLiveTheme` ([`../Src/Theme.lua#L194`](`../Src/Theme.lua#L194`))
  - `SetTheme` logic switches between `_G.YapperDB` and `_G.YapperLocalConf` as the root for `_appliedTheme` based on `UseGlobalProfile`.
  - Global wrappers on root table: `Yapper:RegisterTheme` ([`../Src/Theme.lua#L24`](`../Src/Theme.lua#L24`))
  - Global wrappers on root table: `Yapper:SetTheme` ([`../Src/Theme.lua#L43`](`../Src/Theme.lua#L43`))
  - Global wrappers on root table: `Yapper:GetRegisteredThemes` ([`../Src/Theme.lua#L250`](`../Src/Theme.lua#L250`))
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
  - [TODO] `LayoutCursor:Pad() → nil`: No description provided. ([`../Src/Interface.lua#L115`](../Src/Interface.lua#L115))
  - [TODO] `LayoutCursor:Advance() → nil`: No description provided. ([`../Src/Interface.lua#L110`](../Src/Interface.lua#L110))
  - [TODO] `LayoutCursor:Y() → nil`: No description provided. ([`../Src/Interface.lua#L106`](../Src/Interface.lua#L106))
  - [TODO] `LayoutCursor:New(startY) → table`: No description provided. ([`../Src/Interface.lua#L102`](../Src/Interface.lua#L102))
  - `InitPopups` ([`../Src/Interface.lua#L308`](`../Src/Interface.lua#L308`))
  - `BuildConfigUI` ([`../Src/Interface.lua#L440`](`../Src/Interface.lua#L440`))
  - `ShowMainWindow` ([`../Src/Interface.lua#L720`](`../Src/Interface.lua#L720`))
  - `OpenToCategory` ([`../Src/Interface.lua#L730`](`../Src/Interface.lua#L730`))
  - `ToggleMainWindow` ([`../Src/Interface.lua#L741`](`../Src/Interface.lua#L741`))
  - `HandleLauncherClick` ([`../Src/Interface.lua#L771`](`../Src/Interface.lua#L771`))
  - `CloseFrame` ([`../Src/Interface.lua#L802`](`../Src/Interface.lua#L802`))
  - `Init` ([`../Src/Interface.lua#L813`](`../Src/Interface.lua#L813`))
  - `CreateLauncher` ([`../Src/Interface.lua#L837`](`../Src/Interface.lua#L837`))
- Global function:
  - `Yapper_FromCompartment(...)` ([`../Src/Interface.lua#L789`](../Src/Interface.lua#L789)).

## Interface.Schema

Build-time render schema module used by window/UI builders.

- Description: Settings schema composition and category metadata.
- Fields:
  - `_COLOUR_KEYS`, `_CHANNEL_OVERRIDE_OPTIONS`, `_CREDITS_BUNDLED`, `_CREDITS_OPTIONAL`, `_FONT_OUTLINE_OPTIONS`, `_SETTING_TOOLTIPS`, `_FRIENDLY_LABELS`, `_CATEGORIES`, `_PATH_TO_CATEGORY` *private by convention; do not rely on* ([`../Src/Interface/Schema.lua#L506-L514`](../Src/Interface/Schema.lua#L514)).
- Methods:
  - `BuildRenderSchema` ([`../Src/Interface/Schema.lua#L330`](`../Src/Interface/Schema.lua#L330`))
  - `GetRenderSchema` ([`../Src/Interface/Schema.lua#L477`](`../Src/Interface/Schema.lua#L477`))
  - `RefreshRenderSchema` ([`../Src/Interface/Schema.lua#L485`](`../Src/Interface/Schema.lua#L485`))
  - `OnWindowClosed` ([`../Src/Interface/Schema.lua#L491`](`../Src/Interface/Schema.lua#L491`))

## Interface.Config

Handles config reads/writes and side-effect fan-out.

- Description: Config root/path helpers, sanitisation, minimap controls.
- Methods:
  - [TODO] `Interface:ResetAllSettings() → nil`: Reset all configuration settings to their default values. ([`../Src/Interface/Config.lua#L50`](../Src/Interface/Config.lua#L50))
  - `GetLocalConfigRoot` ([`../Src/Interface/Config.lua#L34`](`../Src/Interface/Config.lua#L34`))
  - `GetDefaultsRoot` ([`../Src/Interface/Config.lua#L41`](`../Src/Interface/Config.lua#L41`))
  - `GetRenderCacheContainer` ([`../Src/Interface/Config.lua#L75`](`../Src/Interface/Config.lua#L75`))
  - `PurgeRenderCache` ([`../Src/Interface/Config.lua#L86`](`../Src/Interface/Config.lua#L86`))
  - `SetDirty` ([`../Src/Interface/Config.lua#L92`](`../Src/Interface/Config.lua#L92`))
  - `IsDirty` ([`../Src/Interface/Config.lua#L97`](`../Src/Interface/Config.lua#L97`))
  - `SetSettingsChanged` ([`../Src/Interface/Config.lua#L102`](`../Src/Interface/Config.lua#L102`))
  - `GetConfigPath` ([`../Src/Interface/Config.lua#L110`](`../Src/Interface/Config.lua#L110`))
  - `GetDefaultPath` ([`../Src/Interface/Config.lua#L118`](`../Src/Interface/Config.lua#L118`))
  - `UpdateOverrideTextColorCheckboxState` ([`../Src/Interface/Config.lua#L122`](`../Src/Interface/Config.lua#L122`))
  - `SetLocalPath` ([`../Src/Interface/Config.lua#L126`](`../Src/Interface/Config.lua#L126`))
  - `GetLauncherTooltipLines` ([`../Src/Interface/Config.lua#L308`](`../Src/Interface/Config.lua#L308`))
  - `GetMinimapButtonSettings` ([`../Src/Interface/Config.lua#L316`](`../Src/Interface/Config.lua#L316`))
  - `GetMinimapButtonOffset` ([`../Src/Interface/Config.lua#L329`](`../Src/Interface/Config.lua#L329`))
  - `PositionMinimapButton` ([`../Src/Interface/Config.lua#L333`](`../Src/Interface/Config.lua#L333`))
  - `UpdateMinimapButtonAngleFromCursor` ([`../Src/Interface/Config.lua#L349`](`../Src/Interface/Config.lua#L349`))
  - `ApplyMinimapButtonVisibility` ([`../Src/Interface/Config.lua#L366`](`../Src/Interface/Config.lua#L366`))
  - `IsPathDisabledByTheme` ([`../Src/Interface/Config.lua#L406`](`../Src/Interface/Config.lua#L406`))
  - `GetFriendlyLabel` ([`../Src/Interface/Config.lua#L431`](`../Src/Interface/Config.lua#L431`))
  - `SanitizeLocalConfig` ([`../Src/Interface/Config.lua#L460`](`../Src/Interface/Config.lua#L460`))
- Non-obvious rationale migrated from old docs:
  - `SetLocalPath` is the **single authoritative write source** for configuration; it handles profile-aware routing, theme-override marking, and automatic `PromoteCharacterToGlobal` triggers during profile toggles.
  - `SetLocalPath` enforces channel marker sync (`Chat.DELINEATOR` and `Chat.PREFIX`) as a single logical setting update.

## Interface.Window

Builds and controls top-level frames.

- Description: Main window, welcome/what's-new flows, UI font scaling.
- Fields:
  - `_activeCategory` *private by convention; do not rely on* ([`../Src/Interface/Window.lua#L175`](../Src/Interface/Window.lua#L175)).
- Methods:
  - `GetMainWindowPositionStore` ([`../Src/Interface/Window.lua#L31`](`../Src/Interface/Window.lua#L31`))
  - `SaveMainWindowPosition` ([`../Src/Interface/Window.lua#L48`](`../Src/Interface/Window.lua#L48`))
  - `ApplyMainWindowPosition` ([`../Src/Interface/Window.lua#L65`](`../Src/Interface/Window.lua#L65`))
  - `ShouldShowWelcomeChoice` ([`../Src/Interface/Window.lua#L280`](`../Src/Interface/Window.lua#L280`))
  - `ShouldShowWhatsNew` ([`../Src/Interface/Window.lua#L288`](`../Src/Interface/Window.lua#L288`))
  - `MarkWelcomeShown` ([`../Src/Interface/Window.lua#L297`](`../Src/Interface/Window.lua#L297`))
  - `MarkVersionSeen` ([`../Src/Interface/Window.lua#L302`](`../Src/Interface/Window.lua#L302`))
  - `CreateWelcomeChoiceFrame` ([`../Src/Interface/Window.lua#L356`](`../Src/Interface/Window.lua#L356`))
  - `CreateWhatsNewFrame` ([`../Src/Interface/Window.lua#L520`](`../Src/Interface/Window.lua#L520`))
  - `CreateMainWindow` ([`../Src/Interface/Window.lua#L647`](`../Src/Interface/Window.lua#L647`))
  - `UpdateSidebarSelection` ([`../Src/Interface/Window.lua#L832`](`../Src/Interface/Window.lua#L832`))
  - `GetUIFontOffset` ([`../Src/Interface/Window.lua#L851`](`../Src/Interface/Window.lua#L851`))
  - `SetUIFontOffset` ([`../Src/Interface/Window.lua#L857`](`../Src/Interface/Window.lua#L857`))
  - `ScaledRow` ([`../Src/Interface/Window.lua#L865`](`../Src/Interface/Window.lua#L865`))
  - `ApplyUIFontScale` ([`../Src/Interface/Window.lua#L871`](`../Src/Interface/Window.lua#L871`))
  - `RefreshFontScaleLabel` ([`../Src/Interface/Window.lua#L899`](`../Src/Interface/Window.lua#L899`))

## Interface.Widgets

Widget factory/pool and reusable setting controls.

- Description: UI control allocator with pooling, tooltip plumbing, common controls.
- Fields:
  - `WidgetPool: table` ([`../Src/Interface/Widgets.lua#L56`](../Src/Interface/Widgets.lua#L56)).
  - `_OpenColorPicker: function` *private by convention; do not rely on* ([`../Src/Interface/Widgets.lua#L860`](../Src/Interface/Widgets.lua#L860)).
- Methods:
  - `ClearConfigControls` ([`../Src/Interface/Widgets.lua#L34`](`../Src/Interface/Widgets.lua#L34`))
  - `AddControl` ([`../Src/Interface/Widgets.lua#L45`](`../Src/Interface/Widgets.lua#L45`))
  - `AcquireWidget` ([`../Src/Interface/Widgets.lua#L66`](`../Src/Interface/Widgets.lua#L66`))
  - `ReleaseWidget` ([`../Src/Interface/Widgets.lua#L100`](`../Src/Interface/Widgets.lua#L100`))
  - `GetTooltip` ([`../Src/Interface/Widgets.lua#L152`](`../Src/Interface/Widgets.lua#L152`))
  - `AttachTooltip` ([`../Src/Interface/Widgets.lua#L163`](`../Src/Interface/Widgets.lua#L163`))
  - `CreateResetButton` ([`../Src/Interface/Widgets.lua#L268`](`../Src/Interface/Widgets.lua#L268`))
  - `CreateLabel` ([`../Src/Interface/Widgets.lua#L281`](`../Src/Interface/Widgets.lua#L281`))
  - `CreateCheckBox` ([`../Src/Interface/Widgets.lua#L483`](`../Src/Interface/Widgets.lua#L483`))
  - `CreateTextInput` ([`../Src/Interface/Widgets.lua#L536`](`../Src/Interface/Widgets.lua#L536`))
  - `CreateColorPickerControl` ([`../Src/Interface/Widgets.lua#L627`](`../Src/Interface/Widgets.lua#L627`))
  - `CreateFontSizeDropdown` ([`../Src/Interface/Widgets.lua#L712`](`../Src/Interface/Widgets.lua#L712`))
  - `CreateFontOutlineDropdown` ([`../Src/Interface/Widgets.lua#L811`](`../Src/Interface/Widgets.lua#L811`))
- Non-obvious rationale migrated from old docs:
  - `CreateResetButton` self-registers with control tracking; do not double-register via `AddControl`.

## Interface.Pages

Per-category page builders called by `BuildConfigUI`.

- Description: Concrete settings page construction routines.
- Methods:
  - `CreateChannelOverrideControls` ([`../Src/Interface/Pages.lua#L41`](`../Src/Interface/Pages.lua#L41`))
  - `CreateGlobalSyncControls` ([`../Src/Interface/Pages.lua#L332`](`../Src/Interface/Pages.lua#L332`))
  - `CreateYALLMLearningPage` ([`../Src/Interface/Pages.lua#L389`](`../Src/Interface/Pages.lua#L389`))
  - `CreateQueueDiagnostics` ([`../Src/Interface/Pages.lua#L634`](`../Src/Interface/Pages.lua#L634`))
  - `CreateTutorialPage` ([`../Src/Interface/Pages.lua#L738`](`../Src/Interface/Pages.lua#L738`))
  - `CreateCreditsPage` ([`../Src/Interface/Pages.lua#L883`](`../Src/Interface/Pages.lua#L883`))
  - `CreateSpellcheckLocaleDropdown` ([`../Src/Interface/Pages.lua#L951`](`../Src/Interface/Pages.lua#L951`))
  - `CreateSpellcheckKeyboardLayoutDropdown` ([`../Src/Interface/Pages.lua#L1052`](`../Src/Interface/Pages.lua#L1052`))
  - `CreateSpellcheckUnderlineDropdown` ([`../Src/Interface/Pages.lua#L1101`](`../Src/Interface/Pages.lua#L1101`))
  - `CreateSpellcheckUserDictEditor` ([`../Src/Interface/Pages.lua#L1165`](`../Src/Interface/Pages.lua#L1165`))
  - `CreateThemeDropdown` ([`../Src/Interface/Pages.lua#L1319`](`../Src/Interface/Pages.lua#L1319`))
- Invariants:
  - Dropdown handlers assume config roots are initialised.
