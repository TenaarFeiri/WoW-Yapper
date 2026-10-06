#!/usr/bin/env lua
-- Blizzard-facing active-editor contract: the same InsertLink/OpenChat rules
-- must work while the overlay or multiline editor owns the chat session.

local PASS, FAIL = "PASS", "FAIL"
local TESTS, FAILURES = 0, 0

local function check(label, condition)
    TESTS = TESTS + 1
    if condition then
        print("  [" .. PASS .. "] " .. label)
    else
        FAILURES = FAILURES + 1
        print("  [" .. FAIL .. "] " .. label)
    end
end

local function frame(name)
    local f = { name = name, shown = false, focused = false, text = "", cursor = 0 }
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false; self.focused = false end
    function f:IsShown() return self.shown end
    function f:SetFocus() self.focused = true end
    function f:ClearFocus() self.focused = false end
    function f:HasFocus() return self.focused end
    function f:SetText(text) self.text = text or ""; self.cursor = #self.text end
    function f:GetText() return self.text end
    function f:SetCursorPosition(position) self.cursor = position end
    function f:GetCursorPosition() return self.cursor end
    function f:Insert(text)
        self.text = self.text:sub(1, self.cursor) .. text .. self.text:sub(self.cursor + 1)
        self.cursor = self.cursor + #text
    end
    function f:SetParent() end
    function f:GetParent() return _G.UIParent end
    function f:SetScript() end
    function f:HookScript() end
    function f:SetTextColor() end
    return f
end

_G.UIParent = frame("UIParent")
_G.UIParent:Show()
_G.DEFAULT_CHAT_FRAME = { editBox = frame("NativeEditBox") }
_G.ChatFrame1EditBox = _G.DEFAULT_CHAT_FRAME.editBox
_G.C_Timer = { After = function(_, callback) callback() end }
_G.CreateFrame = function() return frame("compat-header") end
_G.ChatEdit_GetActiveWindow = function() return _G.ACTIVE_CHAT_EDIT_BOX end

local focusOverride
_G.ChatFrameUtil = {
    -- Mirrors Blizzard: GetActiveWindow just returns ACTIVE_CHAT_EDIT_BOX and
    -- is NEVER reassigned by Yapper -- an addon function in this slot taints
    -- every secure call chain that queries it (map-pin CopyToClipboard, 12.1).
    GetActiveWindow = function() return _G.ACTIVE_CHAT_EDIT_BOX end,
    -- Mirrors Blizzard's ActivateChat: clears the focus override, deactivates
    -- the previous window, claims ACTIVE_CHAT_EDIT_BOX, shows and focuses.
    ActivateChat = function(editBox)
        focusOverride = nil
        local prev = _G.ACTIVE_CHAT_EDIT_BOX
        if prev and prev ~= editBox and prev.Deactivate then prev:Deactivate() end
        _G.ACTIVE_CHAT_EDIT_BOX = editBox
        if editBox.Show then editBox:Show() end
        if editBox.SetFocus then editBox:SetFocus() end
    end,
    DeactivateChat = function(editBox)
        if _G.ACTIVE_CHAT_EDIT_BOX == editBox then _G.ACTIVE_CHAT_EDIT_BOX = nil end
        if editBox.Deactivate then editBox:Deactivate() end
    end,
    SetChatFocusOverride = function(box) focusOverride = box end,
    ClearChatFocusOverride = function() focusOverride = nil end,
    FocusActiveWindow = function()
        local active = ChatFrameUtil.GetActiveWindow()
        if active then ChatFrameUtil.ActivateChat(active) end
    end,
    OpenChat = function(text)
        if focusOverride and (not text or text:sub(1, 1) ~= "/" or focusOverride.supportsSlashCommands) then
            focusOverride:SetFocus()
            if text then focusOverride:SetText(text) end
            return focusOverride
        end
        return ChatFrameUtil.GetActiveWindow()
    end,
    InsertLink = function(link)
        local active = ChatFrameUtil.GetActiveWindow()
        if not active then return false end
        active:Insert(link)
        return true
    end,
}

local YapperTable = {
    Config = { System = {}, EditBox = {} },
    Utils = {
        IsChatLockdown = function() return false end,
        NormaliseCharName = function(_, name) return name end,
    },
    State = {},
    Recolour = {
        CanonicalText = function(box) return box:GetText() end,
    },
}

local function load(path)
    local loader, err = loadfile(path)
    assert(loader, err)
    loader("Yapper", YapperTable)
end

-- Load the real editor selector, then the real compatibility routing.
local nativeGetActiveWindow = ChatFrameUtil.GetActiveWindow
load("Src/EditBox.lua")
local EditBox = YapperTable.EditBox
EditBox.Overlay = frame("YapperOverlay")
EditBox.OverlayEdit = frame("YapperOverlayEdit")
YapperTable.Multiline = {
    Frame = frame("YapperMultilineFrame"),
    EditBox = frame("YapperMultilineEdit"),
    CreateFrame = function() end,
}
load("Src/EditBoxCompat.lua")

print("\nContract 0: native function identity + lockdown release")
EditBox:SetChatCompatibilityEnabled(false)
check("GetActiveWindow stays native when disabled", ChatFrameUtil.GetActiveWindow == nativeGetActiveWindow)
EditBox:SetChatCompatibilityEnabled(true)
check("GetActiveWindow stays native when enabled", ChatFrameUtil.GetActiveWindow == nativeGetActiveWindow)

local link = "|cnIQ4:|Hitem:1234|h[Coiled Serpent Idol]|h|r"

print("\nContract 1: overlay active editor")
EditBox.Overlay:Show()
EditBox.OverlayEdit:SetFocus()
EditBox:UpdateFocusOverride()
check("overlay is active editor", EditBox:GetActiveEditor() == EditBox.OverlayEdit)
check("overlay claims ACTIVE_CHAT_EDIT_BOX", _G.ACTIVE_CHAT_EDIT_BOX == EditBox.OverlayEdit)
check("GetActiveWindow returns overlay", ChatFrameUtil.GetActiveWindow() == EditBox.OverlayEdit)
check("GetActiveWindow fn is still native", ChatFrameUtil.GetActiveWindow == nativeGetActiveWindow)
check("focus override points to overlay", focusOverride == EditBox.OverlayEdit)
check("OpenChat targets overlay via focus override", ChatFrameUtil.OpenChat("draft") == EditBox.OverlayEdit
    and EditBox.OverlayEdit:GetText() == "draft")
check("InsertLink reaches overlay", ChatFrameUtil.InsertLink(link)
    and EditBox.OverlayEdit:GetText() == "draft" .. link)

-- Compat-off while open must release the slot so lockdown/bypass paths
-- expose native state, then re-claim cleanly on re-enable.
EditBox:SetChatCompatibilityEnabled(false)
check("compat disable releases ACTIVE_CHAT_EDIT_BOX", _G.ACTIVE_CHAT_EDIT_BOX == nil)
EditBox:SetChatCompatibilityEnabled(true)
check("compat enable reclaims ACTIVE_CHAT_EDIT_BOX", _G.ACTIVE_CHAT_EDIT_BOX == EditBox.OverlayEdit)
check("GetActiveWindow fn still native after toggles", ChatFrameUtil.GetActiveWindow == nativeGetActiveWindow)

print("\nContract 2: multiline takes ownership")
YapperTable.Multiline.Frame:Show()
YapperTable.Multiline.EditBox:SetFocus()
EditBox:UpdateFocusOverride()
check("multiline is active editor", EditBox:GetActiveEditor() == YapperTable.Multiline.EditBox)
check("multiline claims ACTIVE_CHAT_EDIT_BOX", _G.ACTIVE_CHAT_EDIT_BOX == YapperTable.Multiline.EditBox)
check("GetActiveWindow returns multiline", ChatFrameUtil.GetActiveWindow() == YapperTable.Multiline.EditBox)
check("focus override points to multiline", focusOverride == YapperTable.Multiline.EditBox)
check("OpenChat targets multiline via focus override", ChatFrameUtil.OpenChat("draft") == YapperTable.Multiline.EditBox
    and YapperTable.Multiline.EditBox:GetText() == "draft")
YapperTable.Multiline.EditBox:ClearFocus()
ChatFrameUtil.FocusActiveWindow()
check("FocusActiveWindow focuses multiline", YapperTable.Multiline.EditBox:HasFocus())
check("InsertLink reaches multiline", ChatFrameUtil.InsertLink(link)
    and YapperTable.Multiline.EditBox:GetText() == "draft" .. link)

print("\nContract 3: migration back and closed fallback")
YapperTable.Multiline.Frame:Hide()
EditBox.Overlay:Show()
EditBox:UpdateFocusOverride()
check("overlay regains active editor", EditBox:GetActiveEditor() == EditBox.OverlayEdit)
check("overlay reclaims ACTIVE_CHAT_EDIT_BOX", _G.ACTIVE_CHAT_EDIT_BOX == EditBox.OverlayEdit)
check("GetActiveWindow returns overlay after exit", ChatFrameUtil.GetActiveWindow() == EditBox.OverlayEdit)
check("focus override returns to overlay", focusOverride == EditBox.OverlayEdit)

EditBox.Overlay:Hide()
EditBox:UpdateFocusOverride()
check("closed Yapper releases ACTIVE_CHAT_EDIT_BOX", _G.ACTIVE_CHAT_EDIT_BOX == nil)
check("GetActiveWindow query stays untainted (native fn)", ChatFrameUtil.GetActiveWindow == nativeGetActiveWindow)
check("closed Yapper clears focus override", focusOverride == nil)

print("\nContract 4: focus watchers poll HasFocus edges")
-- RegisterFocusWatcher exists so focus transitions never execute addon
-- Lua inside a foreign stack (map-pin CHATLINK click -> InsertLink ->
-- SetFocus -> OnEditFocusGained): script handlers there taint the rest of
-- the stack and 12.1's protected CopyToClipboard then fails. The harness
-- has no NewTicker, so edges are driven by _PollFocusWatchers directly.
local gained, lost = 0, 0
EditBox:RegisterFocusWatcher(EditBox.OverlayEdit,
    function() gained = gained + 1 end,
    function() lost = lost + 1 end)
check("watcher seeds current focus state",
    EditBox._focusWatchers[#EditBox._focusWatchers].focused == true)
EditBox.OverlayEdit:ClearFocus()
EditBox:_PollFocusWatchers()
check("focus-loss edge fires once", lost == 1 and gained == 0)
EditBox:_PollFocusWatchers()
check("steady state does not refire", lost == 1 and gained == 0)
EditBox.OverlayEdit:SetFocus()
EditBox:_PollFocusWatchers()
check("focus-gain edge fires", gained == 1 and lost == 1)
EditBox:_PollFocusWatchers()
check("focus-gain fires once only", gained == 1 and lost == 1)

print("\n" .. string.rep("-", 60))
print(("Results: %d/%d passed"):format(TESTS - FAILURES, TESTS))
if FAILURES > 0 then os.exit(1) end
print("All editor contract tests passed.")
