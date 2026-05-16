--[[
    Compatibility helpers for the overlay editbox.
    Provides GetChatType/GetChannelTarget/etc. so Blizzard treats the
    overlay like a normal chat box and avoids nil-method crashes.
    Also hooks InsertLink and ensures it routes to the active Yapper editor.
]]

local _, YapperTable = ...

local EditBox = YapperTable.EditBox
if not EditBox then
    return
end

-- Let Blizzard code query chat state from the overlay widget the
-- same way it would from a native ChatFrameEditBox.

local function GetCompatAttribute(box, key)
    if key == "chatType" then
        return EditBox.ChatType
    elseif key == "channelTarget" then
        return EditBox.ChatType == "CHANNEL" and EditBox.Target or nil
    elseif key == "tellTarget" then
        local ct = EditBox.ChatType
        return (ct == "WHISPER" or ct == "BN_WHISPER") and EditBox.Target or nil
    elseif key == "language" then
        return EditBox.Language
    end
    return nil
end

function YapperTable.InstallCompatMethods(box)
    if not box or box._yapperCompatInstalled then
        return
    end
    box._yapperCompatInstalled = true

    function box:GetChatType() return GetCompatAttribute(self, "chatType") end

    function box:GetChannelTarget() return GetCompatAttribute(self, "channelTarget") end

    function box:GetTellTarget() return GetCompatAttribute(self, "tellTarget") end

    function box:GetLanguage() return GetCompatAttribute(self, "language") end

    function box:GetAttribute(key) return GetCompatAttribute(self, key) end
    
    -- Parity Fields: direct access fields used by some addons.
    box.chatType = box:GetChatType() or "SAY"
    box.chatLanguage = box:GetLanguage() or "Common"

    -- Satisfy addons (like TRP3) that expect the active editbox to have
    -- a parent chatFrame and a header.
    if not box.chatFrame then
        box.chatFrame = _G.DEFAULT_CHAT_FRAME
    end
    if not box.header then
        box.header = CreateFrame("Frame", nil, box)
    end

    -- Blizzard Compatibility Stubs: Prevent nil-method crashes when
    -- ChatFrameUtil or addons try to manage Yapper as an active chat box.
    box.Deactivate = box.Deactivate or function() end
    box.UpdateHeader = box.UpdateHeader or function() end
    box.SetFocusRegionsShown = box.SetFocusRegionsShown or function() end
    box.UpdateNewcomerEditBoxHint = box.UpdateNewcomerEditBoxHint or function() end
end

-- Install on overlay at creation time.
local originalCreateOverlay = EditBox.CreateOverlay
function EditBox:CreateOverlay(...)
    originalCreateOverlay(self, ...)
    YapperTable.InstallCompatMethods(self.OverlayEdit)
end

-- Also install on Multiline at creation time if it exists.
local Multiline = YapperTable.Multiline
if Multiline then
    local originalCreateMultiline = Multiline.CreateFrame
    function Multiline:CreateFrame(...)
        originalCreateMultiline(self, ...)
        YapperTable.InstallCompatMethods(self.EditBox)
    end
end

-- Install immediately if components already exist (e.g. reload).
if EditBox.OverlayEdit then
    YapperTable.InstallCompatMethods(EditBox.OverlayEdit)
end
if Multiline and Multiline.EditBox then
    YapperTable.InstallCompatMethods(Multiline.EditBox)
end


-- Hook InsertLink: when a Yapper editor is active and focused, we insert the text
-- directly into our box and return 'true' to signal Blizzard that the link
-- has been handled. This prevents Blizzard's native fallback logic from
-- triggering.

local origInsertLink = ChatFrameUtil.InsertLink
local function overlayInsertLink(link)
    -- Multiline editor takes priority: the overlay is hidden while it's open.
    local state = YapperTable.State
    local ml    = YapperTable.Multiline
    if state and state.IsMultiline and state:IsMultiline()
        and ml and ml.EditBox and ml.Frame and ml.Frame:IsShown() then
        ml.EditBox:Insert(link)
        return true
    end

    -- Single-line overlay.
    -- We allow insertion even if focus is temporarily lost (e.g. to a TRP3 popup),
    -- as long as the overlay is the intended recipient.
    if EditBox.Overlay and EditBox.Overlay:IsShown() and EditBox.OverlayEdit then
        EditBox.OverlayEdit:Insert(link)
        return true
    end
    -- Fall back to original Blizzard logic if Yapper isn't active.
    return origInsertLink(link)
end

ChatFrameUtil.InsertLink = overlayInsertLink
-- Keep the deprecated global alias in sync.
if _G.ChatEdit_InsertLink then
    _G.ChatEdit_InsertLink = overlayInsertLink
end

-- Tell Blizz that Yapper is the active chat frame when focused.
-- This ensures Blizzard's ChatEdit_GetActiveWindow() returns Yapper,
-- which is required for certain native link-handling and UI behaviors.
local function SyncActiveChatEditBox()
    local ml = YapperTable.Multiline
    -- Multiline priority: Claim only if focused to avoid zombie state locks.
    if ml and ml.Frame and ml.Frame:IsShown() and ml.EditBox and ml.EditBox:HasFocus() then
        _G.ACTIVE_CHAT_EDIT_BOX = ml.EditBox
        return
    end

    -- Single-line overlay: Claim only if focused.
    if EditBox.Overlay and EditBox.Overlay:IsShown()
        and EditBox.OverlayEdit and EditBox.OverlayEdit:HasFocus() then
        _G.ACTIVE_CHAT_EDIT_BOX = EditBox.OverlayEdit
        return
    end

    -- If neither Yapper box is focused, clear the global.
    local current = _G.ACTIVE_CHAT_EDIT_BOX
    if current and current._yapperCompatInstalled then
        _G.ACTIVE_CHAT_EDIT_BOX = nil
    end
end
YapperTable.SyncActiveChatEditBox = SyncActiveChatEditBox

-- Compatibility Bridge: Some addons (like TRP3) use ChatFrameUtil.GetActiveWindow()
-- or the legacy ChatEdit_GetActiveWindow() to determine where to insert links.
-- We monkey-patch these to return Yapper if it's shown, even if it doesn't
-- currently have hardware focus. This ensures links from popups are routed
-- directly to Yapper without flickering or delays.
local function YapperGetActiveWindow(...)
    local ml = YapperTable.Multiline
    if ml and ml.Frame and ml.Frame:IsShown() and ml.EditBox then
        return ml.EditBox
    end
    local eb = YapperTable.EditBox
    if eb and eb.Overlay and eb.Overlay:IsShown() and eb.OverlayEdit then
        return eb.OverlayEdit
    end
    return nil
end

if ChatFrameUtil and ChatFrameUtil.GetActiveWindow then
    local origGetActive = ChatFrameUtil.GetActiveWindow
    ChatFrameUtil.GetActiveWindow = function(...)
        local yapper = YapperGetActiveWindow(...)
        if yapper then return yapper end
        return origGetActive(...)
    end
end

if _G.ChatEdit_GetActiveWindow then
    local origGetActive = _G.ChatEdit_GetActiveWindow
    _G.ChatEdit_GetActiveWindow = function(...)
        local yapper = YapperGetActiveWindow(...)
        if yapper then return yapper end
        return origGetActive(...)
    end
end

-- Hook into Yapper's internal API events to keep the global in sync.
-- This handles state transitions (e.g. from single-line to multiline).
if _G.YapperAPI then
    _G.YapperAPI:RegisterCallback("EDITBOX_SHOW", SyncActiveChatEditBox)
    _G.YapperAPI:RegisterCallback("STATE_CHANGED", SyncActiveChatEditBox)
    _G.YapperAPI:RegisterCallback("EDITBOX_HIDE", SyncActiveChatEditBox)
end
