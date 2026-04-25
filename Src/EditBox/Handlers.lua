--[[
    EditBox/Handlers.lua
    All overlay script handlers (OnTextChanged, OnEnterPressed,
    OnEscapePressed, OnKeyDown, OnHide, OnEditFocusLost/Gained),
    event registration, lockdown detection, and idle timer management.
]]

local _, YapperTable = ...
local EditBox        = YapperTable.EditBox

-- Re-localise shared helpers from hub.
local SLASH_MAP            = EditBox._SLASH_MAP
local GetLastTellTargetInfo = EditBox.GetLastTellTargetInfo

-- Resolve from Overlay.lua (loaded before us).
local ResolveChannelName   = EditBox._ResolveChannelName

-- Closure accessors for mutable hub-scoped locals.
local function UserBypassingYapper() return EditBox._UserBypassingYapper() end
local function SetUserBypassingYapper(v) EditBox._SetUserBypassingYapper(v) end

-- Re-localise Lua globals.
local type       = type
local tostring   = tostring
local tonumber   = tonumber
local strmatch   = string.match
local strlower   = string.lower
local strbyte    = string.byte

function EditBox:SetupOverlayScripts()
    local edit         = self.OverlayEdit
    local frame        = self.Overlay

    -- When true, we're changing text programmatically (skip OnTextChanged).
    local updatingText = false

    -- ── OnTextChanged: slash-command channel switches ──────────────────
    edit:SetScript("OnTextChanged", function(box, isUserInput)
        if updatingText then return end

        if YapperTable.Spellcheck and type(YapperTable.Spellcheck.OnTextChanged) == "function" then
            YapperTable.Spellcheck:OnTextChanged(box, isUserInput)
        end
        -- If a suggestion was just applied via numeric hotkey, the engine may
        -- also inject the numeric character into the editbox. Remove it here
        -- before further processing.
        if YapperTable.Spellcheck and YapperTable.Spellcheck._suppressNextChar then
            local sc = YapperTable.Spellcheck
            local textNow = box:GetText() or ""
            if sc._expectedText and sc._suppressChar and textNow == (sc._expectedText .. sc._suppressChar) then
                updatingText = true
                box:SetText(sc._expectedText)
                if sc._expectedCursor then box:SetCursorPosition(sc._expectedCursor) end
                updatingText = false
                sc._suppressNextChar = nil
                sc._suppressChar = nil
                sc._expectedText = nil
                sc._expectedCursor = nil
                return
            else
                sc._suppressNextChar = nil
                sc._suppressChar = nil
                sc._expectedText = nil
                sc._expectedCursor = nil
            end
        end
        if not isUserInput then return end

        local text = box:GetText() or ""

        -- Update autocomplete ghost text on every user keystroke.
        if YapperTable.Autocomplete and type(YapperTable.Autocomplete.OnTextChanged) == "function" then
            YapperTable.Autocomplete:OnTextChanged(box)
        end

        -- Icon gallery: detect open `{word` pattern and show/hide picker.
        if YapperTable.IconGallery then
            YapperTable.IconGallery:OnTextChanged(box, frame)
        end

        -- Auto-expand into multiline when text fills the overlay.
        local ml = YapperTable.Multiline
        if ml and type(ml.ShouldAutoExpand) == "function" and not ml.Active then
            local textW = box.GetStringWidth and box:GetStringWidth() or 0
            local boxW  = box.GetWidth and box:GetWidth() or 0
            if ml:ShouldAutoExpand(textW, boxW) then
                ml:Enter(text, self.ChatType, self.Language, self.Target)
                return
            end
        end

        if strbyte(text, 1) ~= 47 then -- '/'
            self.HistoryIndex = nil
            self.HistoryCache = nil
            return
        end

        -- Bare numeric channel: "/2 message"
        local num, rest = strmatch(text, "^/(%d+)%s+(.*)")
        if num then
            local resolved = ResolveChannelName(tonumber(num))
            if resolved then
                self.ChatType    = "CHANNEL"
                self.Target      = num
                self.ChannelName = resolved
                self.Language    = nil
                updatingText     = true
                box:SetText(rest or "")
                updatingText = false
                self:RefreshLabel()
                box:SetCursorPosition(#(rest or ""))
            end
            return
        end

        -- "/cmd rest" — need a space before we act.
        local cmd, rest2 = strmatch(text, "^/([%w_]+)%s+(.*)")
        if not cmd then return end
        cmd = strlower(cmd)

        -- /c, /channel — wait for a space after the channel ID too,
        -- so we don't fire while the user is still typing it.
        if cmd == "c" or cmd == "channel" then
            local ch, remainder = strmatch(rest2 or "", "^(%S+)%s+(.*)")
            if ch then
                local chNum = tonumber(ch)
                if chNum then
                    local resolved = ResolveChannelName(chNum)
                    if not resolved then return end
                    self.ChatType    = "CHANNEL"
                    self.Target      = tostring(chNum)
                    self.ChannelName = resolved
                else
                    self.ChatType    = "CHANNEL"
                    self.Target      = ch
                    self.ChannelName = nil
                end
                self.Language = nil
                updatingText = true
                box:SetText(remainder or "")
                updatingText = false
                self:RefreshLabel()
                box:SetCursorPosition(#(remainder or ""))
            end
            return
        end

        if cmd == "w" or cmd == "whisper" or cmd == "tell" or cmd == "t"
            or cmd == "cw" or cmd == "send" or cmd == "charwhisper" then
            local target, remainder = strmatch(rest2 or "", "^(%S+)%s+(.*)")
            if target then
                self.ChatType = "WHISPER"
                self.Target   = target
                self.Language = nil
                updatingText  = true
                box:SetText(remainder or "")
                updatingText = false
                self:RefreshLabel()
                box:SetCursorPosition(#(remainder or ""))
            end
            return
        end

        if cmd == "r" or cmd == "reply" then
            local lastType, lastTell = GetLastTellTargetInfo()
            if lastTell and lastTell ~= "" then
                self.ChatType = lastType
                self.Target   = lastTell
                self.Language = nil
                updatingText  = true
                box:SetText(rest2 or "")
                updatingText = false
                self:RefreshLabel()
                box:SetCursorPosition(#(rest2 or ""))
            end
            return
        end

        if SLASH_MAP[cmd] then
            local ct = SLASH_MAP[cmd]

            -- Intelligent Fallbacks for group types (Mirror Blizzard behavior)
            if ct == "INSTANCE_CHAT" then
                -- Target Instance Chat: Fallback to Raid or Party if not in Instance Category.
                if not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
                    if IsInRaid(LE_PARTY_CATEGORY_HOME) then
                        ct = "RAID"
                    elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
                        ct = "PARTY"
                    end
                end
            elseif ct == "PARTY" or ct == "PARTY_LEADER" then
                -- Target Party: Fallback to Instance if not in Home Party.
                if not IsInGroup(LE_PARTY_CATEGORY_HOME) and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
                    ct = "INSTANCE_CHAT"
                end
            elseif ct == "RAID" or ct == "RAID_LEADER" then
                -- Target Raid: Fallback to Instance if not in Home Raid.
                if not IsInRaid(LE_PARTY_CATEGORY_HOME) and IsInRaid(LE_PARTY_CATEGORY_INSTANCE) then
                    ct = "INSTANCE_CHAT"
                end
            end

            self.ChatType = ct
            self.Target   = nil
            updatingText  = true
            box:SetText(rest2 or "")
            updatingText = false
            self:RefreshLabel()
            box:SetCursorPosition(#(rest2 or ""))
            return
        end
    end)

    edit:SetScript("OnEnterPressed", function(box)
        if YapperTable.Spellcheck and YapperTable.Spellcheck._justAppliedSuggestion then
            return
        end
        -- Shift+Enter is consumed by OnKeyDown to enter multiline mode.
        -- Guard here too in case the key event fires OnEnterPressed anyway.
        if IsShiftKeyDown() then return end
        -- Also bail if multiline transition just started.
        local ml = YapperTable.Multiline
        if ml and ml.Active then return end
        local text = box:GetText() or ""
        local trimmed = strmatch(text, "^%s*(.-)%s*$") or ""

        if trimmed == "" then
            if self._openedFromBnetTransition
                and self.ChatType
                and self.ChatType ~= "BN_WHISPER" then
                self._preferStickyAfterBnet = true
            end
            self._closedClean = true
            if YapperTable.History then
                YapperTable.History:ClearDraft(box)
            end
            self:PersistLastUsed()
            self:Hide()
            return
        end

        -- Slash commands: some (/w Name, /r) won't have been consumed by
        -- OnTextChanged because it waits for a trailing space. Handle
        -- those here before forwarding anything unrecognised to Blizzard.
        if strbyte(trimmed, 1) == 47 then -- '/'
            local enterCmd, enterRest = strmatch(trimmed, "^/([%w_]+)%s*(.*)")
            if enterCmd then
                enterCmd = strlower(enterCmd)

                if enterCmd == "w" or enterCmd == "whisper"
                    or enterCmd == "tell" or enterCmd == "t"
                    or enterCmd == "cw" or enterCmd == "send" or enterCmd == "charwhisper" then
                    local target = strmatch(enterRest or "", "^(%S+)")
                    if target then
                        self.ChatType = "WHISPER"
                        self.Target   = target
                        self.Language = nil
                        -- Fix: Use self.OrigEditBox (eb was undefined here).
                        -- This suppresses the Blizzard UI 'ghost' when switching to whisper modes.
                        local eb      = self.OrigEditBox
                        if eb and eb.Hide and eb:IsShown() then
                            eb:Hide()
                        end
                        box:SetText("")
                        updatingText = false
                        self:RefreshLabel()
                        -- Don't close — user now has an empty whisper box.
                        return
                    end
                end

                if enterCmd == "r" or enterCmd == "reply" then
                    local lastType, lastTell = GetLastTellTargetInfo()
                    if lastTell and lastTell ~= "" then
                        self.ChatType = lastType
                        self.Target   = lastTell
                        self.Language = nil
                        updatingText  = true
                        box:SetText(enterRest or "")
                        updatingText = false
                        self:RefreshLabel()
                        box:SetCursorPosition(#(enterRest or ""))
                        return
                    end
                end

                if enterCmd == "c" or enterCmd == "channel" then
                    local ch = strmatch(enterRest or "", "^(%S+)")
                    if ch then
                        local chNum = tonumber(ch)
                        if chNum then
                            local resolved = ResolveChannelName(chNum)
                            if resolved then
                                self.ChatType    = "CHANNEL"
                                self.Target      = tostring(chNum)
                                self.ChannelName = resolved
                                self.Language    = nil
                                updatingText     = true
                                box:SetText("")
                                updatingText = false
                                self:RefreshLabel()
                                return
                            end
                        else
                            self.ChatType    = "CHANNEL"
                            self.Target      = ch
                            self.ChannelName = nil
                            self.Language    = nil
                            updatingText     = true
                            box:SetText("")
                            updatingText = false
                            self:RefreshLabel()
                            return
                        end
                    end
                end

                if SLASH_MAP[enterCmd] then
                    local ct = SLASH_MAP[enterCmd]

                    -- Intelligent Fallbacks for group types (Mirror Blizzard behavior)
                    if ct == "INSTANCE_CHAT" then
                        if not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
                            if IsInRaid(LE_PARTY_CATEGORY_HOME) then
                                ct = "RAID"
                            elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
                                ct = "PARTY"
                            end
                        end
                    elseif ct == "PARTY" or ct == "PARTY_LEADER" then
                        if not IsInGroup(LE_PARTY_CATEGORY_HOME) and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
                            ct = "INSTANCE_CHAT"
                        end
                    elseif ct == "RAID" or ct == "RAID_LEADER" then
                        if not IsInRaid(LE_PARTY_CATEGORY_HOME) and IsInRaid(LE_PARTY_CATEGORY_INSTANCE) then
                            ct = "INSTANCE_CHAT"
                        end
                    end

                    self.ChatType = ct
                    self.Target   = nil
                    self.Language = nil
                    updatingText  = true
                    box:SetText(enterRest or "")
                    updatingText = false
                    self:RefreshLabel()
                    box:SetCursorPosition(#(enterRest or ""))
                    if (enterRest or "") == "" then
                        return
                    end
                    -- Text after the command — fall through to send.
                end
            end

            if strbyte(trimmed, 1) == 47 then -- '/'
                self._closedClean = true
                if YapperTable.History then
                    YapperTable.History:ClearDraft(box)
                    -- Add regular slash commands to history (no channel context).
                    YapperTable.History:AddChatHistory(trimmed, nil, nil)
                end
                self:ForwardSlashCommand(trimmed)
                self:Hide()
                return
            end
        end

        -- If chat is locked down (combat/m+ lockdown), save draft and handoff
        -- ALSO hand off to blizz if we are manually sidestepping.
        -- note to self: if I am editing this, I am probably looking for
        -- the lockdown check further down. This one handles the case where
        -- we're already in lockdown, NOT when the lockdown initiates during
        -- user input.
        if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
            self:HandoffToBlizzard()
            return
        end

        -- If user is manually bypassing Yapper, hand off to Blizzard
        if UserBypassingYapper() then
            SetUserBypassingYapper(false)
            self:HandoffToBlizzard()
            return
        end

        -- If a suggestion is open or was just applied, accept the
        -- suggestion instead of sending. Spellcheck may apply the
        -- suggestion in OnKeyDown, which hides the frame immediately;
        -- we therefore also check the transient _justAppliedSuggestion
        -- flag as a final safety guard.
        if YapperTable.Spellcheck and type(YapperTable.Spellcheck.IsSuggestionOpen) == "function" then
            local sc = YapperTable.Spellcheck
            if sc:IsSuggestionOpen() or sc._justAppliedSuggestion then
                local idx = sc.ActiveIndex or 1
                if type(sc.ApplySuggestion) == "function" then
                    sc:ApplySuggestion(idx)
                end
                sc._justAppliedSuggestion = nil
                return
            end
        end

        local lang = self.Language
        if not lang then
            -- Fallback to sticky choice or character default.
            lang = (self.LastUsed and self.LastUsed.language) or (GetDefaultLanguage and GetDefaultLanguage())
        end

        if self.OnSend then
            self.OnSend(trimmed, self.ChatType or "SAY", lang, self.Target)
        else
            if C_ChatInfo and C_ChatInfo.SendChatMessage then
                C_ChatInfo.SendChatMessage(trimmed, self.ChatType or "SAY", lang, self.Target)
            end
        end

        -- Track outgoing whispers as reply targets too (move to front).
        if (self.ChatType == "WHISPER" or self.ChatType == "BN_WHISPER") and self.Target and self.Target ~= "" then
            self:AddReplyTarget(self.Target, self.ChatType)
        end

        if self.OrigEditBox then
            self.OrigEditBox:AddHistoryLine(text)
        end

        self._closedClean = true
        if YapperTable.History then
            YapperTable.History:ClearDraft(box)
        end
        self:PersistLastUsed()
        self:Hide()
    end)

    edit:SetScript("OnEscapePressed", function(box)
        -- If icon gallery is open, close it and stay.
        if YapperTable.IconGallery and YapperTable.IconGallery.Active then
            YapperTable.IconGallery:Hide()
            return
        end
        -- If spell suggestions are open, close them only and keep the
        -- overlay active. This prevents ESC from accidentally closing
        -- the whole overlay when the user expected to dismiss hints.
        if YapperTable.Spellcheck and type(YapperTable.Spellcheck.IsSuggestionOpen) == "function"
            and YapperTable.Spellcheck:IsSuggestionOpen() then
            YapperTable.Spellcheck:HideSuggestions()
            return
        end
        local text = box:GetText() or ""
        local cfg = YapperTable.Config and YapperTable.Config.EditBox or {}
        local recoverOnEscape = (cfg.RecoverOnEscape == true)
        if text == "" then
            self._closedClean = true
            if YapperTable.History then
                YapperTable.History:ClearDraft(box)
            end
        else
            if recoverOnEscape then
                -- User bailed with text in the box
                -- Draft is saved in OnHide below.
                self._closedClean = false
            else
                -- Save to history, but do not keep a draft.
                if YapperTable.History then
                    YapperTable.History:AddChatHistory(text, self.ChatType, self.Target)
                    YapperTable.History:MarkDirty(false)
                end
                self._closedClean = true
            end
        end
        box:SetText("")
        self:Hide()
    end)

    edit:HookScript("OnCursorChanged", function(box, x, y, w, h)
        if YapperTable.Spellcheck and type(YapperTable.Spellcheck.OnCursorChanged) == "function" then
            YapperTable.Spellcheck:OnCursorChanged(box, x, y, w, h)
        end
    end)

    -- Intercept OnChar to remove numeric hotkey characters appended after
    -- applying a suggestion. This ensures pressing '1'..'4' to select a
    -- suggestion does not also insert the digit into the editbox.
    edit:HookScript("OnChar", function(box, char)
        if YapperTable.IconGallery and YapperTable.IconGallery._suppressNextChar then
            local ig = YapperTable.IconGallery
            if ig._suppressChar == char then
                local expected = ig._expectedText or (box:GetText() or "")
                local cursor   = ig._expectedCursor
                box:SetText(expected)
                if cursor then box:SetCursorPosition(cursor) end
                ig._suppressNextChar = nil
                ig._suppressChar     = nil
                ig._expectedText     = nil
                ig._expectedCursor   = nil
                return
            end
        end
        if YapperTable.Spellcheck and YapperTable.Spellcheck._suppressNextChar then
            local sc = YapperTable.Spellcheck
            if sc._suppressChar == char then
                -- Immediately restore expected text/cursor and clear flags.
                local expected = sc._expectedText or (box:GetText() or "")
                local cursor = sc._expectedCursor
                box:SetText(expected)
                if cursor then box:SetCursorPosition(cursor) end
                sc._suppressNextChar = nil
                sc._suppressChar = nil
                sc._expectedText = nil
                sc._expectedCursor = nil
                return
            end
        end
    end)

    edit:HookScript("OnKeyDown", function(box, key)
        -- Let icon gallery consume ESC/numbers/Enter/Tab first.
        if YapperTable.IconGallery and YapperTable.IconGallery:HandleKeyDown(key) then
            return
        end
        if YapperTable.Spellcheck and type(YapperTable.Spellcheck.HandleKeyDown) == "function" then
            if YapperTable.Spellcheck:HandleKeyDown(key) then
                return
            end
        end
        if key == "ENTER" and IsShiftKeyDown() then
            -- Shift+Enter: expand into multi-line storyteller editor.
            local ml = YapperTable.Multiline
            if ml and type(ml.Enter) == "function" and not ml.Active then
                local text = box:GetText() or ""
                ml:Enter(text, self.ChatType, self.Language, self.Target)
                return
            end
        elseif key == "TAB" then
            -- If ALT is held we should not cycle chat targets; spellcheck
            -- already owns Alt+Tab behavior, so let it (or other handlers)
            -- handle the key instead.
            if IsAltKeyDown() then
                return
            end
            -- Try autocomplete acceptance first; fall through to channel cycling.
            if YapperTable.Autocomplete and type(YapperTable.Autocomplete.OnTabPressed) == "function" then
                if YapperTable.Autocomplete:OnTabPressed(edit) then
                    return
                end
            end
            self:CycleChat(IsShiftKeyDown() and -1 or 1)
        elseif key == "UP" then
            self:NavigateHistory(-1)
        elseif key == "DOWN" then
            self:NavigateHistory(1)
        end
    end)

    frame:SetScript("OnHide", function()
        self.HistoryIndex = nil
        self.HistoryCache = nil

        if YapperTable.IconGallery and YapperTable.IconGallery.Active then
            YapperTable.IconGallery:Hide()
        end

        if YapperTable.Spellcheck and type(YapperTable.Spellcheck.OnOverlayHide) == "function" then
            YapperTable.Spellcheck:OnOverlayHide()
        end

        if YapperTable.Autocomplete and type(YapperTable.Autocomplete.OnOverlayHide) == "function" then
            YapperTable.Autocomplete:OnOverlayHide()
        end

        if not self._closedClean and YapperTable.History then
            local eb = self.OverlayEdit
            if eb then
                local text = eb:GetText() or ""
                if text ~= "" then
                    YapperTable.History:SaveDraft(eb)
                    -- Normal (non-lockdown) saves should not be treated
                    -- as lockdown drafts.
                    self._lockdown.savedDraft = false
                end
                YapperTable.History:MarkDirty(true)
            end
        end
        self._closedClean = false
    end)

    -- When focus leaves the overlay editbox (e.g. clicking the game world),
    -- keep the overlay visible but let keypresses propagate through to the
    -- game so the player can move with WASD, use abilities, etc.
    edit:HookScript("OnEditFocusLost", function(box)
        self._overlayUnfocused = true
        if YapperTable.Spellcheck then
            YapperTable.Spellcheck:UpdateHint()
        end
        -- SetPropagateKeyboardInput removal: SetAutoFocus(false) allows
        -- native WASD fallback when focus is lost without triggering combat errors.
    end)

    edit:HookScript("OnEditFocusGained", function(box)
        self._overlayUnfocused = false
        if YapperTable.Spellcheck then
            YapperTable.Spellcheck:UpdateHint()
        end
    end)

    -- Combat lockdown detection
    -- When InChatMessagingLockdown becomes true mid-typing, hand the
    -- overlay state back to Blizzard's secure editbox.
    -- Lockdown may activate slightly AFTER PLAYER_REGEN_DISABLED, so
    -- we poll briefly via a ticker if the first check is negative.
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("CHALLENGE_MODE_START")
    frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    -- Track incoming whispers so we can cycle reply targets.
    frame:RegisterEvent("CHAT_MSG_WHISPER")
    frame:RegisterEvent("CHAT_MSG_BN_WHISPER")

    -- Also we want to watch for when the user shows or hides their UI, to close our editbox.
    UIParent:HookScript("OnHide", function()
        -- housing editor hides UIParent; don't close if the editor is active.
        if C_HouseEditor and C_HouseEditor.IsHouseEditorActive
            and C_HouseEditor.IsHouseEditorActive() then
            return
        end
        -- Make sure we're hidden.
        if EditBox.Overlay and EditBox.Overlay:IsShown() then
            EditBox:Hide()
        end
    end)

    frame:HookScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_REGEN_DISABLED" or event == "CHALLENGE_MODE_START" then
            -- Helper: begin the deferred handoff.
            local function beginDeferredHandoff()
                local text = self.OverlayEdit and self.OverlayEdit:GetText() or ""
                if text == "" then
                    if self._lockdown.idleTimer then
                        self._lockdown.idleTimer:Cancel()
                        self._lockdown.idleTimer = nil
                    end
                    self:HandoffToBlizzard()
                    return
                end

                self:ResetLockdownIdleTimer()

                -- Hook OnTextChanged to reset the idle timer while the user keeps typing.
                if not self._lockdown.textHooked and self.OverlayEdit then
                    self._lockdown.textHooked = true
                    self.OverlayEdit:HookScript("OnTextChanged", function(box, isUserInput)
                        if isUserInput and self._lockdown.idleTimer then
                            self:ResetLockdownIdleTimer()
                        end
                    end)
                end
            end

            -- Immediate check.
            if (YapperTable.Utils and YapperTable.Utils:IsChatLockdown()) or YapperTable.Config.System.DEBUG then
                if not self._lockdown.eventRunning then
                    self._lockdown.eventRunning = true
                    YapperTable.Utils:DebugPrint("Lockdown event triggered (DEBUG or real lockdown).")
                    beginDeferredHandoff()
                end
                return
            end
            -- Not in lockdown yet — poll briefly.
            if self._lockdown.ticker then
                self._lockdown.ticker:Cancel()
            end
            local ticks = 0
            self._lockdown.ticker = C_Timer.NewTicker(0.1, function(ticker)
                ticks = ticks + 1
                if not self.Overlay or not self.Overlay:IsShown() then
                    ticker:Cancel()
                    self._lockdown.ticker = nil
                    return
                end
                if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
                    beginDeferredHandoff()
                    ticker:Cancel()
                    self._lockdown.ticker = nil
                    return
                end
                if ticks >= 20 then -- 2 seconds
                    ticker:Cancel()
                    self._lockdown.ticker = nil
                end
            end)
        elseif event == "PLAYER_REGEN_ENABLED" or event == "CHALLENGE_MODE_COMPLETED" then
            -- Combat / M+ over — centralised cleanup.
            self:ClearLockdownState()
            -- If we saved a draft during lockdown, poll until lockdown
            -- is truly over (checks every 1s for up to 5s).
            if self._lockdown.handedOff then
                local checks = 0
                C_Timer.NewTicker(1, function(ticker)
                    checks = checks + 1
                    if not (YapperTable.Utils and YapperTable.Utils:IsChatLockdown()) then
                        self._lockdown.handedOff = false
                        -- If Blizzard sends during lockdown changed the channel,
                        -- persist that sticky choice now.
                        if self._lockdown.savedDuring then
                            self:PersistLastUsed()
                            self._lockdown.savedDuring = false
                        end
                        -- Allow Show-hook lockdown logic to run again after lockdown.
                        self._lockdown.showHandled = false
                        YapperTable.Utils:Print("info", "Lockdown ended — press Enter to resume typing.")
                        ticker:Cancel()
                        return
                    end
                    if checks >= 5 then
                        ticker:Cancel()
                    end
                end)
            end
        elseif event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then
            -- Incoming whisper: arg2 is sender name for both events.
            local sender = select(2, ...)
            if sender and sender ~= "" then
                if event == "CHAT_MSG_BN_WHISPER" then
                    self:AddReplyTarget(sender, "BN_WHISPER")
                else
                    self:AddReplyTarget(sender, "WHISPER")
                end
            end
        end
    end)
end

function EditBox:ResetLockdownIdleTimer()
    if self._lockdown.idleTimer then
        self._lockdown.idleTimer:Cancel()
    end
    YapperTable.Utils:DebugPrint("Lockdown handoff timer started/reset (1.5s idle wait)...")
    self._lockdown.idleTimer = C_Timer.NewTimer(1.5, function()
        -- Sanity check: if the overlay was closed normally (sent or escaped)
        -- in the meantime, do not execute the handoff.
        if not self.Overlay or not self.Overlay:IsShown() then
            YapperTable.Utils:DebugPrint("Timer fired but overlay was hidden - bailing handoff.")
            self._lockdown.idleTimer = nil
            return
        end

        YapperTable.Utils:DebugPrint("Lockdown idle timer fired!")
        self._lockdown.idleTimer = nil
        self:HandoffToBlizzard()
    end)
end

