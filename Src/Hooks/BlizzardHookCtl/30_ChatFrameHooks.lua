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

local type = type
local tonumber = tonumber
local tostring = tostring
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

    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb then
            EnsureEditBoxHooked(eb)
        end
    end

    if YapperTable.Utils then
        YapperTable.Utils:VerbosePrint("EditBox overlays hooked for " .. (NUM_CHAT_WINDOWS or 10) .. " chat frames.")
    end

    -- Record sends made through Blizzard's native editbox (lockdown / bypass /
    -- handoff fallback) into Yapper's history.  Registered once; the overlay is
    -- not a ChatFrameEditBoxMixin and never fires this event, so normal Yapper
    -- sends are not double-recorded.
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
            local linkType = ParseLinkType(link)
            TriggerTrace("ChatFrame.OnHyperlinkClick", string.format("type=%s button=%s frame=%s link=%s",
                tostring(linkType),
                tostring(button),
                tostring(chatFrame and chatFrame.GetName and chatFrame:GetName() or nil),
                tostring(link)
            ))

            if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
                TriggerTrace("ChatFrame.OnHyperlinkClick.PassToBlizzard", string.format("reason=lockdown link=%s", tostring(link)))
            end
        end, self)
        self._hyperlinkIntentRegistered = true
    end

    -- Capture the raw OpenChat argument so we can preserve leading slashes
    -- that ParseText/OnUpdate may strip before Blizzard's editbox text is set.
    if ChatFrameUtil and ChatFrameUtil.OpenChat and not self._openChatHooked then
        hooksecurefunc(ChatFrameUtil, "OpenChat", function(text, chatFrame, ...)
            TriggerTrace("ChatFrameUtil.OpenChat", string.format("text=%s frame=%s",
                tostring(text), tostring(chatFrame and chatFrame.GetName and chatFrame:GetName() or nil)))
            if self._suppressOpenChatHook then
                self._suppressOpenChatHook = nil
                return
            end
            if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
                -- Hands-off in lockdown: let Blizzard own OpenChat/ActivateChat/ParseText
                -- end-to-end to minimize taint spread into HandleChatType/UpdateHeader.
                TriggerTrace("ChatFrameUtil.OpenChat.PassToBlizzard", "reason=lockdown")
                return
            end

            -- When CHAT_FOCUS_OVERRIDE points at our overlay, Blizzard's OpenChat
            -- body has already called SetFocus()+SetText() on the overlay directly.
            -- SetFocus() is synchronous, so the triggering keybind's character event
            -- fires on the overlay after all Lua returns (e.g. Shift-R -> "R" in box).
            -- Fix: clear focus now (still sync, before the char event) and re-apply
            -- it next frame so the char finds no focused editbox and is discarded.
            local focusOverrideIntercepted = (_G.CHAT_FOCUS_OVERRIDE == self.OverlayEdit)
                and (chatFrame == nil)

            -- Also intercept if overlay is already shown (e.g., TRP3 calling OpenChat after send).
            -- In this case, reclaim focus immediately instead of deferring through watchdog.
            -- Also treat channel link clicks (slash prefills) as overlay-already-shown when Yapper is open.
            local overlayAlreadyShown = (self.Overlay and self.Overlay:IsShown())
                and (chatFrame == nil or (text and text ~= "" and Core.IsChannelSlashPrefill(text)))

            -- If user is bypassing Yapper:
            -- - NOT in lockdown: kick back to Yapper (clear bypass, force intercept)
            -- - IN lockdown: stay in Blizzard's box (return early)
            if UserBypassingYapper() then
                local inLockdown = YapperTable.Utils and YapperTable.Utils:IsChatLockdown()
                if inLockdown then
                    -- Stay in Blizzard's box during lockdown
                    self._openingWatchdog = false
                    return
                else
                    -- Kick back to Yapper when not in lockdown
                    SetUserBypassingYapper(false)
                    SetBypassEditBox(nil)
                    self:UpdateFocusOverride()
                    -- Force the intercept to run so Yapper actually opens
                    focusOverrideIntercepted = true
                end
            end

            if focusOverrideIntercepted or overlayAlreadyShown then

                if overlayAlreadyShown then
                    -- Overlay already shown: apply slash-prefill channel/target
                    -- immediately so link-click channel switching works without
                    -- requiring a full Show() cycle.
                    if text and text ~= "" and self.OverlayEdit then
                        if Core.IsChannelSlashPrefill(text) then
                            local ct, tgt, remainder = Core.ParseChannelSlash(text)
                            if ct then
                                TriggerTrace("IntentPath.OpenChatEarly", string.format("kind=channel chatType=%s target=%s",
                                    tostring(ct), tostring(tgt)))
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
                                local cur = self.OverlayEdit:GetText() or ""
                                if cur == text then
                                    local nextText = remainder or ""
                                    self.OverlayEdit:SetText(nextText)
                                    self.OverlayEdit:SetCursorPosition(#nextText)
                                end
                            end
                        elseif Core.IsWhisperSlashPrefill(text) then
                            local tgt, remainder = Core.ParseWhisperSlash(text)
                            if tgt then
                                TriggerTrace("IntentPath.OpenChatEarly", string.format("kind=whisper target=%s", tostring(tgt)))
                                StampRecentOpenChatIntent(self, "WHISPER", tgt)
                                self.ChatType = "WHISPER"
                                self.Target = tgt
                                self.ChannelName = nil
                                self:RefreshLabel()
                                if YapperTable.API then
                                    YapperTable.API:Fire("EDITBOX_CHANNEL_CHANGED", self.ChatType, self.Target)
                                end

                                local cur = self.OverlayEdit:GetText() or ""
                                if cur == text then
                                    local nextText = remainder or ""
                                    self.OverlayEdit:SetText(nextText)
                                    self.OverlayEdit:SetCursorPosition(#nextText)
                                end
                            end
                        end
                    end

                    -- Overlay already shown (TRP3 case): just reclaim focus immediately
                    if self.OverlayEdit then
                        self.OverlayEdit:SetFocus()
                    end
                    self:EnsureProxyBackgroundShown()
                    C_Timer.After(0, function()
                        self:EnsureProxyBackgroundShown()
                    end)
                    self._openingWatchdog = false
                    return
                end

                -- Focus override case: need to clear and re-apply to prevent char event capture
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
                self._openingWatchdog = false
                return
            end

            -- Capture explicit channel-selection intent from any slash command
            -- routed through OpenChat: channel links ([Guild], [General], etc.
            -- via ItemRef handlers call OpenChat("/GUILD", frame); typing "/g"
            -- does the same. This is consumed once by Show()/the live-update so
            -- the selection overrides the LastUsed sticky — without it, non-target
            -- chat types (GUILD/PARTY/...) never beat the remembered channel.
            if text and text ~= "" then
                if Core.IsChannelSlashPrefill(text) then
                    local ct, tgt = Core.ParseChannelSlash(text)
                    if ct then
                        TriggerTrace("IntentPath.OpenChatDeferred", string.format("kind=channel chatType=%s target=%s",
                            tostring(ct), tostring(tgt)))
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
                        TriggerTrace("IntentPath.OpenChatDeferred", string.format("kind=whisper target=%s", tostring(tgt)))
                        StampRecentOpenChatIntent(self, "WHISPER", tgt)
                        self._explicitChannel = {
                            chatType = "WHISPER",
                            target   = tgt,
                            t        = GetTime(),
                        }
                    end
                end
            end

            -- For all other cases (slash-starting text, specific chatFrame opens, etc.)
            -- just signal the watchdog so ForwardTextToYapper can route to the overlay
            -- while it isn't shown yet. Do NOT call Show() or pre-populate
            -- _pendingOpenChatText here — the blizzard editbox Show() hook handles
            -- opening the overlay on the next frame, by which point the physical key
            -- char has already been consumed by the blizzard editbox, not ours.
            --
            -- Exception: tab clicks / chat-area clicks (chatFrame ~= nil with empty/nil text).
            -- In IM mode, a click on the chat area is a user intent to open chat on that window.
            -- In Classic mode, suppress to avoid spurious opens on tab navigation.
            -- If Yapper is already open, allow text routing via watchdog regardless.
            if chatFrame ~= nil and (text == nil or text == "") then
                if self.Overlay and self.Overlay:IsShown() then
                    -- Yapper is open: allow text routing via watchdog
                    self._openingWatchdog = true
                else
                    -- Classic mode: suppress the open on tab navigation.
                    -- IM mode is handled by the ActivateChat hook instead.
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
            else
                -- Normal Enter-to-chat or other cases
                self._openingWatchdog = true
            end
        end)
        -- NOTE: Do NOT replace ChatFrameUtil.OpenChat with a tainted wrapper.
        -- Doing so taints the arguments passed to Blizzard's secure code,
        -- causing strlenutf8 / UpdateHeader failures post-combat.
        -- The UIParent guard is already applied in EditBox:Show() and the
        -- UIParent OnHide hook in SetupOverlayScripts.
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
                -- Suppress OpenChat hook while menu responder runs to avoid
                -- triggering the watchdog/Show path when Yapper is already open
                self._suppressOpenChatHook = true
                local ok, result = pcall(orig, data, menuInputData, menuProxy)
                self._suppressOpenChatHook = nil

                -- Record/adopt the channel the menu applied to the active editbox.
                -- Apply twice (now + next frame) to cover responders that finalize
                -- chatType/target on deferred updates.
                local function CaptureMenuSelection()
                    local active = (ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
                        or (ChatFrameUtil.GetLastActiveWindow and ChatFrameUtil.GetLastActiveWindow())
                        or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
                        or self.OrigEditBox
                    if not (active and active.GetChatType) then return nil end

                    local ct = active:GetChatType()
                    if not (ct and ct ~= "") then return nil end

                    local tgt, chanName
                    if ct == "WHISPER" or ct == "BN_WHISPER" then
                        tgt = active.GetAttribute and active:GetAttribute("tellTarget")
                    elseif ct == "CHANNEL" then
                        tgt = active.GetAttribute and active:GetAttribute("channelTarget")
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

                    -- If Yapper is already open, adopt immediately while preserving text.
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

                -- Capture while override is still cleared, then restore it.
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

    -- Hook DeactivateChat so that when Yapper's overlay steals focus, Blizzard's
    -- Deactivate doesn't leave the proxy background hidden in Classic style.
    -- RestoreProxyMode still hides it on Yapper close, so the Classic lifecycle
    -- is preserved.
    if ChatFrameUtil and ChatFrameUtil.DeactivateChat and not self._deactivateChatHooked then
        hooksecurefunc(ChatFrameUtil, "DeactivateChat", function(editBox)
            if self._closing then return end
            if self.OrigEditBox == editBox and self.Overlay and self.Overlay:IsShown() then
                self:EnsureProxyBackgroundShown()
            end
        end)
        self._deactivateChatHooked = true
    end

    -- Hook ActivateChat to intercept direct activation calls (e.g., from EditBox:SetFocus)
    -- This complements the OpenChat hook and ensures Yapper catches all show paths.
    if ChatFrameUtil and ChatFrameUtil.ActivateChat and not self._activateChatHooked then
        hooksecurefunc(ChatFrameUtil, "ActivateChat", function(editBox)
            -- Only intercept if this is a chat frame editbox we're managing
            if not editBox or not editBox.GetName then return end
            local name = editBox:GetName()
            if not name or not name:match("ChatFrame%d+EditBox") then return end

            if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
                return
            end
            if UserBypassingYapper() then return end
            if self._suppressActivateChatHook then return end
            if self.Overlay and self.Overlay:IsShown() then return end

            -- In IM mode, the editbox is always shown, so our hooksecurefunc on
            -- editBox:Show never fires for a user-initiated open. Instead,
            -- ActivateChat is called, Show() fires (but IsShown() was already true
            -- so our Show hook blocked it). Handle the open here instead.
            local chatStyle = GetCVar("chatStyle")
            if chatStyle == "im" then
                self:_IMPushActive(editBox)
                C_Timer.After(0, function()
                    if self.Overlay and self.Overlay:IsShown() then return end
                    if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then return end
                    if UserBypassingYapper() then return end
                    -- Re-check focus override was cleared by ActivateChat; restore it.
                    self:UpdateFocusOverride()
                    self:Show(editBox)
                end)
                return
            end

            -- Non-IM: let the editbox Show() hook handle presentation.
            self._activateChatTriggered = true
            C_Timer.After(0, function()
                self._activateChatTriggered = nil
            end)
        end)
        self._activateChatHooked = true
    end

    -- Intercept whispers initiated OUTSIDE the unit-popup menu: chat name
    -- left-click, LFG, Professions, Communities, ItemRef.  Menu whispers are
    -- handled earlier by the UnitPopupWhisperButtonMixin override, which never
    -- calls SendTell, so the two paths do not overlap.  Fires AFTER Blizzard's
    -- editbox opens, so we snapshot its whisper state and reopen as Yapper.
    if ChatFrameUtil and ChatFrameUtil.SendTell and not self._sendTellHooked then
        hooksecurefunc(ChatFrameUtil, "SendTell", function(target, chatFrame)
            TriggerTrace("ChatFrameUtil.SendTell", string.format("target=%s frame=%s",
                tostring(target), tostring(chatFrame and chatFrame.GetName and chatFrame:GetName() or nil)))
            -- Fail fast on unusable input or lockdown: leave Blizzard's box as-is.
            if type(target) ~= "string" or target == "" then return end
            if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then return end

            local blizzBox = chatFrame and chatFrame.editBox
            if not self:IsNativeChatEditBox(blizzBox) then
                blizzBox = ChatEdit_GetActiveWindow()
            end
            if not self:IsNativeChatEditBox(blizzBox) then
                local fallback = self.OrigEditBox
                    or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
                    or _G.ChatFrame1EditBox
                blizzBox = self:IsNativeChatEditBox(fallback) and fallback or nil
            end

            -- Yapper already open: retarget in place via the shared helper
            -- (prevents SendTell reentrancy races).
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

            -- Show Yapper - Show() reads _attrCache and picks up the whisper
            -- context set by Blizzard's ParseText (SetAttribute chatType/tellTarget).
            self:Show(blizzBox or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox) or _G.ChatFrame1EditBox)

            -- Force whisper context AFTER Show() as the final authority, in case
            -- the cache was stale or a race overwrote it.
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

    -- Intercept BNet whispers started from hyperlink handlers and social UI.
    -- Mirrors SendTell handling while preserving BN_WHISPER routing.
    if ChatFrameUtil and ChatFrameUtil.SendBNetTell and not self._sendBNetTellHooked then
        hooksecurefunc(ChatFrameUtil, "SendBNetTell", function(target)
            TriggerTrace("ChatFrameUtil.SendBNetTell", string.format("target=%s", tostring(target)))
            if type(target) ~= "string" or target == "" then return end
            if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then return end

            local blizzBox = ChatEdit_GetActiveWindow()
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

    -- REMOVED: ChatFrameUtil.ReplyTell2 hook (lines 1800-1817)
    -- Originally intercepted Re-Whisper keybind to open Yapper instead of Blizzard's editbox.
    -- Functionality now handled by keybind system (REPLYTELL2 override in Keybinds.lua).
    -- Removed as part of hook reduction effort - keybind system provides primary path.
    -- Potential impact: Addons that call ReplyTell2 programmatically may not trigger Yapper overlay.

    -- Handle Native ChatEdit_InsertLink Bypass
    -- TRP3 natively calls ChatEdit_InsertLink when shift-clicking links.
    -- If Yapper is closed, this bypasses ChatFrame_OpenChat entirely,
    -- inserting text into the hidden YapperOverlayEditBox and failing SetFocus.
    if not self._insertLinkHooked then
        hooksecurefunc("ChatEdit_InsertLink", function(text)
            if CHAT_FOCUS_OVERRIDE and CHAT_FOCUS_OVERRIDE == self.OverlayEdit then
                if not (self.Overlay and self.Overlay:IsShown()) then
                    self:Show(DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
                    self.OverlayEdit:SetFocus()
                end
            end
        end)
        self._insertLinkHooked = true
    end

    -- Hook FCF_Tab_OnClick to detect tab switches while Yapper is open or about
    -- to open. Tab clicks don't trigger the editbox Show() hook, so we hook the
    -- tab UI directly. Whisper tabs use Blizzard's chatType/chatTarget; other
    -- tabs use Yapper's session-only per-tab channel memory.
    if FCF_Tab_OnClick and not self._tabClickHooked then
        local editBox = self

        -- Apply a resolved switch immediately (Yapper open) or stash it for the
        -- next open (Yapper closed).
        local function ApplyOrStashSwitch(chatFrame, switch)
            if editBox.Overlay and editBox.Overlay:IsShown() then
                -- Prime the pending switch so Show()'s priority logic picks it up,
                -- then delegate to Show() which handles re-parent, re-anchor, re-scale,
                -- proxy swap, font/height recalculation, and focus.
                -- Show()'s text guard (only sets text when coming from hidden) preserves
                -- any in-progress text the user has typed.
                editBox._pendingTabSwitch = {
                    chatType    = switch.chatType,
                    target      = switch.target,
                    channelName = switch.channelName,
                    language    = switch.language,
                    chatFrame   = chatFrame,
                    editBox     = chatFrame.editBox,
                }
                editBox:Show(chatFrame.editBox)
                YapperTable.Utils:VerbosePrint("Applied tab switch via Show(): chatType="..tostring(switch.chatType).." target="..tostring(switch.target))
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
                YapperTable.Utils:VerbosePrint("Stored pending tab switch: chatType="..tostring(switch.chatType).." target="..tostring(switch.target))
            end
        end

        hooksecurefunc("FCF_Tab_OnClick", function(tab, button)
            -- Only process left-clicks
            if button ~= "LeftButton" then return end

            local chatFrame = FCF_GetChatFrameByID(tab:GetID())
            if not chatFrame then return end
            EnsureEditBoxHooked(chatFrame.editBox)

            -- Save the outgoing frame's state before we switch context.
            -- When Yapper is OPEN, the blizzEditBox Show hook already recorded the
            -- outgoing frame (before OverlayEdit.chatFrame was swapped), so we must
            -- NOT record again here: OverlayEdit.chatFrame now points at the INCOMING
            -- frame, and recording would write the old channel onto the new frame.
            if not (editBox.Overlay and editBox.Overlay:IsShown())
                    and editBox._pendingTabSwitch and editBox._pendingTabSwitch.chatFrame then
                -- Yapper is closed: a previous tab click already stashed a switch.
                -- Flush that stash into _tabChannelMemory under the correct key
                -- before we overwrite it, so rapid tab clicks don't lose state.
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

            -- Track active window for IM mode so keybind opens on the right frame.
            if chatFrame.editBox then
                editBox:_IMPushActive(chatFrame.editBox)
            end

            -- If a close just happened, _IMPopActive already restored the right
            -- memory via _IMApplyWindowMemory. Don't overwrite it.
            if editBox._suppressTabSwitchMemory then return end

            local cfType = chatFrame.chatType
            local cfTarget = chatFrame.chatTarget
            YapperTable.Utils:VerbosePrint("Tab click: chatFrame="..(chatFrame:GetName() or "nil").." chatType="..tostring(cfType).." chatTarget="..tostring(cfTarget))

            if chatFrame.isTemporary and cfType and (cfType == "WHISPER" or cfType == "BN_WHISPER")
                and cfTarget and cfTarget ~= "" then
                -- Whisper tab: restore from Blizzard's chatTarget.
                ApplyOrStashSwitch(chatFrame, {
                    chatType = cfType,
                    target   = cfTarget,
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

    -- Hook FCF_MaximizeFrame to detect when a minimized undocked window is restored.
    -- The chat frame's OnShow fires but the editbox Show() hook doesn't (child visibility).
    -- Update _lastActiveIMEditBox so the keybind opens on the restored frame.
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

    -- Hook FCF_MinimizeFrame: close Yapper if open on this frame, then pop the history.
    -- After popping, activate the restored editbox so Blizzard shows it properly.
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
                -- Immediately deactivate so it fades to idle (not focused).
                pcall(function() ChatFrameUtil.DeactivateChat(restoredEB) end)
                editBox._suppressActivateChatHook = false
            end
        end)
        self._minimizeHooked = true
    end

    -- Hook FCF_Close (window fully closed): pop history, fall back to ChatFrame1.
    if FCF_Close and not self._closeHooked then
        local editBox = self
        hooksecurefunc("FCF_Close", function(frame)
            if not frame or not frame.editBox then return end
            -- Suppress the tab-click hook's ApplyOrStashSwitch: FCF_UnDockFrame
            -- (called inside FCF_Close) triggers FCF_Tab_OnClick on the newly
            -- selected tab, which would overwrite our restored memory.
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
