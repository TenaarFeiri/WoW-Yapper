--[[
    Compatibility helpers for the overlay editbox.
    Provides GetChatType/GetChannelTarget/etc. so Blizzard treats the
    overlay like a normal chat box and avoids nil-method crashes.
    Also hooks InsertLink and temporarily hides the overlay from
    GetActiveWindow to sidestep protected-call taint errors during
    achievement/community linking.
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

local function InstallCompatMethods(box)
    if not box or box._yapperCompatInstalled then
        return
    end
    box._yapperCompatInstalled = true

    function box:GetChatType()      return GetCompatAttribute(self, "chatType") end
    function box:GetChannelTarget() return GetCompatAttribute(self, "channelTarget") end
    function box:GetTellTarget()    return GetCompatAttribute(self, "tellTarget") end
    function box:GetLanguage()      return GetCompatAttribute(self, "language") end
    function box:GetAttribute(key)  return GetCompatAttribute(self, key) end
end

-- Install on overlay at creation time.
local originalCreateOverlay = EditBox.CreateOverlay
function EditBox:CreateOverlay(...)
    originalCreateOverlay(self, ...)
    InstallCompatMethods(self.OverlayEdit)
end

-- Install immediately if overlay already exists (shouldn't happen, but safe).
if EditBox.OverlayEdit then
    InstallCompatMethods(EditBox.OverlayEdit)
end


local _suppressOverlayReturn = false


-- Hook InsertLink: when the overlay is active and focused, we insert the text
-- directly into our box and return 'true' to signal Blizzard that the link
-- has been handled. This prevents Blizzard's native fallback logic from 
-- triggering (e.g., accidental item-stack splitting or quest-tracker toggling).

local origInsertLink = ChatFrameUtil.InsertLink
local function overlayInsertLink(link)
    if EditBox.Overlay and EditBox.Overlay:IsShown()
        and EditBox.OverlayEdit and EditBox.OverlayEdit:HasFocus() then
        EditBox.OverlayEdit:Insert(link)
        return true -- Signals Blizzard that the link was handled
    end
    -- Fall back to original Blizzard logic if Yapper isn't active
    return origInsertLink(link)
end

ChatFrameUtil.InsertLink = overlayInsertLink
-- Keep the deprecated global alias in sync.
if _G.ChatEdit_InsertLink then
    _G.ChatEdit_InsertLink = overlayInsertLink
end

--[[ 
    -- Secure Hook Implementation (Taint-Free but causes Split-Stack bugs):
    local function OnLinkInserted(link)
        if EditBox.Overlay and EditBox.Overlay:IsShown()
            and EditBox.OverlayEdit and EditBox.OverlayEdit:HasFocus() then
            EditBox.OverlayEdit:Insert(link)
        end
    end

    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", OnLinkInserted)
    end

    if _G.ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", OnLinkInserted)
    end
]]