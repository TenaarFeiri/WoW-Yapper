local _, YapperTable = ...
local EditBox = YapperTable.EditBox

local Ctl = YapperTable.BlizzardHookCtl
local Core = Ctl.Core
local ResolveChannelName = Ctl.ResolveChannelName
local UserBypassingYapper = Ctl.UserBypassingYapper
local SetUserBypassingYapper = Ctl.SetUserBypassingYapper
local SetBypassEditBox = Ctl.SetBypassEditBox
local TriggerTrace = Ctl.TriggerTrace
local StampRecentOpenChatIntent = Ctl.StampRecentOpenChatIntent
local ParseLinkType = Ctl.ParseLinkType

local type = type
local tonumber = tonumber
local tostring = tostring
local nativeToString = tostring

local function SafeToString(value)
    local utils = YapperTable.Utils
    if utils and type(utils.SafeToString) == "function" then
        return utils:SafeToString(value)
    end
    local ok, result = pcall(nativeToString, value)
    return ok and result or "<unavailable>"
end

local function OpenBnetAccountWhisper(bnetAccountID, chatFrame, name)
    local utils = YapperTable.Utils
    bnetAccountID = utils and utils:SanitizeTarget(bnetAccountID) or bnetAccountID
    if (type(bnetAccountID) ~= "string" and type(bnetAccountID) ~= "number")
        or bnetAccountID == "" then
        return
    end

    if utils and utils.IsChatLockdown and utils:IsChatLockdown() then
        return
    end

    local target = tonumber(bnetAccountID) or bnetAccountID
    if not chatFrame and ChatFrameUtil and ChatFrameUtil.GetActiveWindow then
        local activeEditBox = ChatFrameUtil.GetActiveWindow()
        chatFrame = activeEditBox and activeEditBox.chatFrame
    end

    local handler = YapperTable.EditBox
    if handler and type(handler.OpenWhisperFromUnitMenu) == "function" then
        name = utils and utils:SanitizeTarget(name) or name
        handler:OpenWhisperFromUnitMenu({
            bnetIDAccount = target,
            name = name,
            chatFrame = chatFrame,
        })
    end
end

function EditBox:HookAllChatFrames()
    local function EnsureEditBoxHooked(eb)
        if not eb then return end
        if not self.HookedBoxes[eb] then
            self:HookBlizzardEditBox(eb)
        end
    end

    -- Link runtime LastUsed to the persistent config table.
    local cfg = YapperTable.Config and YapperTable.Config.EditBox
    if cfg and cfg.LastUsed then
        self.LastUsed = cfg.LastUsed
    end

    -- IM window history: a stack so minimize can pop back to the previous window.
    -- _lastActiveIMEditBox always mirrors the top of the stack for read compatibility.
    self._imWindowHistory = {}
    local seed = (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
        or _G["ChatFrame1EditBox"]
    if seed then
        self._imWindowHistory[1] = seed
        self._lastActiveIMEditBox = seed
    end

    local maxChatWindows = (Constants and Constants.ChatFrameConstants
        and Constants.ChatFrameConstants.MaxChatWindows) or 10
    for i = 1, maxChatWindows do
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb then
            EnsureEditBoxHooked(eb)
        end
    end

    if YapperTable.Utils then
        YapperTable.Utils:VerbosePrint("EditBox overlays hooked for " .. maxChatWindows .. " chat frames.")
    end

    -- Record sends made through Blizzard's native editbox (lockdown /
    -- bypass / handoff) into Yapper's history. The overlay isn't a
    -- ChatFrameEditBoxMixin and never fires this event, so Yapper sends
    -- aren't double-recorded.
    if EventRegistry and not self._fallbackHistoryRegistered then
        EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText", function(_, editBox)
            self:RecordFallbackSend(editBox)
        end, self)
        self._fallbackHistoryRegistered = true
    end

    -- Observe chat hyperlinks without altering Blizzard's execution flow.
    -- Native SetItemRef/LinkUtil/OpenChat handling remains authoritative.
    if EventRegistry and not self._hyperlinkIntentRegistered then
        EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkClick", function(_, chatFrame, link, _, button)
            local linkType
            if not (YapperTable.Utils and YapperTable.Utils:IsSecret(link)) then
                linkType = ParseLinkType(link)
            end
            TriggerTrace("ChatFrame.OnHyperlinkClick", string.format("type=%s button=%s frame=%s link=%s",
                SafeToString(linkType),
                SafeToString(button),
                SafeToString(chatFrame and chatFrame.GetName and chatFrame:GetName() or nil),
                SafeToString(link)
            ))

            if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
                TriggerTrace("ChatFrame.OnHyperlinkClick.PassToBlizzard", string.format("reason=lockdown link=%s", SafeToString(link)))
            end
        end, self)
        self._hyperlinkIntentRegistered = true
    end

    if LinkUtil and LinkUtil.ProcessLink and not self._bnetLinkHooked then
        hooksecurefunc(LinkUtil, "ProcessLink", function(link, _, contextData)
            if type(contextData) ~= "table" or contextData.button ~= "LeftButton" then
                return
            end
            if IsModifiedClick and IsModifiedClick("CHATLINK") then
                return
            end

            local utils = YapperTable.Utils
            local safeLink = utils and utils:SanitizeTarget(link) or link
            if not safeLink then
                return
            end

            local linkType, options = LinkUtil.SplitLinkData(safeLink)
            if linkType ~= LinkTypes.BNPlayer and linkType ~= LinkTypes.BNPlayerCommunity then
                return
            end

            local _, bnetAccountID = LinkUtil.SplitLinkOptions(options)
            bnetAccountID = utils and utils:SanitizeTarget(bnetAccountID) or bnetAccountID
            local numericID = bnetAccountID and tonumber(bnetAccountID)
            if numericID then
                OpenBnetAccountWhisper(numericID, contextData.frame)
            end
        end)
        self._bnetLinkHooked = true
    end

    local function GetSelectedBnetFriend()
        if not FriendsFrame
            or FriendsFrame.selectedFriendType ~= FRIENDS_BUTTON_TYPE_BNET
            or not FriendsFrame.selectedFriend
            or not C_BattleNet
            or type(C_BattleNet.GetFriendAccountInfo) ~= "function" then
            return nil
        end

        local accountInfo = C_BattleNet.GetFriendAccountInfo(FriendsFrame.selectedFriend)
        if not accountInfo then
            return nil
        end

        local utils = YapperTable.Utils
        local bnetAccountID = utils and utils:SanitizeTarget(accountInfo.bnetAccountID)
            or accountInfo.bnetAccountID
        if (type(bnetAccountID) ~= "string" and type(bnetAccountID) ~= "number")
            or bnetAccountID == "" then
            return nil
        end

        return tonumber(bnetAccountID) or bnetAccountID,
            utils and utils:SanitizeTarget(accountInfo.accountName) or accountInfo.accountName
    end

    local function HookFriendsFrameSendMessage()
        local button = FriendsFrameSendMessageButton
        if self._friendsBnetButtonHooked
            or not button
            or type(button.HookScript) ~= "function" then
            return
        end

        button:HookScript("PreClick", function()
            self._pendingBnetWhisper = nil
            local bnetAccountID, name = GetSelectedBnetFriend()
            if bnetAccountID then
                self._pendingBnetWhisper = {
                    target = bnetAccountID,
                    name = name,
                    t = GetTime(),
                }
            end
        end)
        button:HookScript("OnClick", function()
            local pending = self._pendingBnetWhisper
            if pending and GetTime() - pending.t <= 1 then
                OpenBnetAccountWhisper(pending.target, nil, pending.name)
            end
        end)
        self._friendsBnetButtonHooked = true
    end

    HookFriendsFrameSendMessage()
    if not self._friendsBnetAddonLoadedHooked and CreateFrame then
        local addonFrame = CreateFrame("Frame")
        addonFrame:RegisterEvent("ADDON_LOADED")
        addonFrame:SetScript("OnEvent", function(_, _, addonName)
            if addonName == "Blizzard_FriendsFrame" then
                HookFriendsFrameSendMessage()
            end
        end)
        self._friendsBnetAddonLoadedHooked = true
    end

    -- Capture the raw OpenChat argument so we can preserve leading slashes
    -- that ParseText/OnUpdate may strip before Blizzard's editbox text is set.
    if ChatFrameUtil and ChatFrameUtil.OpenChat and not self._openChatHooked then
        hooksecurefunc(ChatFrameUtil, "OpenChat", function(text, chatFrame, ...)
            TriggerTrace("ChatFrameUtil.OpenChat", string.format("text=%s frame=%s",
                SafeToString(text), SafeToString(chatFrame and chatFrame.GetName and chatFrame:GetName() or nil)))
            if text and YapperTable.Utils and YapperTable.Utils:IsSecret(text) then
                return
            end
            if self._suppressOpenChatHook then
                self._suppressOpenChatHook = nil
                return
            end
            if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
                -- Hands-off in lockdown: Blizzard owns OpenChat/ActivateChat/
                -- ParseText end-to-end to minimize taint spread.
                TriggerTrace("ChatFrameUtil.OpenChat.PassToBlizzard", "reason=lockdown")
                return
            end

            -- When CHAT_FOCUS_OVERRIDE points at our overlay, OpenChat's
            -- body already ran SetFocus()+SetText() on it. SetFocus is
            -- synchronous, so the triggering keybind's char event lands on
            -- the overlay after Lua returns (Shift-R -> "R" in the box).
            -- Fix: clear focus now (still sync, before the char event) and
            -- re-apply next frame so the char is discarded.
            local focusOverrideIntercepted = (_G.CHAT_FOCUS_OVERRIDE == self.OverlayEdit)
                and (chatFrame == nil)

            -- Also intercept when the overlay is already shown (e.g. TRP3
            -- calling OpenChat after send), or on channel-link clicks
            -- (slash prefills) while Yapper is open.
            local overlayAlreadyShown = (self.Overlay and self.Overlay:IsShown())
                and (chatFrame == nil or (text and text ~= "" and Core.IsChannelSlashPrefill(text)))

            -- Bypassing Yapper: outside lockdown, clear bypass and force
            -- the intercept; in lockdown, stay in Blizzard's box.
            if UserBypassingYapper() then
                local inLockdown = YapperTable.Utils and YapperTable.Utils:IsChatLockdown()
                if inLockdown then
                    return
                else
                    -- Kick back to Yapper; force the intercept to run.
                    SetUserBypassingYapper(false)
                    SetBypassEditBox(nil)
                    self:UpdateFocusOverride()
                    focusOverrideIntercepted = true
                end
            end

            if focusOverrideIntercepted or overlayAlreadyShown then

                if overlayAlreadyShown then
                    -- Apply slash-prefill channel/target immediately so
                    -- link-click switching works without a Show() cycle.
                    if text and text ~= "" and self.OverlayEdit then
                        if Core.IsChannelSlashPrefill(text) then
                            local ct, tgt, remainder = Core.ParseChannelSlash(text)
                            if ct then
                                TriggerTrace("IntentPath.OpenChatEarly", string.format("kind=channel chatType=%s target=%s",
                                    SafeToString(ct), SafeToString(tgt)))
                                StampRecentOpenChatIntent(self, ct, (ct == "CHANNEL") and tgt or nil)
                                self.ChatType = ct
                                if ct == "CHANNEL" then
                                    self.Target = tgt
                                    self.ChannelName = tgt and ResolveChannelName(tonumber(tgt)) or nil
                                else
                                    self.Target = nil
                                    self.ChannelName = nil
                                end
                                self:RefreshLabel()
                                if YapperTable.API then
                                    YapperTable.API:Fire("EDITBOX_CHANNEL_CHANGED", self.ChatType, self.Target)
                                end

                                -- If OpenChat wrote the raw slash prefill into the
                                -- overlay directly, strip it to the parsed remainder.
                                local cur = YapperTable.Recolour.CanonicalText(self.OverlayEdit)
                                if cur == text then
                                    local nextText = remainder or ""
                                    self.OverlayEdit:SetText(nextText)
                                    self.OverlayEdit:SetCursorPosition(#nextText)
                                end
                            end
                        elseif Core.IsWhisperSlashPrefill(text) then
                            local tgt, remainder = Core.ParseWhisperSlash(text)
                            if tgt then
                                TriggerTrace("IntentPath.OpenChatEarly", string.format("kind=whisper target=%s", SafeToString(tgt)))
                                StampRecentOpenChatIntent(self, "WHISPER", tgt)
                                self.ChatType = "WHISPER"
                                self.Target = tgt
                                self.ChannelName = nil
                                self:RefreshLabel()
                                if YapperTable.API then
                                    YapperTable.API:Fire("EDITBOX_CHANNEL_CHANGED", self.ChatType, self.Target)
                                end

                                local cur = YapperTable.Recolour.CanonicalText(self.OverlayEdit)
                                if cur == text then
                                    local nextText = remainder or ""
                                    self.OverlayEdit:SetText(nextText)
                                    self.OverlayEdit:SetCursorPosition(#nextText)
                                end
                            end
                        end
                    end

                    -- TRP3 case: just reclaim focus.
                    if self.OverlayEdit then
                        self.OverlayEdit:SetFocus()
                    end
                    self:EnsureProxyBackgroundShown()
                    C_Timer.After(0, function()
                        self:EnsureProxyBackgroundShown()
                    end)
                    return
                end

                -- Focus-override case: clear + re-apply so the char event
                -- isn't captured by the overlay.
                if not (self.Overlay and self.Overlay:IsShown()) then
                    self:Show(DEFAULT_CHAT_FRAME.editBox)
                end
                if self.OverlayEdit then
                    self.OverlayEdit:ClearFocus()
                end
                C_Timer.After(0, function()
                    if self.OverlayEdit and self.Overlay and self.Overlay:IsShown() then
                        self.OverlayEdit:SetFocus()
                    end
                end)
                return
            end

            -- Capture explicit channel-selection intent from slash commands
            -- routed through OpenChat: channel links ([Guild], [General])
            -- call OpenChat("/GUILD", frame) via ItemRef handlers; typing
            -- "/g" does the same. Consumed once by Show()/the live-update so
            -- the selection beats the LastUsed sticky -- without it,
            -- non-target chat types (GUILD/PARTY/...) lose to the
            -- remembered channel.
            if text and text ~= "" then
                if Core.IsChannelSlashPrefill(text) then
                    local ct, tgt = Core.ParseChannelSlash(text)
                    if ct then
                        TriggerTrace("IntentPath.OpenChatDeferred", string.format("kind=channel chatType=%s target=%s",
                            SafeToString(ct), SafeToString(tgt)))
                        StampRecentOpenChatIntent(self, ct, (ct == "CHANNEL") and tgt or nil)
                        self._explicitChannel = {
                            chatType    = ct,
                            target      = (ct == "CHANNEL") and tgt or nil,
                            channelName = (ct == "CHANNEL" and tgt)
                                and ResolveChannelName(tonumber(tgt)) or nil,
                            t           = GetTime(),
                        }
                    end
                elseif Core.IsWhisperSlashPrefill(text) then
                    local tgt = Core.ParseWhisperSlash(text)
                    if tgt then
                        TriggerTrace("IntentPath.OpenChatDeferred", string.format("kind=whisper target=%s", SafeToString(tgt)))
                        StampRecentOpenChatIntent(self, "WHISPER", tgt)
                        self._explicitChannel = {
                            chatType = "WHISPER",
                            target   = tgt,
                            t        = GetTime(),
                        }
                    end
                end
            end

            -- Tab clicks / chat-area clicks (chatFrame ~= nil, empty text):
            -- suppress the spurious overlay open on tab navigation while
            -- Yapper is closed (IM mode is handled by the ActivateChat
            -- hook). Normal Enter-to-chat needs no flag: the Show() hook
            -- opens the overlay next frame, after the blizzard editbox has
            -- consumed the physical char.
            if chatFrame ~= nil and (text == nil or text == "")
                and not (self.Overlay and self.Overlay:IsShown()) then
                local eb = chatFrame.editBox
                if eb and eb.GetName then
                    self._suppressNextShowFor = eb:GetName()
                    C_Timer.After(0, function()
                        if self._suppressNextShowFor == eb:GetName() then
                            self._suppressNextShowFor = nil
                        end
                    end)
                end
            end
        end)
        -- NOTE: do NOT wrap OpenChat -- a tainted wrapper taints the
        -- arguments passed to Blizzard's secure code, causing
        -- strlenutf8/UpdateHeader failures post-combat. The UIParent guard
        -- lives in EditBox:Show() and the UIParent OnHide hook.
        self._openChatHooked = true
    end

    -- The chat menu button (speech bubble) selects a channel via:
    --     local editBox = ChatFrameUtil.OpenChat("");
    --     editBox:SetChatType(chatType);
    -- With CHAT_FOCUS_OVERRIDE pointing at our overlay, OpenChat("") returns nil
    -- (it just refocuses the overlay), so SetChatType errors and the channel is
    -- never applied. We wrap each menu responder to (a) temporarily clear the
    -- override so OpenChat returns a real editbox, and (b) record the resulting
    -- chat type as an explicit selection that Show()/the live-update will adopt.
    if Menu and Menu.ModifyMenu and MenuUtil and MenuUtil.TraverseMenu
        and not self._chatMenuResponderHooked then
        local function WrapResponder(description)
            local orig = description.responder
            if type(orig) ~= "function" or description._yapperWrapped then return end
            description._yapperWrapped = true

            description.responder = function(data, menuInputData, menuProxy)
                local hadOverride = _G.CHAT_FOCUS_OVERRIDE
                _G.CHAT_FOCUS_OVERRIDE = nil
                -- Suppress our OpenChat hook while the menu responder runs
                -- so it doesn't trigger the Show path while Yapper is open.
                self._suppressOpenChatHook = true
                local ok, result = pcall(orig, data, menuInputData, menuProxy)
                self._suppressOpenChatHook = nil

                -- Adopt the channel the menu applied; capture twice (now +
                -- next frame) because some responders finalize chatType/
                -- target on deferred updates.
                local function CaptureMenuSelection()
                    local active = (ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
                        or (ChatFrameUtil.GetLastActiveWindow and ChatFrameUtil.GetLastActiveWindow())
                        or self.OrigEditBox
                    if not (active and active.GetChatType) then return nil end

                    local ct = active:GetChatType()
                    if not (ct and ct ~= "") then return nil end

                    local tgt, chanName
                    if ct == "WHISPER" or ct == "BN_WHISPER" then
                        tgt = active.GetAttribute
                            and YapperTable.Utils:SanitizeTarget(active:GetAttribute("tellTarget"))
                        if not tgt then return nil end
                    elseif ct == "CHANNEL" then
                        tgt = active.GetAttribute
                            and YapperTable.Utils:SanitizeTarget(active:GetAttribute("channelTarget"))
                        if not tgt then return nil end
                        chanName = tgt and ResolveChannelName(tonumber(tgt)) or nil
                    end

                    return {
                        chatType = ct,
                        target = tgt,
                        channelName = chanName,
                        active = active,
                    }
                end

                local function AdoptMenuSelection(selection)
                    if not selection then return end

                    self._explicitChannel = {
                        chatType    = selection.chatType,
                        target      = selection.target,
                        channelName = selection.channelName,
                        t           = GetTime(),
                    }

                    -- Already open: adopt immediately, preserving text.
                    if self.Overlay and self.Overlay:IsShown() then
                        local ct = selection.chatType
                        local tgt = selection.target
                        local chanName = selection.channelName
                        local changed = (self.ChatType ~= ct)
                            or (self.Target ~= tgt)
                            or (self.ChannelName ~= chanName)
                        self._explicitChannel = nil
                        self.ChatType    = ct
                        self.Target      = tgt
                        self.ChannelName = chanName
                        self:RefreshLabel()
                        self:UpdateFocusOverride()
                        self:EnsureProxyBackgroundShown()
                        if changed and YapperTable.API then
                            YapperTable.API:Fire("EDITBOX_CHANNEL_CHANGED", self.ChatType, self.Target)
                        end
                        if selection.active and ChatFrameUtil and ChatFrameUtil.DeactivateChat then
                            pcall(function() ChatFrameUtil.DeactivateChat(selection.active) end)
                        end
                        if self.OverlayEdit and self.OverlayEdit.SetFocus then
                            self.OverlayEdit:SetFocus()
                        end
                    end
                end

                -- Capture while the override is still cleared, then restore.
                local immediateSelection = CaptureMenuSelection()
                _G.CHAT_FOCUS_OVERRIDE = hadOverride

                AdoptMenuSelection(immediateSelection)
                C_Timer.After(0, function()
                    local deferredHadOverride = _G.CHAT_FOCUS_OVERRIDE
                    _G.CHAT_FOCUS_OVERRIDE = nil
                    local deferredSelection = CaptureMenuSelection()
                    _G.CHAT_FOCUS_OVERRIDE = deferredHadOverride

                    AdoptMenuSelection(deferredSelection)
                    if self.Overlay and self.Overlay:IsShown() then
                        if self.OverlayEdit and self.OverlayEdit.SetFocus then
                            self.OverlayEdit:SetFocus()
                        end
                        self:EnsureProxyBackgroundShown()
                    end
                end)

                if not ok then return nil end
                return result
            end
        end

        Menu.ModifyMenu("MENU_CHAT_SHORTCUTS", function(owner, rootDescription)
            MenuUtil.TraverseMenu(rootDescription, WrapResponder)
        end)
        self._chatMenuResponderHooked = true
    end

    -- DeactivateChat hook: in Classic style, Blizzard's Deactivate on the
    -- orig editbox would leave the proxy background hidden while the
    -- overlay is shown; re-show it. RestoreProxyMode still hides it on
    -- Yapper close, so the Classic lifecycle is preserved.
    if ChatFrameUtil and ChatFrameUtil.DeactivateChat and not self._deactivateChatHooked then
        hooksecurefunc(ChatFrameUtil, "DeactivateChat", function(editBox)
            if self._closing then return end
            if self.OrigEditBox == editBox and self.Overlay and self.Overlay:IsShown() then
                self:EnsureProxyBackgroundShown()
                return
            end
            -- Blizzard auto-deactivated our ACTIVE editor (e.g. world click):
            -- re-sync ownership next frame unless Yapper is closing/bypassed
            -- (closing paths clear _chatCompatEnabled before we get here).
            if editBox == self.OverlayEdit
                or (YapperTable.Multiline and editBox == YapperTable.Multiline.EditBox) then
                local after = C_Timer and C_Timer.After
                if after and self._chatCompatEnabled ~= false then
                    after(0, function()
                        if not (self.GetActiveEditor and self:GetActiveEditor()) then return end
                        if self._chatCompatEnabled == false then return end
                        if UserBypassingYapper() then return end
                        if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then return end
                        self:UpdateFocusOverride()
                    end)
                end
            end
        end)
        self._deactivateChatHooked = true
    end

    -- ActivateChat hook: complements OpenChat so Yapper catches all show
    -- paths (e.g. direct EditBox:SetFocus).
    if ChatFrameUtil and ChatFrameUtil.ActivateChat and not self._activateChatHooked then
        hooksecurefunc(ChatFrameUtil, "ActivateChat", function(editBox)
            -- A Yapper editor activated via a native path (FocusActiveWindow
            -- on our ACTIVE_CHAT_EDIT_BOX, IM-mode ChooseBoxForSend):
            -- ActivateChat clears CHAT_FOCUS_OVERRIDE internally, so re-sync
            -- it here.
            if editBox == self.OverlayEdit
                or (YapperTable.Multiline and editBox == YapperTable.Multiline.EditBox) then
                if self.UpdateFocusOverride then
                    self:UpdateFocusOverride()
                end
                return
            end
            if not editBox or not editBox.GetName then return end
            local name = editBox:GetName()
            if not name or not name:match("ChatFrame%d+EditBox") then return end

            if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
                return
            end
            if UserBypassingYapper() then return end
            if self._suppressActivateChatHook then return end
            if self.Overlay and self.Overlay:IsShown() then
                -- Native code activated a Blizzard box while our editor is
                -- up; reclaim ACTIVE_CHAT_EDIT_BOX next frame so
                -- GetActiveWindow keeps returning the overlay (the old
                -- GetActiveWindow wrapper's semantics).
                local after = C_Timer and C_Timer.After
                if after then
                    after(0, function()
                        if not (self.Overlay and self.Overlay:IsShown()) then return end
                        if self._chatCompatEnabled == false then return end
                        if UserBypassingYapper() then return end
                        if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then return end
                        self:UpdateFocusOverride()
                    end)
                end
                return
            end

            -- IM mode: the editbox is always shown, so our Show hook never
            -- fires for a user open (IsShown was already true). ActivateChat
            -- is the real entry point; handle the open here.
            local chatStyle = GetCVar("chatStyle")
            if chatStyle == "im" then
                self:_IMPushActive(editBox)
                C_Timer.After(0, function()
                    if self.Overlay and self.Overlay:IsShown() then return end
                    if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then return end
                    if UserBypassingYapper() then return end
                    -- ActivateChat cleared the focus override; restore it.
                    self:UpdateFocusOverride()
                    self:Show(editBox)
                end)
                return
            end

            -- Non-IM: the editbox Show() hook handles presentation.
            self._activateChatTriggered = true
            C_Timer.After(0, function()
                self._activateChatTriggered = nil
            end)
        end)
        self._activateChatHooked = true
    end

    -- Intercept whispers initiated OUTSIDE the unit-popup menu (chat name
    -- left-click, LFG, Professions, Communities, ItemRef). Menu whispers go
    -- through the responder in Hooks/UnitPopup.lua and never call SendTell
    -- (except during lockdown, where this hook early-returns anyway), so
    -- the paths don't overlap. Fires AFTER Blizzard's box opens, so we
    -- snapshot its whisper state and reopen as Yapper.
    if ChatFrameUtil and ChatFrameUtil.SendTell and not self._sendTellHooked then
        hooksecurefunc(ChatFrameUtil, "SendTell", function(target, chatFrame)
            -- Sanitize before ANY comparison: a secret target is unusable
            -- input (Blizzard's own path still runs).
            target = YapperTable.Utils and YapperTable.Utils:SanitizeTarget(target) or nil
            TriggerTrace("ChatFrameUtil.SendTell", string.format("target=%s frame=%s",
                SafeToString(target), SafeToString(chatFrame and chatFrame.GetName and chatFrame:GetName() or nil)))
            -- Unusable input or lockdown: leave Blizzard's box as-is.
            if type(target) ~= "string" or target == "" then return end
            if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then return end

            local blizzBox = chatFrame and chatFrame.editBox
            if not self:IsNativeChatEditBox(blizzBox)
                and ChatFrameUtil and ChatFrameUtil.GetActiveWindow then
                blizzBox = ChatFrameUtil.GetActiveWindow()
            end
            if not self:IsNativeChatEditBox(blizzBox) then
                local fallback = self.OrigEditBox
                    or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
                    or _G.ChatFrame1EditBox
                blizzBox = self:IsNativeChatEditBox(fallback) and fallback or nil
            end

            -- Already open: retarget in place via the shared helper
            -- (avoids SendTell reentrancy races).
            if self.Overlay and self.Overlay:IsShown() then
                self:RetargetOpenWhisper(target, blizzBox)
                return
            end

            -- Yapper closed: snapshot the whisper attributes BEFORE hiding.
            -- Hide() -> Deactivate -> ResetChatTypeToSticky -> SetChatType("SAY")
            -- would otherwise wipe the _attrCache whisper info Show() depends on.
            local existingText = ""
            if self:IsNativeChatEditBox(blizzBox) then
                existingText = blizzBox:GetText() or ""
                local c = self._attrCache[blizzBox]
                local savedCache = c and { chatType = c.chatType, tellTarget = c.tellTarget,
                                           channelTarget = c.channelTarget, language = c.language } or nil
                blizzBox:Hide()
                blizzBox:SetText("")
                if savedCache then
                    self._attrCache[blizzBox] = savedCache
                end
            end

            -- Show() reads _attrCache and picks up the whisper context
            -- Blizzard's ParseText set via SetAttribute.
            self:Show(blizzBox or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox) or _G.ChatFrame1EditBox)

            -- Force whisper context AFTER Show() as the final authority in
            -- case the cache was stale or a race overwrote it.
            self.ChatType = "WHISPER"
            self.Target = target
            self.ChannelName = nil
            self._externalWhisperTarget = target

            if existingText ~= "" and self.OverlayEdit then
                self.OverlayEdit:SetText(existingText)
            end

            self:RefreshLabel()
        end)
        self._sendTellHooked = true
    end

    -- Intercept BNet whispers from non-menu sources (hyperlink handlers,
    -- social UI). Menu BNet whispers (BN_FRIEND* right-click) go through
    -- the responder in Hooks/UnitPopup.lua, which bypasses SendBNetTell to
    -- avoid the OpenChat("") -> CHAT_FOCUS_OVERRIDE race. This hook covers
    -- the remaining paths and mirrors SendTell handling with BN_WHISPER.
    if ChatFrameUtil and ChatFrameUtil.SendBNetTell and not self._sendBNetTellHooked then
        hooksecurefunc(ChatFrameUtil, "SendBNetTell", function(target)
            -- Same secret quarantine as the SendTell hook above.
            target = YapperTable.Utils and YapperTable.Utils:SanitizeTarget(target) or nil
            TriggerTrace("ChatFrameUtil.SendBNetTell", string.format("target=%s", SafeToString(target)))
            if type(target) ~= "string" or target == "" then return end
            if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then return end

            local blizzBox = ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow()
            if not self:IsNativeChatEditBox(blizzBox) then
                local fallback = self.OrigEditBox
                    or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
                    or _G.ChatFrame1EditBox
                blizzBox = self:IsNativeChatEditBox(fallback) and fallback or nil
            end

            if self.Overlay and self.Overlay:IsShown() then
                self.ChatType = "BN_WHISPER"
                self.Target = target
                self.ChannelName = nil
                self._externalWhisperTarget = target
                self:RefreshLabel()
                self:EnsureProxyBackgroundShown()
                if self.OverlayEdit then
                    self.OverlayEdit:SetFocus()
                end
                return
            end

            local existingText = ""
            if self:IsNativeChatEditBox(blizzBox) then
                existingText = blizzBox:GetText() or ""
                blizzBox:Hide()
                blizzBox:SetText("")
            end

            self:Show(blizzBox or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox) or _G.ChatFrame1EditBox)
            self.ChatType = "BN_WHISPER"
            self.Target = target
            self.ChannelName = nil
            self._externalWhisperTarget = target

            if existingText ~= "" and self.OverlayEdit then
                self.OverlayEdit:SetText(existingText)
            end

            self:RefreshLabel()
        end)
        self._sendBNetTellHooked = true
    end

    -- REMOVED: ChatFrameUtil.ReplyTell2 hook. Re-Whisper is handled by the
    -- REPLYTELL2 keybind override in Keybinds.lua now. Impact: addons that
    -- call ReplyTell2 programmatically won't trigger the overlay.

    -- InsertLink: TRP3 shift-clicking links calls ChatFrameUtil.InsertLink
    -- (or the deprecated ChatEdit_InsertLink alias). With Yapper closed this
    -- bypasses OpenChat entirely, inserting text into the hidden
    -- YapperOverlayEditBox and failing SetFocus.
    if not self._insertLinkHooked then
        local function OnInsertLink(text)
            -- Keep the editor Blizzard routed to focused -- important for
            -- multiline, whose frame replaces the hidden overlay while the
            -- link API runs.
            local activeEditor = self.GetActiveEditor and self:GetActiveEditor()
            local routedEditor = ChatFrameUtil and ChatFrameUtil.GetActiveWindow
                and ChatFrameUtil.GetActiveWindow()
            if activeEditor and routedEditor == activeEditor then
                if activeEditor.SetFocus then
                    activeEditor:SetFocus()
                end
                return
            end

            if CHAT_FOCUS_OVERRIDE and CHAT_FOCUS_OVERRIDE == self.OverlayEdit then
                if not (self.Overlay and self.Overlay:IsShown()) then
                    self:Show(DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
                    self.OverlayEdit:SetFocus()
                end
            end
        end
        -- The deprecated alias is a separate function reference, so both
        -- entry points need their own hook.
        if ChatFrameUtil and ChatFrameUtil.InsertLink then
            hooksecurefunc(ChatFrameUtil, "InsertLink", OnInsertLink)
        end
        if _G.ChatEdit_InsertLink then
            hooksecurefunc("ChatEdit_InsertLink", OnInsertLink)
        end
        self._insertLinkHooked = true
    end

    -- Work around waypoint pins attempting copytoclipboard on shift-click
    -- (thanks blizz). Rather than patching WaypointLocationPinMixin -- a write
    -- onto pooled pin frames that gets blamed for unrelated combat-protected
    -- calls like SetPassThroughButtons during pin refresh -- consume CHATLINK
    -- clicks through MapCanvas's taint-aware global pin handler registry:
    -- handlers run before OnMouseClickAction and a truthy return skips it, so
    -- the protected CopyToClipboard is never reached and no Blizzard object
    -- is written.
    local OnWaypointPinMouseAction
    do
        local copyFrame
        local function ShowWaypointSlashCommand()
            local waypoint = C_Map and C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
            if not waypoint then return end
            -- POSITION_FACTOR in WaypointLocationDataProvider.lua: 0..1 -> 0..100.
            local slashCommand = SLASH_MAPPIN1 .. string.format(" %d %.1f %.1f",
                waypoint.uiMapID,
                waypoint.position.x * 100,
                waypoint.position.y * 100)
            -- Restricted contexts (combat lockdown, pet battles): don't pop
            -- UI at all; leave the command in chat where it can be seen.
            if InCombatLockdown()
                or (C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle())
            then
                if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
                    DEFAULT_CHAT_FRAME:AddMessage(slashCommand)
                end
                return
            end
            if not copyFrame then
                copyFrame = CreateFrame("Frame", "YapperWaypointCopyFrame", UIParent, "BackdropTemplate")
                copyFrame:SetSize(360, 64)
                copyFrame:SetFrameStrata("DIALOG")
                copyFrame:SetClampedToScreen(true)
                copyFrame:EnableMouse(true)
                copyFrame:SetBackdrop({
                    bgFile = "Interface/ChatFrame/ChatFrameBackground",
                    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
                    edgeSize = 16,
                    insets = { left = 4, right = 4, top = 4, bottom = 4 },
                })
                copyFrame:SetBackdropColor(0, 0, 0, 0.9)
                -- Breathing border glow to draw the eye.
                local glow = CreateFrame("Frame", nil, copyFrame, "BackdropTemplate")
                glow:SetPoint("TOPLEFT", -2, 2)
                glow:SetPoint("BOTTOMRIGHT", 2, -2)
                glow:SetBackdrop({
                    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                    edgeSize = 14,
                    insets = { left = 3, right = 3, top = 3, bottom = 3 },
                })
                glow:SetBackdropBorderColor(1, 0.82, 0, 1)
                glow:SetFrameLevel(copyFrame:GetFrameLevel() + 1)
                local glowTime = 0
                glow:SetScript("OnUpdate", function(_, elapsed)
                    glowTime = glowTime + elapsed
                    glow:SetAlpha(0.55 + 0.45 * math.sin(glowTime * 4))
                end)
                glow:Hide()
                copyFrame.glow = glow
                local title = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                title:SetPoint("TOP", 0, -8)
                title:SetText("Waypoint command -- press Ctrl+C to copy")
                local countdown = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                countdown:SetPoint("BOTTOM", 0, 6)
                countdown:Hide()
                copyFrame.countdown = countdown
                -- Once armed by a focus loss, closes 10s later even if the
                -- user refocuses the field.
                copyFrame:SetScript("OnUpdate", function()
                    if not copyFrame.closeDeadline then return end
                    local remaining = copyFrame.closeDeadline - GetTime()
                    if remaining <= 0 then
                        copyFrame:Hide()
                    else
                        countdown:SetFormattedText("Closing in %d...", math.ceil(remaining))
                    end
                end)
                local eb = CreateFrame("EditBox", nil, copyFrame)
                eb:SetPoint("CENTER", 0, -4)
                eb:SetSize(320, 20)
                eb:SetFontObject(GameFontHighlight)
                eb:SetAutoFocus(false)
                eb:SetScript("OnEscapePressed", function(b) b:ClearFocus() copyFrame:Hide() end)
                eb:SetScript("OnEnterPressed", function(b) b:ClearFocus() copyFrame:Hide() end)
                eb:SetScript("OnKeyDown", function(_, key)
                    if key == "C" and IsControlKeyDown() then
                        -- Let the native copy land first, then dismiss --
                        -- unless a newer command was shown in the meantime.
                        local copied = copyFrame.command
                        C_Timer.After(0.05, function()
                            if copyFrame.command == copied then copyFrame:Hide() end
                        end)
                    end
                end)
                -- Clicking into the field re-selects the whole command, and
                -- any user edit is undone: this is a copy box, not an editor.
                eb:SetScript("OnEditFocusGained", function(b) b:HighlightText() end)
                eb:SetScript("OnMouseUp", function(b) b:HighlightText() end)
                eb:SetScript("OnEditFocusLost", function()
                    copyFrame.closeDeadline = GetTime() + 10
                    countdown:Show()
                end)
                eb:SetScript("OnTextChanged", function(b, userInput)
                    if userInput and copyFrame.command and b:GetText() ~= copyFrame.command then
                        b:SetText(copyFrame.command)
                        b:HighlightText()
                    end
                end)
                copyFrame.editBox = eb
                copyFrame:SetScript("OnShow", function()
                    copyFrame.glow:Show()
                    copyFrame.closeDeadline = nil
                    countdown:Hide()
                    if SOUNDKIT and SOUNDKIT.UI_BNET_TOAST then
                        PlaySound(SOUNDKIT.UI_BNET_TOAST)
                    end
                end)
                -- Hand keyboard focus back to the chat editor on dismiss.
                copyFrame:SetScript("OnHide", function()
                    copyFrame.glow:Hide()
                    copyFrame.closeDeadline = nil
                    countdown:Hide()
                    local editor = self.GetActiveEditor and self:GetActiveEditor()
                    if editor and editor.SetFocus then editor:SetFocus() end
                end)
                tinsert(UISpecialFrames, "YapperWaypointCopyFrame")
            end
            copyFrame.command = slashCommand
            copyFrame.editBox:SetText(slashCommand)
            -- Under the map while it is windowed; flip above when the space
            -- below is too tight; centre screen when no map is up.
            -- ClampedToScreen covers any remaining edge overlap.
            copyFrame:ClearAllPoints()
            local margin = 8
            local needed = copyFrame:GetHeight() + margin
            if WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown()
                and not (WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized())
            then
                if (WorldMapFrame:GetBottom() or 0) >= needed then
                    copyFrame:SetPoint("TOP", WorldMapFrame, "BOTTOM", 0, -margin)
                elseif ((UIParent:GetTop() or 0) - (WorldMapFrame:GetTop() or 0)) >= needed then
                    copyFrame:SetPoint("BOTTOM", WorldMapFrame, "TOP", 0, margin)
                else
                    -- No clean side; stay under and let the clamp pull it in.
                    copyFrame:SetPoint("TOP", WorldMapFrame, "BOTTOM", 0, -margin)
                end
            else
                copyFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
            end
            copyFrame:Show()
            copyFrame.editBox:SetFocus()
            copyFrame.editBox:HighlightText()
        end
        -- Consume CHATLINK clicks on the waypoint pin: do InsertLink + share
        -- sound + copy frame ourselves, then skip OnMouseClickAction (and the
        -- protected CopyToClipboard inside it) by returning true.
        local function WaypointChatLinkHandler(mapCanvas, mouseAction, button)
            local click = MapCanvasMixin and MapCanvasMixin.MouseAction
                and MapCanvasMixin.MouseAction.Click
            if mouseAction ~= click or button ~= "LeftButton"
                or not IsModifiedClick("CHATLINK") then
                return false
            end
            for pin in mapCanvas:EnumeratePinsByTemplate("WaypointLocationPinTemplate") do
                if pin:IsMouseOver() then
                    local link = C_Map.GetUserWaypointHyperlink()
                    if link then ChatFrameUtil.InsertLink(link) end
                    ShowWaypointSlashCommand()
                    if SOUNDKIT and SOUNDKIT.UI_MAP_WAYPOINT_CHAT_SHARE then
                        PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_CHAT_SHARE)
                    end
                    return true
                end
            end
            return false
        end
        OnWaypointPinMouseAction = WaypointChatLinkHandler
    end
    local function RegisterWaypointChatLinkHandler()
        if self._waypointChatLinkHooked then return end
        if not (WorldMapFrame and WorldMapFrame.AddGlobalPinMouseActionHandler) then
            return
        end
        -- Far-lowest priority: every other registered handler (debug 100,
        -- the provider's placement logic at 90, third-party observers) sees
        -- the click first; we only consume a CHATLINK click nobody claimed.
        WorldMapFrame:AddGlobalPinMouseActionHandler(OnWaypointPinMouseAction, -1000)
        self._waypointChatLinkHooked = true
    end
    RegisterWaypointChatLinkHandler()
    -- WorldMapFrame may not exist until the map addon loads: retry then.
    if not self._waypointAddonLoadedHooked and CreateFrame then
        local addonFrame = CreateFrame("Frame")
        addonFrame:RegisterEvent("ADDON_LOADED")
        addonFrame:SetScript("OnEvent", function(_, _, addonName)
            if addonName == "Blizzard_WorldMap" then
                RegisterWaypointChatLinkHandler()
            end
        end)
        self._waypointAddonLoadedHooked = true
    end

    -- Tab clicks don't trigger the editbox Show() hook, so hook the tab UI.
    -- Whisper tabs use Blizzard's chatType/chatTarget; other tabs use
    -- Yapper's session-only per-tab channel memory.
    if FCF_Tab_OnClick and not self._tabClickHooked then
        local editBox = self

        -- Yapper open: apply the switch now. Yapper closed: stash for the
        -- next open.
        local function ApplyOrStashSwitch(chatFrame, switch)
            if editBox.Overlay and editBox.Overlay:IsShown() then
                -- Prime the pending switch so Show()'s priority logic picks
                -- it up, then delegate: Show() handles re-parent, re-anchor,
                -- re-scale, proxy swap, font recalc, and focus. Its text
                -- guard preserves in-progress text.
                editBox._pendingTabSwitch = {
                    chatType    = switch.chatType,
                    target      = switch.target,
                    channelName = switch.channelName,
                    language    = switch.language,
                    chatFrame   = chatFrame,
                    editBox     = chatFrame.editBox,
                }
                editBox:Show(chatFrame.editBox)
                YapperTable.Utils:VerbosePrint("Applied tab switch via Show(): chatType="..SafeToString(switch.chatType).." target="..SafeToString(switch.target))
            else
                editBox._pendingTabSwitch = {
                    chatType    = switch.chatType,
                    target      = switch.target,
                    channelName = switch.channelName,
                    language    = switch.language,
                    chatFrame   = chatFrame,
                    editBox     = chatFrame.editBox,
                }
                editBox._suppressNextShowFor = nil
                YapperTable.Utils:VerbosePrint("Stored pending tab switch: chatType="..SafeToString(switch.chatType).." target="..SafeToString(switch.target))
            end
        end

        hooksecurefunc("FCF_Tab_OnClick", function(tab, button)
            if button ~= "LeftButton" then return end

            local chatFrame = FCF_GetChatFrameByID(tab:GetID())
            if not chatFrame then return end
            EnsureEditBoxHooked(chatFrame.editBox)

            -- Save outgoing state before switching. When Yapper is OPEN the
            -- Show hook already recorded the outgoing frame (before
            -- OverlayEdit.chatFrame was swapped), so do NOT record again:
            -- chatFrame now points at the INCOMING frame and we'd write the
            -- old channel onto the new frame.
            if not (editBox.Overlay and editBox.Overlay:IsShown())
                    and editBox._pendingTabSwitch and editBox._pendingTabSwitch.chatFrame then
                -- Yapper closed: flush a previously stashed switch into
                -- _tabChannelMemory under the correct key before
                -- overwriting, so rapid tab clicks don't lose state.
                local prev = editBox._pendingTabSwitch
                local prevKey = prev.chatFrame.GetName and prev.chatFrame:GetName()
                if prevKey and prev.chatType
                        and prev.chatType ~= "WHISPER" and prev.chatType ~= "BN_WHISPER" then
                    editBox._tabChannelMemory = editBox._tabChannelMemory or {}
                    editBox._tabChannelMemory[prevKey] = {
                        chatType    = prev.chatType,
                        target      = prev.target,
                        channelName = prev.channelName,
                        language    = prev.language,
                    }
                end
            end

            -- Track the active window so keybinds open on the right frame.
            if chatFrame.editBox then
                editBox:_IMPushActive(chatFrame.editBox)
            end

            -- If a close just happened, _IMPopActive already restored the
            -- right memory via _IMApplyWindowMemory; don't overwrite it.
            if editBox._suppressTabSwitchMemory then return end

            local cfType = chatFrame.chatType
            -- chatTarget can be secret under forced restrictions; treat a
            -- secret as targetless below.
            local cfTarget = YapperTable.Utils:SanitizeTarget(chatFrame.chatTarget)
            YapperTable.Utils:VerbosePrint("Tab click: chatFrame="..(chatFrame:GetName() or "nil").." chatType="..SafeToString(cfType).." chatTarget="..SafeToString(cfTarget))

            -- Whisper tab: restore from Blizzard's chatTarget.  The helper
            -- also resolves BN_WHISPER |K-token/secret targets to a numeric
            -- BNet account ID so the whisper doesn't collapse to SAY.
            local whisperType, whisperTarget = editBox:ResolveWhisperFrameTarget(chatFrame)
            if whisperType and whisperTarget then
                ApplyOrStashSwitch(chatFrame, {
                    chatType = whisperType,
                    target   = whisperTarget,
                })
            else
                -- Non-whisper tab: restore from per-tab memory if available,
                -- otherwise use this frame's own chatType so LastUsed doesn't bleed.
                local key = chatFrame.GetName and chatFrame:GetName()
                local mem = key and editBox._tabChannelMemory[key]
                ApplyOrStashSwitch(chatFrame, {
                    chatType    = mem and mem.chatType    or cfType or "SAY",
                    target      = mem and mem.target      or nil,
                    channelName = mem and mem.channelName or nil,
                    language    = mem and mem.language    or nil,
                })
            end
        end)
        self._tabClickHooked = true
    end

    -- FCF_MaximizeFrame: restoring a minimized undocked window fires the
    -- frame's OnShow but not the editbox Show() hook (child visibility), so
    -- update _lastActiveIMEditBox here so keybinds open on it.
    if FCF_MaximizeFrame and not self._maximizeHooked then
        local editBox = self
        hooksecurefunc("FCF_MaximizeFrame", function(chatFrame)
            if not chatFrame or not chatFrame.editBox then return end
            EnsureEditBoxHooked(chatFrame.editBox)
            editBox:_IMPushActive(chatFrame.editBox)
            -- Restore the remembered channel state for this window.
            editBox:_IMApplyWindowMemory(chatFrame)
        end)
        self._maximizeHooked = true
    end

    -- FCF_MinimizeFrame: close Yapper if open on this frame, pop the IM
    -- history, then reactivate the restored editbox.
    if FCF_MinimizeFrame and not self._minimizeHooked then
        local editBox = self
        hooksecurefunc("FCF_MinimizeFrame", function(chatFrame)
            if not chatFrame or not chatFrame.editBox then return end
            if editBox.Overlay and editBox.Overlay:IsShown()
                and editBox.OrigEditBox == chatFrame.editBox then
                editBox:Hide()
            end
            editBox:_IMPopActive(chatFrame.editBox)
            -- Restore channel memory for the window we popped back to.
            local restoredEB = editBox._lastActiveIMEditBox
            if restoredEB and restoredEB.chatFrame then
                editBox:_IMApplyWindowMemory(restoredEB.chatFrame)
            end
            -- Show the restored window's editbox in its normal IM idle state.
            if restoredEB and ChatFrameUtil and ChatFrameUtil.ActivateChat then
                editBox._suppressActivateChatHook = true
                pcall(function() ChatFrameUtil.ActivateChat(restoredEB) end)
                -- Then deactivate so it fades to idle, not focused.
                pcall(function() ChatFrameUtil.DeactivateChat(restoredEB) end)
                editBox._suppressActivateChatHook = false
            end
        end)
        self._minimizeHooked = true
    end

    -- FCF_Close (window fully closed): pop history, fall back to
    -- ChatFrame1.
    if FCF_Close and not self._closeHooked then
        local editBox = self
        hooksecurefunc("FCF_Close", function(frame)
            if not frame or not frame.editBox then return end
            -- FCF_UnDockFrame inside FCF_Close fires FCF_Tab_OnClick on the
            -- newly selected tab; suppress the tab hook's memory write so
            -- it can't overwrite the memory we restore here.
            editBox._suppressTabSwitchMemory = true
            editBox:_IMPopActive(frame.editBox)
            -- Apply the restored window's channel memory.
            local restoredEB = editBox._lastActiveIMEditBox
            if restoredEB and restoredEB.chatFrame then
                editBox:_IMApplyWindowMemory(restoredEB.chatFrame)
            end
            C_Timer.After(0, function()
                editBox._suppressTabSwitchMemory = false
            end)
        end)
        self._closeHooked = true
    end
end

--- Push an editbox onto the IM active window history stack.
--- Deduplicates: if already at the top, does nothing.
