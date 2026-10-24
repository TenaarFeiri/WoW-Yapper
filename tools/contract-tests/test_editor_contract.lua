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
_G.C_Timer = {
    After = function(_, callback) callback() end,
    NewTimer = function() return { Cancel = function() end } end,
    NewTicker = function() return { Cancel = function() end } end,
}
_G.InCombatLockdown = function() return false end
_G.issecretvalue = function() return false end
_G.canaccessvalue = function() return true end
_G.issecrettable = function() return false end
_G.canaccesstable = function() return true end
_G.CreateFrame = function() return frame("compat-header") end
_G.ChatEdit_GetActiveWindow = function() return _G.ACTIVE_CHAT_EDIT_BOX end
_G.GetCVar = function(key)
    if key == "chatStyle" then return "im" end
    return ""
end
_G.hooksecurefunc = function(target, method, callback)
    if type(target) == "table" then
        local original = target[method]
        target[method] = function(...)
            local result
            if original then result = original(...) end
            callback(...)
            return result
        end
    end
end

local focusOverride
_G.ChatFrameUtil = {
    -- Mirrors Blizzard: GetActiveWindow just returns ACTIVE_CHAT_EDIT_BOX and
    -- is NEVER reassigned by Yapper -- an addon function in this slot taints
    -- every secure call chain that queries it (map-pin CopyToClipboard, 12.1).
    GetActiveWindow = function() return _G.ACTIVE_CHAT_EDIT_BOX end,
    GetLastActiveWindow = function() return _G.LAST_ACTIVE_CHAT_EDIT_BOX end,
    -- Mirrors Blizzard's ActivateChat: early-returns on disableActivate
    -- boxes, clears the focus override, deactivates the previous window,
    -- claims ACTIVE_CHAT_EDIT_BOX, writes LAST_ACTIVE_CHAT_EDIT_BOX,
    -- shows and focuses.
    ActivateChat = function(editBox)
        if editBox.disableActivate then return end
        focusOverride = nil
        local prev = _G.ACTIVE_CHAT_EDIT_BOX
        if prev and prev ~= editBox and prev.Deactivate then prev:Deactivate() end
        _G.ACTIVE_CHAT_EDIT_BOX = editBox
        ChatFrameUtil.SetLastActiveWindow(editBox)
        if editBox.Show then editBox:Show() end
        if editBox.SetFocus then editBox:SetFocus() end
    end,
    -- Mirrors Blizzard's SetLastActiveWindow: early-returns on
    -- disableActivate boxes; under chatStyle=="im" it hides the PREVIOUS
    -- window's editbox -- the vector that hid our input widget while the
    -- overlay frame stayed up (invisible typing, Enter still sent).
    SetLastActiveWindow = function(editBox)
        if editBox ~= nil and editBox.disableActivate then return end
        local prev = _G.LAST_ACTIVE_CHAT_EDIT_BOX
        if prev and not prev.isGM and prev ~= editBox
            and _G.GetCVar("chatStyle") == "im" then
            if prev.Hide then prev:Hide() end
        end
        _G.LAST_ACTIVE_CHAT_EDIT_BOX = editBox
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
        -- Mirrors Utils:SafeWidgetBoolean: nil for absent/unreadable reads.
        SafeWidgetBoolean = function(_, widget, method)
            if not widget or type(method) ~= "string" then return nil end
            local fn = widget[method]
            if type(fn) ~= "function" then return nil end
            local ok, raw = pcall(fn, widget)
            if not ok then return nil end
            local ok2, result = pcall(function(v) return v and true or false end, raw)
            if not ok2 then return nil end
            return result
        end,
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
check("FocusActiveWindow refocuses multiline via post-hook", YapperTable.Multiline.EditBox:HasFocus())
check("FocusActiveWindow did not pollute LAST_ACTIVE", _G.LAST_ACTIVE_CHAT_EDIT_BOX ~= YapperTable.Multiline.EditBox)
check("focus override survives FocusActiveWindow", focusOverride == YapperTable.Multiline.EditBox)
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

print("\nContract 4: focus edges are signal-driven, never polled")
-- RegisterFocusHandler installs hooksecurefunc post-hooks on
-- SetFocus/ClearFocus so focus transitions fire from the calls that move
-- focus -- never from OnEditFocus* scripts (foreign-stack taint: a
-- map-pin CHATLINK click's protected CopyToClipboard fails
-- ADDON_ACTION_FORBIDDEN) and never from a poll ticker (secret-boolean
-- HasFocus errors under restrictions, plus callback cascades). The
-- harness's hooksecurefunc wraps methods, so a SetFocus/ClearFocus call
-- delivers the edge directly.
local gained, lost = 0, 0
EditBox:RegisterFocusHandler(EditBox.OverlayEdit,
    function() gained = gained + 1 end,
    function() lost = lost + 1 end)
EditBox.OverlayEdit:ClearFocus()
check("ClearFocus signal fires lost edge", lost == 1 and gained == 0)
EditBox.OverlayEdit:ClearFocus()
check("deduped state does not refire", lost == 1 and gained == 0)
EditBox.OverlayEdit:SetFocus()
check("SetFocus signal fires gained edge", gained == 1 and lost == 1)
check("IsEditorFocused tracks signals",
    EditBox:IsEditorFocused(EditBox.OverlayEdit) == true)
EditBox.OverlayEdit:SetFocus()
check("gained edge dedupes", gained == 1 and lost == 1)

print("\nContract 5: IM-mode bookkeeping cannot hide the input widget")
-- 2.4.6 regression: ActivateChat(overlay) wrote LAST_ACTIVE_CHAT_EDIT_BOX
-- and every later im-mode SetLastActiveWindow called
-- previousValue:Hide() on it -- hiding the input widget while the overlay
-- frame stayed visible. Hidden editboxes still take focus and fire
-- OnEnterPressed, so users typed blind but sends kept working.
EditBox.Overlay:Show()
EditBox.OverlayEdit:SetFocus()
EditBox:UpdateFocusOverride()
check("overlay is active editor", EditBox:GetActiveEditor() == EditBox.OverlayEdit)
check("overlay editbox opts out of activation", EditBox.OverlayEdit.disableActivate == true)
check("multiline editbox opts out of activation", YapperTable.Multiline.EditBox.disableActivate == true)
ChatFrameUtil.FocusActiveWindow()
check("FocusActiveWindow leaves LAST_ACTIVE alone", _G.LAST_ACTIVE_CHAT_EDIT_BOX ~= EditBox.OverlayEdit)
check("focus override still points to overlay", focusOverride == EditBox.OverlayEdit)

-- Even if the global is polluted by a direct write, the widget-hide is
-- vetoed and the next sync hands LAST_ACTIVE back to a native box.
_G.LAST_ACTIVE_CHAT_EDIT_BOX = EditBox.OverlayEdit
ChatFrameUtil.SetLastActiveWindow(_G.DEFAULT_CHAT_FRAME.editBox)
check("widget Hide() is vetoed", EditBox.OverlayEdit:IsShown())
_G.LAST_ACTIVE_CHAT_EDIT_BOX = EditBox.OverlayEdit
EditBox:UpdateFocusOverride()
check("polluted LAST_ACTIVE handed back to native", _G.LAST_ACTIVE_CHAT_EDIT_BOX == _G.DEFAULT_CHAT_FRAME.editBox)

print("\nContract 6: foreign displacement deferred, release is leaf-only")
-- C stack overflow regression: _SyncActiveChatWindow used to run
-- DeactivateChat inside whatever stack reached it (OnShow dispatch,
-- hook post-hooks), and that cascade could re-enter Show/UpdateFocusOverride
-- without bound. The claim is now a direct global write and the foreign
-- holder's Deactivate bookkeeping runs on the deferred pass (immediate in
-- this harness's C_Timer.After).
local foreign = frame("ForeignBox")
foreign.deactivated = 0
function foreign:Deactivate() self.deactivated = self.deactivated + 1 end
_G.ACTIVE_CHAT_EDIT_BOX = foreign
EditBox.Overlay:Show()
EditBox:UpdateFocusOverride()
check("overlay claims ACTIVE via plain write", _G.ACTIVE_CHAT_EDIT_BOX == EditBox.OverlayEdit)
check("displaced foreign box deactivated on deferred pass", foreign.deactivated == 1)

-- Releasing our slot must write the global directly: our editors'
-- Deactivate is a stub, so DeactivateChat only ever cleared the global
-- while inviting foreign post-hooks into our stack.
local ourDeactivateCalls = 0
local prevDeactivate = EditBox.OverlayEdit.Deactivate
EditBox.OverlayEdit.Deactivate = function() ourDeactivateCalls = ourDeactivateCalls + 1 end
EditBox.Overlay:Hide()
EditBox:UpdateFocusOverride()
check("release clears ACTIVE via plain write", _G.ACTIVE_CHAT_EDIT_BOX == nil)
check("release never ran our Deactivate stub", ourDeactivateCalls == 0)
EditBox.OverlayEdit.Deactivate = prevDeactivate

print("\n" .. string.rep("-", 60))
print(("Results: %d/%d passed"):format(TESTS - FAILURES, TESTS))
if FAILURES > 0 then os.exit(1) end
print("All editor contract tests passed.")
