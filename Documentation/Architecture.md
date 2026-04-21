# Architecture map

This page is the runtime map for Yapper at this commit.

Primary load-order source: [`Yapper.toc`](../Yapper.toc).

## Module load map (TOC order)

```text
Src/Core.lua
Src/Utils.lua
Src/Error.lua
Src/Frames.lua
Src/Events.lua
Src/API.lua
Src/Spellcheck.lua
Src/Spellcheck/Dictionary.lua
Src/Spellcheck/YALLM.lua
Src/Spellcheck/UI.lua
Src/Spellcheck/Underline.lua
Src/Spellcheck/Engine.lua
Src/IconGallery.lua
Src/EditBox.lua
Src/EditBox/SkinProxy.lua
Src/EditBox/Overlay.lua
Src/EditBox/Handlers.lua
Src/EditBox/Hooks.lua
Src/EditBoxCompat.lua
Src/Bridges/GopherBridge.lua
Src/Bridges/TypingTrackerBridge.lua
Src/Bridges/RPPrefixBridge.lua
Src/Bridges/WIMBridge.lua
Src/Bridges/ElvUIBridge.lua
Src/Router.lua
Src/Chunking.lua
Src/Queue.lua
Src/Chat.lua
Src/Multiline.lua
Src/Autocomplete.lua
Src/History.lua
Src/Theme.lua
Src/Themes/Blizzard.lua
Src/Interface.lua
Src/Interface/Schema.lua
Src/Interface/Config.lua
Src/Interface/Window.lua
Src/Interface/Widgets.lua
Src/Interface/Pages.lua
Yapper.lua
```

## Boot sequence

```mermaid
flowchart TD
    A[Yapper.toc load order] --> B[Yapper.lua loaded last]
    B --> C[Yapper = YapperTable]
    C --> D[EventFrames:Init]
    D --> E[Register ADDON_LOADED handler]
    D --> F[Register PLAYER_ENTERING_WORLD handler]

    E --> G[ADDON_LOADED for Yapper]
    G --> G1[Core:InitSavedVars]
    G --> G2[Interface:InitPopups]
    G --> G3[Theme:SetTheme(saved)]
    G --> G4[Interface:CreateLauncher]
    G --> G5[Spellcheck:Init]
    G --> G6[History:InitDB]

    F --> H[PLAYER_ENTERING_WORLD]
    H --> H1[Interface:PurgeRenderCache]
    H --> H2[EditBox:HookAllChatFrames]
    H --> H3[Chat:Init]
    H --> H4[History:HookOverlayEditBox]
```

Code anchors:

- Boot registration and handlers: [`Yapper.lua#L63-L189`](../Yapper.lua#L63-L189)
- SavedVariables init: [`Src/Core.lua#L359`](../Src/Core.lua#L359)
- Spellcheck init call site: [`Yapper.lua#L135-L137`](../Yapper.lua#L135-L137)
- `PLAYER_ENTERING_WORLD` path: [`Yapper.lua#L149-L169`](../Yapper.lua#L149-L169)

## Runtime component graph

```text
User input / WoW chat events
  ├─ EditBox overlay stack
  │   ├─ EditBox.Overlay / Handlers / Hooks / SkinProxy
  │   ├─ Spellcheck (UI + Underline + Engine + Dictionary + YALLM)
  │   ├─ Autocomplete
  │   └─ Multiline editor
  │
  ├─ Chat pipeline
  │   EditBox -> Chat -> Chunking -> Queue -> Router -> WoW send API
  │
  ├─ Bridges (optional behaviour overlays)
  │   Gopher, TypingTracker, RPPrefix, WIM, ElvUI
  │
  └─ Settings/UI
      Interface + Theme + History + API callbacks/filters
```

## Hot path 1: Send path

```mermaid
flowchart LR
    U[User presses Enter] --> E[EditBox overlay handler]
    E --> C[Chat:OnSend]
    C --> F1[API PRE_SEND filter]
    C -->|long text| CH[Chunking:Split]
    CH --> F2[API PRE_CHUNK filter]
    CH --> Q[Queue:Enqueue/Flush]
    C -->|short text| D[Chat:DirectSend]
    Q --> D
    D --> F3[API PRE_DELIVER filter]
    D --> R[Router:Send]
    R --> W1[SendChatMessage]
    R --> W2[BNSendWhisper]
    R --> W3[C_Club.SendMessage]
    D --> CB[API POST_SEND callback]
```

Bridge integration points:

- **GopherBridge**: can become active sender path (`Router:Send` delegates to bridge send) ([`Src/Router.lua#L235-L240`](../Src/Router.lua#L235-L240), [`Src/Bridges/GopherBridge.lua#L103`](../Src/Bridges/GopherBridge.lua#L103)).
- **RPPrefixBridge**: pre-send text mutation via API filter ([`Src/Bridges/RPPrefixBridge.lua`](../Src/Bridges/RPPrefixBridge.lua)).
- **TypingTrackerBridge**: overlay focus/send signal callbacks from editbox lifecycle ([`Src/Bridges/TypingTrackerBridge.lua`](../Src/Bridges/TypingTrackerBridge.lua)).
- **WIMBridge**: can suppress editbox open via `PRE_EDITBOX_SHOW` ownership checks ([`Src/Bridges/WIMBridge.lua`](../Src/Bridges/WIMBridge.lua)).
- **ElvUIBridge**: theme sync/reactivity, not in send path payload but in runtime UI lifecycle ([`Src/Bridges/ElvUIBridge.lua`](../Src/Bridges/ElvUIBridge.lua)).

## Hot path 2: Open path

```mermaid
flowchart TD
    B1[Blizzard ChatFrameUtil.OpenChat/ActivateChat] --> B2[Blizzard EditBox:Show]
    B2 --> H[HookBlizzardEditBox Show hook]
    H -->|allowed| YS[EditBox:Show]
    YS --> O1[CreateOverlay]
    YS --> O2[SetupOverlayScripts]
    YS --> O3[Focus handoff to OverlayEdit]
    H --> B3[Hide Blizzard editbox on deferred timer]
```

Reentrancy note (issue #21 fix):

- Show hook uses `_inBlizzShowHook` guard and defers focus reclaim via `C_Timer.After(0, ...)` to avoid recursive focus ping-pong with Blizzard `ActivateChat` ([`Src/EditBox/Hooks.lua#L1119-L1283`](../Src/EditBox/Hooks.lua#L1119-L1283)).

## Hot path 3: Spellcheck path

```mermaid
flowchart LR
    T[OnTextChanged / OnCursorChanged] --> D[ScheduleRefresh debounce]
    D --> R[Rebuild]
    R --> C[CollectMisspellings]
    C --> DL[Dictionary set/phonetics lookups]
    C --> EN[Engine scoring + edit distance]
    EN --> S[Suggestions frame state]
    S --> U[Underline redraw + hint]
```

Code anchors:

- Debounce and rebuild: [`Src/Spellcheck/UI.lua#L333-L368`](../Src/Spellcheck/UI.lua#L333-L368)
- Misspelling collection: [`Src/Spellcheck/Engine.lua#L77-L121`](../Src/Spellcheck/Engine.lua#L77-L121)
- Suggestion generation: [`Src/Spellcheck/Engine.lua#L796`](../Src/Spellcheck/Engine.lua#L796)
- Suggestions UI open/refresh: [`Src/Spellcheck/UI.lua#L720-L909`](../Src/Spellcheck/UI.lua#L720-L909)

## SavedVariables layout

## `YapperDB` (account-wide)

- Defaults root and account profile values.
- Owns render cache container (`InterfaceUI`), version stamp, and global profile data.
- Initialised/normalised in [`Src/Core.lua#L382-L446`](../Src/Core.lua#L382-L446).

## `YapperLocalConf` (per-character)

- Character-level overrides.
- Receives defaults, then inherits from `YapperDB` via recursive metatable wiring.
- Becomes live config table (`YapperTable.Config = YapperLocalConf`) in [`Src/Core.lua#L430-L434`](../Src/Core.lua#L430-L434).

## `YapperLocalHistory` (per-character)

- Drafts, undo/redo snapshots, local chat history ring data.
- Initialised in [`Src/Core.lua#L447-L455`](../Src/Core.lua#L447-L455), then used by [`Src/History.lua`](../Src/History.lua).

## Merge/migration behaviour

- `ApplyDefaults` seeds missing keys.
- `SyncParity` removes unknown keys and repairs type mismatches on version bump.
- Version markers:
  - Config: `table.System.VERSION`
  - History: `table.VERSION`
- `LoadSavedVariablesFirst: 1` guarantees this runs before module runtime init hooks.

## LOD dictionary architecture

```mermaid
flowchart TD
    A[Spellcheck:EnsureLocale(locale)] --> B[LoadDictionary(locale) builder path]
    A --> C{Is locale already available?}
    C -- no --> D[Resolve locale addon name]
    D --> E[C_AddOns.LoadAddOn(addon)]
    E --> F[LOD addon loads Engine.lua/Dict_*.lua]
    F --> G[YapperAPI:RegisterLanguageEngine]
    F --> H[YapperAPI:RegisterDictionary]
    H --> I[Spellcheck:RegisterDictionary]
    I --> J[Spellcheck.Dictionaries[locale] populated]
    J --> K[ScheduleLocaleRefresh/Rebuild]
```

Key files:

- Loader and availability checks: [`Src/Spellcheck/Dictionary.lua`](../Src/Spellcheck/Dictionary.lua)
- Public registration bridge: [`Src/API.lua#L817-L875`](../Src/API.lua#L817-L875)
- Example LOD addon registration:
  - [`Dictionaries/Yapper_Dict_en/Engine.lua`](../Dictionaries/Yapper_Dict_en/Engine.lua)
  - [`Dictionaries/Yapper_Dict_en/Dict_enBase.lua`](../Dictionaries/Yapper_Dict_en/Dict_enBase.lua)

## Error handling

Errors are centralised in [`Src/Error.lua`](../Src/Error.lua). Runtime throw path is `YapperTable.Error:Throw(code, ...)` ([`Src/Error.lua#L92`](../Src/Error.lua#L92)).

| Code | Meaning |
|---|---|
| `BAD_STRING` | Malformed string cannot be posted |
| `BAD_ARG` | Function received wrong argument type |
| `EVENT_REGISTER_MISSING_FRAME` | Event registration attempted on missing frame |
| `EVENT_UNREGISTER_MISSING_FRAME` | Event unregistration attempted on missing frame |
| `EVENT_HANDLER_NOT_FUNCTION` | Event handler is not callable |
| `MISSING_UTILS` | `YapperTable.Utils` missing |
| `MISSING_CONFIG` | `YapperTable.Config` missing |
| `MISSING_EVENTS` | `YapperTable.Events` missing |
| `MISSING_FRAMES` | `YapperTable.Frames` missing |
| `MISSING_INTERFACE` | Interface critical function missing during boot |
| `HOOKS_NOT_TABLE` | Frame hooks container invalid |
| `HOOK_NOT_FUNCTION` | Specific hook is not callable |
| `BAD_PATCH` | Compat patch failed |
| `PATCH_MISSING_COMPATLIB` | CompatLib missing for patching |
| `YAPPER_MISSING_COMPATLIB` | CompatLib missing globally |
| `BAD_CHAT_TYPE` | Unsupported chat type in send path |
| `UNKNOWN` | Generic fallback error template |

## Practical mental model

- `Yapper.lua` handles lifecycle and wiring only.
- `EditBox` owns UX and input state.
- `Chat/Chunking/Queue/Router` own delivery mechanics.
- `Spellcheck` is its own subsystem with dictionary LOD + engine + UI layers.
- `Interface/Theme` own configuration surface and visual state.
- `API` is the extension boundary.
