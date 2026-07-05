# Unit-popup whispers, taint, and why we use Menu.ModifyMenu

This page documents how Yapper intercepts the **Whisper** button in the
right-click ("unit popup") menus, why the old approach broke other menu
buttons, and why the current approach is safe. Written for someone new to
WoW addon development — no prior taint knowledge assumed.

Implementation: [`Src/Hooks/UnitPopup.lua`](../Src/Hooks/UnitPopup.lua),
installed from `Yapper.lua` on `PLAYER_ENTERING_WORLD`.

## Background: what "taint" is

WoW divides all running Lua into two trust levels:

- **Secure** — Blizzard's own code. Only secure code may call *protected*
  functions (targeting, focus, inviting, `CopyToClipboard`, ...).
- **Tainted** — anything an addon wrote or touched. If secure code so much as
  *reads* a value an addon wrote, the running execution becomes tainted from
  that point on.

Taint is sticky and it spreads **forward**: once an execution path goes
tainted, everything it produces (closures, frames, table entries) is tainted
too. When a tainted path later calls a protected function, the client blocks
it and blames whichever addon originally wrote the value ("*Yapper has been
blocked from an action only available to the Blizzard UI*").

The key trap: taint does not require you to break anything. Writing one field
into a Blizzard table is enough, even if the field is "just data".

## What we tried first (and why it failed)

Yapper needs menu whispers ("right-click player → Whisper") to open *Yapper's*
editbox instead of Blizzard's. The first attempt replaced the click handler on
Blizzard's shared button definition:

```lua
-- OLD, REMOVED. Do not do this.
UnitPopupWhisperButtonMixin.OnClick = function(self, contextData) ... end
```

That *felt* legitimate — we weren't editing Blizzard's files, just swapping a
function in a table that mixins are "meant" to compose from. Here is why it
poisoned the whole menu anyway:

1. Since patch 10.2.6, unit popups are built by the new **Menu** system.
   When a menu opens, Blizzard's **secure** generator walks the entry list and,
   for each button, reads its `OnClick` to build the menu element
   (`UnitPopupButtonBaseMixin:CreateMenuDescription` does
   `GenerateClosure(self.OnClick, self, contextData)` — see
   `Blizzard_UnitPopupShared/UnitPopupSharedButtonMixins.lua`).
2. Our replacement `OnClick` was an **addon-written value**. The moment the
   secure generator read it, the *entire remainder of the menu build* became
   tainted — every element created after the Whisper entry.
3. **Copy Character Name** is built after Whisper in most menus, and its
   handler calls `CopyToClipboard()`, a protected function. Tainted element →
   protected call → blocked, attributed to Yapper. Same risk for Set Focus,
   Invite, Report, etc., depending on menu order.

Lesson: under the new Menu system there is **no taint-free way to write into
the `UnitPopup*Mixin` tables**. The old folklore about `UnitPopupButtons` /
`UnitPopupMenus` being addon-editable comes from the pre-10.2.6
UIDropDownMenu era and no longer applies.

## What we do now: Menu.ModifyMenu + SetResponder

Blizzard built an official addon customization surface into the new Menu
system, and its design goal is documented in the client source
(`Blizzard_Menu/11_0_0_MenuImplementationGuide.lua`):

> "The menu system was designed with consideration to better support addon
> customization without taint consequences."

How Yapper uses it (all in `Src/Hooks/UnitPopup.lua`):

1. Every unit popup tags its menu `"MENU_UNIT_<TYPE>"` (e.g.
   `MENU_UNIT_PLAYER`). `Menu.ModifyMenu(tag, callback)` registers a callback
   that runs **after** Blizzard's secure generator has finished building the
   menu, behind a `securecallfunction` boundary — so nothing we do in the
   callback can retroactively taint the build pass.
2. In the callback we walk the finished menu with `MenuUtil.TraverseMenu` and
   find the Whisper element by its label (`MenuUtil.GetElementText(desc) ==
   WHISPER` — comparing against the same localized global Blizzard used, so
   this is locale-safe).
3. We swap that one element's click handler:
   `desc:SetResponder(function() ... end)`. Menu elements are **per-element
   proxy objects**; a replaced responder taints only *that element's click*,
   not its neighbours. Copy Character Name, Set Focus, etc. keep their
   pristine secure handlers.
4. Opening a whisper is **not** a protected action, so our tainted whisper
   click is harmless. The responder routes into
   `EditBox:OpenWhisperFromUnitMenu(contextData)` and returns
   `MenuResponse.CloseAll` to close the menu.

### Division of labour with the other whisper hooks

| Entry point | Handled by |
| --- | --- |
| Right-click menu → Whisper (character) | `Menu.ModifyMenu` responder → `OpenWhisperFromUnitMenu` |
| Right-click menu → Whisper (Battle.net) | Left native; `SendBNetTell` hooksecurefunc in `30_ChatFrameHooks.lua` |
| Chat name left-click, LFG, Professions, Communities, ItemRef | `SendTell` hooksecurefunc in `30_ChatFrameHooks.lua` |
| Any of the above during chat lockdown | Native Blizzard editbox (all Yapper paths early-return) |

Both menu and non-menu character whispers converge on the same helper
(`EditBox:RetargetOpenWhisper` in `Hooks/ShowHide.lua`) when the overlay is
already open, so the two entry points cannot drift apart.

BNet contexts are detected at menu-open time (`contextData.bnetIDAccount` or
`playerLocation:IsBattleNetGUID()`) and skipped entirely — Blizzard's native
button runs, calls `ChatFrameUtil.SendBNetTell`, and Yapper's existing hook
routes it. During lockdown, the responder replicates the native button by
calling `ChatFrameUtil.SendTell` itself (not protected, safe from tainted
code); the SendTell hook early-returns under lockdown, so Blizzard's editbox
takes over with no reentrancy.

### Why this kills the race conditions

The old SendTell-only interception had to fight Blizzard's own editbox
lifecycle: `SendTell` → `OpenChat` → editbox `Show()` (fires Yapper's show
hook mid-flight) → `ParseText` → *then* our post-hook. The menu responder
never touches Blizzard's editbox at all — no `OpenChat`, no `ParseText`, no
show-hook interplay, no attribute-cache snapshotting. There is simply no
window for a race.

## Rules of thumb (checklist for future menu work)

- **Never write** to `UnitPopup*Mixin` tables, `UnitPopupMenus`, or anything
  Blizzard's secure generator reads. Reading them is fine; writing is poison.
- To add or change unit menu items, always go through `Menu.ModifyMenu`.
- Inserting *new* elements is explicitly blessed by Blizzard. Replacing an
  existing element's responder (what we do) is contained by the proxy design
  but less explicitly documented — if it ever regresses, the fallback is
  `desc:HookResponder(fn)` (runs after the native handler) combined with the
  SendTell hook.
- Only replace responders for actions that are **not protected**. A tainted
  responder that calls a protected function will be blocked.
- Debugging aids:
  - `/console taintLog 1`, reproduce, then check `Logs/taint.log`.
  - `/run Menu.PrintOpenMenuTags()` while a menu is open to find its tag.
  - `/eventtrace` shows `Menu.OpenMenuTag` events when tagged menus open.
- Regression test after any change here: open a player menu and click
  **Copy Character Name** and **Set Focus** — both must work with no
  "blocked action" popup — then verify Whisper opens the Yapper overlay,
  retargets an already-open overlay, and falls back to Blizzard's box during
  combat lockdown.
