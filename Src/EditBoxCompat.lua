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
    -- The shim's __index redirects .editBox back to Yapper's own box so
    -- TRP3's shift-click name-replacement path (ChatFrame.lua:766) targets
    -- the correct editor instead of Blizzard's ChatFrame1EditBox.
    if not box._yapperChatFrameShim then
        box._yapperChatFrameShim = setmetatable({}, {
            __index = function(_, key)
                if key == "editBox" then
                    return box
                end
                return _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME[key]
            end
        })
    end
    box.chatFrame = box._yapperChatFrameShim
    if not box.header then
        box.header = CreateFrame("Frame", nil, box)
    end

    -- Blizzard Compatibility Stubs: Prevent nil-method crashes when
    -- ChatFrameUtil or addons try to manage Yapper as an active chat box.
    box.Deactivate = box.Deactivate or function() end
    box.UpdateHeader = box.UpdateHeader or function() end
    box.SetFocusRegionsShown = box.SetFocusRegionsShown or function() end
    box.UpdateNewcomerEditBoxHint = box.UpdateNewcomerEditBoxHint or function() end

    -- supportsSlashCommands = false: we do NOT want Blizzard's CHAT_FOCUS_OVERRIDE
    -- path to intercept slash-starting text (e.g. "/" key press, "/w name").
    -- If set to true, Blizzard calls SetText("/") on the overlay AND the physical
    -- keypress then fires OnChar on the now-focused overlay, producing "//".
    -- With false, slash text goes to the normal Blizzard editbox path which our
    -- Show() hook already intercepts cleanly, consuming the physical char first.
    -- Non-slash content (item links, empty open) still flows through CHAT_FOCUS_OVERRIDE.
    box.supportsSlashCommands = false
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

-- Hook GetActiveWindow: When Yapper is active, visible, and not bypassed,
-- we route GetActiveWindow to Yapper's active editor (overlay or multiline).
-- Under real combat lockdown, we immediately fall back to the native implementation.
-- This ensures 100% compatibility with Shift-Clicking links and TRP3 link insertion,
-- while keeping the native secure chat state completely untainted.
if ChatFrameUtil and ChatFrameUtil.GetActiveWindow then
    local origGetActiveWindow = ChatFrameUtil.GetActiveWindow
    ChatFrameUtil.GetActiveWindow = function()
        local eb = YapperTable.EditBox
        if eb and eb.Overlay and eb.Overlay:IsShown() then
            local bypass = eb._UserBypassingYapper and eb._UserBypassingYapper()
            local preShow = eb._preShowSuppressed
            if not bypass and not preShow and not (YapperTable.Utils and YapperTable.Utils:IsChatLockdown()) then
                local ml = YapperTable.Multiline
                if ml and ml.Frame and ml.Frame:IsShown() and ml.EditBox then
                    return ml.EditBox
                end
                return eb.OverlayEdit
            end
        end
        return origGetActiveWindow()
    end
    _G.ChatEdit_GetActiveWindow = ChatFrameUtil.GetActiveWindow
end




