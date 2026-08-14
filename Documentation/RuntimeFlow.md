# Runtime relationship guide

This guide explains how Yapper's moving parts cooperate at runtime. It is
intentionally about ownership, lifecycle, and boundaries rather than a complete
API listing.

For the static load map and subsystem inventory, start with
[`Architecture.md`](Architecture.md). For the actual load order, always treat
[`Yapper.toc`](../Yapper.toc) as authoritative.

## The central problem

Yapper replaces Blizzard's chat editbox while preserving the behavior expected
by Blizzard's UI and by other addons. The native editbox is therefore not just
a widget that can be hidden; it is also a source of channel attributes, a focus
destination, a fallback sender, and an integration surface.

At runtime there are three possible editor owners:

| Editor | Normal role | When it owns input |
|---|---|---|
| Blizzard native editbox | Behavioral and secure fallback | Chat messaging lockdown, explicit bypass, or a Yapper path that delegates to Blizzard |
| Yapper single-line overlay | Normal short-form chat editor | Yapper is active and multiline is closed |
| Yapper multiline editor | Expanded composition editor | The user enters multiline/storyteller mode |

Only one editor should be the active focus destination at a time. The selection
is exposed through `EditBox:GetActiveEditor()` and reflected into Blizzard's
`CHAT_FOCUS_OVERRIDE` when Yapper owns the open path.

## Ownership model

```text
                         normal editing
     Blizzard Show() ───────────────────────────────┐
          │                                           │
          v                                           v
  native editbox attributes                    Yapper overlay
  and chat-frame context                    (single-line editor)
          │                                           │
          │ Shift-Enter / multiline                   │
          └──────────────────────┐                    │
                                 v                    │
                         Yapper multiline             │
                         editor owns focus            │
                                 │                    │
                                 └────────────────────┘
                                      submit/cancel

     chat messaging lockdown or explicit bypass
                         │
                         v
             Blizzard native editbox owns flow
```

The overlay is a replacement for presentation and input handling, not a
replacement for every Blizzard data source. It mirrors or reads Blizzard's
attributes where needed, while keeping its own channel and draft state in
`YapperTable.EditBox`.

### Active-editor rules

1. Multiline wins while `Multiline.Frame` is shown.
2. Otherwise the visible single-line overlay wins.
3. If neither Yapper editor is visible, focus override must be cleared so
   `OpenChat()` and `ChatEdit_GetActiveWindow()` can reach Blizzard normally.
4. If Yapper has handed off, the hidden overlay must not remain the focus
   override target.
5. During lockdown, Blizzard is the behavioral authority even if Yapper still
   has draft data to recover.

The core selection and focus rules are in
[`EditBox:GetActiveEditor()` and `UpdateFocusOverride()`](../Src/EditBox.lua#L94-L130).

## Boot and wiring

The TOC is a dependency graph written as a list. Important phases are:

```text
Core and policies
  -> utility/error/frame/event foundations
  -> public API and State
  -> spellcheck and supporting editor services
  -> EditBox core and editor parts
  -> Blizzard hooks
  -> optional bridges
  -> Chat delivery pipeline
  -> multiline, autocomplete, UI, and final bootstrap
```

The practical implications are:

- Modules capture `YapperTable.*` references at load time.
- A module must not assume a later TOC entry already exists.
- Hook files depend on the shared hub and on the editor helpers loaded before
  them.
- New bridges should use the public API rather than reaching into private core
  tables.

When adding a module, first decide whether it is a load-order dependency, a
runtime owner, or an optional integration. That determines where it belongs in
`Yapper.toc` and whether it should be a core module or a bridge.

## Open and focus lifecycle

The open path begins with Blizzard or a keybind, not necessarily with a direct
call to `EditBox:Show()`:

```text
user presses chat key / addon calls OpenChat
  -> Blizzard opens or activates a native editbox
  -> Blizzard hook observes the open/show path
  -> Yapper resolves channel, target, language, and active chat frame
  -> Yapper creates or reuses the overlay
  -> native editbox is hidden or kept as a proxy surface
  -> Yapper editor receives focus
  -> CHAT_FOCUS_OVERRIDE points at the active Yapper editor
```

The show hook has to handle more than a normal open:

- whisper and Battle.net target attributes may arrive at different times;
- external addons may have claimed the open through a filter;
- the active chat tab may change while the editbox is opening;
- multiline may already own focus;
- the queue may be waiting for a hardware event instead of a new message;
- the user may have explicitly bypassed Yapper.

`Hooks/ShowHide.lua` owns the overlay lifecycle and orchestrates open
selection; `Policies/ChannelPolicy.lua` owns the channel-selection rules.
`BlizzardHookCtl/20_EditBoxHooks.lua` observes native attribute and text changes.
`BlizzardHookCtl/30_ChatFrameHooks.lua` handles the broader chat-frame/open-chat
surface. The files cooperate; none of them is the complete open implementation.

### Focus override contract

`ChatFrameUtil.SetChatFocusOverride()` is a routing mechanism, not merely a
convenience for focusing a frame. If it points at a hidden overlay, Blizzard's
next `OpenChat()` may appear to succeed while focusing the wrong object.

Therefore:

```text
visible Yapper editor + Yapper owns input
  -> SetChatFocusOverride(active editor)

handoff, bypass, normal hide, or no active editor
  -> ClearChatFocusOverride()
```

The handoff path deliberately sets `handedOff = true` before updating focus so
the hidden overlay cannot survive as the override target. See
[`EditBox:HandoffToBlizzard()`](../Src/Hooks/ShowHide.lua#L731-L815).

## Send lifecycle

There is one delivery pipeline, even though there are multiple editor entry
points:

```text
single-line Enter ───────┐
                         v
multiline Submit ───> Chat:SendPosts
                         │
                         ├─ chat-lockdown guard
                         ├─ canonicalise display text
                         ├─ record history
                         ├─ PRE_SEND filters
                         ├─ split into posts and chunks
                         ├─ PRE_CHUNK filters
                         ├─ queue multi-chunk delivery
                         ├─ PRE_DELIVER filters
                         ├─ Router selects WoW API
                         └─ POST_SEND / acknowledgement handling
```

`Chat:SendPosts()` is the important convergence point. Single-line handling is
in `Chat:OnSend()`; multiline calls the same pipeline from `Multiline:Submit()`.
Callers remain responsible for editor cleanup and lockdown recovery, while
`Chat` owns delivery semantics.

The lower-level responsibilities are intentionally separate:

| Layer | Responsibility |
|---|---|
| `Chat` | Orchestrate filters, history, chunking, and delivery |
| `Chunking` | Split text without breaking links or byte limits |
| `Queue` | Preserve order, await acknowledgements, recover stalls |
| `Router` | Select `SendChatMessage`, whisper, club, or related API |
| Bridges | Rewrite or observe behavior through API filters/callbacks |

Do not add an alternate send path merely because one editor has a special UI.
That creates divergence in history, filters, chunking, lockdown checks, and
queue recovery.

The main pipeline is documented in
[`Chat:SendPosts()`](../Src/Chat.lua#L88-L215).

## Lockdown is a family of concepts

Yapper uses several related but distinct meanings of “lockdown”:

| Concept | Meaning | Typical API/state |
|---|---|---|
| Protected-frame combat lockdown | Secure-frame operations are restricted | `InCombatLockdown()` |
| Chat messaging lockdown | Blizzard restricts addon chat messaging | `C_ChatInfo.InChatMessagingLockdown()` |
| Yapper lockdown state | Yapper has handed editing back to Blizzard | `State.LOCKDOWN` |
| Handoff state | The overlay has been closed for recovery | `EditBox._lockdown.handedOff` |

These must not be treated as synonyms. Ordinary combat can fire
`PLAYER_REGEN_DISABLED` without chat messaging being restricted. Conversely,
chat restrictions may have timing that does not line up exactly with the first
combat event.

The policy seam is in
[`Policies/LockdownPolicy.lua`](../Src/Policies/LockdownPolicy.lua#L9-L26).
Use the chat-lockdown predicate when deciding whether addon chat delivery or a
Yapper editor must yield. Use combat lockdown only when deciding whether a
protected-frame operation is legal.

### Lockdown start

The event is a signal to check the restriction, not proof that chat messaging
is locked:

```text
PLAYER_REGEN_DISABLED / CHALLENGE_MODE_START / encounter signal
  -> check C_ChatInfo.InChatMessagingLockdown()
  -> if not active, poll briefly for delayed activation
  -> if still not active, leave the Yapper editor alone
  -> if active, begin the handoff path
```

The single-line handler performs this check and polling in
[`EditBox:SetupOverlayScripts()`](../Src/EditBox/Handlers.lua#L760-L857).
Multiline has its own visible editor and therefore has a matching check in
[`Multiline:OnLockdownStart()`](../Src/Multiline.lua#L1029-L1069).

This distinction is important for environmental damage, training dummies, and
other situations that enter combat without entering a restricted encounter.

### Handoff sequence

A valid handoff follows this order:

```text
1. Read canonical draft text
2. Set _lockdown.handedOff = true
3. Enter Yapper LOCKDOWN state
4. Clear CHAT_FOCUS_OVERRIDE
5. Cancel start timers/tickers
6. Save a recoverable draft if needed
7. Hide the Yapper editor
8. Let Blizzard own subsequent chat input
```

The ordering is deliberate. Clearing the focus override before marking the
handoff can leave the hidden overlay installed as Blizzard's focus destination.
Saving after clearing the text can lose the user's draft. Reopening Blizzard's
editbox automatically during the handoff can reactivate protected UI at the
wrong time.

### Lockdown recovery

Combat ending is not necessarily identical to chat restriction ending. The
recovery path therefore:

```text
PLAYER_REGEN_ENABLED / challenge completion
  -> cancel transient start timers
  -> return the logical state to IDLE
  -> wait until chat messaging lockdown is actually false
  -> clear handedOff
  -> persist deferred channel changes
  -> allow the next Yapper open to recover the draft/channel
```

The native editbox remains authoritative during this interval. Yapper's job is
to preserve state and avoid reclaiming focus prematurely.

## Multiline relationship to the overlay

Multiline is not a second send system. It is a second editor frontend:

```text
single-line overlay
  -> capture channel/language/target
  -> create multiline frame
  -> hide or suppress single-line input
  -> multiline edits composition
  -> submit through Chat:SendPosts
  -> restore/close editor state
```

While the multiline frame is visible, any Blizzard open attempt must be
redirected back to the multiline editbox. On cancel, multiline returns the
composition to the single-line lifecycle. On lockdown, it first preserves the
full draft, then delegates the final Blizzard handoff to the shared editbox
owner.

The important invariant is that multiline owns **editing**, but `EditBox` owns
the overall editor/focus contract and `Chat` owns delivery.

## Hooks and bridges

Hooks and bridges are different kinds of extension:

### Blizzard hooks

Blizzard hook modules are part of Yapper's compatibility core. They observe or
redirect native lifecycle calls such as show, hide, text changes, attributes,
chat-frame activation, slash commands, and unit-popup whispers.

They may need to protect Blizzard's behavior from Yapper's overlay, but should
not invent independent delivery or channel semantics.

### Optional bridges

Bridges adapt another addon or optional subsystem to Yapper's public API. The
current bridge families include:

- Gopher detection and deprecation handling;
- typing-tracker lifecycle signals;
- RP Prefix pre-send rewriting;
- WIM and WhisperMessenger ownership/fallback behavior;
- TotalRP3 language integration;
- CEBE integration;
- Languages integration.

A bridge should be able to be absent without breaking the core editor. The
preferred boundary is the public API plus narrow callbacks and filters. Some
older compatibility bridges still read or wrap `YapperTable.EditBox` directly;
when changing those bridges, reduce that private coupling rather than adding
more of it.

## State and flag glossary

`State.lua` provides the coarse logical mode:

| State | Meaning |
|---|---|
| `INITIALISING` | Startup is incomplete |
| `IDLE` | No active editor or send |
| `EDITING` | Single-line editor is active |
| `MULTILINE` | Expanded editor is active |
| `SENDING` | Delivery is in progress |
| `STALLED` | Queue awaits hardware continuation |
| `LOCKDOWN` | Yapper handed editing to Blizzard |
| `CONFIG` | Configuration UI is active |

The editor's `_lockdown` table is a separate, short-lived handoff FSM:

| Field | Meaning |
|---|---|
| `ticker` | Poll for delayed chat-lockdown activation |
| `handedOff` | Overlay has yielded to Blizzard |
| `idleTimer` | Grace period while the user finishes typing |
| `eventRunning` | Start event is currently being processed |
| `textHooked` | Idle timer reset hook has been installed |
| `savedDraft` | Handoff saved recoverable text |
| `savedDuring` | Native Blizzard changes need deferred persistence |
| `showHandled` | Reserved/reset-only flag; no active branch currently reads it |

Multiline has an analogous check ticker and idle timer because it owns a
separate visible editor. `OnLockdownEnd()` cancels both; a pending check ticker
also self-cancels when the multiline frame is no longer shown.

## Invariants to preserve

When changing this area, check these first:

1. **One active editor:** native, overlay, and multiline must not compete for
   focus.
2. **No hidden focus override:** clear `CHAT_FOCUS_OVERRIDE` whenever Yapper
   no longer owns a visible editor.
3. **Chat lockdown is not generic combat:** use the policy predicate, not the
   presence of `PLAYER_REGEN_DISABLED`, as the final decision.
4. **One send pipeline:** single-line and multiline must converge at
   `Chat:SendPosts()`.
5. **Handoff ordering matters:** mark `handedOff` before clearing focus and
   save the canonical draft before clearing the editor.
6. **Native Blizzard behavior remains available:** under lockdown and bypass,
   Blizzard is the authority rather than an implementation detail to imitate.
7. **Flags need both producers and consumers:** when moving code between hook
   files, verify every `_lockdown.*` flag is still written and cleared.
8. **TOC order is executable architecture:** a module cannot safely consume a
   table that has not been created yet.
9. **Optional bridges remain optional:** core behavior must not require a bridge
   to be installed or loaded.
10. **External OpenChat callers must work:** closing Yapper must restore a valid
    native active-window path.

## Debugging workflow

For a lifecycle bug, do not begin by reading every editor file. Trace one path:

1. Identify the user-visible symptom: focus, draft loss, wrong channel, failed
   send, or unexpected fallback.
2. Search for the event, state, flag, or user-facing message involved.
3. Draw the path from the Blizzard event/caller to the final side effect.
4. Compare single-line and multiline implementations.
5. Check both lockdown predicates separately.
6. Check who owns `CHAT_FOCUS_OVERRIDE` at each step.
7. Check whether a hook, bridge, or queue can short-circuit the path.
8. Add a regression test at the narrowest boundary that reproduces the issue.
9. Run the focused test, then `tools/run_tests.sh`.

Useful first searches:

```text
PLAYER_REGEN_DISABLED
InChatMessagingLockdown
CHAT_FOCUS_OVERRIDE
HandoffToBlizzard
_lockdown.
GetActiveEditor
Chat:SendPosts
```

## Source map

| Question | Start here |
|---|---|
| Who owns the active editor? | `Src/EditBox.lua`, `Src/Hooks/ShowHide.lua` |
| Why did an open get intercepted? | `Src/Hooks/BlizzardHookCtl/30_ChatFrameHooks.lua`, `Src/EditBox/Keybinds.lua` |
| Why did focus disappear? | `EditBox:UpdateFocusOverride()`, `HandoffToBlizzard()` |
| Why was a message not sent? | `Src/Chat.lua`, `Src/Queue.lua`, `Src/Router.lua` |
| Why was a draft saved or lost? | `Src/Hooks/ShowHide.lua`, `Src/History.lua`, `Src/Multiline.lua` |
| Why did combat trigger a handoff? | `Src/Policies/LockdownPolicy.lua`, `Src/EditBox/Handlers.lua`, `Src/Multiline.lua` |
| Why did a third-party addon change behavior? | `Src/Bridges/`, `Src/API.lua`, `Src/Hooks/` |
| Why did startup break? | `Yapper.toc`, `Yapper.lua`, `Src/Core.lua` |
