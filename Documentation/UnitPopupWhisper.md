# Unit-popup whisper routing

Yapper replaces the **Whisper** action in Blizzard unit-popup menus with a
route into the Yapper editbox overlay.

Implementation:

- `Src/Hooks/UnitPopup.lua`
- Installed by `Yapper.lua` during `PLAYER_ENTERING_WORLD`

## Menu registration

`EditBox:InstallUnitPopupWhisperOverride()` registers a
`Menu.ModifyMenu` callback for the unit-menu tags listed in
`WHISPER_MENU_TAGS`.

The callback runs after Blizzard has generated the menu. For each menu open it:

1. Validates `contextData`.
2. Traverses the generated menu with `MenuUtil.TraverseMenu`.
3. Finds the element whose localized text equals `WHISPER`.
4. Replaces that element's responder with Yapper's whisper handler.
5. Returns `MenuResponse.CloseAll` after the handler runs.

Menu descriptions are regenerated for each open, so the responder is installed
per menu instance. Yapper does not write to `UnitPopup*Mixin` tables,
`UnitPopupMenus`, or other data read by Blizzard's secure menu generator.

## Whisper handler

`EditBox:OpenWhisperFromUnitMenu(contextData)` handles both character and
Battle.net contexts.

### Character context

- Rejects non-player units.
- Resolves the full `Name-Realm` target with
  `UnitPopupSharedUtil.GetFullPlayerName`, with a field-based fallback.
- Uses chat type `WHISPER`.

### Battle.net context

A context is treated as Battle.net when `contextData.bnetIDAccount` is present.

- Uses the account ID as the Yapper target.
- Uses chat type `BN_WHISPER`.
- Uses `contextData.name` when delegating to Blizzard's native BNet tell path.

The account ID is used as the overlay target because friend-list names may be
protected or tokenized. Target values are sanitized before they enter Yapper
state.

## Overlay and lockdown behavior

When chat lockdown is active, or the overlay cannot be shown, the handler
preserves Blizzard behavior:

- Character context: `ChatFrameUtil.SendTell`
- Battle.net context: `ChatFrameUtil.SendBNetTell`

Yapper's `SendTell` and `SendBNetTell` hooks return early during lockdown, so
Blizzard's editbox remains authoritative.

Outside lockdown:

- If the Yapper overlay is already open, `RetargetOpenWhisper` changes the
  target in place. Battle.net menu whispers pass `BN_WHISPER` so the channel is
  updated correctly.
- If the overlay is closed, the native editbox is hidden, its current text is
  copied to the overlay, and the target and chat type are set on the overlay.
- The opened target is stored as `_externalWhisperTarget` and is not promoted to
  the persistent sticky target.

## Whisper hook ownership

| Entry point | Handler | Chat type |
| --- | --- | --- |
| Unit popup: character Whisper | `Menu.ModifyMenu` responder | `WHISPER` |
| Unit popup: Battle.net Whisper | `Menu.ModifyMenu` responder | `BN_WHISPER` |
| Chat name, LFG, Professions, Communities, ItemRef | `hooksecurefunc(ChatFrameUtil, "SendTell")` | `WHISPER` |
| Non-menu Battle.net sources, including hyperlinks and social UI | `hooksecurefunc(ChatFrameUtil, "SendBNetTell")` | `BN_WHISPER` |
| Any source during chat lockdown | Blizzard's native editbox | Native Blizzard state |

Menu Battle.net whispers are handled directly by the menu responder. Non-menu
Battle.net whispers continue through the `SendBNetTell` hook.

Character menu and non-menu paths converge on `RetargetOpenWhisper` when the
overlay is already visible.

## Taint constraints

- Use `Menu.ModifyMenu` for unit-menu customization.
- Do not modify `UnitPopup*Mixin`, `UnitPopupMenus`, or secure generator input.
- Replace only the Whisper element's responder. Other menu elements retain
  Blizzard's responders.
- Keep protected actions such as **Copy Character Name** and **Set Focus** on
  Blizzard's handlers.
- The replacement responder must route only through the unprotected chat APIs
  and Yapper overlay methods used by `OpenWhisperFromUnitMenu`.

## Verification

After changing this integration:

1. Open a player unit menu.
2. Verify **Whisper** opens or retargets the Yapper overlay.
3. Verify **Copy Character Name** and **Set Focus** still work without a blocked
   action error.
4. Test character and Battle.net targets.
5. Test the same actions during chat lockdown and verify that Blizzard's editbox
   is used.

Useful diagnostics:

- `/console taintLog 1`, then inspect `Logs/taint.log`.
- `/run Menu.PrintOpenMenuTags()` while a menu is open.
- `/eventtrace` for `Menu.OpenMenuTag` events.
