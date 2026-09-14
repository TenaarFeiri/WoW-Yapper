#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_keybinds.lua  —  Keybind open-path regression tests
-- Run from the repo root: lua tools/2.0testsuites/test_keybinds.lua
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

local function MockFrame(name)
    local f = { _name = name, _shown = false, _scripts = {} }
    function f:GetName() return self._name end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:IsShown() return self._shown end
    function f:SetAttribute() end
    function f:RegisterForClicks() end
    function f:SetScript(scriptName, fn) self._scripts[scriptName] = fn end
    function f:GetScript(scriptName) return self._scripts[scriptName] end
    function f:SetFocus() self._focused = true end
    function f:ClearFocus() self._focused = false end
    return f
end

local function MockEditBox(name)
    local eb = MockFrame(name)
    eb._text = ""
    function eb:SetText(text) self._text = text or "" end
    function eb:GetText() return self._text end
    return eb
end

_G.InCombatLockdown = function() return false end
_G.GetBindingKey = function()
    return nil, nil
end
_G.SetOverrideBindingClick = function() end
_G.ClearOverrideBindings = function() end
_G.ChatEdit_GetActiveWindow = function() return _G.DEFAULT_CHAT_FRAME.editBox end
_G.ChatFrameUtil = {
    GetActiveWindow = function() return _G.DEFAULT_CHAT_FRAME.editBox end,
    OpenChat = function() end,
}
_G.DEFAULT_CHAT_FRAME = {
    editBox = MockEditBox("ChatFrame1EditBox"),
    AddMessage = function() end,
}
_G.ChatFrame1EditBox = _G.DEFAULT_CHAT_FRAME.editBox
_G.CreateFrame = function(frameType, name)
    if frameType == "EditBox" then
        return MockEditBox(name)
    end
    return MockFrame(name)
end

local YapperTable = {}
YapperTable.Utils = {
    IsChatLockdown = function() return false end,
    IsChatOrCombatLockdown = function() return false end,
    SanitizeTarget = function(_, value) return value end,
    DebugPrint = function() end,
    VerbosePrint = function() end,
}
YapperTable.Events = {
    Register = function() end,
}

local overlay = MockFrame("YapperOverlay")
local overlayEdit = MockEditBox("YapperOverlayEditBox")
YapperTable.EditBox = {
    Overlay = overlay,
    OverlayEdit = overlayEdit,
    LastUsed = { chatType = "SAY", target = nil, language = nil },
    Show = function(self)
        self.Overlay:Show()
    end,
    UpdateFocusOverride = function(self)
        self._focusOverrideUpdated = true
    end,
}

local function loadModule(path)
    local loader, err = loadfile(path)
    if not loader then
        print("FATAL: cannot load " .. path .. ": " .. tostring(err))
        os.exit(1)
    end
    loader("Yapper", YapperTable)
end

loadModule("Src/EditBox/Keybinds.lua")

local Keybinds = YapperTable.EditBox.Keybinds
Keybinds:Init()

local function clickBinding(bindingName, capturedText)
    overlay:Hide()
    overlayEdit:SetText("")
    YapperTable.EditBox._focusOverrideUpdated = false

    local button = Keybinds._secureButtons[bindingName]
    local postClick = button and button:GetScript("PostClick")
    if not postClick then
        print("FATAL: missing PostClick for " .. tostring(bindingName))
        os.exit(1)
    end
    postClick(button)
end

print("Test 1: OPENCHAT opens cleanly without a focus trap")
clickBinding("OPENCHAT")
check("plain open leaves text empty", overlayEdit:GetText() == "")
check("plain open updates focus override", YapperTable.EditBox._focusOverrideUpdated == true)
check("plain open shows overlay", overlay:IsShown())

print("\nTest 2: OPENCHATSLASH does not manually pre-fill (physical char does it)")
clickBinding("OPENCHATSLASH")
check("slash open does not double-fill", overlayEdit:GetText() == "")
check("slash open still shows overlay", overlay:IsShown())
check("slash open still updates focus override", YapperTable.EditBox._focusOverrideUpdated == true)

print("\nTest 3: OPENCHATSLASH does not require focus-trap state")
YapperTable.EditBox._focusTrap = nil
YapperTable.EditBox._focusTrapText = "stale"
clickBinding("OPENCHATSLASH")
check("slash open ignores stale focus-trap text", overlayEdit:GetText() == "")

print("\nTest 4: REPLY uses the safe target resolver")
YapperTable.EditBox.GetLastTellTargetInfo = function() return "WHISPER", "Alice" end
clickBinding("REPLY")
check("reply opens overlay", overlay:IsShown())
check("reply selects incoming whisper type", YapperTable.EditBox.ChatType == "WHISPER")
check("reply selects incoming whisper target", YapperTable.EditBox.Target == "Alice")

print("\nTest 5: secret/unavailable REPLY is a clean no-op")
YapperTable.EditBox.GetLastTellTargetInfo = function() return nil, nil end
clickBinding("REPLY")
check("unavailable reply does not open overlay", not overlay:IsShown())

print("\nTest 6: REPLYTELL2 uses the outgoing target resolver")
YapperTable.EditBox.GetLastToldTargetInfo = function() return "WHISPER", "Bob" end
clickBinding("REPLYTELL2")
check("re-whisper selects outgoing whisper target", YapperTable.EditBox.Target == "Bob")

print("\nTest 7: overrides yield keys claimed by an active binding context")
-- Simulate the housing decor context claiming R while REPLY is bound to R.
-- Overrides are per-button: ClearOverrideBindings(owner) must only clear
-- that owner's keys, mirroring the real API.
local overridden = {}
_G.SetOverrideBindingClick = function(owner, isPriority, key)
    overridden[owner] = overridden[owner] or {}
    overridden[owner][key] = true
end
_G.ClearOverrideBindings = function(owner)
    overridden[owner] = {}
end
_G.Enum = { BindingContext = { None = 0, HousingEditorBasicAndExpertDecorMode = 7 } }
local contextActive = false
local decorSelected = false
_G.C_KeyBindings = {
    IsBindingContextActive = function(ctx) return contextActive and ctx ~= 0 end,
    GetBindingByKey = function(key, ctx)
        if ctx == 7 and key == "R" then return "HOUSING_REMOVEDECOR" end
        return "NONE"
    end,
}
_G.C_HousingDecor = {
    IsDecorSelected = function() return decorSelected end,
}
_G.GetBindingKey = function(action)
    if action == "REPLY" then return "R" end
    return nil
end

local replyButton = Keybinds._secureButtons["REPLY"]
local function replyOverridden()
    return overridden[replyButton] and overridden[replyButton]["R"] == true
end

-- Selection state is tracked from event payloads in-game; drive it directly.
Keybinds._decorSelectionObserved = true
local function setDecorSelected(v)
    Keybinds._decorSelected = v
end

contextActive = true
setDecorSelected(true)
Keybinds:RegisterOverrides()
check("context-claimed key is not overridden while decor selected", not replyOverridden())

setDecorSelected(false)
Keybinds:RefreshOverrides()
check("key keeps its chat meaning when no decor is selected", replyOverridden())

setDecorSelected(true)
Keybinds:RefreshOverrides()
check("key is yielded again when decor is re-selected", not replyOverridden())

contextActive = false
Keybinds:RefreshOverrides()
check("key is overridden once the context is inactive", replyOverridden())

contextActive = true
Keybinds:RefreshOverrides()
check("key is yielded again when the context reactivates", not replyOverridden())

-- Context sync must also apply under lockdown: SyncContextYields skips the
-- combat/chat-lockdown deferral because clearing an override is safe.
YapperTable.Utils.IsChatLockdown = function() return true end
setDecorSelected(false)
Keybinds:SyncContextYields()
check("context sync still applies under chat lockdown", replyOverridden())
setDecorSelected(true)
Keybinds:SyncContextYields()
check("yield applies under chat lockdown", not replyOverridden())
YapperTable.Utils.IsChatLockdown = function() return false end

-- Before any selection event is observed, the C API fallback is used; an
-- erroring/unusable return must not leave the key unbound (fail = stay live).
Keybinds._decorSelectionObserved = false
_G.C_HousingDecor.IsDecorSelected = function() error("restricted") end
Keybinds:SyncContextYields()
check("unusable selection API yields rather than breaking", not replyOverridden())

print(("\nResults: %d/%d passed"):format(TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    os.exit(1)
end
