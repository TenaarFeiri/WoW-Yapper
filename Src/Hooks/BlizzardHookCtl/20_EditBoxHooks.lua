local _, YapperTable = ...
local EditBox = YapperTable.EditBox
local State = YapperTable.State

local Ctl = YapperTable.BlizzardHookCtl
local Core = Ctl.Core
local ResolveChannelName = Ctl.ResolveChannelName
local UserBypassingYapper = Ctl.UserBypassingYapper
local SetUserBypassingYapper = Ctl.SetUserBypassingYapper
local BypassEditBox = Ctl.BypassEditBox
local SetBypassEditBox = Ctl.SetBypassEditBox
local TriggerTrace = Ctl.TriggerTrace
local GATE_SKIP_SETTEXT_INTENT_ADOPTION_ON_EXPLICIT = Ctl.GATE_SKIP_SETTEXT_INTENT_ADOPTION_ON_EXPLICIT

local type = type
local tonumber = tonumber
local tostring = tostring

local function SafeToString(value)
    local utils = YapperTable.Utils
    if utils and type(utils.SafeToString) == "function" then
        return utils:SafeToString(value)
    end
    local ok, result = pcall(tostring, value)
    return ok and result or "<unavailable>"
end

function EditBox:HookBlizzardEditBox(blizzEditBox)
    if self.HookedBoxes[blizzEditBox] then return end
    self.HookedBoxes[blizzEditBox] = true
    self._attrCache[blizzEditBox] = {}

    -- Capture chatType / tellTarget / channelTarget as they're set.
    -- BNet whisper: attributes arrive BEFORE Show.
    -- WoW whisper:  attributes arrive one frame AFTER Show (deferred).
    -- The live-update path below handles the deferred case.
    hooksecurefunc(blizzEditBox, "SetAttribute", function(eb, key, value)
        -- Skip while syncing Yapper -> Blizzard to avoid a
        -- RefreshLabel -> SyncAttributesToBlizzard -> SetAttribute loop.
        if self._syncingAttributes then return end

        local c = self._attrCache[eb]
        if not c then
            c = {}
            self._attrCache[eb] = c
        end
        if key == "chatType" or key == "tellTarget"
            or key == "channelTarget" or key == "language" then
            -- Secret quarantine: never absorb a secret target. Downstream
            -- consumers compare/normalise these from tainted code, which is
            -- an immediate Lua error on secrets; a secret target reads as
            -- "no target".
            if (key == "tellTarget" or key == "channelTarget")
                and value ~= nil
                and YapperTable.Utils and YapperTable.Utils:IsSecret(value) then
                c[key] = nil
            else
                c[key] = value
            end
        end

        -- If chat is locked down and Blizzard's untainted editbox is
        -- being manipulated (user changed channel/target/language),
        -- mirror that choice into our sticky `LastUsed` unless we have
        -- a draft saved due to lockdown (the draft should take
        -- precedence).
        if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
            local ct = c.chatType or (eb.GetAttribute and eb:GetAttribute("chatType"))
            if ct and ct ~= "BN_WHISPER" then
                -- The cache is already secret-quarantined; the raw GetAttribute
                -- fallbacks are not, so sanitize them before the value can reach
                -- LastUsed (and later comparisons/persistence).
                local target = nil
                if ct == "WHISPER" then
                    target = c.tellTarget
                        or (eb.GetAttribute and YapperTable.Utils:SanitizeTarget(eb:GetAttribute("tellTarget")))
                elseif ct == "CHANNEL" then
                    target = c.channelTarget
                        or (eb.GetAttribute and YapperTable.Utils:SanitizeTarget(eb:GetAttribute("channelTarget")))
                end
                -- A targeted type whose target was secret-quarantined must not
                -- overwrite the existing sticky; skip this mirror entirely.
                if (ct == "WHISPER" or ct == "CHANNEL") and not target then
                    return
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

        -- BNet -> non-BNet transition: if Blizzard's box was showing for a
        -- BNet whisper and a slash command changed chatType, reclaim it.
        -- Skipped in lockdown or after an explicit user bypass.
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
                    -- If the box was dismissed (Escape) rather than
                    -- channel-switched, it's hidden by now -- bail.
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
                            -- Suppressing the open (e.g. WIM taking focus):
                            -- return to IDLE so bridges stop typing signals.
                            if State and not State:IsIdle() then
                                State:ToIdle()
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
                    self._secureReplySource = nil
                    if newChatType == "WHISPER" and savedEB.GetAttribute then
                        -- Raw GetAttribute can return a secret under any active
                        -- restriction type; SanitizeTarget quarantines to nil.
                        self.Target = YapperTable.Utils:SanitizeTarget(savedEB:GetAttribute("tellTarget"))
                    elseif newChatType == "CHANNEL" and savedEB.GetAttribute then
                        local ch         = YapperTable.Utils:SanitizeTarget(savedEB:GetAttribute("channelTarget"))
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
                self._secureReplySource = nil
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
                        local Utils = YapperTable.Utils
                        if Utils:NormaliseCharName(ext) == Utils:NormaliseCharName(tt) then
                            self._externalWhisperTarget = tt
                        end
                    end
                    self.ChatType = ct
                    self.Target   = tt
                    -- tt is the native editbox's current target, not necessarily
                    -- the last-incoming-whisper reply target, so do not force a
                    -- GetLastTellTarget re-resolution; use it as a fallback only.
                    self._secureReplySource = nil
                    self:RefreshLabel()
                elseif ct == "CHANNEL" and ch and ch ~= "" then
                    self.ChatType    = "CHANNEL"
                    self.Target      = ch
                    self._secureReplySource = nil
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
        elseif self.Overlay and self.OverlayEdit
            and (self.Overlay:IsShown() or self._inBlizzShowHook) then
            -- Mirror only when the overlay is shown or mid-Show
            -- (_inBlizzShowHook); do NOT capture before the overlay exists.
            -- Early capture (the old `_openingWatchdog`) stole the SetText
            -- in the OpenChat("") -> GetActiveWindow -> SetText -> SendText
            -- addon contract (e.g. PasteNG writes the native box then sends
            -- on it), blanking the box so the send went out empty.
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
                        local intentTarget = YapperTable.Utils:SanitizeTarget(intent.target)
                        local currentTarget = YapperTable.Utils:SanitizeTarget(target)
                        return intentTarget ~= nil and currentTarget ~= nil
                            and tostring(intentTarget) == tostring(currentTarget)
                    end
                    if chatType == "WHISPER" then
                        local utils = YapperTable.Utils
                        local intentTarget = utils:SanitizeTarget(intent.target)
                        local currentTarget = utils:SanitizeTarget(target)
                        -- Canonicalise both sides: retail Name↔Name-Realm and
                        -- Forever "First Last"↔"First-Last" must compare equal.
                        local nIntent = intentTarget and utils:NormaliseCharName(intentTarget) or nil
                        local nCurrent = currentTarget and utils:NormaliseCharName(currentTarget) or nil
                        return nIntent ~= nil and nIntent == nCurrent
                    end
                    return true
                end

                return Matches(self._explicitChannel) or Matches(self._recentOpenChatIntent)
            end

            -- Ignore the matching SetText("") we write to the source below.
            self._ignoreSetText = true
            if isInsert then
                targetBox:Insert(text)
            else
                -- Blizzard's deferred OnUpdate writes slash prefills (e.g.
                -- "/cw charname " from a friend-list click); parse and strip
                -- rather than showing the raw command in the overlay.
                -- OnTextChanged can't help: isUserInput=false skips slash
                -- handling there.
                if not isInsert and Core.IsWhisperSlashPrefill(text) then
                    local preTarget, preRemainder = Core.ParseWhisperSlash(text)
                    if preTarget then
                        local explicitWins = GATE_SKIP_SETTEXT_INTENT_ADOPTION_ON_EXPLICIT
                            and HasRecentExplicitIntent("WHISPER", preTarget)
                        if explicitWins then
                            TriggerTrace("IntentPath.SetTextFallback.Gated", string.format("kind=whisper source=%s target=%s action=sanitize-only",
                                tostring(isInsert and "Insert" or "SetText"), SafeToString(preTarget)))
                        else
                            TriggerTrace("IntentPath.SetTextFallback", string.format("kind=whisper source=%s target=%s",
                                tostring(isInsert and "Insert" or "SetText"), SafeToString(preTarget)))
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
                            self._secureReplySource = nil
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

                -- Same for channel/built-in slash prefills ("/1", "/g")
                -- written by a channel-link click or the chat menu. The
                -- channel itself was already adopted via explicit-channel
                -- capture; here we strip the raw slash (otherwise numbered
                -- channels prefill "/n").
                if not isInsert and Core.IsChannelSlashPrefill(text) then
                    local chanType, chanTarget, chanRemainder = Core.ParseChannelSlash(text)
                    if chanType then
                        local explicitWins = GATE_SKIP_SETTEXT_INTENT_ADOPTION_ON_EXPLICIT
                            and HasRecentExplicitIntent(chanType, chanTarget)
                        if explicitWins then
                            TriggerTrace("IntentPath.SetTextFallback.Gated", string.format("kind=channel source=%s chatType=%s target=%s action=sanitize-only",
                                tostring(isInsert and "Insert" or "SetText"), SafeToString(chanType), SafeToString(chanTarget)))
                        else
                            TriggerTrace("IntentPath.SetTextFallback", string.format("kind=channel source=%s chatType=%s target=%s",
                                tostring(isInsert and "Insert" or "SetText"), SafeToString(chanType), SafeToString(chanTarget)))
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
                                self._secureReplySource = nil
                                local num = tonumber(chanTarget)
                                self.ChannelName = num and ResolveChannelName(num) or nil
                            else
                                self.Target = nil
                                self._secureReplySource = nil
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
                -- With the overlay active, preserve user text against stale
                -- native SetText payloads (common on refocus in proxy mode);
                -- explicit slash-prefill paths above still pass.
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
            -- Wipe the source box so it doesn't hold stale data.
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

    -- Mirror language changes from the chat menu. Language is
    -- character-global: apply it to LastUsed for all future opens.
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
            if type(self.PersistLastUsed) == "function" then
                self:PersistLastUsed()
            end
            if self.Overlay and self.Overlay:IsShown()
                and type(self.RefreshLabel) == "function" then
                self:RefreshLabel()
            end
            YapperTable.Utils:VerbosePrint("SetGameLanguage: " .. SafeToString(self.Language))
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

        -- Skip IM-mode tab reattachments: in popout modes Blizzard
        -- reattaches the already-visible editbox to different tabs, firing
        -- Show() without a user-initiated open.
        local whisperMode = GetCVar("whisperMode")
        if (whisperMode == "popout" or whisperMode == "popout_and_inline") then
            if blizzEditBox:IsShown() then
                return
            end
        end

        -- chatStyle "im" tab clicks fire Show() then Deactivate() via
        -- SetLastActiveWindow. Editbox shown + Yapper not shown = tab
        -- switch, not an open. (Yapper shown falls through to the tab-switch
        -- handling below.)
        local chatStyle = GetCVar("chatStyle")
        if chatStyle == "im" and blizzEditBox:IsShown() and not (self.Overlay and self.Overlay:IsShown()) then
            return
        end

        -- Yapper shown + a different editbox showing = tab switch: update
        -- OrigEditBox and refresh the label for the new tab's context.
        if self.Overlay and self.Overlay:IsShown() then
            if blizzEditBox ~= self.OrigEditBox then
                -- Save the outgoing frame's channel once, before proxy
                -- swapping changes OverlayEdit.chatFrame. The guard blocks
                -- re-entrant Show() calls from Restore/ApplyProxyMode.
                if not self._recordingTabSwitch then
                    self._recordingTabSwitch = true
                    if self.ChatType and self.ChatType ~= "" then
                        self:RecordTabChannel()
                    end
                    self._recordingTabSwitch = nil
                end
                self:_IMPushActive(blizzEditBox)
                -- Proxy mode: swap which editbox stays visible.
                local cfg = YapperTable.Config and YapperTable.Config.EditBox
                local isProxy = cfg and cfg.UseBlizzardSkinProxy == true

                if isProxy and self.RestoreProxyMode then
                    pcall(function() self:RestoreProxyMode() end)
                end

                self.OrigEditBox = blizzEditBox

                if isProxy and self.ApplyProxyMode then
                    pcall(function() self:ApplyProxyMode(blizzEditBox) end)
                end

                -- Blizzard code expects the editbox to know its chatFrame.
                if blizzEditBox and blizzEditBox.chatFrame then
                    self.OverlayEdit.chatFrame = blizzEditBox.chatFrame
                    if self.ChannelLabel then
                        self.ChannelLabel.chatFrame = blizzEditBox.chatFrame
                    end
                end
                local chatFrame = blizzEditBox:GetParent() or blizzEditBox.chatFrame
                if chatFrame then
                    local cfType = chatFrame.chatType
                    -- SanitizeTarget: secret chatTarget must not enter self.Target.
                    local cfTarget = YapperTable.Utils:SanitizeTarget(chatFrame.chatTarget)
                    if cfType then
                        self.ChatType = cfType
                    end
                    if cfTarget and cfTarget ~= "" then
                        self.Target = cfTarget
                        self._secureReplySource = nil
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
                        self._secureReplySource = nil
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
                return
            end
            if UserBypassingYapper() then
                return
            end
            if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
                return
            end

            -- If Blizzard hid its editbox during the defer (proxy
            -- Deactivate, rapid open/close), fall back to the last active
            -- editbox instead of aborting; attributes were still written
            -- before the Hide().
            local targetEB = blizzEditBox:IsShown() and blizzEditBox
                or self._lastActiveIMEditBox
                or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
            if not targetEB then
                return
            end

            -- PRE_EDITBOX_SHOW filter: external addons (including WIMBridge)
            -- can inspect the pending open and cancel it.
            if YapperTable.API then
                local filterCT = targetEB.GetAttribute and targetEB:GetAttribute("chatType") or "SAY"
                local filterTarget
                if filterCT == "WHISPER" and targetEB.GetAttribute then
                    filterTarget = YapperTable.Utils:SanitizeTarget(targetEB:GetAttribute("tellTarget"))
                elseif filterCT == "CHANNEL" and targetEB.GetAttribute then
                    filterTarget = YapperTable.Utils:SanitizeTarget(targetEB:GetAttribute("channelTarget"))
                end
                local result = YapperTable.API:RunFilter("PRE_EDITBOX_SHOW", {
                    chatType = filterCT,
                    target   = filterTarget,
                })
                if result == false then
                    -- Suppressing the open (e.g. WIM taking focus): return
                    -- to IDLE so bridges stop typing signals.
                    if State and not State:IsIdle() then
                        State:ToIdle()
                    end
                    return
                end
            end

            -- Classic-mode equivalent of IM's ActivateChat tracking.
            self:_IMPushActive(targetEB)
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
