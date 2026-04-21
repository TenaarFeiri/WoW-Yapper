# Internals reference (`_G.Yapper` / `YapperTable`)

> ⚠️ Everything documented here is **internal**. Use `YapperAPI` (see `API.md`) when possible. Internals are documented because third-party addons sometimes need them, but they may change without notice. If you find yourself relying on an internal, please open an issue proposing an addition to the public API.

All sections below follow TOC load order from [`Yapper.toc`](../Yapper.toc).

## Second-pass audit checklist

This pass re-checked `Src/**/*.lua` function definitions and table-field assignments against this document. Covered module set:

- `Core`, `Utils`, `Error`, `Frame`, `EventFrames`, `Events`, `API`
- `Spellcheck`, `Spellcheck.Dictionary`, `Spellcheck.Engine`, `Spellcheck.UI`, `Spellcheck.Underline`, `Spellcheck.YALLM`
- `IconGallery`, `EditBox`, `EditBox.SkinProxy`, `EditBox.Overlay`, `EditBox.Handlers`, `EditBox.Hooks`
- `GopherBridge`, `TypingTrackerBridge`, `RPPrefixBridge`, `WIMBridge`, `ElvUIBridge`
- `Router`, `Chunking`, `Queue`, `Chat`, `Multiline`, `Autocomplete`, `History`, `Theme`
- `Interface`, `Interface.Schema`, `Interface.Config`, `Interface.Window`, `Interface.Widgets`, `Interface.Pages`

## YapperTable root (`_G.Yapper`)

Published in [`../Yapper.lua#L64`](../Yapper.lua#L64).

- Description: global namespace alias for the addon-private table.
- Fields:
  - `YapperTable.YAPPER_DISABLED: boolean` set by override toggle ([`../Yapper.lua#L205`](../Yapper.lua#L205)).
- Methods:
  - `YapperTable:OverrideYapper(disable: boolean) → nil` ([`../Yapper.lua#L200`](../Yapper.lua#L200)) — toggles runtime ownership between Yapper overlay and Blizzard chat; cancels queue and unregisters events when disabling.

## Core

Initialised on `ADDON_LOADED` by [`Yapper.lua#L105-L110`](../Yapper.lua#L105-L110).

- Description: SavedVariables schema/default/migration authority.
- Fields:
  - `Yapper.Config: table` live config root ([`../Src/Core.lua#L268`](../Src/Core.lua#L268)).
- Methods:
  - `Core:InitSavedVars() → nil` ([`../Src/Core.lua#L359`](../Src/Core.lua#L359)) — creates/migrates `YapperDB`, `YapperLocalConf`, `YapperLocalHistory`; mutates metatables for inheritance.
  - `Core:GetVersion() → string` ([`../Src/Core.lua#L466`](../Src/Core.lua#L466))
  - `Core:GetDefaults() → table` ([`../Src/Core.lua#L470`](../Src/Core.lua#L470))
  - `Core:SetVerbose(bool: boolean) → nil` ([`../Src/Core.lua#L474`](../Src/Core.lua#L474))
  - `Core:SaveSetting(category, key, value) → nil` ([`../Src/Core.lua#L487`](../Src/Core.lua#L487)) — marks `SettingsHaveChanged`.
  - `Core:PushToGlobal() → nil` ([`../Src/Core.lua#L515`](../Src/Core.lua#L515)) — copies local overrides to account profile.
- Invariants:
  - Must run before feature init (`LoadSavedVariablesFirst: 1`).

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
  - `_lastCancelOwner: string|nil` *private by convention; do not rely on* ([`../Src/API.lua#L1132`](../Src/API.lua#L1132)).
- Methods:
  - `API:_createClaim(text, chatType, language, target, owner) → number` ([`../Src/API.lua#L1051`](../Src/API.lua#L1051))
  - `API:RunFilter(hookPoint, payload) → table|false` ([`../Src/API.lua#L1118`](../Src/API.lua#L1118))
  - `API:Fire(event, ...) → nil` ([`../Src/API.lua#L1153`](../Src/API.lua#L1153))
- Side effects:
  - Catches external addon errors and emits/targets `API_ERROR`.

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
  - Dictionary/user state: `UserDictCache`, `_pendingLocaleLoads`, `DictionaryBuilders` ([`../Src/Spellcheck.lua#L69-L71`](../Src/Spellcheck.lua#L69-L71)).
  - Edit-distance buffers: `_ed_prev`, `_ed_cur`, `_ed_prev_prev` *private by convention; do not rely on* ([`../Src/Spellcheck.lua#L73-L75`](../Src/Spellcheck.lua#L73-L75)).
  - Tunable constants/helpers: `_SCORE_WEIGHTS`, `_MAX_SUGGESTION_ROWS`, `_RAID_ICONS`, `_KB_LAYOUTS`, `_DICT_CHUNK_SIZE` *private by convention; do not rely on* ([`../Src/Spellcheck.lua#L665-L675`](../Src/Spellcheck.lua#L665-L675)).
- Methods:
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
  - `Spellcheck:EvictOldestMeta(dict, count) → nil` ([`../Src/Spellcheck.lua#L425`](../Src/Spellcheck.lua#L425))
  - `Spellcheck:GetUserDictStore() → table` ([`../Src/Spellcheck.lua#L445`](../Src/Spellcheck.lua#L445))
  - `Spellcheck:GetUserDict(locale) → table` ([`../Src/Spellcheck.lua#L469`](../Src/Spellcheck.lua#L469))
  - `Spellcheck:TouchUserDict(dict) → nil` ([`../Src/Spellcheck.lua#L480`](../Src/Spellcheck.lua#L480))
  - `Spellcheck:BuildWordSet(list) → table` ([`../Src/Spellcheck.lua#L484`](../Src/Spellcheck.lua#L484))
  - `Spellcheck:GetUserSets(locale) → table, table` ([`../Src/Spellcheck.lua#L495`](../Src/Spellcheck.lua#L495))
  - `Spellcheck:AddUserWord(locale, word) → nil` ([`../Src/Spellcheck.lua#L510`](../Src/Spellcheck.lua#L510))
  - `Spellcheck:IgnoreWord(locale, word) → nil` ([`../Src/Spellcheck.lua#L533`](../Src/Spellcheck.lua#L533))
  - `Spellcheck:ClearSuggestionCache() → nil` ([`../Src/Spellcheck.lua#L557`](../Src/Spellcheck.lua#L557))
  - Accessors: `GetMaxSuggestions`, `GetMaxCandidates`, `GetSuggestionCacheSize`, `GetReshuffleAttempts`, `GetMaxWrongLetters`, `GetMinWordLength`, `GetUnderlineStyle`, `GetKeyboardLayout`, `GetKBDistTable`, `_GetKBDistFromLayouts` ([`../Src/Spellcheck.lua#L562-L629`](../Src/Spellcheck.lua#L562-L629)).
- Callbacks fired:
  - `SPELLCHECK_WORD_ADDED`, `SPELLCHECK_WORD_IGNORED`.

## Spellcheck.Dictionary

Used lazily by `GetDictionary`, locale switches, and LOD registration.

- Description: Dictionary registration/loading, locale availability, async indexing.
- Methods:
  - `Spellcheck:LoadDictionary(locale) → nil` ([`../Src/Spellcheck/Dictionary.lua#L34`](../Src/Spellcheck/Dictionary.lua#L34))
  - `Spellcheck:RegisterDictionary(locale, data) → nil` ([`../Src/Spellcheck/Dictionary.lua#L61`](../Src/Spellcheck/Dictionary.lua#L61))
  - `Spellcheck:_OnDictRegistrationComplete(locale) → nil` ([`../Src/Spellcheck/Dictionary.lua#L305`](../Src/Spellcheck/Dictionary.lua#L305))
  - `Spellcheck:GetAvailableLocales() → string[]` ([`../Src/Spellcheck/Dictionary.lua#L350`](../Src/Spellcheck/Dictionary.lua#L350))
  - `Spellcheck:GetLocaleAddon(locale) → string|nil` ([`../Src/Spellcheck/Dictionary.lua#L359`](../Src/Spellcheck/Dictionary.lua#L359))
  - `Spellcheck:HasLocaleAddon(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L364`](../Src/Spellcheck/Dictionary.lua#L364))
  - `Spellcheck:HasAnyDictionary() → boolean` ([`../Src/Spellcheck/Dictionary.lua#L395`](../Src/Spellcheck/Dictionary.lua#L395))
  - `Spellcheck:IsLocaleAvailable(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L407`](../Src/Spellcheck/Dictionary.lua#L407))
  - `Spellcheck:CanLoadLocale(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L421`](../Src/Spellcheck/Dictionary.lua#L421))
  - `Spellcheck:Notify(msg) → nil` ([`../Src/Spellcheck/Dictionary.lua#L436`](../Src/Spellcheck/Dictionary.lua#L436))
  - `Spellcheck:EnsureLocale(locale) → boolean` ([`../Src/Spellcheck/Dictionary.lua#L442`](../Src/Spellcheck/Dictionary.lua#L442))
  - `Spellcheck:ScheduleLocaleRefresh(locale) → nil` ([`../Src/Spellcheck/Dictionary.lua#L485`](../Src/Spellcheck/Dictionary.lua#L485))
- Side effects:
  - Schedules `C_Timer.After(0, ...)` chunk processing and refresh tickers.

## Spellcheck.Engine

Runs during suggestion/underline rebuild.

- Description: Tokenisation, misspelling detection, candidate scoring.
- Methods:
  - `CollectMisspellings`, `ShouldCheckWord`, `GetIgnoredRanges`, `IsRangeIgnored`, `IsWordCorrect`, `ResolveImplicitTrace`, `UpdateActiveWord`, `GetWordAtCursor`, `GetSuggestions`, `EditDistance`, `FormatSuggestionLabel` ([`../Src/Spellcheck/Engine.lua#L77-L1118`](../Src/Spellcheck/Engine.lua#L77-L1118)).
- Filters run:
  - `PRE_SPELLCHECK` via `API:RunFilter`.

## Spellcheck.UI

Bound when overlay exists; reacts to text/cursor updates.

- Description: UI state machine for underlines, hint, and suggestions.
- Methods:
  - `Bind`, `BindMultiline`, `UnbindMultiline`, `PurgeOtherDictionaries`, `UnloadAllDictionaries`, `ApplyState`, `OnConfigChanged`, `OnTextChanged`, `OnCursorChanged`, `OnOverlayHide`, `ScheduleRefresh`, `Rebuild`, `EnsureMeasureFontString`, `EnsureSuggestionFrame`, `SuggestionsEqual`, `EnsureHintFrame`, `CancelHintTimer`, `ScheduleHintShow`, `ShowHint`, `HideHint`, `UpdateHint`, `IsSuggestionOpen`, `IsSuggestionEligible`, `HandleKeyDown`, `MoveSelection`, `RefreshSuggestionSelection`, `OpenOrCycleSuggestions`, `ShowSuggestions`, `NextSuggestionsPage`, `HideSuggestions`, `ApplySuggestion` ([`../Src/Spellcheck/UI.lua#L29-L909`](../Src/Spellcheck/UI.lua#L29-L909)).
- Fields:
  - `HintDelay: number` ([`../Src/Spellcheck/UI.lua#L515`](../Src/Spellcheck/UI.lua#L515)).
- Callbacks fired:
  - `SPELLCHECK_SUGGESTION`, `SPELLCHECK_APPLIED`.

## Spellcheck.Underline

Used by `Rebuild` and cursor movement.

- Description: Underline geometry and draw-pool management.
- Methods:
  - `GetCaretXOffset`, `ApplyOverlayFont`, `MeasureText`, `GetScrollOffset`, `UpdateUnderlines`, `RedrawUnderlines`, `DrawUnderline`, `EnsureUnderlineLayer`, `AcquireUnderline`, `ClearUnderlines`, `EnsureMLMeasureFS`, `SyncMLMeasureFont`, `MeasureMLWord`, `GetVerticalScroll`, `RedrawUnderlines_ML`, `DrawUnderline_ML` ([`../Src/Spellcheck/Underline.lua#L23-L509`](../Src/Spellcheck/Underline.lua#L23-L509)).
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
  - `GetFreqCap`, `GetBiasCap`, `GetAutoThreshold`, `Init`, `GetLocaleDB`, `IsSaneWord`, `RecordUsage`, `RecordSelection`, `RecordImplicitCorrection`, `RecordRejection`, `RecordIgnored`, `GetBonus`, `Prune`, `Reset`, `GetDataSummary`, `ClearSpecificUsage` ([`../Src/Spellcheck/YALLM.lua#L38-L540`](../Src/Spellcheck/YALLM.lua#L38-L540)).
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
  - `Init`, `Show`, `Hide`, `Filter`, `Select`, `HandleKeyDown`, `_GetIconMeta`, `OnTextChanged` ([`../Src/IconGallery.lua#L19-L212`](../Src/IconGallery.lua#L19-L212)).
- Callbacks fired:
  - `ICON_GALLERY_SHOW`, `ICON_GALLERY_HIDE`, `ICON_GALLERY_SELECT`.

## EditBox

Overlay root; hooked on `PLAYER_ENTERING_WORLD` via `HookAllChatFrames`.

- Description: Core overlay state and high-level editbox operations.
- Fields:
  - Runtime frames/state: `Overlay`, `OverlayEdit`, `ChannelLabel`, `LabelBg`, `OrigEditBox`, `ChatType`, `Language`, `Target`, `ChannelName` ([`../Src/EditBox.lua#L24-L36`](../Src/EditBox.lua#L24-L36)).
  - State tables: `HookedBoxes`, `LastUsed`, `ReplyQueue`, `_attrCache` ([`../Src/EditBox.lua#L30-L40`](../Src/EditBox.lua#L30-L40), [`../Src/EditBox.lua#L59`](../Src/EditBox.lua#L59)).
  - History pointers: `HistoryIndex`, `HistoryCache` ([`../Src/EditBox.lua#L37-L38`](../Src/EditBox.lua#L37-L38)).
  - `_lockdown`, `_overlayUnfocused` *private by convention; do not rely on* ([`../Src/EditBox.lua#L44-L56`](../Src/EditBox.lua#L44-L56)).
  - Internal constants/closures exported for submodules (`_UserBypassingYapper`, `_SetUserBypassingYapper`, `_BypassEditBox`, `_SetBypassEditBox`, `_SLASH_MAP`, `_TAB_CYCLE`, `_LABEL_PREFIXES`, `_GROUP_CHAT_TYPES`, `_CHATTYPE_TO_OVERRIDE_KEY`, `_REPLY_QUEUE_MAX`) *private by convention; do not rely on* ([`../Src/EditBox.lua#L329-L338`](../Src/EditBox.lua#L329-L338)).
  - Internal helper exports: `IsWhisperSlashPrefill`, `ParseWhisperSlash`, `GetLastTellTargetInfo`, `SetFrameFillColour` ([`../Src/EditBox.lua#L339-L342`](../Src/EditBox.lua#L339-L342)).
- Methods:
  - `ClearLockdownState`, `AddReplyTarget`, `NextReplyTarget`, `OpenBlizzardChat`, `SetOnSend`, `SetPreShowCheck` ([`../Src/EditBox.lua#L65-L350`](../Src/EditBox.lua#L65-L350)).
- Invariants:
  - Overlay behaviour valid only after `HookAllChatFrames()` has run.

## EditBox.SkinProxy

Attached during overlay show lifecycle.

- Description: Mirrors Blizzard editbox visual skin.
- Methods:
  - `AttachBlizzardSkinProxy`, `TintSkinProxyTextures`, `DetachBlizzardSkinProxy` ([`../Src/EditBox/SkinProxy.lua#L17-L210`](../Src/EditBox/SkinProxy.lua#L17-L210)).

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
  - `Show`, `Hide`, `HandoffToBlizzard`, `ApplyConfigToLiveOverlay`, `RefreshLabel`, `PersistLastUsed`, `CycleChat`, `IsChatTypeAvailable`, `GetResolvedChatType`, `NavigateHistory`, `ForwardSlashCommand`, `HookBlizzardEditBox`, `HookAllChatFrames` ([`../Src/EditBox/Hooks.lua#L52-L1318`](../Src/EditBox/Hooks.lua#L52-L1318)).
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
  - `active: boolean`, `_gopher: table|nil` ([`../Src/Bridges/GopherBridge.lua#L25-L26`](../Src/Bridges/GopherBridge.lua#L25-L26)).
- Methods:
  - `Init`, `UpdateState`, `Send`, `IsActive`, `IsBusy` ([`../Src/Bridges/GopherBridge.lua#L53-L152`](../Src/Bridges/GopherBridge.lua#L53-L152)).

## TypingTrackerBridge

Initialised by `Chat:Init` (state refresh), then driven by overlay callbacks.

- Description: Signals external typing tracker addon.
- Methods:
  - `UpdateState`, `OnOverlayFocusGained`, `OnOverlayFocusLost`, `OnOverlaySent`, `OnChannelChanged` ([`../Src/Bridges/TypingTrackerBridge.lua#L276-L327`](../Src/Bridges/TypingTrackerBridge.lua#L276-L327)).

## RPPrefixBridge

Initialised by `Chat:Init`.

- Description: Prefixes outgoing RP marker text.
- Methods:
  - `Init`, `IsActive`, `ApplyPrefix` ([`../Src/Bridges/RPPrefixBridge.lua#L62-L138`](../Src/Bridges/RPPrefixBridge.lua#L62-L138)).

## WIMBridge

Initialised by `Chat:Init`.

- Description: Cooperates with WIM focus ownership.
- Methods:
  - `IsFocusActive`, `IsLoaded`, `Init` ([`../Src/Bridges/WIMBridge.lua#L25-L50`](../Src/Bridges/WIMBridge.lua#L25-L50)).

## ElvUIBridge

Syncs theme colours based on ElvUI state when enabled.

- Description: Optional ElvUI theme adaptation bridge.
- Fields:
  - `active: boolean` ([`../Src/Bridges/ElvUIBridge.lua#L107`](../Src/Bridges/ElvUIBridge.lua#L107)).
- Methods:
  - `Activate`, `Deactivate`, `RefreshColors`, `Sync` ([`../Src/Bridges/ElvUIBridge.lua#L112-L225`](../Src/Bridges/ElvUIBridge.lua#L112-L225)).

## Router

Initialised by `Chat:Init`.

- Description: Resolves concrete WoW send API for chat target.
- Fields:
  - `SendChatMessage`, `BNSendWhisper`, `ClubSendMessage` cached function refs ([`../Src/Router.lua#L26-L28`](../Src/Router.lua#L26-L28)).
- Methods:
  - `ResolveBnetTarget`, `_ResolveBnetTargetUncached`, `ResolveBnetDisplay`, `FlushBnetCache`, `Init`, `DetectCommunityChannel`, `Send` ([`../Src/Router.lua#L63-L234`](../Src/Router.lua#L63-L234)).
- Side effects:
  - May delegate to `GopherBridge:Send`.

## Chunking

Called from `Chat:OnSend` for oversized messages.

- Description: UTF-8 aware message splitting.
- Methods:
  - `Chunking:Split(text, limit, ignoreParagraphMerging?, useDelineators?, delineator?, prefix?) → string[]` ([`../Src/Chunking.lua#L315`](../Src/Chunking.lua#L315))
  - `Chunking:GetDelineators() → table` ([`../Src/Chunking.lua#L532`](../Src/Chunking.lua#L532))

## Queue

Initialised by `Chat:Init`; registers many chat confirm events.

- Description: Ordered chunk delivery with ack/stall policy.
- Fields:
  - Queue state: `Entries`, `Active`, `PlayerGUID`, `NeedsContinue`, `StallTimer`, `StallTimeout`, `PendingEntry`, `PendingAckEntry`, `PendingAckText`, `PendingAckEvent`, `PendingAckPolicyClass`, `StrictAckMatching`, `_lastEscTime`, `ContinueFrame` ([`../Src/Queue.lua#L159-L179`](../Src/Queue.lua#L159-L179)).
- Methods:
  - `Init`, `Reset`, `IsOpenWorld`, `IsCommunityChannelEntry`, `ClassifyEntry`, `GetPolicy`, `GetConfirmEventForEntry`, `TrackPendingAck`, `GetActivePolicySnapshot`, `ClearPendingAck`, `Enqueue`, `Flush`, `RequiresHardwareEvent`, `SendNext`, `BeginEntry`, `HandleAck`, `AssumeAck`, `RawSend`, `Complete`, `OnChatEvent`, `OnOpenChat`, `TryContinue`, `ResetStallTimer`, `CancelStallTimer`, `OnStallTimeout`, `CreateContinueFrame`, `ShowContinuePrompt`, `HideContinuePrompt`, `EnableEscapeCancel`, `DisableEscapeCancel`, `Cancel` ([`../Src/Queue.lua#L185-L758`](../Src/Queue.lua#L185-L758)).
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
  - `Chat:Init() → nil` ([`../Src/Chat.lua#L40`](../Src/Chat.lua#L40))
  - `Chat:OnSend(text, chatType, language, target) → nil` ([`../Src/Chat.lua#L85`](../Src/Chat.lua#L85))
  - `Chat:DirectSend(msg, chatType, language, target) → nil` ([`../Src/Chat.lua#L199`](../Src/Chat.lua#L199))
- Filters run:
  - `PRE_SEND`, `PRE_CHUNK`, `PRE_DELIVER`.
- Callbacks fired:
  - `POST_SEND`, `POST_CLAIMED`.

## Multiline

Lazy frame creation; active only when user enters multiline mode.

- Description: Expanded multiline editor that bypasses single-line overlay.
- Fields:
  - `Frame`, `ScrollFrame`, `EditBox`, `LabelFS`, `Active`, `ChatType`, `Language`, `Target` ([`../Src/Multiline.lua#L46-L53`](../Src/Multiline.lua#L46-L53)).
- Methods:
  - `UpdateLabelGap`, `CreateFrame`, `Enter`, `Exit`, `Submit`, `Cancel`, `ShouldAutoExpand`, `ApplyTheme` ([`../Src/Multiline.lua#L102-L843`](../Src/Multiline.lua#L102-L843)).
- Invariants:
  - While `Active`, single-line overlay show path should early-return.

## Autocomplete

Binds to overlay (or multiline) editbox when available.

- Description: Ghost-text completion from dictionary + YALLM.
- Fields:
  - `GhostFS`, `CurrentSugg`, `CurrentPrefix`, `PrefixText`, `Active`, `Enabled`, `_activeEditBox`, `_isMultiline` ([`../Src/Autocomplete.lua#L57-L64`](../Src/Autocomplete.lua#L57-L64)).
- Methods:
  - `IsEnabled`, `ExtractWordAtCursor`, `SearchDictionary`, `GetSuggestion`, `GetGhostFS`, `_InstallCursorHook`, `PositionGhost`, `ShowGhost`, `HideGhost`, `OnTextChanged`, `OnTabPressed`, `OnOverlayHide`, `SyncFont`, `SyncGhostFont`, `BindMultiline`, `UnbindMultiline` ([`../Src/Autocomplete.lua#L89-L757`](../Src/Autocomplete.lua#L89-L757)).

## History

Initialised on `ADDON_LOADED`; hooks overlay on `PLAYER_ENTERING_WORLD`.

- Description: Persistent chat history, draft store, undo/redo snapshots.
- Methods:
  - `InitDB`, `SaveDB`, `AddChatHistory`, `GetChatHistory`, `GetDraftStore`, `SaveDraft`, `GetDraft`, `MarkDirty`, `ClearDraft`, `CancelPauseTimer`, `AddSnapshot`, `Undo`, `Redo`, `HookOverlayEditBox` ([`../Src/History.lua#L69-L367`](../Src/History.lua#L69-L367)).
- Global state touched:
  - `_G.YapperLocalHistory`.

## Theme

Loaded with defaults; active theme restored on `ADDON_LOADED`.

- Description: Theme registry, application, persistence, live sync.
- Fields:
  - `_registry`, `_current` *private by convention; do not rely on* ([`../Src/Theme.lua#L16-L17`](../Src/Theme.lua#L16-L17)).
- Methods:
  - `RegisterTheme`, `GetTheme`, `GetRegisteredNames`, `SetTheme`, `ApplyToFrame`, `GetCurrentName`, `SetLiveTheme` ([`../Src/Theme.lua#L24-L184`](../Src/Theme.lua#L24-L184)).
  - Global wrappers on root table: `Yapper:RegisterTheme`, `Yapper:SetTheme`, `Yapper:GetRegisteredThemes` ([`../Src/Theme.lua#L238-L240`](../Src/Theme.lua#L238-L240)).
- Callbacks fired:
  - `THEME_CHANGED`.

## Interface

Created during `ADDON_LOADED` startup path and owns settings UI lifecycle.

- Description: Main settings shell, launcher integration, category navigation.
- Fields:
  - `MouseWheelStepRate`, `IsVisible`, `DICTIONARY_DOWNLOAD_URL` ([`../Src/Interface.lua#L8-L12`](../Src/Interface.lua#L8-L12)).
  - Helpers/constants exported as underscored fields (`_LAYOUT`, `_LayoutCursor`, `_UI_FONT_*`) *private by convention; do not rely on* ([`../Src/Interface.lua#L120-L124`](../Src/Interface.lua#L120-L124)).
- Methods:
  - `InitPopups`, `BuildConfigUI`, `ShowMainWindow`, `OpenToCategory`, `ToggleMainWindow`, `HandleLauncherClick`, `CloseFrame`, `Init`, `CreateLauncher` ([`../Src/Interface.lua#L308-L839`](../Src/Interface.lua#L308-L839)).
- Global function:
  - `Yapper_FromCompartment(...)` ([`../Src/Interface.lua#L791`](../Src/Interface.lua#L791)).

## Interface.Schema

Build-time render schema module used by window/UI builders.

- Description: Settings schema composition and category metadata.
- Fields:
  - `_COLOUR_KEYS`, `_CHANNEL_OVERRIDE_OPTIONS`, `_CREDITS_BUNDLED`, `_CREDITS_OPTIONAL`, `_FONT_OUTLINE_OPTIONS`, `_SETTING_TOOLTIPS`, `_FRIENDLY_LABELS`, `_CATEGORIES`, `_PATH_TO_CATEGORY` *private by convention; do not rely on* ([`../Src/Interface/Schema.lua#L506-L514`](../Src/Interface/Schema.lua#L506-L514)).
- Methods:
  - `BuildRenderSchema`, `GetRenderSchema`, `RefreshRenderSchema`, `OnWindowClosed` ([`../Src/Interface/Schema.lua#L337-L499`](../Src/Interface/Schema.lua#L337-L499)).

## Interface.Config

Handles config reads/writes and side-effect fan-out.

- Description: Config root/path helpers, sanitisation, minimap controls.
- Methods:
  - `GetLocalConfigRoot`, `GetDefaultsRoot`, `GetRenderCacheContainer`, `PurgeRenderCache`, `SetDirty`, `IsDirty`, `SetSettingsChanged`, `GetConfigPath`, `GetDefaultPath`, `UpdateOverrideTextColorCheckboxState`, `SetLocalPath`, `GetLauncherTooltipLines`, `GetMinimapButtonSettings`, `GetMinimapButtonOffset`, `PositionMinimapButton`, `UpdateMinimapButtonAngleFromCursor`, `ApplyMinimapButtonVisibility`, `IsPathDisabledByTheme`, `GetFriendlyLabel`, `SanitizeLocalConfig` ([`../Src/Interface/Config.lua#L34-L396`](../Src/Interface/Config.lua#L34-L396)).
- Callbacks fired:
  - `CONFIG_CHANGED`.
- Non-obvious rationale migrated from old docs:
  - `SetLocalPath` enforces channel marker sync (`Chat.DELINEATOR` and `Chat.PREFIX`) as a single logical setting update.

## Interface.Window

Builds and controls top-level frames.

- Description: Main window, welcome/what's-new flows, UI font scaling.
- Fields:
  - `_activeCategory` *private by convention; do not rely on* ([`../Src/Interface/Window.lua#L175`](../Src/Interface/Window.lua#L175)).
- Methods:
  - `GetMainWindowPositionStore`, `SaveMainWindowPosition`, `ApplyMainWindowPosition`, `ShouldShowWelcomeChoice`, `ShouldShowWhatsNew`, `MarkWelcomeShown`, `MarkVersionSeen`, `CreateWelcomeChoiceFrame`, `CreateWhatsNewFrame`, `CreateMainWindow`, `UpdateSidebarSelection`, `GetUIFontOffset`, `SetUIFontOffset`, `ScaledRow`, `ApplyUIFontScale`, `RefreshFontScaleLabel` ([`../Src/Interface/Window.lua#L31-L899`](../Src/Interface/Window.lua#L31-L899)).

## Interface.Widgets

Widget factory/pool and reusable setting controls.

- Description: UI control allocator with pooling, tooltip plumbing, common controls.
- Fields:
  - `WidgetPool: table` ([`../Src/Interface/Widgets.lua#L56`](../Src/Interface/Widgets.lua#L56)).
  - `_OpenColorPicker: function` *private by convention; do not rely on* ([`../Src/Interface/Widgets.lua#L860`](../Src/Interface/Widgets.lua#L860)).
- Methods:
  - `ClearConfigControls`, `AddControl`, `AcquireWidget`, `ReleaseWidget`, `GetTooltip`, `AttachTooltip`, `CreateResetButton`, `CreateLabel`, `CreateCheckBox`, `CreateTextInput`, `CreateColorPickerControl`, `CreateFontSizeDropdown`, `CreateFontOutlineDropdown` ([`../Src/Interface/Widgets.lua#L34-L811`](../Src/Interface/Widgets.lua#L34-L811)).
- Non-obvious rationale migrated from old docs:
  - `CreateResetButton` self-registers with control tracking; do not double-register via `AddControl`.

## Interface.Pages

Per-category page builders called by `BuildConfigUI`.

- Description: Concrete settings page construction routines.
- Methods:
  - `CreateChannelOverrideControls`, `CreateGlobalSyncControls`, `CreateYALLMLearningPage`, `CreateQueueDiagnostics`, `CreateTutorialPage`, `CreateCreditsPage`, `CreateSpellcheckLocaleDropdown`, `CreateSpellcheckKeyboardLayoutDropdown`, `CreateSpellcheckUnderlineDropdown`, `CreateSpellcheckUserDictEditor`, `CreateThemeDropdown` ([`../Src/Interface/Pages.lua#L41-L1319`](../Src/Interface/Pages.lua#L41-L1319)).
- Invariants:
  - Dropdown handlers assume config roots are initialised.
