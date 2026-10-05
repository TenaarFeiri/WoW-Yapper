#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_whisper_tab_target.lua — Whisper/BNet whisper tab targeting tests
-- Run from the repo root:  lua tools/2.0testsuites/test_whisper_tab_target.lua
--
-- Regression coverage for BNet whisper tabs sending to /say:
--
--   Temporary whisper tabs carry routing in chatFrame.chatType/chatTarget,
--   but BN_WHISPER tabs can hold a "|K...|k" presence token (or a secret
--   value) there — SanitizeTarget must reject both, which used to collapse
--   every whisper-tab open to SAY.  EditBox:ResolveWhisperFrameTarget
--   recovers the numeric BNet account ID via BNet_GetBNetIDAccount, and
--   Show()'s fallback now consults the chat window the user is actually
--   looking at (selected window / dock-selected tab) so repeat Enter
--   presses keep targeting the whisper instead of falling back to LastUsed
--   (whispers are intentionally never persisted into LastUsed).
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
-- Minimal WoW environment mock (same shape as test_lockdown_fsm.lua)
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

_G.InCombatLockdown = function() return false end
_G.C_ChatInfo = { InChatMessagingLockdown = function() return false end }
_G.issecretvalue = function(value)
    return type(value) == "number" and value == 777
end
_G.canaccessvalue = function(value)
    return value ~= 777
end

_G.ChatFrameUtil = {
    SetChatFocusOverride = function() end,
    ClearChatFocusOverride = function() end,
    DeactivateChat = function() end,
    OpenChat = function() end,
}

_G.C_Timer = {
    NewTimer = function() return { Cancel = function() end } end,
    NewTicker = function() return { Cancel = function() end } end,
    After = function() end,
}

local function MockFontString()
    local fs = { _text = "" }
    function fs:SetText(t) self._text = t end
    function fs:GetText() return self._text end
    function fs:GetStringWidth() return #self._text * 7 end
    function fs:SetFont() end
    function fs:GetFont() return "Fonts\\FRIZQT__.TTF", 14, "" end
    function fs:SetTextColor() end
    function fs:SetWidth() end
    function fs:SetJustifyH() end
    function fs:SetPoint() end
    return fs
end

local function MockFrame(name)
    local f = {
        _name = name, _shown = false, _points = {}, _parent = nil, _scale = 1,
        _left = 10, _bottom = 30, _top = 60, _width = 390, _height = 30,
    }
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
    function f:GetLeft() return self._left end
    function f:GetRight() return self._left + self._width end
    function f:GetTop() return self._top end
    function f:GetBottom() return self._bottom end
    function f:GetWidth() return self._width end
    function f:GetHeight() return self._height end
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
    f._attrs = {}
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
    function f:SetAttribute(k, v) self._attrs[k] = v end
    function f:GetAttribute(k) return self._attrs[k] end
    return f
end

_G.UIParent = MockFrame("UIParent")
_G.UIParent:Show()
_G.CreateFrame = function(frameType, name)
    if frameType == "EditBox" then return MockEditBoxFrame(name) end
    return MockFrame(name)
end
_G.hooksecurefunc = function() end

-- ===========================================================================
-- Chat frame fixtures
-- ===========================================================================

local function MockChatFrame(name, chatType, chatTarget)
    local eb = MockEditBoxFrame(name .. "EditBox")
    local f = MockFrame(name)
    f.editBox = eb
    eb.chatFrame = f
    f.chatType = chatType
    f.chatTarget = chatTarget
    f.isTemporary = (chatType == "WHISPER" or chatType == "BN_WHISPER") or nil
    return f, eb
end

local mainFrame, mainEB = MockChatFrame("ChatFrame1", nil, nil)
_G.DEFAULT_CHAT_FRAME = mainFrame
_G.DEFAULT_CHAT_FRAME.AddMessage = function() end
_G.ChatFrame1EditBox = mainEB
mainFrame:Show()

-- BNet whisper tab carrying a |K-protected presence token (the reported
-- failure mode: SanitizeTarget must reject it, so Yapper fell back to SAY).
local bnFrame, bnEB = MockChatFrame("ChatFrame4", "BN_WHISPER", "|Kf42|k")
-- Plain-name whisper tab.
local whisperFrame, whisperEB = MockChatFrame("ChatFrame5", "WHISPER", "Alice")
-- BNet whisper tab with a plain account-name target.
local bnNameFrame = MockChatFrame("ChatFrame6", "BN_WHISPER", "Carol#1234")
-- A non-temporary frame that transiently reports WHISPER (SendTell race).
local fakeWhisperFrame = MockChatFrame("ChatFrame7", "WHISPER", "Bob")
fakeWhisperFrame.isTemporary = false

-- The C API consumes |K tokens/secrets Lua can't read and returns the ID.
_G.BNet_GetBNetIDAccount = function(token)
    if token == "|Kf42|k" then return 42 end
    return nil
end

-- "What the user is looking at" globals used by the Show() fallback.
_G.SELECTED_CHAT_FRAME = mainFrame
_G.GENERAL_CHAT_DOCK = { _selected = mainFrame }
_G.FCFDock_GetSelectedWindow = function(dock) return dock._selected end

-- ===========================================================================
-- Build YapperTable and load the real modules
-- ===========================================================================

local YapperTable = {}

YapperTable.Config = {
    System = { DEBUG = false },
    EditBox = {},
}

YapperTable.History = {
    SaveDraft = function() end,
    MarkDirty = function() end,
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

local function loadModule(path)
    local loader, err = loadfile(path)
    if not loader then
        print("FATAL: cannot load " .. path .. ": " .. tostring(err))
        os.exit(1)
    end
    loader("Yapper", YapperTable)
end

loadModule("Src/Utils.lua")
YapperTable.Utils.Print = function() end
YapperTable.Utils.DebugPrint = function() end
YapperTable.Utils.VerbosePrint = function() end
YapperTable.Utils.GetChatParent = function() return _G.UIParent end

loadModule("Src/State.lua")
loadModule("Src/Spellcheck/Recolour.lua")
loadModule("Src/Policies/ChannelPolicy.lua")
loadModule("Src/EditBox.lua")
loadModule("Src/Hooks/ShowHide.lua")

local EditBox = YapperTable.EditBox
local State = YapperTable.State

EditBox.CreateOverlay = function(self)
    if self.Overlay then return end
    self.Overlay = MockFrame("YapperOverlay")
    self.OverlayEdit = MockEditBoxFrame("YapperOverlayEditBox")
    self.ChannelLabel = MockFontString()
    self.LabelBg = MockFrame("YapperLabelBg")
end
EditBox.RefreshLabel = function() end

local function ResetEditBox()
    if EditBox.Overlay and EditBox.Overlay:IsShown() then
        EditBox:Hide()
    end
    EditBox.ChatType = nil
    EditBox.Target = nil
    EditBox.Language = nil
    EditBox.ChannelName = nil
    EditBox.LastUsed = { chatType = "SAY" }
    EditBox._attrCache = {}
    EditBox._pendingTabSwitch = nil
    EditBox._incomingWhisperAffinity = nil
    State:ToIdle()
end

-- ===========================================================================
-- 1. ResolveWhisperFrameTarget unit checks
-- ===========================================================================
print("\nTest 1: ResolveWhisperFrameTarget")

local t, target = EditBox:ResolveWhisperFrameTarget(bnFrame)
check("BN whisper |K token resolves to account ID",
    t == "BN_WHISPER" and target == 42)

t, target = EditBox:ResolveWhisperFrameTarget(whisperFrame)
check("plain whisper tab resolves name",
    t == "WHISPER" and target == "Alice")

t, target = EditBox:ResolveWhisperFrameTarget(bnNameFrame)
check("plain BN name target passes through",
    t == "BN_WHISPER" and target == "Carol#1234")

t, target = EditBox:ResolveWhisperFrameTarget(mainFrame)
check("non-whisper frame resolves nil", t == nil and target == nil)

t, target = EditBox:ResolveWhisperFrameTarget(fakeWhisperFrame)
check("non-temporary whisper frame resolves nil", t == nil and target == nil)

t, target = EditBox:ResolveWhisperFrameTarget(nil)
check("nil frame resolves nil", t == nil and target == nil)

local noTargetFrame = MockChatFrame("ChatFrame8", "WHISPER", nil)
t, target = EditBox:ResolveWhisperFrameTarget(noTargetFrame)
check("whisper frame without target resolves nil", t == nil and target == nil)

-- ===========================================================================
-- 2. Show() resolves the selected BN whisper tab (classic-mode open)
-- ===========================================================================
print("\nTest 2: Show() adopts the selected whisper tab")

ResetEditBox()
bnFrame:Show()                      -- the whisper tab is what's on screen
_G.SELECTED_CHAT_FRAME = bnFrame
EditBox:Show(mainEB)
check("open on whisper tab -> BN_WHISPER", EditBox.ChatType == "BN_WHISPER")
check("numeric BNet target adopted",
    EditBox.Target == 42 or EditBox.Target == "42")
check("overlay anchored on the main editbox", EditBox.OrigEditBox == mainEB)
EditBox:Hide()

-- Repeat the open with no new state (pendingTabSwitch consumed by the first
-- open): the selected tab must still win over the SAY LastUsed.
ResetEditBox()
EditBox:Show(mainEB)
check("second open keeps BN_WHISPER (no /say collapse)",
    EditBox.ChatType == "BN_WHISPER")
check("second open keeps the target",
    EditBox.Target == 42 or EditBox.Target == "42")
EditBox:Hide()

-- A plain whisper tab behaves the same via the normal target path.
ResetEditBox()
whisperFrame:Show()
_G.SELECTED_CHAT_FRAME = whisperFrame
EditBox:Show(mainEB)
check("open on whisper tab -> WHISPER", EditBox.ChatType == "WHISPER")
check("whisper target adopted", EditBox.Target == "Alice")
EditBox:Hide()

-- ===========================================================================
-- 3. Selected normal tab does NOT get hijacked by a background whisper tab
-- ===========================================================================
print("\nTest 3: visible normal tab stays SAY")

ResetEditBox()
_G.SELECTED_CHAT_FRAME = mainFrame
GENERAL_CHAT_DOCK._selected = mainFrame
-- The whisper tab still exists in the dock but isn't selected/shown.
bnFrame:Hide()
EditBox:Show(mainEB)
check("normal tab open -> SAY", EditBox.ChatType == "SAY")
check("no target leaked", EditBox.Target == nil)
EditBox:Hide()

-- A docked-but-unselected whisper frame must not hijack either.
ResetEditBox()
bnFrame:Show()                       -- still exists
_G.SELECTED_CHAT_FRAME = mainFrame  -- user is looking at the main tab
EditBox:Show(mainEB)
check("unselected whisper tab does not hijack", EditBox.ChatType == "SAY")
check("unselected whisper tab leaks no target", EditBox.Target == nil)
EditBox:Hide()

-- ===========================================================================
-- 4. IM-style open: the editbox's own frame is the whisper tab
-- ===========================================================================
print("\nTest 4: IM-style open on the whisper tab's own editbox")

ResetEditBox()
_G.SELECTED_CHAT_FRAME = mainFrame
bnFrame:Show()
EditBox:Show(bnEB)
check("whisper editbox open -> BN_WHISPER", EditBox.ChatType == "BN_WHISPER")
check("whisper editbox target adopted",
    EditBox.Target == 42 or EditBox.Target == "42")
EditBox:Hide()

-- ===========================================================================
-- 5. pendingTabSwitch (tab click while closed) resolves BN routing
-- ===========================================================================
print("\nTest 5: pendingTabSwitch carries BN routing")

ResetEditBox()
EditBox._pendingTabSwitch = {
    chatType  = "BN_WHISPER",
    target    = 42,
    chatFrame = bnFrame,
    editBox   = bnEB,
}
EditBox:Show(mainEB)
check("pending whisper switch -> BN_WHISPER", EditBox.ChatType == "BN_WHISPER")
check("pending switch target adopted",
    EditBox.Target == 42 or EditBox.Target == "42")
EditBox:Hide()

-- ===========================================================================
-- Summary
-- ===========================================================================
print(string.rep("-", 60))
print(string.format("Results: %d/%d passed", TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    print(FAILURES .. " FAILURE(S)")
    os.exit(1)
else
    print("All tests passed!")
end
