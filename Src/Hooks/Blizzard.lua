--[[
    Hooks/Blizzard.lua
    Hook into Blizzard editboxes (taint-free).
    HookBlizzardEditBox, HookAllChatFrames, and all secure hooks.
]]

local _, YapperTable = ...
local EditBox = YapperTable.EditBox
local State = YapperTable.State

-- Resolve locals from Hub.lua
local Core = YapperTable.EditBoxHooksCore
local CHATTYPE_TO_OVERRIDE_KEY = Core.CHATTYPE_TO_OVERRIDE_KEY
local ResolveChannelName = Core.ResolveChannelName
local UserBypassingYapper = Core.UserBypassingYapper
local SetUserBypassingYapper = Core.SetUserBypassingYapper
local BypassEditBox = Core.BypassEditBox
local SetBypassEditBox = Core.SetBypassEditBox

-- Re-localise Lua globals.
local type = type
local tonumber = tonumber

-- ---------------------------------------------------------------------------
-- Implicit state flags used across this module and ShowHide.lua
-- ---------------------------------------------------------------------------
-- These flags coordinate multi-frame hook interactions that cannot be
-- expressed by the formal State machine (they operate below the lifecycle
-- level, managing *how* a transition happens rather than *what* state we
-- end up in).
--
-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ CATEGORY 1: One-shot transition signals                                │
-- │ Set in one hook, consumed by Show() on the next frame.                 │
-- ├─────────────────────────────────┬───────────────────────────────────────┤
-- │ _nextShowFromBnetTransition     │ The next Show() was triggered by a    │
-- │                                 │ BNet→non-BNet channel switch. Tells   │
-- │                                 │ ShowHide to skip LastUsed sticky.     │
-- │ _pendingTabSwitch               │ Pre-computed {chatType, target, ...}  │
-- │                                 │ from a tab/window click. Show() uses  │
-- │                                 │ it as highest-priority channel source.│
-- │ _openingWatchdog                │ Text arriving NOW should route to the │
-- │                                 │ overlay via ForwardTextToYapper even  │
-- │                                 │ though it isn't visible yet (OpenChat │
-- │                                 │ fired, Show() is deferred one frame). │
-- ├─────────────────────────────────────────────────────────────────────────┤
-- │ CATEGORY 2: Suppression / re-entrancy guards                           │
-- │ Prevent hooks from firing when WE caused the triggering event.         │
-- ├─────────────────────────────────┬───────────────────────────────────────┤
-- │ _ignoreNextShow                 │ We're about to call Show() ourselves; │
-- │                                 │ skip the hooksecurefunc intercept.    │
-- │ _suppressNextShowFor            │ Name of a specific editbox whose next │
-- │                                 │ Show() is a tab-click side-effect.    │
-- │ _suppressActivateChatHook       │ We're calling ActivateChat ourselves  │
-- │                                 │ (minimize fallback); ignore the hook. │
-- │ _suppressTabSwitchMemory        │ FCF_Close triggers FCF_Tab_OnClick    │
-- │                                 │ internally — don't save channel mem.  │
-- │ _recordingTabSwitch             │ Re-entrancy guard for RecordTabChannel│
-- │ _ignoreSetText                  │ We're forwarding text; don't recurse. │
-- │ _inBlizzShowHook                │ Currently inside a Show hook handler. │
-- ├─────────────────────────────────────────────────────────────────────────┤
-- │ CATEGORY 3: Persistent references / multi-frame context                │
-- │ Track ongoing operations or IM navigation history.                     │
-- ├─────────────────────────────────┬───────────────────────────────────────┤
-- │ _bnetEditBox                    │ The editbox that was showing a BNet   │
-- │                                 │ whisper (for transition reclaim).     │
-- │ _lastActiveIMEditBox            │ Most recent IM-mode window editbox.   │
-- │ _imWindowHistory                │ Stack of previously-active IM windows.│
-- │ _activateChatTriggered          │ Brief marker that ActivateChat fired  │
-- │                                 │ (consumed next frame by Show hook).   │
-- │ _attrCache[editbox]             │ Per-editbox attribute mirror. Captures│
-- │                                 │ chatType/tellTarget/channelTarget as  │
-- │                                 │ they arrive via SetAttribute.         │
-- └─────────────────────────────────┴───────────────────────────────────────┘

-- ---------------------------------------------------------------------------
-- Hook into Blizzard editboxes (taint-free)
-- ---------------------------------------------------------------------------

--- In proxy mode the native editbox is the visible background. A channel link
--- or chat-menu selection activates that editbox, and when focus returns to the
--- overlay Blizzard deactivates it on empty-text focus loss — which, in classic
--- chat style, also Hides it, wiping the background. Re-show it next frame so
--- the proxy background survives. No-op outside proxy mode.
function EditBox:EnsureProxyBackgroundShown()
    local cfg = YapperTable.Config and YapperTable.Config.EditBox
    local isProxy = cfg and cfg.UseBlizzardSkinProxy == true and cfg.UseLegacyCloneProxy ~= true
    if not isProxy then return end
    local eb = self.OrigEditBox
    if not eb or not eb.Show then return end
    C_Timer.After(0, function()
        -- Don't resurrect the background if the user just closed Yapper —
        -- Classic style relies on the natural Deactivate/Hide path then.
        if self._closing then return end
        if self.Overlay and self.Overlay:IsShown() and eb and not eb:IsShown() then
            pcall(function()
                eb:Show()
                if eb.SetAlpha then eb:SetAlpha(1.0) end
            end)
        end
        -- In proxy mode the Blizzard editbox is only a visual shell under Yapper.
        -- Keep its text empty so deferred OpenChat/ParseText writes never show underneath.
        if self.Overlay and self.Overlay:IsShown() and eb and eb.GetText and eb.SetText then
            local blizzText = eb:GetText() or ""
            if blizzText ~= "" then
                pcall(function() eb:SetText("") end)
            end
        end
        if self.EnsureProxyHeaderHidden then
            self:EnsureProxyHeaderHidden(eb)
        end
    end)
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
                        local curText = targetBox:GetText() or ""
                        local nextText = preRemainder or ""
                        local keepExistingText = (targetBox == self.OverlayEdit)
                            and self.Overlay and self.Overlay:IsShown()
                            and curText ~= "" and nextText == ""
                        self._ignoreSetText = nil
                        self.ChatType = "WHISPER"
                        self.Target   = preTarget
                        self._ignoreSetText = true
                        if not keepExistingText and nextText ~= curText then
                            targetBox:SetText(nextText)
                        end
                        self._ignoreSetText = nil
                        eb:SetText("")
                        self:RefreshLabel()
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
                        local curText = targetBox:GetText() or ""
                        local nextText = chanRemainder or ""
                        local keepExistingText = (targetBox == self.OverlayEdit)
                            and self.Overlay and self.Overlay:IsShown()
                            and curText ~= "" and nextText == ""
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
                        if not keepExistingText and nextText ~= curText then
                            targetBox:SetText(nextText)
                        end
                        self._ignoreSetText = nil
                        eb:SetText("")
                        self:RefreshLabel()
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
function EditBox:HookAllChatFrames()
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
            self:HookBlizzardEditBox(eb)
        end
    end

    if YapperTable.Utils then
        YapperTable.Utils:VerbosePrint("EditBox overlays hooked for " .. (NUM_CHAT_WINDOWS or 10) .. " chat frames.")
    end

    -- Capture the raw OpenChat argument so we can preserve leading slashes
    -- that ParseText/OnUpdate may strip before Blizzard's editbox text is set.
    if ChatFrameUtil and ChatFrameUtil.OpenChat and not self._openChatHooked then
        hooksecurefunc(ChatFrameUtil, "OpenChat", function(text, chatFrame, ...)
            if self._suppressOpenChatHook then
                self._suppressOpenChatHook = nil
                return
            end
            if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
                -- Fix focus override getting stuck if lockdown started while chat was closed.
                self:UpdateFocusOverride()
                if self.OverlayEdit and self.OverlayEdit:HasFocus() then
                    self.OverlayEdit:ClearFocus()
                    self.OverlayEdit:Hide()
                    local eb = self.OrigEditBox or (chatFrame and chatFrame.editBox) or _G.ChatFrame1EditBox
                    C_Timer.After(0, function()
                        if eb then
                            if eb.Show then eb:Show() end
                            if eb.SetFocus then eb:SetFocus() end
                        end
                    end)
                end
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

    -- Hook SendTell to intercept right-click whispers on player frames
    -- This fires AFTER Blizzard's editbox opens, so we close it and open Yapper instead
    if ChatFrameUtil and ChatFrameUtil.SendTell and not self._sendTellHooked then
        hooksecurefunc(ChatFrameUtil, "SendTell", function(target, chatFrame)
            if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
                -- In lockdown: let Blizzard handle it
                return
            end

            local blizzBox = chatFrame and chatFrame.editBox
            if not blizzBox then
                blizzBox = ChatEdit_GetActiveWindow()
            end

            -- Capture any text already typed (user was fast)
            local existingText = ""
            if blizzBox then
                existingText = blizzBox:GetText() or ""
            end

            -- Snapshot the attribute cache BEFORE hiding.
            -- Hide() triggers Deactivate → ResetChatTypeToSticky → SetChatType("SAY"),
            -- which overwrites the _attrCache whisper info that Show() depends on.
            local savedCache
            if blizzBox then
                savedCache = self._attrCache[blizzBox]
                -- Deep-copy so the SetAttribute hook doesn't corrupt our snapshot
                if savedCache then
                    savedCache = { chatType = savedCache.chatType, tellTarget = savedCache.tellTarget,
                                   channelTarget = savedCache.channelTarget, language = savedCache.language }
                end
            end

            -- Close Blizzard's editbox so proxy mode can re-show it cleanly.
            if blizzBox then
                blizzBox:Hide()
                blizzBox:SetText("")
            end

            -- Restore the cache that Hide()/Deactivate poisoned.
            if blizzBox and savedCache then
                self._attrCache[blizzBox] = savedCache
            end

            -- Show Yapper — Show() reads _attrCache and picks up the whisper context
            -- set by Blizzard's ParseText (SetAttribute "chatType"/"tellTarget").
            self:Show(blizzBox)

            -- Force whisper context AFTER Show() as the final authority,
            -- in case the cache was stale or overwritten by a race.
            self.ChatType = "WHISPER"
            self.Target = target

            if existingText ~= "" and self.OverlayEdit and self.OverlayEdit.SetText then
                self.OverlayEdit:SetText(existingText)
            end

            self:RefreshLabel()
        end)
        self._sendTellHooked = true
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

            if cfType and (cfType == "WHISPER" or cfType == "BN_WHISPER")
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
function EditBox:_IMPushActive(eb)
    if not eb then return end
    local history = self._imWindowHistory
    if history[#history] ~= eb then
        -- Remove any existing entry for this editbox further down the stack
        -- to keep it clean (same window shouldn't appear twice).
        for i = #history, 1, -1 do
            if history[i] == eb then
                table.remove(history, i)
                break
            end
        end
        history[#history + 1] = eb
    end
    self._lastActiveIMEditBox = eb
end

--- Restore the remembered channel state for a chat frame from _tabChannelMemory.
--- If Yapper is open the switch is applied immediately; otherwise it is stashed
--- in _pendingTabSwitch to be consumed on the next open.
function EditBox:_IMApplyWindowMemory(chatFrame)
    if not chatFrame then return end
    local cfType   = chatFrame.chatType
    local cfTarget = chatFrame.chatTarget
    -- Whisper frames: use Blizzard's live chatTarget.
    if cfType and (cfType == "WHISPER" or cfType == "BN_WHISPER")
        and cfTarget and cfTarget ~= "" then
        self._pendingTabSwitch = {
            chatType  = cfType,
            target    = cfTarget,
            chatFrame = chatFrame,
            editBox   = chatFrame.editBox,
        }
        return
    end
    -- Non-whisper: restore from session memory.
    local key = chatFrame.GetName and chatFrame:GetName()
    local mem = key and self._tabChannelMemory and self._tabChannelMemory[key]
    if mem and mem.chatType then
        self._pendingTabSwitch = {
            chatType    = mem.chatType,
            target      = mem.target,
            channelName = mem.channelName,
            language    = mem.language,
            chatFrame   = chatFrame,
            editBox     = chatFrame.editBox,
        }
    end
end

--- Pop the given editbox off the IM active window history stack and restore
--- the previous entry as the active window.
function EditBox:_IMPopActive(eb)
    if not eb then return end
    local history = self._imWindowHistory
    -- Remove this editbox from the stack (wherever it is).
    for i = #history, 1, -1 do
        if history[i] == eb then
            table.remove(history, i)
            break
        end
    end
    -- Restore the new top as active (fall back to ChatFrame1EditBox if empty).
    local top = history[#history]
        or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
        or _G["ChatFrame1EditBox"]
    self._lastActiveIMEditBox = top
end
