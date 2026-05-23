# Removed Hooks Documentation

This file tracks hooks that have been removed from Yapper as part of the hook reduction effort, moving toward a keybind-driven architecture.

## Removed Hooks

### 1. ChatFrameUtil.ReplyTell2 Hook
**File**: `Src/EditBox/Hooks.lua`  
**Lines Removed**: 1800-1817  
**Date**: 2026-05-23  
**Reason**: Redundant with keybind system - REPLYTELL2 is now overridden directly in Keybinds.lua

**Original Functionality**:
- Intercepted the Re-Whisper keybind (ChatFrameUtil.ReplyTell2) to open Yapper instead of Blizzard's editbox
- Primed ChatType and Target directly before ReplyTell2 called OpenChat
- Provided guaranteed values for Show-hook regardless of attribute-cache timing race
- Maintained addon compatibility for addons that call ReplyTell2 programmatically

**Replacement**:
- Keybind system now handles REPLYTELL2 override directly in `Src/EditBox/Keybinds.lua`
- Primary path for re-whisper functionality through keybind system

**Potential Impact**:
- Addons that call ReplyTell2 programmatically may not trigger Yapper overlay
- Users relying on addon-triggered re-whispers may see Blizzard editbox instead of Yapper overlay

**Code Changes**:
- Removed hook registration in HookBlizzardEditBox()
- Removed _pendingReWhisperType and _pendingReWhisperTarget priority handling in DetermineChatType()
- Added removal comment at original hook location

### 2. blizzEditBox.Show Hook
**File**: `Src/EditBox/Hooks.lua`  
**Lines Removed**: 1420-1609  
**Date**: 2026-05-23  
**Reason**: Replaced by keybind system - OPENCHAT/OPENCHATSLASH/REPLYTELL2 overrides now handle show interception

**Original Functionality**:
- Main show interception and overlay activation
- Bypass session management and suppression
- Overlay suppression when already shown
- BNet whisper dismissal tracking
- Lockdown state transitions and attribute handling
- LastUsed seeding from Blizzard attributes
- Queue PreShowCheck integration
- PRE_EDITBOX_SHOW filter for external addons (WIM, etc.)
- Ghost detection for sticky-chat restore
- Deferred overlay activation

**Replacement**:
- Keybind system handles primary show path through secure button PostClick script
- Overlay activation triggered directly by keybind overrides

**Potential Impact**:
- Loss of bypass session management
- Loss of lockdown state transitions
- Loss of Queue integration (PreShowCheck)
- Loss of external addon compatibility (WIM, PRE_EDITBOX_SHOW filter)
- Loss of ghost detection for sticky-chat restore
- Loss of BNet whisper dismissal tracking
- Loss of LastUsed seeding from Blizzard attributes

**Code Changes**:
- Commented out entire hooksecurefunc(blizzEditBox, "Show", ...) block
- Added comprehensive removal comment documenting lost functionality
- Hook preserved in comments for potential restoration

**RESTORED (2026-05-23)**:
- Minimal Show hook restored to catch programmatic opens (Friends list, addon calls)
- Keybind system only intercepts key presses; Show hook catches everything else
- Restored with basic guards: ignore if overlay shown, bypass mode, lockdown, or Queue handling
- Does not restore full original functionality (bypass session, ghost detection, etc.)

### 3. blizzEditBox.Hide Hook
**File**: `Src/EditBox/Hooks.lua`  
**Lines Removed**: 1611-1643  
**Date**: 2026-05-23  
**Reason**: Replaced by keybind system - hide tracking now handled through alternative mechanisms

**Original Functionality**:
- Hide tracking and bypass session cleanup
- Bypass session cleanup on editbox close
- BNet editbox dismissal tracking
- State machine return to IDLE when Blizzard box hidden

**Replacement**:
- Keybind system handles hide state through overlay lifecycle
- Alternative mechanisms for state machine management

**Potential Impact**:
- Loss of bypass session cleanup on editbox close
- Loss of BNet editbox dismissal tracking
- Loss of automatic state machine return to IDLE on hide

**Code Changes**:
- Commented out entire hooksecurefunc(blizzEditBox, "Hide", ...) block
- Added removal comment documenting lost functionality
- Hook preserved in comments for potential restoration

### 4. ChatFrameUtil.GetActiveWindow Hook
**File**: `Src/EditBoxCompat.lua`  
**Lines Modified**: 119-137  
**Date**: 2026-05-23  
**Reason**: Initially removed due to suspected conflicts with Chattynator, but restored with defensive checks

**Original Functionality**:
- Routed GetActiveWindow to Yapper's active editor when overlay was shown
- Under lockdown, fell back to native implementation
- Ensured compatibility with Shift-Clicking links and TRP3 link insertion
- Kept native secure chat state untainted

**Current State**: **RESTORED with defensive checks**
- Added additional check: `eb.OverlayEdit:HasFocus()` 
- Only returns Yapper's editor when overlay is shown AND has focus
- Reduces conflicts with addons that manage focus state
- Still falls back to native behavior during lockdown or bypass

**Reason for Restoration**:
- Item linking requires GetActiveWindow to return the correct editbox
- CHAT_FOCUS_OVERRIDE alone is insufficient for item link insertion
- Defensive focus check should prevent Chattynator conflicts

**Potential Impact**:
- Should restore item linking functionality
- May still have conflicts with Chattynator (testing needed)
- More defensive approach should reduce but not eliminate conflicts

**Code Changes**:
- Restored hook with additional `:HasFocus()` check
- Updated documentation to reflect defensive approach

---

## Future Hook Removal Candidates

### High Priority (Show-Hide Pipeline)
- `ChatFrameUtil.OpenChat` - Open chat interception and focus handling

### Medium Priority
- `blizzEditBox.SetAttribute` - Attribute tracking for chat type/target timing
- `blizzEditBox.SetText/Insert` - Text forwarding from Blizzard box to Yapper
- `blizzEditBox.SetGameLanguage` - Language mirroring

### Low Priority (Add-on Compatibility)
- `ChatFrameUtil.DeactivateChat` - Chattynator addon compatibility
- `ChatEdit_InsertLink` - TRP3 link insertion compatibility
- `FCF_SetFullScreenFrame / FCF_ClearFullScreenFrame` - Fullscreen chat feature
- `Interface.MainWindowFrame.Show/Hide` - Window visibility tracking

---

## Testing Notes

When testing hook removals, verify:
1. Keybind system still triggers overlay correctly
2. Lockdown transitions work properly
3. External addon compatibility (WIM, TRP3, etc.)
4. Re-whisper functionality through keybinds
5. Text synchronization between Blizzard box and Yapper
6. Channel switching and target handling
7. Bypass session functionality
8. BNet whisper handling
9. Queue integration (if still needed)
10. State machine transitions
