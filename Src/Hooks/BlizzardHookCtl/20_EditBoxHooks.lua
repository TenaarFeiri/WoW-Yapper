local _, YapperTable = ...
local EditBox = YapperTable.EditBox
local State = YapperTable.State

local Ctl = YapperTable.BlizzardHookCtl
local Core = Ctl.Core
local CHATTYPE_TO_OVERRIDE_KEY = Ctl.CHATTYPE_TO_OVERRIDE_KEY
local ResolveChannelName = Ctl.ResolveChannelName
local UserBypassingYapper = Ctl.UserBypassingYapper
local SetUserBypassingYapper = Ctl.SetUserBypassingYapper
local BypassEditBox = Ctl.BypassEditBox
local SetBypassEditBox = Ctl.SetBypassEditBox
local TriggerTrace = Ctl.TriggerTrace
local StampRecentOpenChatIntent = Ctl.StampRecentOpenChatIntent
local ParseLinkType = Ctl.ParseLinkType
local GATE_SKIP_SETTEXT_INTENT_ADOPTION_ON_EXPLICIT = Ctl.GATE_SKIP_SETTEXT_INTENT_ADOPTION_ON_EXPLICIT

local type = type
local tonumber = tonumber
local tostring = tostring
function EditBox:HookBlizzardEditBox(blizzEditBox)
    if self.HookedBoxes[blizzEditBox] then return end
    self.HookedBoxes[blizzEditBox] = true
    self._attrCache[blizzEditBox] = {}

    -- Capture chatType / tellTarget / channelTarget as they're set.
    -- BNet whisper: attributes arrive BEFORE Show.
    -- WoW whisper:  attributes arrive one frame AFTER Show (deferred).
    -- The live-update path below handles the deferred case.
    hooksecurefunc(blizzEditBox, "SetAttribute", function(eb, key, value)
        -- Skip if we're syncing attributes from Yapper to Blizzard
        -- to avoid RefreshLabel → SyncAttributesToBlizzard → SetAttribute → RefreshLabel loop
        if self._syncingAttributes then return end

        local c = self._attrCache[eb]
        if not c then
            c = {}
            self._attrCache[eb] = c
        end
        if key == "chatType" or key == "tellTarget"
            or key == "channelTarget" or key == "language" then
            c[key] = value
        end

        -- If chat is locked down and Blizzard's untainted editbox is
        -- being manipulated (user changed channel/target/language),
        -- mirror that choice into our sticky `LastUsed` unless we have
        -- a draft saved due to lockdown (the draft should take
        -- precedence).
        if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
            local ct = c.chatType or (eb.GetAttribute and eb:GetAttribute("chatType"))
            if ct and ct ~= "BN_WHISPER" then
                local target = nil
                if ct == "WHISPER" then
                    target = c.tellTarget or (eb.GetAttribute and eb:GetAttribute("tellTarget"))
                elseif ct == "CHANNEL" then
                    target = c.channelTarget or (eb.GetAttribute and eb:GetAttribute("channelTarget"))
                end
                local lang = c.language or eb.languageID or (eb.GetAttribute and eb:GetAttribute("language"))

                if not self._lockdown.savedDraft then
                    self.LastUsed.chatType = ct
                    self.LastUsed.target = target
                    self.LastUsed.language = lang
                    -- Persist after lockdown ends if we are still locked.
                    if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
                        self._lockdown.savedDuring = true
                    else
                        self:PersistLastUsed()
                    end
                end
            end
        end

        -- ── BNet → non-BNet transition ───────────────────────────────
        -- If Blizzard's box was showing for a BNet whisper and the user
        -- typed a slash command that changed chatType, reclaim it.
        -- Skip if we are in lockdown or the user explicitly bypassed Yapper.
        if key == "chatType" and value ~= "BN_WHISPER"
            and (not self.Overlay or not self.Overlay:IsShown())
            and eb:IsShown()
            and not (YapperTable.Utils and YapperTable.Utils:IsChatLockdown())
            and not BypassEditBox() then
            local prevType = c._prevChatType
            if prevType == "BN_WHISPER" then
                local savedEB = self._bnetEditBox or eb
                local newChatType = value
                -- Defer to next frame; overlay creation needs to be
                -- outside the SetAttribute hook context.
                C_Timer.After(0, function()
                    -- If the editbox was dismissed (Escape) rather than
                    -- channel-switched, it will be hidden by now — bail out.
                    if not savedEB or not savedEB:IsShown() then
                        self._bnetEditBox = nil
                        return
                    end

                    -- If WIM grabbed whisper focus in the meantime, do not
                    -- reclaim this box for Yapper's overlay.
                    if YapperTable.WIMBridge and YapperTable.WIMBridge:IsFocusActive() then
                        self._bnetEditBox = nil
                        return
                    end

                    -- Read leftover text after ParseText stripped the slash prefix.
                    local leftover = savedEB and savedEB.GetText and savedEB:GetText() or ""
                    leftover = leftover:match("^%s*(.-)%s*$") or ""

                    if savedEB and savedEB.Deactivate and savedEB:IsShown() then
                        savedEB:Deactivate()
                    end

                    -- PRE_EDITBOX_SHOW filter: external addons (including WIMBridge)
                    -- can inspect the pending open and cancel it.
                    if YapperTable.API then
                        local cache = self._attrCache[savedEB] or {}
                        local filterCT = newChatType or cache.chatType or (savedEB.GetAttribute and savedEB:GetAttribute("chatType"))
                        local filterTarget = cache.tellTarget or cache.channelTarget
                        local result = YapperTable.API:RunFilter("PRE_EDITBOX_SHOW", {
                            chatType = filterCT,
                            target   = filterTarget,
                        })
                        if result == false then
                            -- If we are suppressing the overlay open (e.g. WIM taking focus),
                            -- ensure we return to IDLE so bridges (TypingTracker, etc) stop.
                            if State and not State:IsIdle() then
                                YapperAPI:SetState("IDLE")
                            end
                            self._bnetEditBox = nil
                            return
                        end
                    end

                    self._nextShowFromBnetTransition = true
                    self:Show(savedEB)

                    -- Force the correct chat type (cache may hold stale BNet attrs).
                    self.ChatType = newChatType
                    self.Target   = nil
                    if newChatType == "WHISPER" and savedEB.GetAttribute then
                        self.Target = savedEB:GetAttribute("tellTarget")
                    elseif newChatType == "CHANNEL" and savedEB.GetAttribute then
                        local ch         = savedEB:GetAttribute("channelTarget")
                        self.Target      = ch
                        self.ChannelName = ResolveChannelName(tonumber(ch))
                    end
                    self:RefreshLabel()

                    -- Carry over message text if any.
                    if leftover ~= "" and self.OverlayEdit then
                        self.OverlayEdit:SetText(leftover)
                        self.OverlayEdit:SetCursorPosition(#leftover)
                    end
                    self._bnetEditBox = nil
                end)
            end
        end
        if key == "chatType" then
            c._prevChatType = value
        end

        -- Live update: attributes arrived after we already showed
        -- (WoW whisper deferred case). RefreshLabel is safe here because
        -- the _syncingAttributes guard prevents a loop back to SetAttribute.
        if self.OrigEditBox == eb
            and self.Overlay and self.Overlay:IsShown() then
            local ec = self._explicitChannel
            if ec and ec.chatType and (GetTime() - (ec.t or 0)) <= 1 then
                self._explicitChannel = nil
                self.ChatType    = ec.chatType
                self.Target      = ec.target
                self.ChannelName = ec.channelName
                self:RefreshLabel()
                self:EnsureProxyBackgroundShown()
                if YapperTable.API then
                    YapperTable.API:Fire("EDITBOX_CHANNEL_CHANGED", self.ChatType, self.Target)
                end
            else
                local ct = c.chatType
                local tt = c.tellTarget
                local ch = c.channelTarget

                if (ct == "WHISPER" or ct == "BN_WHISPER") and tt and tt ~= "" then
                    -- If an external-whisper episode is active and Blizzard
                    -- renormalised the target here (e.g. a cross-realm whisper
                    -- where "Char" becomes "Char-Realm"), keep the marker in sync
                    -- so the persistence/draft gates still treat it as transient.
                    -- Match by base name only, so a deliberate mid-open /w to a
                    -- different person still persists normally.
                    local ext = self._externalWhisperTarget
                    if ext then
                        local extBase = tostring(ext):gsub("%-.*$", ""):lower()
                        local ttBase  = tostring(tt):gsub("%-.*$", ""):lower()
                        if extBase == ttBase then
                            self._externalWhisperTarget = tt
                        end
                    end
                    self.ChatType = ct
                    self.Target   = tt
                    self:RefreshLabel()
                elseif ct == "CHANNEL" and ch and ch ~= "" then
                    self.ChatType    = "CHANNEL"
                    self.Target      = ch
                    self.ChannelName = ResolveChannelName(tonumber(ch))
                    self:RefreshLabel()
                end
            end
        end
    end)

    -- Mirror Blizzard's text changes while we're overlaid. This ensures that
    -- programmatic updates (like item links or slash-command prefills) are
    -- captured even if the addon targets a hidden Blizzard editbox.
    local function ForwardTextToYapper(eb, text, isInsert)
        if self._ignoreSetText then return end
        if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then return end

        local targetBox
        local state = YapperTable.State
        local ml = YapperTable.Multiline

        -- Determine the active Yapper editor
        if state and state.IsMultiline and state:IsMultiline()
            and ml and ml.EditBox and ml.Frame and ml.Frame:IsShown() then
            targetBox = ml.EditBox
        elseif self.Overlay and (self.Overlay:IsShown() or self._inBlizzShowHook or self._openingWatchdog) and self.OverlayEdit then
            targetBox = self.OverlayEdit
        end

        if targetBox and text and text ~= "" then
            local function HasRecentExplicitIntent(chatType, target)
                local function Matches(intent)
                    if not (intent and intent.chatType and (GetTime() - (intent.t or 0)) <= 1) then
                        return false
                    end
                    if intent.chatType ~= chatType then
                        return false
                    end
                    if chatType == "CHANNEL" then
                        return tostring(intent.target or "") == tostring(target or "")
                    end
                    if chatType == "WHISPER" then
                        return tostring(intent.target or ""):lower() == tostring(target or ""):lower()
                    end
                    return true
                end

                return Matches(self._explicitChannel) or Matches(self._recentOpenChatIntent)
            end

            -- Avoid recursive loops by ignoring the subsequent SetText("") on the source
            self._ignoreSetText = true
            if isInsert then
                targetBox:Insert(text)
            else
                -- If Blizzard's deferred OnUpdate writes a whisper/channel slash prefill
                -- (e.g. "/cw charname " from a friend-list click), parse and strip it
                -- here rather than displaying the raw command in the overlay.
                -- OnTextChanged won't do this because isUserInput=false skips slash handling.
                if not isInsert and Core.IsWhisperSlashPrefill(text) then
                    local preTarget, preRemainder = Core.ParseWhisperSlash(text)
                    if preTarget then
                        local explicitWins = GATE_SKIP_SETTEXT_INTENT_ADOPTION_ON_EXPLICIT
                            and HasRecentExplicitIntent("WHISPER", preTarget)
                        if explicitWins then
                            TriggerTrace("IntentPath.SetTextFallback.Gated", string.format("kind=whisper source=%s target=%s action=sanitize-only",
                                tostring(isInsert and "Insert" or "SetText"), tostring(preTarget)))
                        else
                            TriggerTrace("IntentPath.SetTextFallback", string.format("kind=whisper source=%s target=%s",
                                tostring(isInsert and "Insert" or "SetText"), tostring(preTarget)))
                        end
                        local curText = targetBox:GetText() or ""
                        local nextText = preRemainder or ""
                        local keepExistingText = (targetBox == self.OverlayEdit)
                            and self.Overlay and self.Overlay:IsShown()
                            and curText ~= "" and nextText == ""
                        if not explicitWins then
                            self._ignoreSetText = nil
                            self.ChatType = "WHISPER"
                            self.Target   = preTarget
                            self._ignoreSetText = true
                        end
                        if not keepExistingText and nextText ~= curText then
                            targetBox:SetText(nextText)
                        end
                        self._ignoreSetText = nil
                        eb:SetText("")
                        if not explicitWins then
                            self:RefreshLabel()
                        end
                        return
                    end
                end

                -- Same for channel/built-in slash prefills (e.g. "/1", "/g") that
                -- a channel-link click or the chat menu writes into the native box.
                -- The channel itself is already adopted via the explicit-channel
                -- capture; here we just strip the raw slash so it never appears in
                -- the overlay. Without this, numbered channels prefill "/n".
                if not isInsert and Core.IsChannelSlashPrefill(text) then
                    local chanType, chanTarget, chanRemainder = Core.ParseChannelSlash(text)
                    if chanType then
                        local explicitWins = GATE_SKIP_SETTEXT_INTENT_ADOPTION_ON_EXPLICIT
                            and HasRecentExplicitIntent(chanType, chanTarget)
                        if explicitWins then
                            TriggerTrace("IntentPath.SetTextFallback.Gated", string.format("kind=channel source=%s chatType=%s target=%s action=sanitize-only",
                                tostring(isInsert and "Insert" or "SetText"), tostring(chanType), tostring(chanTarget)))
                        else
                            TriggerTrace("IntentPath.SetTextFallback", string.format("kind=channel source=%s chatType=%s target=%s",
                                tostring(isInsert and "Insert" or "SetText"), tostring(chanType), tostring(chanTarget)))
                        end
                        local curText = targetBox:GetText() or ""
                        local nextText = chanRemainder or ""
                        local keepExistingText = (targetBox == self.OverlayEdit)
                            and self.Overlay and self.Overlay:IsShown()
                            and curText ~= "" and nextText == ""
                        if not explicitWins then
                            self._ignoreSetText = nil
                            self.ChatType = chanType
                            if chanType == "CHANNEL" then
                                self.Target = chanTarget
                                local num = tonumber(chanTarget)
                                self.ChannelName = num and ResolveChannelName(num) or nil
                            else
                                self.Target = nil
                                self.ChannelName = nil
                            end
                            self._ignoreSetText = true
                        end
                        if not keepExistingText and nextText ~= curText then
                            targetBox:SetText(nextText)
                        end
                        self._ignoreSetText = nil
                        eb:SetText("")
                        if not explicitWins then
                            self:RefreshLabel()
                        end
                        self:EnsureProxyBackgroundShown()
                        return
                    end
                end

                local cur = targetBox:GetText() or ""
                -- When overlay is already active, preserve user text against
                -- stale native SetText payloads (common on refocus in proxy mode).
                -- Explicit slash-prefill paths are handled above and still allowed.
                if not isInsert and targetBox == self.OverlayEdit
                    and self.Overlay and self.Overlay:IsShown()
                    and cur ~= "" and text ~= cur then
                    if eb and eb.SetText then
                        eb:SetText("")
                    end
                    self:EnsureProxyBackgroundShown()
                    self._ignoreSetText = nil
                    return
                end
                if text ~= cur then
                    targetBox:SetText(text)
                end
            end
            -- Wipe the Blizzard source box so it doesn't hold stale data
            eb:SetText("")
            self:EnsureProxyBackgroundShown()
            self._ignoreSetText = nil
        end
    end

    hooksecurefunc(blizzEditBox, "SetText", function(eb, text)
        ForwardTextToYapper(eb, text, false)
    end)

    if blizzEditBox.Insert then
        hooksecurefunc(blizzEditBox, "Insert", function(eb, text)
            ForwardTextToYapper(eb, text, true)
        end)
    end

    -- Mirror language changes made via the chat menu button.
    -- Character language is treated as character-global; if changed on one
    -- editbox, apply it to the sticky LastUsed state for all future opens.
    if blizzEditBox.SetGameLanguage then
        hooksecurefunc(blizzEditBox, "SetGameLanguage", function(eb, language, languageId)
            -- Normalise to ensure we store a valid language ID
            local normalisedLang = languageId or language
            if normalisedLang and type(normalisedLang) == "string" then
                normalisedLang = YapperTable.Core:GetCharacterLanguage(normalisedLang)
            end
            self.Language = normalisedLang
            if self.LastUsed then
                self.LastUsed.language = self.Language
            end
            YapperTable.Utils:VerbosePrint("SetGameLanguage: " .. tostring(self.Language))
        end)
    end

    -- Hook Show to catch programmatic opens (Friends list, addon calls, etc.)
    -- The keybind system only intercepts key presses; this catches everything else.
    hooksecurefunc(blizzEditBox, "Show", function()
        if self._ignoreNextShow then
            self._ignoreNextShow = nil
            return
        end

        -- Skip if this editbox is being suppressed (tab click while Yapper closed)
        if self._suppressNextShowFor and blizzEditBox.GetName and blizzEditBox:GetName() == self._suppressNextShowFor then
            return
        end

        -- Skip IM-mode tab reattachments (editbox already shown)
        -- In popout/popout_and_inline modes, Blizzard reattaches the editbox to different tabs
        -- which triggers Show() calls even though the editbox was already visible.
        -- These are not user-initiated opens, just internal reattachments.
        local whisperMode = GetCVar("whisperMode")
        if (whisperMode == "popout" or whisperMode == "popout_and_inline") then
            if blizzEditBox:IsShown() then
                return
            end
        end

        -- Skip IM-style tab switching (chatStyle == "im")
        -- In IM mode, clicking tabs triggers Show() then Deactivate() via SetLastActiveWindow.
        -- If the editbox is already shown and Yapper is NOT shown, this is a tab switch that should not open Yapper.
        -- If Yapper IS shown, we need to handle the tab switch to update context.
        local chatStyle = GetCVar("chatStyle")
        if chatStyle == "im" and blizzEditBox:IsShown() and not (self.Overlay and self.Overlay:IsShown()) then
            return
        end

        -- If Yapper is already shown and a different editbox is showing (tab switch),
        -- update OrigEditBox and refresh the label to adapt to the new tab's context.
        if self.Overlay and self.Overlay:IsShown() then
            if blizzEditBox ~= self.OrigEditBox then
                -- Save the outgoing frame's channel state exactly once, before any proxy
                -- swapping changes OverlayEdit.chatFrame. Use a guard so re-entrant Show()
                -- calls from RestoreProxyMode/ApplyProxyMode don't fire this again.
                if not self._recordingTabSwitch then
                    self._recordingTabSwitch = true
                    if self.ChatType and self.ChatType ~= "" then
                        self:RecordTabChannel()
                    end
                    self._recordingTabSwitch = nil
                end
                self:_IMPushActive(blizzEditBox)
                -- Swap proxy target if in proxy mode
                local cfg = YapperTable.Config and YapperTable.Config.EditBox
                local isProxy = cfg and cfg.UseBlizzardSkinProxy == true and cfg.UseLegacyCloneProxy ~= true

                if isProxy and self.RestoreProxyMode then
                    pcall(function() self:RestoreProxyMode() end)
                end

                self.OrigEditBox = blizzEditBox

                if isProxy and self.ApplyProxyMode then
                    pcall(function() self:ApplyProxyMode(blizzEditBox) end)
                end

                -- Satisfy Blizzard code that expects the editbox to belong to a specific chatFrame.
                if blizzEditBox and blizzEditBox.chatFrame then
                    self.OverlayEdit.chatFrame = blizzEditBox.chatFrame
                    if self.ChannelLabel then
                        self.ChannelLabel.chatFrame = blizzEditBox.chatFrame
                    end
                end
                -- Re-read attributes from chatFrame and refresh label
                local chatFrame = blizzEditBox:GetParent() or blizzEditBox.chatFrame
                if chatFrame then
                    local cfType = chatFrame.chatType
                    local cfTarget = chatFrame.chatTarget
                    if cfType then
                        self.ChatType = cfType
                    end
                    if cfTarget and cfTarget ~= "" then
                        self.Target = cfTarget
                        if self.ChatType == "CHANNEL" then
                            self.ChannelName = ResolveChannelName(tonumber(cfTarget))
                        end
                    elseif self.ChatType ~= "WHISPER"
                        and self.ChatType ~= "BN_WHISPER"
                        and self.ChatType ~= "CHANNEL" then
                        -- Switching from a whisper/channel tab to a non-target
                        -- tab (e.g. General/SAY) must clear stale targets,
                        -- otherwise PersistLastUsed can cling to old whispers.
                        self.Target = nil
                        self.ChannelName = nil
                    end
                end
                self:RefreshLabel()
            end
            return
        end
        if UserBypassingYapper() then
            return
        end
        if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
            return
        end

        -- Skip if Queue is handling this (hardware event capture)
        if self.PreShowCheck and self.PreShowCheck(blizzEditBox) then
            return
        end

        -- Defer by one frame to allow Blizzard's OnUpdate to set attributes
        -- (WoW friend whispers: Show fires first, attributes arrive one frame later)
        C_Timer.After(0, function()
            -- Check again in case state changed during defer
            if self.Overlay and self.Overlay:IsShown() then
                self._openingWatchdog = false
                return
            end
            if UserBypassingYapper() then
                self._openingWatchdog = false
                return
            end
            if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
                self._openingWatchdog = false
                return
            end

            -- If Blizzard hid its editbox during the defer (e.g. proxy Deactivate fired,
            -- or rapid open/close), fall back to the last known active editbox rather
            -- than silently aborting.  The one-frame defer was for attribute timing on
            -- friend-list whispers; attributes were still written before the Hide().
            local targetEB = blizzEditBox:IsShown() and blizzEditBox
                or self._lastActiveIMEditBox
                or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
            if not targetEB then
                self._openingWatchdog = false
                return
            end

            -- PRE_EDITBOX_SHOW filter: external addons (including WIMBridge)
            -- can inspect the pending open and cancel it.
            if YapperTable.API then
                local filterCT = targetEB.GetAttribute and targetEB:GetAttribute("chatType") or "SAY"
                local filterTarget
                if filterCT == "WHISPER" and targetEB.GetAttribute then
                    filterTarget = targetEB:GetAttribute("tellTarget")
                elseif filterCT == "CHANNEL" and targetEB.GetAttribute then
                    filterTarget = targetEB:GetAttribute("channelTarget")
                end
                local result = YapperTable.API:RunFilter("PRE_EDITBOX_SHOW", {
                    chatType = filterCT,
                    target   = filterTarget,
                })
                if result == false then
                    -- If we are suppressing the overlay open (e.g. WIM taking focus),
                    -- ensure we return to IDLE so bridges (TypingTracker, etc) stop.
                    if State and not State:IsIdle() then
                        YapperAPI:SetState("IDLE")
                    end
                    self._openingWatchdog = false
                    return
                end
            end

            -- Track this as the last active window (Classic mode equivalent of IM's ActivateChat hook).
            self:_IMPushActive(targetEB)
            -- Open Yapper's overlay
            self:Show(targetEB)
        end)
    end)

    -- clear bypass if focus leaves the bypassed editbox without a Hide.
    if blizzEditBox and blizzEditBox.HookScript then
        blizzEditBox:HookScript("OnEditFocusLost", function(eb)
            if UserBypassingYapper() then
                SetBypassEditBox(nil)
                SetUserBypassingYapper(false)
                C_Timer.After(0, function()
                    if not (YapperTable.Utils and YapperTable.Utils:IsChatLockdown()) then
                        self:UpdateFocusOverride()
                    end
                end)
            end
        end)
    end
end

--- Hook all NUM_CHAT_WINDOWS editboxes.  Call once on init.
