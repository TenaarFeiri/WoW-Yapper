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

    -- Addons like TRP3 expect the active editbox to expose .chatFrame and
    -- .header. The shim redirects .editBox back to our box so TRP3's
    -- shift-click name replacement (ChatFrame.lua:766) targets Yapper's
    -- editor instead of Blizzard's ChatFrame1EditBox.
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

    -- No-op stubs: prevent nil-method crashes when ChatFrameUtil or addons
    -- manage Yapper as an active chat box.
    box.Deactivate = box.Deactivate or function() end
    box.UpdateHeader = box.UpdateHeader or function() end
    box.SetFocusRegionsShown = box.SetFocusRegionsShown or function() end
    box.UpdateNewcomerEditBoxHint = box.UpdateNewcomerEditBoxHint or function() end
    -- Write-through setters: native paths that land on the overlay as the
    -- active/last-active window (FocusActiveWindow -> ActivateChat ->
    -- LAST_ACTIVE_CHAT_EDIT_BOX, then IM-mode SendTell/SendBNetTell via
    -- ChooseBoxForSend) call these expecting a full Blizzard editbox.
    -- Mirroring the GetAttribute/GetChatType getters keeps the state pair
    -- consistent; targets are sanitized again at send time.
    box.SetChatType = box.SetChatType or function(_, chatType) EditBox.ChatType = chatType end
    box.SetTellTarget = box.SetTellTarget or function(_, target) EditBox.Target = target end
    box.SetStickyType = box.SetStickyType or function() end
    box.GetStickyType = box.GetStickyType or function() return "SAY" end
    -- Deprecated wrappers like ChatEdit_SendText(editBox) drive Blizzard's
    -- SendText path, which expects these mixin methods. ParseText must be
    -- real (below); the rest stay harmless no-ops.
    box.OnPreSendText = box.OnPreSendText or function() end
    box.AddHistory = box.AddHistory or function() end

    -- Functional ParseText (feature parity, not pipeline hijacking).
    -- Blizzard's SendText -- which addons like Paste/PasteNG invoke via
    -- ChatEdit_SendText on the "active window" -- calls ParseText(1) BEFORE
    -- dispatching. Since GetActiveWindow hands those addons our overlay, a
    -- no-op ParseText would drop slash commands or send them as chat text.
    -- So: run slash lines through Blizzard's registry and clear the box so
    -- SendText sends nothing; leave plain text for SendText to dispatch
    -- verbatim via GetChatType()/languageID.
    function box:ParseText(send)
        -- Only act on the send path; parse-only calls (send ~= 1) are no-ops.
        if send ~= 1 then return end
        -- Canonical read: harmless on foreign boxes, required on ours.
        local text = YapperTable.Recolour.CanonicalText(self)
        if not text or text == "" then return end
        local trimmed = text:match("^%s*(.-)%s*$") or ""
        if trimmed:sub(1, 1) ~= "/" then return end -- plain text: SendText handles it
        -- Slash line: run through Blizzard's registry and clear the box so
        -- SendText sends nothing.
        if EditBox.ForwardSlashCommand then
            EditBox:ForwardSlashCommand(trimmed)
        end
        self:SetText("")
    end

    -- supportsSlashCommands = false keeps Blizzard's CHAT_FOCUS_OVERRIDE
    -- path out of slash-typed text ("/" key, "/w name"). With true, Blizzard
    -- would SetText("/") AND the physical keypress would fire OnChar on the
    -- focused overlay, producing "//". With false, slash text takes the
    -- normal path our Show() hook intercepts; non-slash content (item links,
    -- empty open) still flows through CHAT_FOCUS_OVERRIDE.
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

-- Blizzard's active-window ownership.
--
-- GetActiveWindow/FocusActiveWindow are deliberately left UNTOUCHED. The
-- previous implementation swapped in Yapper wrappers so Blizzard's queries
-- returned our editor, but any addon function inside a Blizzard call stack
-- taints the rest of that stack: ChatFrameUtil.InsertLink calls
-- GetActiveWindow internally, and since 12.1 a waypoint pin's
-- OnMouseClickAction calls the protected CopyToClipboard right after
-- InsertLink -- the wrapper made every shift-clicked map pin raise
-- ADDON_ACTION_FORBIDDEN blamed on Yapper.
--
-- Instead we own the real ACTIVE_CHAT_EDIT_BOX global (a plain value slot;
-- writing it doesn't taint -- only addon FUNCTIONS in the call stack do).
-- GetActiveWindow then returns our editor with a fully secure call chain,
-- and InsertLink's Insert/SetFocus are C methods, so the whole path stays
-- untainted while still landing links in our editor.
--
-- DeactivateChat is used to release: it clears the global through
-- Blizzard's own bookkeeping and calls our stubbed Deactivate. We do NOT
-- go through ActivateChat to claim: it would also write
-- LAST_ACTIVE_CHAT_EDIT_BOX, letting IM-mode ChooseBoxForSend hand the
-- overlay to SendTell paths that expect full native editboxes.

function EditBox:_SyncActiveChatWindow()
    if not (ChatFrameUtil and ChatFrameUtil.GetActiveWindow) then return end

    local activeEditor = self.GetActiveEditor and self:GetActiveEditor()
    local desired = activeEditor
    if self._chatCompatEnabled == false
        or (self._lockdown and self._lockdown.handedOff)
        or (self._UserBypassingYapper and self._UserBypassingYapper())
        or (self._BypassEditBox and self._BypassEditBox())
        or (YapperTable.Utils and YapperTable.Utils:IsChatLockdown()) then
        desired = nil
    end

    local current = ChatFrameUtil.GetActiveWindow()
    if current == desired then return end

    if desired then
        if current then
            -- Displace the previous holder through Blizzard's own path so
            -- its Deactivate bookkeeping still runs.
            if ChatFrameUtil.DeactivateChat then
                pcall(ChatFrameUtil.DeactivateChat, current)
            end
        end
        _G.ACTIVE_CHAT_EDIT_BOX = desired
    else
        -- Only release ownership when WE hold the slot; never touch a
        -- genuinely active Blizzard editbox.
        local multilineEdit = YapperTable.Multiline and YapperTable.Multiline.EditBox
        if current == self.OverlayEdit or (multilineEdit and current == multilineEdit) then
            if ChatFrameUtil.DeactivateChat then
                pcall(ChatFrameUtil.DeactivateChat, current)
            else
                _G.ACTIVE_CHAT_EDIT_BOX = nil
            end
        end
    end
end

-- Lockdown/close ownership of the active-window slot. Lifecycle callers
-- disable before handoff and re-enable after recovery; the flag is the
-- gate _SyncActiveChatWindow consults so a hidden/bypassed editor can
-- never claim ACTIVE_CHAT_EDIT_BOX.
function EditBox:SetChatCompatibilityEnabled(enabled)
    self._chatCompatEnabled = enabled and true or false
    if self._SyncActiveChatWindow then
        self:_SyncActiveChatWindow()
    end
end

-- Focus-edge watching without frame scripts.
--
-- OnEditFocusGained/OnEditFocusLost installed via SetScript/HookScript
-- execute inside whatever call stack drove the focus change -- e.g.
-- InsertLink's activeWindow:SetFocus() inside a map-pin CHATLINK click --
-- and any addon Lua there taints the remainder of that stack (12.1 follows
-- InsertLink with the protected CopyToClipboard, which then errors
-- ADDON_ACTION_FORBIDDEN, but only on the click that actually moves
-- focus). hooksecurefunc post-hooks are invoked through the secure
-- trampoline and do not taint the caller; frame scripts have no such
-- isolation, so focus transitions are detected by polling HasFocus from a
-- ticker -- timer callbacks always run outside foreign stacks.
local FOCUS_POLL_INTERVAL = 0.05

function EditBox:RegisterFocusWatcher(editBox, onGained, onLost)
    if not editBox then return end
    local watchers = self._focusWatchers
    if not watchers then
        watchers = {}
        self._focusWatchers = watchers
    end
    watchers[#watchers + 1] = {
        box = editBox,
        focused = editBox.HasFocus and editBox:HasFocus() and true or false,
        onGained = onGained,
        onLost = onLost,
    }
    if not self._focusPollTicker and C_Timer and C_Timer.NewTicker then
        self._focusPollTicker = C_Timer.NewTicker(FOCUS_POLL_INTERVAL, function()
            self:_PollFocusWatchers()
        end)
    end
end

function EditBox:_PollFocusWatchers()
    local watchers = self._focusWatchers
    if not watchers then return end
    for i = 1, #watchers do
        local w = watchers[i]
        local box = w.box
        local focused = box and box.HasFocus and box:HasFocus() and true or false
        if focused ~= w.focused then
            w.focused = focused
            local fn = focused and w.onGained or w.onLost
            if fn then fn(box) end
        end
    end
end




