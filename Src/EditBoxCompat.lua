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
-- Publish the real editor through ACTIVE_CHAT_EDIT_BOX without replacing
-- Blizzard's accessor functions. This preserves their native implementation
-- for link insertion, but it is not a security boundary: addon assignments
-- can taint the global slot and later native readers of it. Neither a direct
-- write nor a call to Blizzard's plain Lua setter elevates execution.
--
-- The slot is claimed and released by writing the global directly -- NOT
-- through DeactivateChat. DeactivateChat runs Blizzard's Deactivate ->
-- Hide/ClearFocus -> OnHide -> SetLastActiveWindow -> Show/ActivateChat
-- bookkeeping plus every third-party hook on that chain (Prat, WIM,
-- TRP3...), and any of those can funnel back through our Show/OnShow
-- handlers and re-enter this sync; unbounded nesting there is a C stack
-- overflow. So this function is LEAF-ONLY: reads plus plain global
-- writes. The one side-effectful step -- DeactivateChat on a foreign box
-- we displaced -- is deferred to a coalesced pass on a fresh timer stack.
-- We do NOT go through ActivateChat to claim either: it would also write
-- LAST_ACTIVE_CHAT_EDIT_BOX, letting IM-mode ChooseBoxForSend hand the
-- overlay to SendTell paths that expect full native editboxes.

function EditBox:_SyncActiveChatWindow()
    -- Re-entry guard: nested calls only mark a pending re-check; the
    -- outermost pass finishes the writes and the deferred pass below
    -- re-evaluates on a clean stack.
    if self._syncActiveWindowRunning then
        self._syncActiveWindowPending = true
        return
    end
    self._syncActiveWindowRunning = true

    local ok, err = pcall(function()
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
            -- Claim is a plain global write: GetActiveWindow reports our
            -- editor immediately, without running any Blizzard code inside
            -- whatever stack reached us.
            _G.ACTIVE_CHAT_EDIT_BOX = desired
            -- A foreign box displaced by the claim still needs its Deactivate
            -- bookkeeping (classic style hides it, im style fades it). Defer
            -- that to the pass below; our own editors need nothing since
            -- their Deactivate is a stub.
            if current
                and current ~= self.OverlayEdit
                and (not multilineEdit or current ~= multilineEdit) then
                self._syncDisplace = current
            end
        else
            -- Only release ownership when WE hold the slot; never touch a
            -- genuinely active Blizzard editbox. Release is a plain write
            -- too: our editors' Deactivate is a stub, so DeactivateChat
            -- only ever cleared this global while inviting foreign
            -- post-hooks into our stack.
            if current == self.OverlayEdit or (multilineEdit and current == multilineEdit) then
                _G.ACTIVE_CHAT_EDIT_BOX = nil
            end
        end
    end)
    self._syncActiveWindowRunning = nil
    if not ok and YapperTable.Utils then
        YapperTable.Utils:VerbosePrint("_SyncActiveChatWindow failed: " .. YapperTable.Utils:SafeToString(err))
    end

    -- Deferred pass: displaced holders get real DeactivateChat bookkeeping
    -- here, on a fresh timer stack where re-entry can never overflow the C
    -- stack. The trailing UpdateFocusOverride also settles any pending
    -- re-check marked by nested calls.
    if (self._syncDisplace or self._syncActiveWindowPending)
        and not self._syncActiveWindowTimer then
        self._syncActiveWindowPending = nil
        self._syncActiveWindowTimer = true
        C_Timer.After(0, function()
            self._syncActiveWindowTimer = nil
            local displace = self._syncDisplace
            self._syncDisplace = nil
            -- Skip when the displaced box was legitimately re-activated in
            -- the meantime: it is then the active window on its own merit.
            if displace and ChatFrameUtil.GetActiveWindow() ~= displace then
                local dok, derr = pcall(ChatFrameUtil.DeactivateChat, displace)
                if not dok and YapperTable.Utils then
                    YapperTable.Utils:VerbosePrint("DeactivateChat failed: " .. YapperTable.Utils:SafeToString(derr))
                end
            end
            if self.UpdateFocusOverride then
                self:UpdateFocusOverride()
            end
        end)
    else
        -- A pass is already queued (or nothing is owed); the queued
        -- UpdateFocusOverride covers this re-check.
        self._syncActiveWindowPending = nil
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

-- Focus edges without frame scripts or polling.
--
-- OnEditFocusGained/OnEditFocusLost installed via SetScript/HookScript
-- execute inside whatever call stack drove the focus change -- e.g.
-- InsertLink's activeWindow:SetFocus() inside a map-pin CHATLINK click --
-- and any addon Lua there taints the remainder of that stack (12.1 follows
-- InsertLink with the protected CopyToClipboard, which then errors
-- ADDON_ACTION_FORBIDDEN). A perpetual HasFocus() ticker was the previous
-- answer and produced two failure modes of its own: raw boolean tests
-- erroring on secret returns under addon restrictions, and subscriber
-- callbacks cascading back through our own hooks from inside the poll.
-- Neither mechanism is needed: the calls that move keyboard focus are
-- enumerable -- SetFocus/ClearFocus on the box, ActivateChat/
-- DeactivateChat on the window, container Hide, Escape/Enter -- and
-- hooksecurefunc post-hooks run on the secure trampoline, taint-free.
-- The only transition no Lua-visible call covers is a click on an
-- unrelated non-chat widget; staleness there is cosmetic and corrects on
-- the next signal, while IsEditorFocused stays queryable (secret-safe)
-- for any path needing ground truth.
--
-- Per-box state is a CACHE: refreshed by every signal and by every
-- successful read; an unreadable (secret) read leaves the cache alone.

-- Secret-safe HasFocus read. The truthiness coercion must stay inside
-- the pcall: that is the expression that errors on a secret return.
local function ReadFocus(box)
    if not box then return nil end
    local ok, focused = pcall(function() return box:HasFocus() and true or false end)
    if not ok then return nil end
    return focused
end

--- Register gained/lost callbacks for an editbox. Edges are delivered
--- from post-hooks on the calls that move focus (SetFocus/ClearFocus on
--- the box itself, installed here; ActivateChat/DeactivateChat/container
--- signals wired in the hook modules) -- never from a poll ticker or
--- OnEditFocus* scripts.
--- @param editBox table
--- @param onGained function|nil  Called as fn(box).
--- @param onLost   function|nil  Called as fn(box).
function EditBox:RegisterFocusHandler(editBox, onGained, onLost)
    if not editBox then return end
    local handlers = self._focusHandlers
    if not handlers then
        handlers = {}
        self._focusHandlers = handlers
    end
    local h = handlers[editBox]
    if not h then
        h = { subs = {}, focused = ReadFocus(editBox) }
        handlers[editBox] = h
        if type(editBox.SetFocus) == "function" then
            hooksecurefunc(editBox, "SetFocus", function()
                self:_NotifyFocus(editBox, true)
            end)
        end
        if type(editBox.ClearFocus) == "function" then
            hooksecurefunc(editBox, "ClearFocus", function()
                self:_NotifyFocus(editBox, false)
            end)
        end
    end
    h.subs[#h.subs + 1] = { onGained = onGained, onLost = onLost }
end

--- Deliver a focus edge for a box from a focus-moving signal. Dedupes
--- against the cached state; each subscriber is pcall'd so a callback
--- that touches secret state cannot starve the rest or error the signal.
function EditBox:_NotifyFocus(editBox, focused)
    local h = self._focusHandlers and self._focusHandlers[editBox]
    if not h or h.focused == focused then return end
    h.focused = focused
    for i = 1, #h.subs do
        local fn = focused and h.subs[i].onGained or h.subs[i].onLost
        if fn then pcall(fn, editBox) end
    end
end

--- Notify every registered box EXCEPT the one just focused/activated:
--- keyboard focus is exclusive, so a signal that grants focus elsewhere
--- is a lost edge for every other watched box.
function EditBox:_NotifyFocusStolen(exceptBox)
    local handlers = self._focusHandlers
    if not handlers then return end
    for box in pairs(handlers) do
        if box ~= exceptBox then
            self:_NotifyFocus(box, false)
        end
    end
end

--- Last known focus state for a box: a fresh secret-safe read when the
--- engine will answer (the cache absorbs it), the signal-tracked cache
--- when it will not.
function EditBox:IsEditorFocused(box)
    local live = ReadFocus(box)
    if live ~= nil then
        local h = self._focusHandlers and self._focusHandlers[box]
        if h then h.focused = live end
        return live
    end
    local h = self._focusHandlers and self._focusHandlers[box]
    return (h and h.focused) == true
end






-- ---------------------------------------------------------------------------
-- Dedicated whisper window warning
-- ---------------------------------------------------------------------------
-- Retail 12.1 hardens chat internals with secret values and
-- DisallowTaintedAccess tables. When whisperMode is "popout" or
-- "popout_and_inline", Blizzard creates dedicated whisper windows inside
-- whichever execution context opened them -- including a tainted addon
-- send chain. State written for that window (dedicatedWindows, window
-- lists, tab alerting) inherits the taint, and later message dispatches
-- that read it hard-fail on the now-secret whisper args: whispers drop,
-- /r breaks, tab alerting errors. Warn once per session while the mode
-- can poison the chat stack.
local whisperModeWarningFrame = CreateFrame("Frame")
whisperModeWarningFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
whisperModeWarningFrame:SetScript("OnEvent", function(_, event)
    if whisperModeWarningFrame._shown then return end
    C_Timer.After(5, function()
        local mode = GetCVar("whisperMode")
        if mode ~= "popout" and mode ~= "popout_and_inline" then return end
        if _G.YapperDB and _G.YapperDB.WhisperModeWarningDismissed then return end
        whisperModeWarningFrame._shown = true
        StaticPopup_Show("YAPPER_WHISPER_MODE_WARNING")
    end)
end)
