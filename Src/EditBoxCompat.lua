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

function YapperTable.InstallCompatMethods(box)
    if not box then
        return
    end
    box._yapperCompatInstalled = true

    function box:GetChatType() return GetCompatAttribute(self, "chatType") end

    function box:GetChannelTarget() return GetCompatAttribute(self, "channelTarget") end

    function box:GetTellTarget() return GetCompatAttribute(self, "tellTarget") end

    function box:GetLanguage() return GetCompatAttribute(self, "language") end

    function box:GetAttribute(key) return GetCompatAttribute(self, key) end

    -- Blizzard Compatibility Stubs: Prevent nil-method crashes when
    -- ChatFrameUtil tries to manage Yapper as an active chat box.
    function box:Deactivate() end

    function box:UpdateHeader() end

    function box:SetFocusRegionsShown() end

    function box:UpdateNewcomerEditBoxHint() end

    -- Satisfy ChatFrameUtil.SetLastActiveWindow: Blizzard expects all
    -- active editboxes to have a parent chatFrame for state tracking.
    if not box.chatFrame then
        box.chatFrame = _G.DEFAULT_CHAT_FRAME
    end

    -- Some Blizzard code expects these frames to have a 'header'
    if not box.header then
        box.header = CreateFrame("Frame", nil, box)
    end

    -- Parity Fields: direct access fields used by some addons.
    box.chatType = box:GetChatType() or "SAY"
    box.chatLanguage = box:GetLanguage() or "Common"
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

-- Tell Blizz that Yapper is a legit chat frame.

local function SyncActiveChatEditBox()
    local ml = YapperTable.Multiline
    if ml and ml.Frame and ml.Frame:IsShown() and ml.EditBox then
        _G.ACTIVE_CHAT_EDIT_BOX = ml.EditBox
        return
    end

    if EditBox.Overlay and EditBox.Overlay:IsShown() and EditBox.OverlayEdit then
        _G.ACTIVE_CHAT_EDIT_BOX = EditBox.OverlayEdit
        return
    end
end

--- If the user has triggered a panic condition,
--- reset the active overlay.
function EditBox:HardRefocus()
    -- Clear any internal guard state that might be preventing focus reclamation.
    self._overlayUnfocused = false
    self._suppressNextShowFor = nil
    self._preShowSuppressed = nil
    self._panicSuppression = nil -- Allow immediate interaction after a forced fix.

    -- Identify the active target: the Multiline editor takes priority if visible.
    local ml = YapperTable.Multiline
    local targetEditBox, targetFrame

    if ml and ml.Frame and ml.Frame:IsShown() and ml.EditBox then
        targetEditBox = ml.EditBox
        targetFrame = ml.Frame
    else
        targetEditBox = self.OverlayEdit
        targetFrame = self.Overlay
    end

    -- Ensure the global ACTIVE_CHAT_EDIT_BOX pointer is authoritative.
    SyncActiveChatEditBox()

    -- If a native Blizzard box is currently the active one, hide it immediately.
    local active = _G.ACTIVE_CHAT_EDIT_BOX
    if active and active ~= targetEditBox and not (active._yapperCompatInstalled) then
        if active.Hide and active:IsShown() then
            active:Hide()
        end
    end

    -- Sanitise hardware interaction flags for both potential editors.
    local editors = { self.OverlayEdit, (ml and ml.EditBox) }
    for _, box in ipairs(editors) do
        if box then
            -- Force-reinstall compat methods to ensure no hooks or stubs were stripped.
            YapperTable.InstallCompatMethods(box)

            if box.SetPropagateKeyboardInput then
                box:SetPropagateKeyboardInput(false)
            end
            box:SetAutoFocus(false)
        end
    end

    -- Re-run the visual refresh engines for the active component.
    if targetEditBox == self.OverlayEdit then
        if self._RefreshOverlayVisuals and YapperTable.Config and YapperTable.Config.EditBox then
            local cfg = YapperTable.Config.EditBox
            local theme = YapperTable.Theme and YapperTable.Theme:GetTheme()
            local border = theme and theme.border == true
            local pad = (border and (self.Overlay and self.Overlay.BorderPad)) or 0
            self:_RefreshOverlayVisuals(cfg, border, pad)
        end
    elseif ml and targetEditBox == ml.EditBox then
        if ml.ApplyTheme then
            ml:ApplyTheme()
        end
        if ml._RefreshLabel then
            ml:_RefreshLabel()
        end
    end

    -- Wrestle control back from whatever caused us to drop focus.
    if targetEditBox and targetEditBox.SetFocus then
        targetEditBox:SetFocus()

        C_Timer.After(0, function()
            if targetFrame and targetFrame:IsShown() and targetEditBox then
                targetEditBox:SetFocus()
                SyncActiveChatEditBox()
            end
        end)

        C_Timer.After(0.05, function()
            if targetFrame and targetFrame:IsShown() and targetEditBox then
                targetEditBox:SetFocus()
                SyncActiveChatEditBox()
            end
        end)
    end
end

local function ClearActiveChatEditBox()
    -- Delay clearing to ensure clicks that cause focus loss still
    -- see the box as active during the event loop.
    C_Timer.After(0.1, function()
        local current = _G.ACTIVE_CHAT_EDIT_BOX
        if current and current._yapperCompatInstalled then
            _G.ACTIVE_CHAT_EDIT_BOX = nil
        end
    end)
end

-- Hook into Yapper's internal API events to keep the global in sync.
if _G.YapperAPI then
    _G.YapperAPI:RegisterCallback("EDITBOX_SHOW", SyncActiveChatEditBox)
    _G.YapperAPI:RegisterCallback("STATE_CHANGED", SyncActiveChatEditBox)
    _G.YapperAPI:RegisterCallback("EDITBOX_HIDE", ClearActiveChatEditBox)
end

local _suppressOverlayReturn = false

-- Hook InsertLink: when the overlay is active and focused, we insert the text
-- directly into our box and return 'true' to signal Blizzard that the link
-- has been handled. This prevents Blizzard's native fallback logic from
-- triggering (e.g., accidental item-stack splitting or quest-tracker toggling).
-- When the multiline editor is active the overlay is hidden, so we check the
-- state machine first and redirect to the multiline EditBox in that case.

local origInsertLink = ChatFrameUtil.InsertLink
local function overlayInsertLink(link)
    -- Multiline editor takes priority: the overlay is hidden while it's open.
    local state = YapperTable.State
    local ml    = YapperTable.Multiline
    if state and state.IsMultiline and state:IsMultiline()
        and ml and ml.EditBox and ml.Frame and ml.Frame:IsShown() then
        ml.EditBox:Insert(link)
        -- Defer focus to ensure it's not immediately stolen by the click interaction
        C_Timer.After(0, function()
            if ml.EditBox and ml.EditBox.SetFocus then
                ml.EditBox:SetFocus()
                SyncActiveChatEditBox()
            end
        end)
        return true -- Signals Blizzard that the link was handled
    end

    -- Single-line overlay.
    if EditBox.Overlay and EditBox.Overlay:IsShown() and EditBox.OverlayEdit then
        EditBox.OverlayEdit:Insert(link)
        -- Defer focus to ensure it's not immediately stolen by the click interaction
        C_Timer.After(0, function()
            if EditBox.OverlayEdit and EditBox.OverlayEdit.SetFocus then
                EditBox.OverlayEdit:SetFocus()
                SyncActiveChatEditBox()
            end
        end)
        return true -- Signals Blizzard that the link was handled
    end
    -- Fall back to original Blizzard logic if Yapper isn't active.
    return origInsertLink(link)
end

ChatFrameUtil.InsertLink = overlayInsertLink
-- Keep the deprecated global alias in sync.
if _G.ChatEdit_InsertLink then
    _G.ChatEdit_InsertLink = overlayInsertLink
end
