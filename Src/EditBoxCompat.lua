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

local originalHookAllChatFrames = EditBox.HookAllChatFrames
function EditBox:HookAllChatFrames(...)
    originalHookAllChatFrames(self, ...)

    -- Re-wrap the GetActiveWindow hooks that HookAllChatFrames just
    -- installed, adding suppression support.
    local yapperGetActive = _G.ChatEdit_GetActiveWindow
    if yapperGetActive then
        _G.ChatEdit_GetActiveWindow = function(...)
            if _suppressOverlayReturn then return nil end
            return yapperGetActive(...)
        end
    end

    local yapperUtilGetActive = _G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow
    if yapperUtilGetActive then
        _G.ChatFrameUtil.GetActiveWindow = function(...)
            if _suppressOverlayReturn then return nil end
            return yapperUtilGetActive(...)
        end
    end

    -- Hook InsertLink: when the overlay is active, insert directly and
    -- suppress GetActiveWindow for the rest of the frame so telemetry
    -- cannot reach a protected call.
    local origInsertLink = ChatFrameUtil.InsertLink
    local function overlayInsertLink(link)
        if self.Overlay and self.Overlay:IsShown()
            and self.OverlayEdit and self.OverlayEdit:HasFocus() then
            self.OverlayEdit:Insert(link)
            _suppressOverlayReturn = true
            C_Timer.After(0, function() _suppressOverlayReturn = false end)
            return true
        end
        return origInsertLink(link)
    end

    ChatFrameUtil.InsertLink = overlayInsertLink
    -- Keep the deprecated global alias in sync.
    if _G.ChatEdit_InsertLink then
        _G.ChatEdit_InsertLink = overlayInsertLink
    end
end