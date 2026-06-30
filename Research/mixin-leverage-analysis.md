# Yapper Mixin Leverage Analysis

**Date:** 2026-06-30  
**Scope:** Identify every place where a Blizzard mixin or official API surface can replace or
simplify a current hook, deferred callback, or manual state-flag in Yapper, without breaking
existing features.  This document covers _what we can_, _what we can't_, and importantly
_what we shouldn't_, even when it is technically possible.

---

## 1. Complete Hook Inventory

The table below catalogs every `hooksecurefunc`, `HookScript`, and `RegisterEvent` site that
drives Yapper's runtime behaviour.  Column **Complexity** ranks the *difficulty of the hook
body*; **Taint Risk** notes whether the hooked function/widget path is security-sensitive.

| # | Target | File | Line | Hook Kind | Complexity | Taint Risk | Can mixin help? |
|---|--------|------|------|-----------|-----------|------------|-----------------|
| 1 | `blizzEditBox.SetAttribute` | Blizzard.lua | 124 | hooksecurefunc (per-box) | Very High | Medium | Partial |
| 2 | `blizzEditBox.SetText` | Blizzard.lua | 416 | hooksecurefunc (per-box) | High | Medium | No |
| 3 | `blizzEditBox.Insert` | Blizzard.lua | 421 | hooksecurefunc (per-box) | Medium | Low | No |
| 4 | `blizzEditBox.SetGameLanguage` | Blizzard.lua | 430 | hooksecurefunc (per-box) | Low | Low | No |
| 5 | `blizzEditBox.Show` | Blizzard.lua | 446 | hooksecurefunc (per-box) | Very High | High | No |
| 6 | `blizzEditBox.OnEditFocusLost` | Blizzard.lua | 615 | HookScript (per-box) | Medium | Low | **Yes — EventRegistry** |
| 7 | `ChatFrameUtil.OpenChat` | Blizzard.lua | 668 | hooksecurefunc (global) | Very High | High | No |
| 8 | `ChatFrameUtil.DeactivateChat` | Blizzard.lua | 1002 | hooksecurefunc (global) | Low | Low | **Yes — EventRegistry** |
| 9 | `ChatFrameUtil.ActivateChat` | Blizzard.lua | 1014 | hooksecurefunc (global) | Medium | Low | **Yes — EventRegistry** |
| 10 | `ChatFrameUtil.SendTell` | Blizzard.lua | 1057 | hooksecurefunc (global) | High | Medium | **Yes — mixin override** |
| 11 | `ChatEdit_InsertLink` | Blizzard.lua | 1193 | hooksecurefunc (global) | Low | Low | **Yes — replace entirely** |
| 12 | `FCF_Tab_OnClick` | Blizzard.lua | 1244 | hooksecurefunc (global) | High | Low | No |
| 13 | `FCF_MaximizeFrame` | Blizzard.lua | 1317 | hooksecurefunc (global) | Low | Low | No |
| 14 | `FCF_MinimizeFrame` | Blizzard.lua | 1331 | hooksecurefunc (global) | Low | Low | No |
| 15 | `FCF_Close` | Blizzard.lua | 1358 | hooksecurefunc (global) | Medium | Low | No |
| 16 | Menu responder wrapping (MENU_CHAT_SHORTCUTS) | Blizzard.lua | 893+ | `Menu.ModifyMenu` (✓) | High | Low | **Already using — refine** |
| 17 | `FCF_SetFullScreenFrame` | Utils.lua | 78 | hooksecurefunc | Low | Low | No |
| 18 | `FCF_ClearFullScreenFrame` | Utils.lua | 81 | hooksecurefunc | Low | Low | No |
| 19 | `FCF_Tab_OnClick` (CEBE bridge) | CEBEBridge.lua | 197 | hooksecurefunc | Low | Low | No |
| 20 | `C_ChatInfo.SendChatMessage` | Overlay.lua | 507 | hooksecurefunc | Low | Low | No |
| 21 | `Interface.MainWindowFrame.Show/Hide` | Interface.lua | 887/890 | hooksecurefunc | Low | Low | No |
| 22 | `Queue.OpenChat` | Queue.lua | 206 | hooksecurefunc | Low | Low | No |
| 23 | OverlayEdit `OnCursorChanged` | Handlers.lua | 560 | HookScript | Low | None | No |
| 24 | OverlayEdit `OnChar` | Handlers.lua | 569 | HookScript | Low | None | No |
| 25 | OverlayEdit `OnKeyDown` | Handlers.lua | 601 | HookScript | Medium | None | No |
| 26 | OverlayEdit `OnEditFocusLost` | Handlers.lua | 708 | HookScript | Medium | None | No |
| 27 | OverlayEdit `OnEditFocusGained` | Handlers.lua | 732 | HookScript | Low | None | No |
| 28 | UIParent `OnHide` | Handlers.lua | 773 | HookScript | Low | Low | No |
| 29 | TRP3 language setter | TotalRP3Bridge.lua | 33 | hooksecurefunc | Low | Low | No |

**Total hooks: 29 active hook sites** (21 hooksecurefunc, 8 HookScript).  
**Candidates where a mixin surface can simplify/replace: 7**

---

## 2. Blizzard Mixin and API Surfaces Relevant to Yapper

### 2A. `ChatFrameEditBoxMixin` — EventRegistry callbacks
**File:** `Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua`

Every `ChatFrameEditBoxMixin` event calls out to a named EventRegistry event.  These are
**already public addons APIs** — Blizzard intentionally exposes them for exactly this purpose.

| EventRegistry event | When fired | Payload |
|---------------------|-----------|---------|
| `ChatFrame.OnEditBoxShow` | Blizzard editbox `.OnShow()` fires | `(editBox)` |
| `ChatFrame.OnEditBoxHide` | Blizzard editbox `.OnHide()` fires | `(editBox)` |
| `ChatFrame.OnEditBoxFocusGained` | editbox gains focus | `(editBox)` |
| `ChatFrame.OnEditBoxFocusLost` | editbox loses focus | `(editBox)` |
| `ChatFrame.OnEditBoxPreSendText` | just before `SendText` dispatches | `(editBox)` |
| `ChatFrame.OnHyperlinkClick` | player clicks a chat hyperlink | `(chatFrame, link, text, button)` |
| `ChatFrame.OnHyperlinkEnter` | cursor enters a chat hyperlink | `(chatFrame, link, text, ...)` |
| `ChatFrame.OnHyperlinkLeave` | cursor leaves a chat hyperlink | `(chatFrame)` |

**How to register:**
```lua
EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusLost", function(ownerID, editBox)
    -- safe, no hooksecurefunc needed
end)
```

### 2B. `ChatFrameMenuButtonMixin` — `Menu.ModifyMenu` / `MENU_CHAT_SHORTCUTS`
**File:** `Blizzard_ChatFrameBase/Mainline/ChatFrameMenuButton.lua`

The speech-bubble menu button calls `rootDescription:SetTag("MENU_CHAT_SHORTCUTS")` on every
open.  Blizzard's official addon extension point is `Menu.ModifyMenu(tag, callback)`, documented
in `11_0_0_MenuImplementationGuide.lua`.  This fires the callback at menu-open time with
`(ownerRegion, rootDescription, contextData)` so addons can add, remove, or wrap items cleanly.

Yapper currently uses `Menu.ModifyMenu("MENU_CHAT_SHORTCUTS", ...)` at hook 16 above — this is
already the right surface.  The question is whether the _body_ of that callback can be
simplified.

Key insight from reading `ChatFrameMenuButton.lua`:
- Every channel type (SAY, PARTY, GUILD, …) is registered as `rootDescription:CreateButton(chatName, function() SetChatTypeAttribute(chatType) end)`.
- The whisper button calls `ChatFrameUtil.OpenChat(SLASH_SMART_WHISPER1.." ")` and lets `ParseText(0)` identify the target.
- The Reply button calls `ChatFrameUtil.ReplyTell()`.

This means Yapper's responder-wrapping approach is the most targeted one available.

### 2C. `UnitPopupWhisperButtonMixin` — runtime override
**File:** `Blizzard_UnitPopupShared/UnitPopupSharedButtonMixins.lua` (line 420)

This is already being overridden (see Yapper.lua InstallUnitPopupWhisperOverride).  The mixin is
a plain Lua table; `OnClick` is looked up dynamically via `GenerateClosure(self.OnClick, self,
contextData)` at menu-build time (line 184 of SharedButtonMixins.lua).  This means:

- Replacing `mixin.OnClick` **before** any menu is built → every future menu sees the override.  
- Replacing it **after** an already-open menu was built → that open menu still runs the old
  closure.  This is fine because menus close before re-opening.

**Callers that use this mixin path (confirmed from wow-ui-source):**

| Menu which | Context | Source |
|------------|---------|--------|
| FRIEND | Contacts list whisper button | FriendsFrame.lua / UnitPopupSharedMenus.lua |
| PARTY | Party member right-click | UnitPopupSharedMenus.lua |
| PLAYER | Friendly player right-click | UnitPopupSharedMenus.lua |
| RAID_PLAYER | Raid member right-click | UnitPopupSharedMenus.lua |
| GUILD | Guild member right-click | UnitPopupSharedMenus.lua |
| GUILD_OFFLINE | Offline guild member | UnitPopupSharedMenus.lua |
| CHAT_ROSTER | Chat channel member list | UnitPopupSharedMenus.lua |
| ENEMY_PLAYER | Enemy (where whisper allowed) | project-specific |
| BN_FRIEND (via SendBNetTell) | BNet friend — **separate path** | does NOT go through WhisperButtonMixin.OnClick for the actual tell |

**Callers that use `ChatFrameUtil.SendTell` but NOT through the UnitPopup mixin:**

| Caller | File | Notes |
|--------|------|-------|
| LFG List applicant | `Blizzard_GroupFinder/Mainline/LFGList.lua:2021,3282` | FindGroup whisper button |
| Professions customer orders | `Blizzard_ProfessionsCustomerOrdersForm.lua:257` | "Whisper Crafter" button |
| Professions crafter view | `Blizzard_ProfessionsCrafterOrderView.lua:174` | "Whisper Customer" button |
| Professions guild member list | `Blizzard_ProfessionsGuildMemberList.lua:29` | Guild crafters |
| Communities frame | `CommunitiesFrame.lua:322` | member whisper |
| ItemRef chat-link left-click | `ItemRefHandlers.lua:44` | direct click (no dropdown) |

**Conclusion:** The mixin override covers 100% of unit-popup-menu whispers.  It does NOT cover
the six direct SendTell callers above (LFG, Professions, Communities, ItemRef).  The existing
`hooksecurefunc(ChatFrameUtil, "SendTell", ...)` at Blizzard.lua:1057 covers those as a
backstop.  **Both are needed; they are complementary, not redundant.**

### 2D. `ChatFrameUtil.InsertLink` — override-aware link insertion
**File:** `Blizzard_ChatFrameBase/Mainline/ChatFrameUtilOverrides.lua`

`ChatFrameUtil.InsertLink(text)` already honours `CHAT_FOCUS_OVERRIDE` and routes to
`GetActiveWindow():Insert(text)`.  Yapper sets `CHAT_FOCUS_OVERRIDE` to `OverlayEdit` while
the overlay is shown.  Therefore:

- If the overlay is open and `CHAT_FOCUS_OVERRIDE == OverlayEdit`, `InsertLink` will already
  write into the overlay.
- The current hook at Blizzard.lua:1193 (`hooksecurefunc("ChatEdit_InsertLink", ...)`) handles
  the TRP3 case where the overlay is _not yet_ shown.  This hook is a thin guard (< 5 lines).

### 2E. `ChatFrameEditBoxBaseMixin` state accessors
**File:** `Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua` (lines 8–70)

Every Blizzard editbox has `GetChatType()`, `SetChatType()`, `GetTellTarget()`,
`SetTellTarget()`, `GetChannelTarget()`, `SetChannelTarget()`, etc.  These read/write from
`GetAttribute`/`SetAttribute`.

Yapper's `_attrCache` (Blizzard.lua:124) captures attribute changes because it needs to know
when they _arrive_ (timing notification).  But the _reads_ of that cache — at Blizzard.lua:163,
280–295, ShowHide.lua:158 — could be replaced with direct mixin getter calls when the notification
has already triggered.  This is a code cleanliness opportunity, not a hook removal.

---

## 3. Analysis Per Candidate

### CANDIDATE 1: `UnitPopupWhisperButtonMixin.OnClick` override
**Status:** Already implemented in Yapper.lua.  
**Coverage:** All unit-popup menu whispers across every menu type.  
**What it replaces:** 85–90 lines of post-fire logic in the `SendTell` hook body that handles
the "Yapper open, retarget in-place" path when the whisper came from a menu (but not when it
came from LFG/Professions/Communities/ItemRef).  
**What it does NOT replace:** The `SendTell` hook entirely — the non-menu callers still need it.  
**Taint:** None.  The mixin is plain Lua, no protected path.  
**Verdict: KEEP and maintain.** The mixin override is the cleanest available surface.

---

### CANDIDATE 2: `Menu.ModifyMenu("MENU_CHAT_SHORTCUTS", ...)` — refine body
**Status:** Already used.  
**Current problem:** The responder-wrapping approach (Blizzard.lua:893–1000) modifies
`description.responder` on each menu item during menu traversal.  It needs to:
  - Temporarily clear `CHAT_FOCUS_OVERRIDE` so `OpenChat` returns a real editbox.
  - Capture what `SetChatType` was called with.
  - Restore the override and adopt/stash the channel.
  
The _mechanism_ is correct but the _body_ is ~110 lines with two-pass deferred capture.

**Can it be simplified?** Partially.  
The core problem is that `SetChatTypeAttribute` inside `ChatFrameMenuButton.lua` calls
`ChatFrameUtil.OpenChat("")` first, which with FOCUS_OVERRIDE returns `nil` (or our overlay).
Then it calls `editBox:SetChatType(chatType)` on that result — which crashes if nil.  

Yapper cannot make `OpenChat("")` return a real editbox _without_ clearing FOCUS_OVERRIDE,
because that's the mechanism.  

**Alternative approach (Menu.ModifyMenu body refactor):**  
Instead of wrapping every responder, Yapper could use `Menu.ModifyMenu` to _add a new button_
(or intercept at description level) that captures the chatType more cleanly:

```lua
Menu.ModifyMenu("MENU_CHAT_SHORTCUTS", function(owner, rootDescription)
    -- Walk existing buttons; for each one that sets a chatType,
    -- wrap it by AddInitializer to tag the description with the chatType.
    -- When picked, read the tag and adopt directly.
end)
```

However this would require understanding which button corresponds to which chatType from the
description label alone — fragile across locales.  The current approach of intercepting
`responder` is actually more robust because it wraps at the callback level, not the label level.

**Verdict: KEEP current approach, but add a comment explaining the two-pass logic.**  
Attempts to "simplify" this further will introduce locale-fragile code.

---

### CANDIDATE 3: EventRegistry `ChatFrame.OnEditBoxFocusLost` / `ChatFrame.OnEditBoxFocusGained`
**Current hook:** `blizzEditBox:HookScript("OnEditFocusLost", ...)` at Blizzard.lua:615.  
**Blizzard surface:** `EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusLost", fn)`  
**Difference in coverage:** The HookScript fires on _every_ Blizzard editbox we've individually
hooked via `HookBlizzardEditBox`.  The EventRegistry fires for _any_ ChatFrameEditBoxMixin
editbox, including ones we haven't explicitly hooked yet.

**Can we replace?** Yes, for the "track focus on Blizzard editbox" purpose.  
**Should we?** **Probably yes for new code; cautious for existing hook.**  

The current HookScript at Blizzard.lua:615 drives classic-mode editbox tracking. Replacing it
with `EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusLost", ...)` would:
- Remove the per-editbox HookScript installation.
- Automatically cover new editboxes (e.g. late-loaded community frames) without calling
  `EnsureEditBoxHooked`.
- Require verifying the payload is always a full ChatFrameEditBoxMixin instance.

**Risk:** The EventRegistry fires _after_ Blizzard's own `OnEditFocusLost` handler has run.
`hooksecurefunc` on `HookScript` also fires after.  Timing is equivalent.  

**Verdict: Medium-risk refactor, net positive.** Worth pursuing as a Phase 1 cleanup once
the mixin override for whispers is confirmed stable.

---

### CANDIDATE 4: EventRegistry `ChatFrame.OnEditBoxShow` / `ChatFrame.OnEditBoxHide`
**Current hook:** `hooksecurefunc(blizzEditBox, "Show", ...)` at Blizzard.lua:446 (per-box).  
**Blizzard surface:** `EventRegistry:RegisterCallback("ChatFrame.OnEditBoxShow", fn)`  

**Can we replace the Show hook body with EventRegistry?**  
**NO. This is the most important "shouldn't" in the whole document.**  

**Corrected execution order** (from `ChatFrameEditBoxMixin:OnShow`):
```
blizzEditBox:Show() is called
  └─ C frame becomes visible
  └─ OnShow script fires (ChatFrameEditBoxMixin:OnShow):
       1. EventRegistry:TriggerEvent("ChatFrame.OnEditBoxShow", self)  ← EventRegistry callback fires HERE
       2. self:ResetChatType()          ← mutates chatType (PARTY→SAY if not in group, etc.)
          └─ self:UpdateHeader()
          └─ self:OnInputLanguageChanged()
  └─ hooksecurefunc("Show") callback fires HERE  ← Yapper's hook fires AFTER full OnShow
```

`hooksecurefunc` is a post-hook like all other hooks — it fires **after** the original function
and all its registered scripts complete. My earlier statement that it fires "before Blizzard's
scripts run" was wrong.

**The real reason EventRegistry cannot replace the Show hook:**

`ResetChatType()` runs *after* the EventRegistry event but *before* the hooksecurefunc
callback. It resets certain chat types to SAY:
- PARTY → SAY (when not in a group)
- RAID → SAY (when not in a raid)
- GUILD/OFFICER → SAY (when not in a guild)
- INSTANCE_CHAT → SAY (when not in an instance group)

If Yapper used the EventRegistry event, it would read the chatType from the attribute cache at
step 1 — before `ResetChatType` has corrected it.  Example: editbox opens with `chatType=PARTY`
while the player left the group; EventRegistry fires and Yapper reads `PARTY`; then Blizzard
corrects it to `SAY`; Yapper displays the wrong channel label.

With the hooksecurefunc, Yapper reads the attribute cache *after* `ResetChatType` has run, so
it always sees the post-correction value.

**Verdict: MUST keep the Show hook. Do NOT replace with EventRegistry.**

---

### CANDIDATE 5: EventRegistry `ChatFrame.OnEditBoxFocusGained` — ActivateChat hook
**Current hook:** `hooksecurefunc(ChatFrameUtil, "ActivateChat", ...)` at Blizzard.lua:1014.  
**Verdict after verification: DO NOT REPLACE.**

Verified Blizzard call sites for `ChatFrameUtil.ActivateChat` (wow-ui-source):
- `ChatFrameEditBox.lua:391` — `OnEditFocusGained`
- `ChatFrameUtil.lua:399` — `OpenChat`
- `ChatFrameUtil.lua:437` — `FocusActiveWindow`
- `ChatFrameUtil.lua:842` — dock selection path

`ChatFrame.OnEditBoxFocusGained` only fires from `OnEditFocusGained` (1 of 4 sites).  The
`OpenChat`/`FocusActiveWindow`/dock paths call `ActivateChat` directly; some of them re-enter
`SetFocus` (which re-fires the event) but not all, and the timing differs (event fires *before*
ActivateChat completes, the hook fires *after*).  A 1:1 swap would change coverage and ordering.
**Not behaviour-preserving.  Keep the hook.**

---

### CANDIDATE 6: EventRegistry `ChatFrame.OnEditBoxFocusLost` — DeactivateChat hook
**Current hook:** `hooksecurefunc(ChatFrameUtil, "DeactivateChat", ...)` at Blizzard.lua:1002.  
**Verdict after verification: DO NOT REPLACE.**

The hook re-shows the proxy background when `OrigEditBox` is deactivated while the overlay is
shown.  Verified Blizzard call sites for `ChatFrameUtil.DeactivateChat` (wow-ui-source):
- `ChatFrameEditBox.lua:380` — `OnHide`
- `ChatFrameEditBox.lua:399` — `OnEditFocusLost`
- `ChatFrameEditBox.lua:537` — `ClearChat` (im/voice path)
- `ChatFrameUtil.lua:448` — `ActivateChat` deactivating the **previous** active box
- `ChatFrameUtil.lua:840/843` — dock close path
- `FloatingChatFrame.lua:765` — floating frame teardown

`ChatFrame.OnEditBoxFocusLost` only fires from `OnEditFocusLost` (1 of 6 sites).  The proxy box
often does **not** have focus (the overlay does), so the deactivations that matter — `OnHide`,
`ClearChat`, and especially `ActivateChat` deactivating the previous box — would never reach an
`OnEditBoxFocusLost` callback.  A swap would silently drop proxy-background re-shows in exactly
those cases.

**My earlier "Phase 1, zero risk" rating for this swap was wrong.**  `DeactivateChat` is a strict
superset of the focus-lost event.  **Keep the hook.**

---

### CANDIDATE 7: `ChatEdit_InsertLink` hook — replace with focus-override routing
**Current hook:** `hooksecurefunc("ChatEdit_InsertLink", ...)` at Blizzard.lua:1193.  

Body (5 lines): if `CHAT_FOCUS_OVERRIDE == OverlayEdit` and overlay is not shown, open Yapper
and give it focus.

`ChatFrameUtil.InsertLink` (the mainline override of `ChatEdit_InsertLink`) already routes to
`GetActiveWindow():Insert(text)` and respects `CHAT_FOCUS_OVERRIDE`.  

When the overlay IS shown: `CHAT_FOCUS_OVERRIDE == OverlayEdit`, so `GetActiveWindow()`
returns `OverlayEdit`, and `InsertLink` writes to the overlay.  No hook needed.

When the overlay is NOT shown: `CHAT_FOCUS_OVERRIDE` may still be set to `OverlayEdit` from a
previous open.  The hook's job is to open the overlay before the insert happens.

**Can we eliminate the hook?**  
Only if we clear `CHAT_FOCUS_OVERRIDE` when the overlay hides (which Yapper does — see
`UpdateFocusOverride()`).  When the overlay is hidden and `CHAT_FOCUS_OVERRIDE` is nil,
`InsertLink` falls through to `GetActiveWindow()` (native editbox) which is correct.

The edge case the hook handles: **TRP3 calls `ChatEdit_InsertLink` globally, and Yapper has set
`CHAT_FOCUS_OVERRIDE` to `OverlayEdit` but the overlay isn't shown yet.**  In this case
`InsertLink` would call `OverlayEdit:Insert(text)` on a hidden, unfocused frame.

So the hook is still needed for this edge case.  However it's already minimal (5 lines) and
low-risk.

**Verdict: KEEP the hook.** It is already as simple as it can be.

---

### CANDIDATE 8: `ChatFrameEditBoxBaseMixin` state getters for `_attrCache` reads
**Blizzard surface:** `GetChatType()`, `GetTellTarget()`, `GetChannelTarget()` on any
ChatFrameEditBoxMixin instance.

**Current pattern:** Yapper reads `self._attrCache[eb].chatType` etc. at many points.  The cache
exists because SetAttribute on the Blizzard editbox fires _before_ the Show hook completes (for
BNet whispers) or _after_ (for WoW whispers, deferred through OnUpdate).

**Can the cache reads be replaced with getter calls?**  
At the _read sites_ (ShowHide.lua:158, Blizzard.lua:280–295) where Yapper is _consuming_ the
cached values, we could call `eb:GetChatType()` and `eb:GetTellTarget()` directly — they return
the same attribute-stored value.

**Should we?**  
**No for the write/notification side.** The SetAttribute hook is still needed to know _when_
attributes arrive.  
**Yes for the read side as a minor cleanup** — directly calling the mixin getter is clearer than
indexing a cache table.  However the cache provides a "snapshot before Hide() reset" that mixin
getters cannot replicate (Deactivate calls `ResetChatTypeToSticky` which stomps the attribute).
So the cache must stay for that snapshot purpose.

**Verdict: Not worth the refactor.** The cache has a valid reason to exist beyond timing.

---

## 4. Summary Table

| # | Hook/Code | Can be replaced? | Should be replaced? | Mechanism | Priority |
|---|-----------|-----------------|---------------------|-----------|---------|
| 5 | `blizzEditBox.Show` | No | No — MUST keep | ResetChatType mutation window | N/A |
| 7 | `ChatFrameUtil.OpenChat` | No | No — MUST keep | Global entry point with complex branching | N/A |
| 12 | `FCF_Tab_OnClick` | No | No — no mixin surface | Tab switching has no EventRegistry event | N/A |
| 1 | `blizzEditBox.SetAttribute` | No (notification side) | No | No equivalent push event | N/A |
| 2 | `blizzEditBox.SetText` | No | No | Deferred prefill stripping has no better hook | N/A |
| 10 | `ChatFrameUtil.SendTell` | Partial (mixin for menu callers) | Keep for non-menu callers | mixin override + `RetargetOpenWhisper` helper | **Done** |
| 11 | `ChatEdit_InsertLink` | No (edge case) | No — already minimal | InsertLink routes correctly when overlay shown | N/A |
| 16 | MENU_CHAT_SHORTCUTS responder wrap | Partial | Not worth simplifying | Menu.ModifyMenu already used correctly | Keep |
| 8 | `ChatFrameUtil.DeactivateChat` | **No** (verified) | **No** | Focus event is a strict subset of call sites | Keep |
| 9 | `ChatFrameUtil.ActivateChat` | **No** (verified) | **No** | Focus event is a strict subset of call sites | Keep |
| — | `ChatFrame.OnEditBoxPreSendText` | n/a (additive) | **Yes — done** | EventRegistry callback → fallback history | **Done** |

### Verification note (correction to earlier draft)

An earlier draft rated the DeactivateChat/ActivateChat swaps as safe Phase 1/2 work.  Verifying
the Blizzard call sites showed the focus EventRegistry events are a **strict subset** of where
those functions are invoked, so the swaps are **not** behaviour-preserving.  They have been
re-classified as "keep".  The genuinely safe, additive win was wiring `OnEditBoxPreSendText` for
fallback history — which has been implemented.

---

## 5. The "Shouldn't" List

These replacements are **technically possible** but should not be done.

### 5A. Do not replace `blizzEditBox.Show` hook with EventRegistry `ChatFrame.OnEditBoxShow`

`hooksecurefunc` is a post-hook — it fires _after_ the original function and all its scripts
complete.  `EventRegistry:TriggerEvent("ChatFrame.OnEditBoxShow")` fires _during_ `OnShow()`,
before `ResetChatType()` runs.  The hooksecurefunc fires after `ResetChatType()` completes.

This ordering matters: `ResetChatType()` can mutate the chatType attribute (e.g. PARTY→SAY
when the player is not in a group).  If Yapper read chatType from an EventRegistry callback,
it would see the pre-correction value.  With hooksecurefunc it sees the post-correction value.
This is not replaceable without introducing a deferred re-read.

### 5B. Do not replace `ChatFrameUtil.OpenChat` hook with EventRegistry

`OpenChat` is the universal chat-open path.  No EventRegistry event covers it.
`ChatFrame.OnEditBoxShow` fires too late (same reason as 5A).  
No mixin fires at OpenChat time.

### 5C. Do not override `ChatFrameMenuButtonMixin.OnClick`

`ChatFrameMenuButtonMixin:OnClick()` only toggles a help tip; the actual menu responders are
closures built inside `OnLoad()`.  Overriding `OnClick` does nothing useful.  
The correct surface for channel menu interception is already `Menu.ModifyMenu("MENU_CHAT_SHORTCUTS")`.

### 5D. Do not apply `ChatFrameEditBoxBaseMixin` to OverlayEdit as a mixin

Applying this mixin to `OverlayEdit` would give it `GetChatType()` / `SetChatType()` backed by
`SetAttribute`/`GetAttribute`.  However:
- `SetAttribute` on OverlayEdit would taint it if called in restricted context.
- OverlayEdit's "chat type" is Yapper's `EditBox.ChatType` field — not stored as a frame
  attribute.  Mixing both would create two sources of truth.
- `UpdateHeader()` in the mixin assumes a `chatFrame` parent and header FontString objects
  that OverlayEdit does not have in the same form.

`EditBoxCompat.lua` already installs compatible method shims more safely than a full mixin
application would.

### 5E. Do not remove the `SendTell` hooksecurefunc, even after the mixin override is confirmed

The mixin override covers menu-initiated whispers.  Six other Blizzard subsystems call
`ChatFrameUtil.SendTell` directly (LFG, Professions, Communities, ItemRef).  The `SendTell`
hook is the only backstop for those callers.

---

## 6. Coverage Map: Every Whisper Entry Point

| Whisper entry point | Blizzard call path | Mixin override coverage | SendTell hook coverage | Notes |
|--------------------|-------------------|------------------------|----------------------|-------|
| Right-click player in world | UnitPopup PLAYER menu | ✓ | ✓ | Double-covered, mixin fires first |
| Right-click party member | UnitPopup PARTY menu | ✓ | ✓ | Same |
| Right-click raid member | UnitPopup RAID_PLAYER menu | ✓ | ✓ | Same |
| Right-click friendly NPC | Not applicable — NPC | — | — | |
| Contacts list (Whisper button) | UnitPopup FRIEND menu | ✓ | ✓ | Friends list |
| Guild list (Whisper button) | UnitPopup GUILD menu | ✓ | ✓ | Guild roster |
| Chat roster (Whisper button) | UnitPopup CHAT_ROSTER menu | ✓ | ✓ | Channel members |
| Left-click player name in chat | `ItemRefHandlers.lua:44` → `SendTell` | ✗ | ✓ | Not a menu; hook-only |
| LFG applicant whisper | `LFGList.lua:2021,3282` → `SendTell` | ✗ | ✓ | Not a menu; hook-only |
| Professions customer whisper | `ProfessionsCustomerOrdersForm.lua` | ✗ | ✓ | Not a menu; hook-only |
| Professions crafter whisper | `ProfessionsCrafterOrderView.lua` | ✗ | ✓ | Not a menu; hook-only |
| Professions guild member | `ProfessionsGuildMemberList.lua` | ✗ | ✓ | Not a menu; hook-only |
| Communities member whisper | `CommunitiesFrame.lua` | ✗ | ✓ | Not a menu; hook-only |
| BNet friend whisper (any path) | `ChatFrameUtil.SendBNetTell` → BN_WHISPER | ✗ | ✗ | Intentionally excluded; native path |
| `/w name` slash command | Through `ParseText` → `SetAttribute` | ✗ | ✗ | Attribute hook covers target extraction |
| Reply keybind (REPLYTELL2) | `Keybinds.lua` override | ✗ | ✗ | Keybind system handles directly |

**Conclusion:** Every non-BNet whisper entry point is covered by either the mixin override, the
SendTell hook, or Yapper's own keybind system.  BNet whispers are intentionally left on Blizzard's
native path.

---

## 7. What Was Implemented (2026-06-30)

After verification, the following changes were made. The EventRegistry focus-event swaps were
**deliberately not done** (see §4 verification note).

### 7.1 `ChatFrame.OnEditBoxPreSendText` -> fallback history (additive, safe)
- New `EditBox:RecordFallbackSend(editBox)` in `Src/Hooks/ShowHide.lua`.
- Registered once in `EditBox:HookAllChatFrames` (`Src/Hooks/BlizzardHookCtl/30_ChatFrameHooks.lua`) guarded by
  `self._fallbackHistoryRegistered`.
- Captures messages sent through Blizzard's native editbox during lockdown / bypass / handoff
  into Yapper's persistent history, so Up/Down history stays complete for the fallback path.
- Reads channel context via the `ChatFrameEditBoxBaseMixin` getters (`GetChatType`,
  `GetTellTarget`, `GetChannelTarget`) - the sensible use of that mixin surface.
- Guards every value with `Utils:IsSecret` before reading/comparing/storing; drops secret
  channel context but keeps the plain message text.
- No double-record: the overlay is not a ChatFrameEditBoxMixin and never fires this event.

### 7.2 Unified external whisper routing (clean up SendTell vs mixin override)
- New `EditBox:RetargetOpenWhisper(target, blizzBox)` and `EditBox:IsNativeChatEditBox(eb)` in
  `Src/Hooks/ShowHide.lua` - one implementation of "retarget the open overlay onto a whisper".
- The `SendTell` hook (`Src/Hooks/BlizzardHookCtl/30_ChatFrameHooks.lua`) and the `UnitPopupWhisperButtonMixin` override
  (`Yapper.lua`) both delegate their "Yapper already open" path to this helper, so they cannot
  drift apart or fight.
- `RetargetOpenWhisper` returns `false` when preconditions fail (overlay not shown, empty
  target) so callers fail fast rather than silently no-op.
- The `SendTell` hook now fails fast on unusable input: `if type(target) ~= "string" or
  target == "" then return end` and the lockdown bail, leaving Blizzard's native box untouched
  instead of attempting elaborate fallback.
- The duplicated local `IsNativeChatEditBox` closure inside the SendTell hook was removed in
  favour of the shared method.

### 7.3 Not done (and why)
- DeactivateChat / ActivateChat -> EventRegistry focus events: focus events are a strict subset
  of the call surface (§4). Swapping would silently drop proxy-background re-shows and
  IM/open activations.
- Show / OpenChat / FCF_Tab_OnClick / SetAttribute / SetText: no safe mixin or event surface.
- Applying `ChatFrameEditBoxBaseMixin` to OverlayEdit: would taint and create dual state (§5D).

---

## 8. Expected Outcome

| Metric | Before | After this change | Change |
|--------|--------|-------------------|--------|
| Global hooksecurefunc count | 14 | 14 | 0 |
| Duplicate whisper-routing implementations | 2 (SendTell hook + mixin override) | 1 (`RetargetOpenWhisper`) | −1 |
| EventRegistry callbacks | 0 | 1 (`OnEditBoxPreSendText`) | +1 |
| Fallback (lockdown/bypass) sends recorded in history | No | Yes | new feature |
| Whisper entry-point coverage | full | full | unchanged |

The hook count did not drop — the verified-safe reductions turned out to be unsafe.  The real
gains are: a single source of truth for external whisper routing (the two entry points can no
longer fight), fail-fast preconditions on that path, and fallback sends now landing in history.

---

## 9. Notable Architectural Constraints That Won't Change

These are not deficiencies — they are the correct approach given WoW's security model.

1. **`Show` hook must stay per-editbox via hooksecurefunc.**  
   `hooksecurefunc` is a post-hook: it fires after the full Show()+OnShow() chain.  The
   EventRegistry `ChatFrame.OnEditBoxShow` fires _during_ OnShow, before `ResetChatType()`
   has run.  Reading chatType at that point can give a stale value that Blizzard corrects
   immediately afterwards.  The hooksecurefunc sees the stable post-correction state.

2. **`OpenChat` hook must stay global via hooksecurefunc.**  
   No alternative entry point covers the full open path (keybinds, slash commands, name-clicks,
   chat-area clicks).

3. **`FCF_Tab_OnClick` hook must stay.**  
   WoW has no EventRegistry or mixin event for tab-switching.  The tab UI is FCF legacy code.

4. **`SetAttribute` hook must stay.**  
   There is no push notification for attribute changes.  The cache-then-read pattern is necessary.

5. **`SetText`/`Insert` hooks must stay.**  
   Blizzard's deferred `OnUpdate` SetText path for whisper prefills has no other interception
   point without the hook.

6. **`SendTell` hook must stay as backstop.**  
   Non-menu UI code (LFG, Professions, ItemRef) calls it directly.

7. **Proxy/IM/Classic mode branching cannot be removed.**  
   It reflects genuine behavioural differences in how Blizzard manages editbox lifecycle in each
   mode.  No mixin abstracts over this.
