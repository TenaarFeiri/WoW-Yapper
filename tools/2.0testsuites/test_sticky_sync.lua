#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_sticky_sync.lua  —  Blizzard stickyType + post-lockdown LastUsed restore
-- Run from the repo root: lua tools/2.0testsuites/test_sticky_sync.lua
-- ---------------------------------------------------------------------------
-- Covers two layers of the Yapper -> ChatFrameNEditBox sync fix:
--
--   Layer 1 (root cause): SyncAttributesToBlizzard now writes stickyType so
--     Blizzard's own ResetChatTypeToSticky() (called from Deactivate on
--     handoff/ClearChat) reverts to the user's last channel instead of SAY.
--     Whispers are demoted out so a transient whisper can't become sticky.
--
--   Layer 2 (regression fix): the keybind post-lockdown path restores
--     LastUsed from the _preLockdownLastUsed stash, recovering the channel
--     the user was on before combat. Restores a safety net removed in 1ec4628
--     that was replaced by a comment referencing a never-implemented
--     ResyncFromBlizzardAfterLockdown function.
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
_G.hooksecurefunc = function() end

-- Controllable lockdown switches.
local chatLockdown = false
_G.InCombatLockdown = function() return false end
_G.C_ChatInfo = { InChatMessagingLockdown = function() return chatLockdown end }

-- ===========================================================================
-- Mock Blizzard editbox that records secure attributes
-- ===========================================================================

local function MockBlizzEditBox(name)
    local attrs = {}
    local f = { _name = name, _shown = false, _focused = false, _text = "" }
    function f:GetName() return self._name end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:IsShown() return self._shown end
    function f:SetFocus() self._focused = true end
    function f:ClearFocus() self._focused = false end
    function f:SetText(t) self._text = t or "" end
    function f:GetText() return self._text end
    function f:SetAttribute(key, value) attrs[key] = value end
    function f:GetAttribute(key) return attrs[key] end
    function f:UpdateHeader() end
    -- Simulate Blizzard's ResetChatTypeToSticky: SetChatType(GetStickyType())
    function f:SimulateDeactivate()
        local sticky = attrs["stickyType"] or "SAY"
        attrs["chatType"] = sticky
    end
    f._attrs = attrs
    return f
end

-- ===========================================================================
-- Build YapperTable and load Label.lua for Layer 1
-- ===========================================================================

local YapperTable = {}

YapperTable.Config = { System = { DEBUG = false }, EditBox = {} }

-- Stub EditBoxHooksCore with the locals Label.lua captures at load time.
YapperTable.EditBoxHooksCore = {
    CHATTYPE_TO_OVERRIDE_KEY = {
        SAY = "SAY", EMOTE = "EMOTE", YELL = "YELL",
        PARTY = "PARTY", PARTY_LEADER = "PARTY",
        RAID = "RAID", RAID_LEADER = "RAID", RAID_WARNING = "RAID_WARNING",
        INSTANCE_CHAT = "INSTANCE_CHAT", GUILD = "GUILD", OFFICER = "OFFICER",
        WHISPER = "WHISPER", BN_WHISPER = "BN_WHISPER", CHANNEL = "CHANNEL",
    },
    GROUP_CHAT_TYPES = { PARTY = true, RAID = true, INSTANCE_CHAT = true },
    BuildLabelText = function() return "label", 1, 1, 1 end,
    GetLabelUsableWidth = function() return 100 end,
    ResetLabelToBaseFont = function() end,
    TruncateLabelToWidth = function(_, label) return label end,
    FitLabelFontToWidth = function() return true end,
    UpdateLabelBackgroundForText = function() end,
}

YapperTable.Utils = {
    IsChatLockdown = function() return chatLockdown end,
    IsCombatLockdown = function() return false end,
    IsChatOrCombatLockdown = function() return chatLockdown end,
    IsUnambiguousBnetTarget = function() return false end,
    IsSecret = function() return false end,
    VerbosePrint = function() end,
    DebugPrint = function() end,
    Print = function() end,
}

YapperTable.Interface = { IsColourTable = function() return false end }

local EditBox = {}
YapperTable.EditBox = EditBox

local function loadModule(path)
    local loader, err = loadfile(path)
    if not loader then
        print("FATAL: cannot load " .. path .. ": " .. tostring(err))
        os.exit(1)
    end
    loader("Yapper", YapperTable)
end

loadModule("Src/Hooks/Label.lua")

-- ===========================================================================
-- Layer 1: SyncAttributesToBlizzard maintains stickyType
-- ===========================================================================
print("Layer 1: SyncAttributesToBlizzard maintains stickyType")

-- 1a: INSTANCE_CHAT is written to stickyType
do
    local blizz = MockBlizzEditBox("ChatFrame1EditBox")
    EditBox.OrigEditBox = blizz
    EditBox.ChatType = "INSTANCE_CHAT"
    EditBox.Target = nil
    EditBox.Language = nil
    EditBox:SyncAttributesToBlizzard()
    check("INSTANCE_CHAT: chatType written", blizz._attrs["chatType"] == "INSTANCE_CHAT")
    check("INSTANCE_CHAT: stickyType written", blizz._attrs["stickyType"] == "INSTANCE_CHAT")
end

-- 1b: PARTY_LEADER resolves to PARTY for stickyType
do
    local blizz = MockBlizzEditBox("ChatFrame1EditBox")
    EditBox.OrigEditBox = blizz
    EditBox.ChatType = "PARTY_LEADER"
    EditBox.Target = nil
    EditBox.Language = nil
    EditBox:SyncAttributesToBlizzard()
    check("PARTY_LEADER: chatType -> PARTY", blizz._attrs["chatType"] == "PARTY")
    check("PARTY_LEADER: stickyType -> PARTY", blizz._attrs["stickyType"] == "PARTY")
end

-- 1c: WHISPER does NOT write stickyType (demoted out)
do
    local blizz = MockBlizzEditBox("ChatFrame1EditBox")
    blizz._attrs["stickyType"] = "PARTY"  -- pre-existing sticky
    EditBox.OrigEditBox = blizz
    EditBox.ChatType = "WHISPER"
    EditBox.Target = "Alice"
    EditBox.Language = nil
    EditBox:SyncAttributesToBlizzard()
    check("WHISPER: chatType written", blizz._attrs["chatType"] == "WHISPER")
    check("WHISPER: tellTarget written", blizz._attrs["tellTarget"] == "Alice")
    check("WHISPER: stickyType NOT overwritten", blizz._attrs["stickyType"] == "PARTY")
end

-- 1d: BN_WHISPER does NOT write stickyType
do
    local blizz = MockBlizzEditBox("ChatFrame1EditBox")
    blizz._attrs["stickyType"] = "SAY"
    EditBox.OrigEditBox = blizz
    EditBox.ChatType = "BN_WHISPER"
    EditBox.Target = "Bob"
    EditBox.Language = nil
    EditBox:SyncAttributesToBlizzard()
    check("BN_WHISPER: stickyType NOT overwritten", blizz._attrs["stickyType"] == "SAY")
end

-- 1e: The dungeon regression — Deactivate reverts to stickyType, not SAY
do
    local blizz = MockBlizzEditBox("ChatFrame1EditBox")
    EditBox.OrigEditBox = blizz
    EditBox.ChatType = "INSTANCE_CHAT"
    EditBox.Target = nil
    EditBox.Language = nil
    EditBox:SyncAttributesToBlizzard()
    -- Simulate Blizzard's Deactivate: ResetChatTypeToSticky + ResetChatType
    blizz:SimulateDeactivate()
    check("dungeon regression: Deactivate reverts to INSTANCE_CHAT not SAY",
        blizz._attrs["chatType"] == "INSTANCE_CHAT")
end

-- 1f: SAY (the default) writes stickyType=SAY — no change in behavior
do
    local blizz = MockBlizzEditBox("ChatFrame1EditBox")
    EditBox.OrigEditBox = blizz
    EditBox.ChatType = "SAY"
    EditBox.Target = nil
    EditBox.Language = nil
    EditBox:SyncAttributesToBlizzard()
    check("SAY: stickyType = SAY", blizz._attrs["stickyType"] == "SAY")
end

-- ===========================================================================
-- Layer 2: Keybind post-lockdown LastUsed restore
-- ===========================================================================
print("\nLayer 2: Keybind post-lockdown LastUsed restore")

-- Rebuild a fresh YapperTable for the Keybinds test to avoid Label.lua's
-- EditBox methods interfering with the Keybinds mock EditBox.
local YapperTable2 = {}
YapperTable2.Config = { System = { DEBUG = false }, EditBox = {} }

YapperTable2.Utils = {
    IsChatLockdown = function() return chatLockdown end,
    DebugPrint = function() end,
    VerbosePrint = function() end,
}
YapperTable2.Events = { Register = function() end }

local function MockFrame2(name)
    local f = { _name = name, _shown = false, _scripts = {} }
    function f:GetName() return self._name end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:IsShown() return self._shown end
    function f:SetAttribute() end
    function f:RegisterForClicks() end
    function f:SetScript(s, fn) self._scripts[s] = fn end
    function f:GetScript(s) return self._scripts[s] end
    function f:SetFocus() self._focused = true end
    function f:ClearFocus() self._focused = false end
    return f
end

local function MockEditBox2(name)
    local eb = MockFrame2(name)
    eb._text = ""
    function eb:SetText(text) self._text = text or "" end
    function eb:GetText() return self._text end
    return eb
end

_G.GetBindingKey = function() return nil, nil end
_G.SetOverrideBindingClick = function() end
_G.ClearOverrideBindings = function() end
_G.ChatEdit_GetActiveWindow = function() return _G.DEFAULT_CHAT_FRAME.editBox end
_G.ChatFrameUtil = {
    GetActiveWindow = function() return _G.DEFAULT_CHAT_FRAME.editBox end,
    OpenChat = function() end,
}
_G.DEFAULT_CHAT_FRAME = {
    editBox = MockEditBox2("ChatFrame1EditBox"),
    AddMessage = function() end,
}
_G.ChatFrame1EditBox = _G.DEFAULT_CHAT_FRAME.editBox
_G.CreateFrame = function(frameType, name)
    if frameType == "EditBox" then return MockEditBox2(name) end
    return MockFrame2(name)
end

local overlay2 = MockFrame2("YapperOverlay")
local overlayEdit2 = MockEditBox2("YapperOverlayEditBox")
YapperTable2.EditBox = {
    Overlay = overlay2,
    OverlayEdit = overlayEdit2,
    LastUsed = { chatType = "SAY", target = nil, language = nil },
    Show = function(self) self.Overlay:Show() end,
    ApplyProgrammaticPrefill = function(self, text, box) box:SetText(text or "") end,
    UpdateFocusOverride = function(self) end,
}

local function loadModule2(path)
    local loader, err = loadfile(path)
    if not loader then
        print("FATAL: cannot load " .. path .. ": " .. tostring(err))
        os.exit(1)
    end
    loader("Yapper", YapperTable2)
end

loadModule2("Src/EditBox/Keybinds.lua")

local Keybinds = YapperTable2.EditBox.Keybinds
Keybinds:Init()

local function clickBinding(bindingName)
    overlay2:Hide()
    overlayEdit2:SetText("")
    local button = Keybinds._secureButtons[bindingName]
    local postClick = button and button:GetScript("PostClick")
    if not postClick then
        print("FATAL: missing PostClick for " .. tostring(bindingName))
        os.exit(1)
    end
    postClick(button)
end

-- 2a: During lockdown, the stash is captured. After lockdown ends, the next
-- keybind click restores LastUsed from the stash.
print("  Scenario: lockdown captures stash, post-lockdown restores it")

-- Pre-lockdown: user is on INSTANCE_CHAT, LastUsed reflects it.
chatLockdown = false
YapperTable2.EditBox.LastUsed = { chatType = "INSTANCE_CHAT", target = nil, language = nil }
Keybinds._preLockdownLastUsed = nil

-- Lockdown starts. The keybind click captures the stash and delegates to
-- Blizzard's OpenChat (no Show).
chatLockdown = true
clickBinding("OPENCHAT")
check("lockdown: stash captured chatType",
    Keybinds._preLockdownLastUsed and Keybinds._preLockdownLastUsed.chatType == "INSTANCE_CHAT")

-- While in lockdown, something clobbers LastUsed to SAY (simulating
-- Blizzard's Deactivate reverting chatType to the stale stickyType).
YapperTable2.EditBox.LastUsed = { chatType = "SAY", target = nil, language = nil }

-- Lockdown ends. The next keybind click should restore LastUsed from the stash.
chatLockdown = false
clickBinding("OPENCHAT")
check("post-lockdown: LastUsed.chatType restored to INSTANCE_CHAT",
    YapperTable2.EditBox.LastUsed.chatType == "INSTANCE_CHAT")
check("post-lockdown: stash cleared", Keybinds._preLockdownLastUsed == nil)

-- 2b: No stash -> no restore (steady state, no spurious writes)
print("  Scenario: no stash, no lockdown -> no spurious restore")
chatLockdown = false
Keybinds._preLockdownLastUsed = nil
YapperTable2.EditBox.LastUsed = { chatType = "PARTY", target = nil, language = nil }
clickBinding("OPENCHAT")
check("no stash: LastUsed unchanged",
    YapperTable2.EditBox.LastUsed.chatType == "PARTY")
check("no stash: stash still nil", Keybinds._preLockdownLastUsed == nil)

-- ===========================================================================
-- Results
-- ===========================================================================
print(("\nResults: %d/%d passed"):format(TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    os.exit(1)
end
