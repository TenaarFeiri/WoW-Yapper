#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_lockdown_fsm.lua  —  Lockdown handoff state machine tests
-- Run from the repo root:  lua tools/2.0testsuites/test_lockdown_fsm.lua
-- ---------------------------------------------------------------------------
-- Loads the REAL Src/State.lua, Src/Utils.lua, Src/EditBox.lua and
-- Src/Hooks/ShowHide.lua and exercises the combat/lockdown handoff FSM:
--
--   1. _lockdown flag defaults
--   2. UpdateFocusOverride truth table (lockdown x combat x overlay x handedOff)
--   3. HandoffToBlizzard sets handedOff BEFORE clearing the focus override
--      (regression: the flag was write-never after the 348668e file split,
--      leaving a stale CHAT_FOCUS_OVERRIDE pointing at the hidden overlay,
--      which silently ate Enter presses around lockdown events)
--   4. HandoffToBlizzard saves a lockdown draft and enters LOCKDOWN state
--   5. Show() resets handedOff so a stale flag can't leak into the next open
--   6. ClearLockdownState cancels timers and resets transient flags
-- ---------------------------------------------------------------------------

local PASS, FAIL, TESTS, FAILURES = "PASS", "FAIL", 0, 0

local function check(label, condition)
    TESTS = TESTS + 1
    if condition then
        print("  [" .. PASS .. "] " .. label)
    else
        FAILURES = FAILURES + 1
        print("  [" .. FAIL .. "] " .. label)
    end
end

-- ===========================================================================
-- Minimal WoW environment mock
-- ===========================================================================

_G.date = os.date
_G.GetTime = function() return 100 end
_G.UnitGUID = function() return "Player-1-AABBCCDD" end
_G.IsInGroup = function() return false end
_G.IsInRaid = function() return false end
_G.IsInGuild = function() return false end
_G.IsInInstance = function() return false end
_G.LE_PARTY_CATEGORY_HOME = 1
_G.LE_PARTY_CATEGORY_INSTANCE = 2

-- Combat / chat lockdown switches the tests flip directly.
local combatLockdown = false
local chatLockdown = false
_G.InCombatLockdown = function() return combatLockdown end
_G.C_ChatInfo = { InChatMessagingLockdown = function() return chatLockdown end }

-- Focus override spy: records the current override target.
local focusOverride = nil
_G.ChatFrameUtil = {
    SetChatFocusOverride = function(box) focusOverride = box end,
    ClearChatFocusOverride = function() focusOverride = nil end,
    GetChatFocusOverride = function() return focusOverride end,
    DeactivateChat = function() end,
    OpenChat = function() end,
}

-- Controllable timers.
local pendingTimers = {}
_G.C_Timer = {
    NewTimer = function(duration, callback)
        local t = { duration = duration, callback = callback, _cancelled = false }
        t.Cancel = function(self) self._cancelled = true end
        pendingTimers[#pendingTimers + 1] = t
        return t
    end,
    NewTicker = function(duration, callback)
        local t = { duration = duration, callback = callback, _cancelled = false, _ticker = true }
        t.Cancel = function(self) self._cancelled = true end
        pendingTimers[#pendingTimers + 1] = t
        return t
    end,
    After = function(duration, callback)
        pendingTimers[#pendingTimers + 1] =
            { duration = duration, callback = callback, _cancelled = false, Cancel = function(self) self._cancelled = true end }
    end,
}

local function MockFontString()
    local fs = { _text = "", _font = { "Fonts\\FRIZQT__.TTF", 14, "" } }
    function fs:SetText(t) self._text = t end
    function fs:GetText() return self._text end
    function fs:GetStringWidth() return #self._text * 7 end
    function fs:SetFont(f, s, fl) self._font = { f, s, fl } end
    function fs:GetFont() return self._font[1], self._font[2], self._font[3] end
    function fs:SetTextColor() end
    function fs:SetWidth() end
    function fs:SetJustifyH() end
    function fs:SetPoint() end
    return fs
end

local function MockFrame(name)
    local f = { _name = name, _shown = false, _points = {}, _parent = nil, _scale = 1 }
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:IsShown() return self._shown end
    function f:GetName() return self._name end
    function f:SetParent(p) self._parent = p end
    function f:GetParent() return self._parent end
    function f:ClearAllPoints() self._points = {} end
    function f:SetPoint(point, relTo, relPoint, x, y)
        self._points[#self._points + 1] = { point, relTo, relPoint, x, y }
    end
    function f:GetNumPoints() return #self._points end
    function f:GetPoint(i)
        local p = self._points[i]
        if not p then return nil end
        return p[1], p[2], p[3], p[4], p[5]
    end
    function f:SetScale(s) self._scale = s end
    function f:GetScale() return self._scale end
    function f:GetEffectiveScale() return self._scale end
    function f:GetLeft() return 10 end
    function f:GetRight() return 400 end
    function f:GetTop() return 60 end
    function f:GetBottom() return 30 end
    function f:GetWidth() return 390 end
    function f:GetHeight() return 30 end
    function f:SetWidth() end
    function f:SetHeight() end
    function f:SetFrameLevel() end
    function f:GetFrameLevel() return 1 end
    function f:SetFrameStrata() end
    function f:EnableMouse() end
    function f:SetAlpha() end
    function f:RegisterEvent() end
    function f:SetScript() end
    function f:HookScript() end
    return f
end

local function MockEditBoxFrame(name)
    local f = MockFrame(name)
    f._text = ""
    f._focused = false
    function f:SetText(t) self._text = t or "" end
    function f:GetText() return self._text end
    function f:SetFocus() self._focused = true end
    function f:ClearFocus() self._focused = false end
    function f:HasFocus() return self._focused end
    function f:SetCursorPosition() end
    function f:GetFont() return "Fonts\\FRIZQT__.TTF", 14, "" end
    function f:SetFont() end
    function f:Deactivate() self._shown = false end
    function f:SetTextColor() end
    return f
end

_G.UIParent = MockFrame("UIParent")
_G.UIParent:Show()
_G.CreateFrame = function(frameType, name)
    if frameType == "EditBox" then return MockEditBoxFrame(name) end
    return MockFrame(name)
end
_G.hooksecurefunc = function() end
_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end, editBox = MockEditBoxFrame("ChatFrame1EditBox") }
_G.ChatFrame1EditBox = _G.DEFAULT_CHAT_FRAME.editBox

-- ===========================================================================
-- Build YapperTable and load the real modules
-- ===========================================================================

local YapperTable = {}

YapperTable.Config = {
    System = { DEBUG = false },
    EditBox = {},
}

-- Stub the modules ShowHide only touches through guarded calls.
local savedDrafts = {}
YapperTable.History = {
    SaveDraft = function(_, editBox) savedDrafts[#savedDrafts + 1] = editBox:GetText() end,
    MarkDirty = function() end,
    LoadDraft = function() return savedDrafts[#savedDrafts] or "" end,
    GetDraft = function() return nil end,
    ClearDraft = function() end,
}
YapperTable.Core = {
    GetCharacterLanguage = function(_, v) return v end,
}
YapperTable.EditBoxHooksCore = {
    ResolveChannelName = function() return nil end,
    IsWhisperSlashPrefill = function() return false end,
    ParseWhisperSlash = function() return nil end,
    RefreshOverlayVisuals = function() end,
}

local function loadModule(path, ...)
    local loader, err = loadfile(path)
    if not loader then
        print("FATAL: cannot load " .. path .. ": " .. tostring(err))
        os.exit(1)
    end
    loader("Yapper", YapperTable)
end

loadModule("Src/Utils.lua")
-- Silence prints from the real Utils.
YapperTable.Utils.Print = function() end
YapperTable.Utils.DebugPrint = function() end
YapperTable.Utils.VerbosePrint = function() end
YapperTable.Utils.GetChatParent = function() return _G.UIParent end
YapperTable.Utils.MakeFullscreenAware = function() end

loadModule("Src/State.lua")
loadModule("Src/EditBox.lua")

-- YapperAPI global used by ShowHide/EditBox for state transitions.
_G.YapperAPI = {
    SetState = function(_, s)
        local State = YapperTable.State
        if s == "IDLE" and State.ToIdle then State:ToIdle()
        elseif s == "EDITING" and State.ToEditing then State:ToEditing()
        elseif s == "LOCKDOWN" and State.ToLockdown then State:ToLockdown()
        elseif State.To and State.To then
            -- fall through: unknown state names are ignored in tests
        end
        _G.YapperAPI._lastState = s
    end,
}

loadModule("Src/Hooks/ShowHide.lua")

local EditBox = YapperTable.EditBox

-- Attach mock overlay widgets; CreateOverlay is defined in Overlay.lua,
-- which pulls in far more UI surface than this FSM test needs.
EditBox.CreateOverlay = function(self)
    if self.Overlay then return end
    self.Overlay = MockFrame("YapperOverlay")
    self.OverlayEdit = MockEditBoxFrame("YapperOverlayEditBox")
    self.ChannelLabel = MockFontString()
    self.LabelBg = MockFrame("YapperLabelBg")
end
EditBox.RefreshLabel = function() end

local blizzBox = MockEditBoxFrame("ChatFrame1EditBox")
blizzBox:Show()

local function ResetWorld()
    combatLockdown = false
    chatLockdown = false
    focusOverride = nil
    pendingTimers = {}
    savedDrafts = {}
    if EditBox.Overlay then EditBox.Overlay:Hide() end
    EditBox._lockdown.handedOff = false
    EditBox._lockdown.savedDraft = false
    EditBox._lockdown.eventRunning = false
    YapperAPI:SetState("IDLE")
end

-- ===========================================================================
-- 1. Defaults
-- ===========================================================================
print("\nTest 1: _lockdown defaults")

check("handedOff defaults false", EditBox._lockdown.handedOff == false)
check("savedDraft defaults false", EditBox._lockdown.savedDraft == false)
check("eventRunning defaults false", EditBox._lockdown.eventRunning == false)

-- ===========================================================================
-- 2. UpdateFocusOverride truth table
-- ===========================================================================
print("\nTest 2: UpdateFocusOverride truth table")

ResetWorld()
EditBox:Show(blizzBox)
EditBox:UpdateFocusOverride()  -- keybind pipeline calls this right after Show
check("open: overlay shown", EditBox.Overlay:IsShown())
check("open (keybind pipeline): focus override -> OverlayEdit", focusOverride == EditBox.OverlayEdit)

-- Combat starts while overlay is open and NOT handed off: override must stay
-- so the user can finish typing during the idle grace window.
combatLockdown = true
EditBox:UpdateFocusOverride()
check("combat + overlay active: override kept", focusOverride == EditBox.OverlayEdit)

-- Same, but the overlay has been handed off: override must clear.
EditBox._lockdown.handedOff = true
EditBox:UpdateFocusOverride()
check("combat + handed off: override cleared", focusOverride == nil)

-- Chat lockdown with overlay closed: override must clear.
ResetWorld()
chatLockdown = true
EditBox:UpdateFocusOverride()
check("chat lockdown + overlay closed: override cleared", focusOverride == nil)

-- No lockdown at all: override set (steady state).
ResetWorld()
EditBox:Show(blizzBox)
EditBox:Hide()
EditBox:UpdateFocusOverride()
check("no lockdown: override set (steady state)", focusOverride == EditBox.OverlayEdit)

-- ===========================================================================
-- 3. HandoffToBlizzard clears the focus override (the 348668e regression)
-- ===========================================================================
print("\nTest 3: HandoffToBlizzard focus override + handedOff")

ResetWorld()
EditBox:Show(blizzBox)
EditBox.OverlayEdit:SetText("half-typed message during a boss pull")
combatLockdown = true
chatLockdown = true

EditBox:HandoffToBlizzard()

check("handoff: handedOff = true", EditBox._lockdown.handedOff == true)
check("handoff: focus override cleared (OpenChat fallback must not target the hidden overlay)",
    focusOverride == nil)
check("handoff: overlay hidden", not EditBox.Overlay:IsShown())
check("handoff: state = LOCKDOWN", YapperAPI._lastState == "LOCKDOWN")
-- Regression: Hide(true) used to SetText+SetFocus the Blizzard editbox
-- unconditionally, re-activating the (proxy-mode) skin frame right after
-- DeactivateChat closed it. bypassOpen defaults true: Blizzard's box must
-- stay untouched until the user presses Enter after combat.
check("handoff (bypassOpen): Blizzard editbox not focused", blizzBox._focused == false)
check("handoff (bypassOpen): Blizzard editbox text untouched", blizzBox:GetText() == "")

-- ===========================================================================
-- 4. Handoff draft semantics
-- ===========================================================================
print("\nTest 4: Handoff draft semantics")

check("handoff: draft saved", savedDrafts[#savedDrafts] == "half-typed message during a boss pull")
check("handoff: savedDraft flag set", EditBox._lockdown.savedDraft == true)
check("handoff: overlay text cleared", EditBox.OverlayEdit:GetText() == "")

-- Empty-text handoff: no draft, but still hands off.
ResetWorld()
EditBox:Show(blizzBox)
EditBox.OverlayEdit:SetText("")
combatLockdown = true
chatLockdown = true
local draftsBefore = #savedDrafts
EditBox:HandoffToBlizzard()
check("empty handoff: no draft saved", #savedDrafts == draftsBefore)
check("empty handoff: handedOff still true", EditBox._lockdown.handedOff == true)

-- ===========================================================================
-- 5. Show() ends the handoff
-- ===========================================================================
print("\nTest 5: Show() resets handedOff")

ResetWorld()
EditBox._lockdown.handedOff = true  -- stale, e.g. lockdown outlived recovery poll
EditBox:Show(blizzBox)
EditBox:UpdateFocusOverride()  -- keybind pipeline calls this right after Show
check("reopen: handedOff reset to false", EditBox._lockdown.handedOff == false)
check("reopen (keybind pipeline): focus override -> OverlayEdit", focusOverride == EditBox.OverlayEdit)

-- The reset matters at the NEXT lockdown start: UpdateFocusOverride while the
-- overlay is open mid-combat must keep the override (grace window), which a
-- stale handedOff=true would break.
combatLockdown = true
EditBox:UpdateFocusOverride()
check("next lockdown start: grace window intact after reopen", focusOverride == EditBox.OverlayEdit)

-- ===========================================================================
-- 6. ClearLockdownState
-- ===========================================================================
print("\nTest 6: ClearLockdownState")

ResetWorld()
EditBox._lockdown.idleTimer = _G.C_Timer.NewTimer(1.5, function() end)
EditBox._lockdown.ticker = _G.C_Timer.NewTicker(0.1, function() end)
EditBox._lockdown.eventRunning = true
EditBox:ClearLockdownState()
check("timers cancelled", pendingTimers[1]._cancelled and pendingTimers[2]._cancelled)
check("idleTimer/ticker fields nil", EditBox._lockdown.idleTimer == nil and EditBox._lockdown.ticker == nil)
check("eventRunning reset", EditBox._lockdown.eventRunning == false)

-- ===========================================================================
print("\n" .. string.rep("-", 50))
print(string.format("Results: %d/%d passed", TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    print(FAILURES .. " FAILURE(S)")
    os.exit(1)
end
print("All tests passed.")
