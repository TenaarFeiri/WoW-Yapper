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
_G.ChatEdit_GetActiveWindow = function() return _G.DEFAULT_CHAT_FRAME.editBox end

local focusOverride
local nativeActive = _G.DEFAULT_CHAT_FRAME.editBox
_G.ChatFrameUtil = {
    GetActiveWindow = function() return nativeActive end,
    SetChatFocusOverride = function(box) focusOverride = box end,
    ClearChatFocusOverride = function() focusOverride = nil end,
    FocusActiveWindow = function()
        local active = ChatFrameUtil.GetActiveWindow()
        if active then active:SetFocus() end
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

local link = "|cnIQ4:|Hitem:1234|h[Coiled Serpent Idol]|h|r"

print("\nContract 1: overlay active editor")
EditBox.Overlay:Show()
EditBox.OverlayEdit:SetFocus()
EditBox:UpdateFocusOverride()
check("overlay is active editor", EditBox:GetActiveEditor() == EditBox.OverlayEdit)
check("GetActiveWindow returns overlay", ChatFrameUtil.GetActiveWindow() == EditBox.OverlayEdit)
check("focus override points to overlay", focusOverride == EditBox.OverlayEdit)
check("InsertLink reaches overlay", ChatFrameUtil.InsertLink(link) and EditBox.OverlayEdit:GetText() == link)

print("\nContract 2: multiline takes ownership")
YapperTable.Multiline.Frame:Show()
YapperTable.Multiline.EditBox:SetFocus()
EditBox:UpdateFocusOverride()
check("multiline is active editor", EditBox:GetActiveEditor() == YapperTable.Multiline.EditBox)
check("GetActiveWindow returns multiline", ChatFrameUtil.GetActiveWindow() == YapperTable.Multiline.EditBox)
check("focus override points to multiline", focusOverride == YapperTable.Multiline.EditBox)
check("FocusActiveWindow focuses multiline", (function()
    YapperTable.Multiline.EditBox:ClearFocus()
    ChatFrameUtil.FocusActiveWindow()
    return YapperTable.Multiline.EditBox:HasFocus()
end)())
check("InsertLink reaches multiline", ChatFrameUtil.InsertLink(link) and YapperTable.Multiline.EditBox:GetText() == link)
check("OpenChat targets multiline", ChatFrameUtil.OpenChat("draft") == YapperTable.Multiline.EditBox
    and YapperTable.Multiline.EditBox:GetText() == "draft")

print("\nContract 3: migration back and closed fallback")
YapperTable.Multiline.Frame:Hide()
EditBox.Overlay:Show()
EditBox:UpdateFocusOverride()
check("overlay regains active editor", EditBox:GetActiveEditor() == EditBox.OverlayEdit)
check("GetActiveWindow returns overlay after exit", ChatFrameUtil.GetActiveWindow() == EditBox.OverlayEdit)
check("focus override returns to overlay", focusOverride == EditBox.OverlayEdit)

EditBox.Overlay:Hide()
EditBox:UpdateFocusOverride()
check("closed Yapper falls back to native active window", ChatFrameUtil.GetActiveWindow() == nativeActive)
check("closed Yapper clears focus override", focusOverride == nil)

print("\n" .. string.rep("-", 60))
print(("Results: %d/%d passed"):format(TESTS - FAILURES, TESTS))
if FAILURES > 0 then os.exit(1) end
print("All editor contract tests passed.")
