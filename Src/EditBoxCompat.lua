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
                return _G.DEFAULT_CHAT_FRAME[key]
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

    -- This box is never a real "window" for Blizzard's activation
    -- bookkeeping: ActivateChat/SetLastActiveWindow must early-return on
    -- it. Without the flag, FocusActiveWindow (static popups, TRP3's
    -- chat-link inserter, pet journal) activates the overlay while we own
    -- ACTIVE_CHAT_EDIT_BOX and writes LAST_ACTIVE_CHAT_EDIT_BOX, which is
    -- never cleared (the mixin OnHide that resets it does not exist on a
    -- plain editbox). Under chatStyle=="im" every later
    -- SetLastActiveWindow then calls previousValue:Hide() -- hiding the
    -- input widget while the overlay frame stays up. A hidden editbox
    -- still takes SetFocus and fires OnEnterPressed, so users typed blind
    -- while sends kept working. disableActivate also preserves
    -- CHAT_FOCUS_OVERRIDE, which ActivateChat clears (the pre-ownership
    -- FocusActiveWindow wrapper existed to prevent exactly that).
    box.disableActivate = true

    -- The widget's visibility is owned by its parent frame; nothing may
    -- hide the editbox itself. LAST_ACTIVE_CHAT_EDIT_BOX writes that
    -- bypass ActivateChat/SetLastActiveWindow (direct global writes) can
    -- still expose the box to previousValue:Hide(), and addons may call
    -- Hide() on the "active window" outright. Post-hook re-show so addon
    -- code never runs inside the caller's stack.
    hooksecurefunc(box, "Hide", function() box:Show() end)
    -- Same ownership invariant for alpha and mouse: editbox-skinning
    -- addons (Prat's Editbox module, Chatter) secure-hook
    -- ChatFrameUtil.DeactivateChat and fade + mouse-disable whatever
    -- frame is deactivated -- including our editors when they release
    -- ACTIVE_CHAT_EDIT_BOX on close, while they are still shown. Alpha
    -- and mouse state persist across hide/show and nothing re-asserts
    -- them, so the first deactivate left every later open
    -- invisible-but-focused (typing, sends, and channel switches all
    -- worked blind). Yapper never fades or mouse-disables its own
    -- editors, so re-assert unconditionally; the flags stop recursion
    -- from our own re-invocation.
    do
        local reassertingAlpha = false
        hooksecurefunc(box, "SetAlpha", function(_, alpha)
            if reassertingAlpha then return end
            if type(alpha) == "number" and alpha > 0 then return end
            reassertingAlpha = true
            box:SetAlpha(1)
            reassertingAlpha = false
        end)
        local reassertingMouse = false
        hooksecurefunc(box, "EnableMouse", function(_, enabled)
            if reassertingMouse then return end
            if enabled then return end
            reassertingMouse = true
            box:EnableMouse(true)
            reassertingMouse = false
        end)
    end
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
    -- The overlay frame owns widget visibility: suspend focus watchers
    -- while it is closed so the poll ticker can stop entirely when
    -- nothing is open. Covers every close path, including multiline
    -- entry hiding the frame without EditBox:Hide().
    if self.Overlay then
        hooksecurefunc(self.Overlay, "Show", function()
            EditBox:SetFocusWatcherActive(EditBox.OverlayEdit, true)
        end)
        hooksecurefunc(self.Overlay, "Hide", function()
            EditBox:SetFocusWatcherActive(EditBox.OverlayEdit, false)
        end)
    end
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
    local multilineEdit = YapperTable.Multiline and YapperTable.Multiline.EditBox

    -- LAST_ACTIVE_CHAT_EDIT_BOX must never hold our editor either:
    -- im-mode ChooseBoxForSend/SetLastActiveWindow paths treat it as a
    -- real window box (including previousValue:Hide()). disableActivate
    -- blocks Blizzard's writers, but a direct global write can still land
    -- here -- hand it back to the default box when we spot it.
    local lastActive = _G.LAST_ACTIVE_CHAT_EDIT_BOX
    if lastActive == self.OverlayEdit or (multilineEdit and lastActive == multilineEdit) then
        _G.LAST_ACTIVE_CHAT_EDIT_BOX = DEFAULT_CHAT_FRAME.editBox
    end

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
            local ok, err = pcall(ChatFrameUtil.DeactivateChat, current)
            if not ok and YapperTable.Utils then
                YapperTable.Utils:VerbosePrint("DeactivateChat failed: " .. YapperTable.Utils:SafeToString(err))
            end
        end
        _G.ACTIVE_CHAT_EDIT_BOX = desired
    else
        -- Only release ownership when WE hold the slot; never touch a
        -- genuinely active Blizzard editbox.
        if current == self.OverlayEdit or (multilineEdit and current == multilineEdit) then
            local ok, err = pcall(ChatFrameUtil.DeactivateChat, current)
            if not ok and YapperTable.Utils then
                YapperTable.Utils:VerbosePrint("DeactivateChat failed: " .. YapperTable.Utils:SafeToString(err))
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

-- Refocus the visible editor after Blizzard's FocusActiveWindow.
-- ActivateChat early-returns on our boxes (disableActivate above), which
-- is what the bookkeeping needs, but static-popup/link-insert flows call
-- FocusActiveWindow to hand chat focus back to the user -- the
-- pre-ownership wrapper refocused our editor directly. A post-hook
-- restores that without tainting the caller's stack.
do
    hooksecurefunc(ChatFrameUtil, "FocusActiveWindow", function()
        local activeEditor = EditBox.GetActiveEditor and EditBox:GetActiveEditor()
        if activeEditor
            and ChatFrameUtil.GetActiveWindow() == activeEditor
            and not EditBox._preShowSuppressed
            and not (EditBox._UserBypassingYapper and EditBox._UserBypassingYapper())
            and not (EditBox._BypassEditBox and EditBox._BypassEditBox())
            and not (YapperTable.Utils and YapperTable.Utils:IsChatLockdown())
            and activeEditor.SetFocus then
            activeEditor:SetFocus()
        end
    end)
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
-- ticker -- timer callbacks always run outside foreign stacks. Reads go
-- through PollFocusState: under enforced addon restrictions (encounters,
-- M+, lockdown) HasFocus can return a SECRET boolean, and a boolean test
-- on a secret raises "attempt to perform boolean test on a secret boolean
-- value" from tainted code. An unreadable sample degrades to "unknown"
-- instead of fabricating a state.
local FOCUS_POLL_INTERVAL = 0.05

-- Secret-safe HasFocus read. The truthiness coercion must stay inside the
-- pcall: that is the expression that errors on a secret return. Returns
-- true/false when readable, nil ("unknown") when the call errors or the
-- result is a secret that cannot be tested.
local function PollFocusState(box)
    if not (box and box.HasFocus) then return nil end
    local ok, focused = pcall(function()
        return box:HasFocus() and true or false
    end)
    if not ok then return nil end
    return focused
end

-- Watcher lifecycle: entries are per-box ({box, subs, focused, suspended})
-- and only polled while the box is open. Suspending delivers a pending
-- lost-edge first -- a closed box cannot hold focus, and subscribers
-- (bypass clearing, typing-state, draft snapshots) must see the same
-- transition the uninterrupted poll would have fired one tick later.

function EditBox:_FireFocusEdge(w, focused)
    for j = 1, #w.subs do
        local fn = focused and w.subs[j].onGained or w.subs[j].onLost
        -- Contain per subscriber: a callback that touches secret state
        -- (GetText etc. under addon restrictions) must not starve the
        -- remaining subscribers or error the poll loop itself.
        if fn then pcall(fn, w.box) end
    end
end

-- Start the poll ticker when at least one watcher is active; cancel it
-- when every watched box is closed/suspended.
function EditBox:_UpdateFocusPollTicker()
    local watchers = self._focusWatchers
    local anyActive = false
    if watchers then
        for i = 1, #watchers do
            if not watchers[i].suspended then
                anyActive = true
                break
            end
        end
    end
    if anyActive then
        if not self._focusPollTicker then
            self._focusPollTicker = C_Timer.NewTicker(FOCUS_POLL_INTERVAL, function()
                self:_PollFocusWatchers()
            end)
        end
    elseif self._focusPollTicker then
        self._focusPollTicker:Cancel()
        self._focusPollTicker = nil
    end
end

--- Suspend or resume edge detection for a watched box. Suspension while
--- the box was last seen focused delivers the lost edge to subscribers
--- before sleeping (a hidden box cannot hold focus); resuming resumes the
--- poll against the last observed state, so a focus change that happened
--- while suspended still fires its edge once readable.
--- @param editBox table  A box previously passed to RegisterFocusWatcher.
--- @param active boolean
function EditBox:SetFocusWatcherActive(editBox, active)
    local watchers = self._focusWatchers
    if watchers then
        for i = 1, #watchers do
            local w = watchers[i]
            if w.box == editBox then
                if active then
                    w.suspended = nil
                elseif not w.suspended then
                    if w.focused == true then
                        w.focused = false
                        self:_FireFocusEdge(w, false)
                    end
                    w.suspended = true
                end
            end
        end
    end
    self:_UpdateFocusPollTicker()
end

function EditBox:RegisterFocusWatcher(editBox, onGained, onLost)
    if not editBox then return end
    local watchers = self._focusWatchers
    if not watchers then
        watchers = {}
        self._focusWatchers = watchers
    end
    -- One entry per box: re-registering the same callback pair is a
    -- no-op; a different pair appends a subscriber to the shared entry
    -- (Handlers + History both watch OverlayEdit, for example).
    local w
    for i = 1, #watchers do
        if watchers[i].box == editBox then
            w = watchers[i]
            break
        end
    end
    if not w then
        w = {
            box = editBox,
            subs = {},
            focused = PollFocusState(editBox),
        }
        watchers[#watchers + 1] = w
        -- Suspend tracking for foreign boxes (Blizzard chat editboxes):
        -- widget Show/Hide post-hooks are trampoline-isolated like the
        -- ticker itself. Our own editors skip this -- their widget Hide is
        -- vetoed by the compat install, so the container frame's hooks
        -- (installed by the CreateOverlay/Multiline wrappers) drive
        -- suspension instead.
        if not editBox._yapperCompatInstalled then
            hooksecurefunc(editBox, "Show", function()
                self:SetFocusWatcherActive(editBox, true)
            end)
            hooksecurefunc(editBox, "Hide", function()
                self:SetFocusWatcherActive(editBox, false)
            end)
        end
        -- A box closed at registration sleeps until its first Show;
        -- IsVisible covers children of hidden parents.
        local utils = YapperTable.Utils
        if utils and utils.SafeWidgetBoolean
            and utils:SafeWidgetBoolean(editBox, "IsVisible") == false then
            w.suspended = true
        end
    end
    for i = 1, #w.subs do
        local s = w.subs[i]
        if s.onGained == onGained and s.onLost == onLost then
            return
        end
    end
    w.subs[#w.subs + 1] = { onGained = onGained, onLost = onLost }
    self:_UpdateFocusPollTicker()
end

function EditBox:_PollFocusWatchers()
    local watchers = self._focusWatchers
    if not watchers then return end
    for i = 1, #watchers do
        local w = watchers[i]
        if not w.suspended then
            local focused = PollFocusState(w.box)
            if focused ~= nil then
                if w.focused == nil then
                    -- First readable sample establishes the baseline; an
                    -- edge cannot be claimed for a transition never
                    -- observed.
                    w.focused = focused
                elseif focused ~= w.focused then
                    w.focused = focused
                    self:_FireFocusEdge(w, focused)
                end
            end
            -- focused == nil: secret/unreadable under addon restrictions.
            -- Keep the last observed state; any real edge still fires once
            -- reads work again, and no spurious edge is emitted meanwhile.
        end
    end
end




