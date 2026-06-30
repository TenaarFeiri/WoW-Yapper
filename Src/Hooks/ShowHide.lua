--[[
    Hooks/ShowHide.lua
    Show/Hide lifecycle, Blizzard handoff, and live config application.
]]

local _, YapperTable = ...
local EditBox = YapperTable.EditBox
local State = YapperTable.State
local Utils = YapperTable.Utils

-- Resolve locals from Hub.lua
local Core = YapperTable.EditBoxHooksCore
local ResolveChannelName = Core.ResolveChannelName
local IsWhisperSlashPrefill = Core.IsWhisperSlashPrefill
local ParseWhisperSlash = Core.ParseWhisperSlash
local RefreshOverlayVisuals = Core.RefreshOverlayVisuals

-- Re-localise Lua globals.
local type       = type
local tostring   = tostring
local tonumber   = tonumber
local math_max   = math.max
local math_min   = math.min

local function FireAPIEvent(event, ...)
    local api = YapperTable and YapperTable.API
    if type(api) == "table" and type(api.Fire) == "function" then
        api:Fire(event, ...)
    end
end

-- ---------------------------------------------------------------------------
-- Positioning
-- ---------------------------------------------------------------------------

--- Reparent and reposition the overlay using absolute coordinates in the
--- current chat parent. This is used on initial show and again when the
--- fullscreen-aware parent changes.
---@param overlay     Frame  Yapper's overlay container.
---@param origEditBox Frame  The Blizzard editbox whose rect we mirror.
---@param useTop      boolean? If true, anchor the overlay's TOPLEFT to the
---                     original's top; otherwise anchor BOTTOMLEFT.
local function RepositionOverlay(overlay, origEditBox, useTop)
    if not overlay or not origEditBox then return end
    local chatParent = YapperTable.Utils:GetChatParent()
    overlay:SetParent(chatParent)
    overlay:ClearAllPoints()

    local parentScale = chatParent:GetEffectiveScale()
    if parentScale == 0 then parentScale = UIParent:GetEffectiveScale() end
    local origScale = origEditBox:GetEffectiveScale()
    if origScale == 0 then origScale = 1 end
    local scale = origScale / parentScale
    overlay:SetScale(scale)

    local chatParentLeft   = chatParent:GetLeft() or 0
    local chatParentBottom = chatParent:GetBottom() or 0
    local origLeft = origEditBox:GetLeft() or 0
    local origY
    if useTop then
        origY = origEditBox:GetTop() or 0
    else
        origY = origEditBox:GetBottom() or 0
    end

    local offsetX = origLeft - (chatParentLeft * parentScale / origScale)
    local offsetY = origY - (chatParentBottom * parentScale / origScale)

    local anchorPoint = useTop and "TOPLEFT" or "BOTTOMLEFT"
    overlay:SetPoint(anchorPoint, chatParent, "BOTTOMLEFT", offsetX, offsetY)
end

-- ---------------------------------------------------------------------------
-- Show / Hide
-- ---------------------------------------------------------------------------

--- Present the overlay in place of a Blizzard editbox.
--- @param origEditBox table  The Blizzard ChatFrameNEditBox we're replacing.
function EditBox:Show(origEditBox)
    -- Don't want to open the overlay while UI is hidden, *unless* we're
    -- inside the housing editor; that mode purposely hides UIParent but we
    -- still want the chat overlay available.
    if not UIParent:IsShown() then
        if C_HouseEditor and C_HouseEditor.IsHouseEditorActive
            and C_HouseEditor.IsHouseEditorActive() then
            -- continue, fullscreen-aware parenting will keep us visible
        else
            if EditBox.Overlay and EditBox.Overlay:IsShown() then
                EditBox:Hide()
            end
            return
        end
    end

    -- Suppress the single-line overlay while the multiline editor is open.
    -- The game will try to re-open the overlay on every keypress that
    -- triggers a chat-open event; this guard stops that.
    -- If the multiline EditBox has lost focus (e.g. user clicked elsewhere),
    -- reclaim it here so Enter reliably activates the expanded editor.
    local ml = YapperTable and YapperTable.Multiline
    if ml and ml.Frame and ml.Frame:IsShown() then
        if origEditBox and origEditBox.Deactivate then
            origEditBox:Deactivate()
        end
        if ml.EditBox and ml.EditBox.SetFocus then
            local mlb = ml.EditBox
            C_Timer.After(0, function()
                -- If we are refocusing, ensure state is set back to MULTILINE
                if State and not State:IsMultiline() then
                    YapperAPI:SetState("MULTILINE")
                end
                if mlb and mlb.SetFocus then
                    mlb:SetFocus()
                end
            end)
        end
        return
    end
    self:CreateOverlay()

    -- Apply pending tab switch info if available (from FCF_Tab_OnClick hook)
    local pendingTabSwitch = self._pendingTabSwitch
    if pendingTabSwitch then
        self._pendingTabSwitch = nil
        YapperTable.Utils:VerbosePrint("Applying pending tab switch: chatType="..tostring(pendingTabSwitch.chatType).." target="..tostring(pendingTabSwitch.target))
        if pendingTabSwitch.editBox and pendingTabSwitch.editBox ~= origEditBox then
            origEditBox = pendingTabSwitch.editBox
        end
    end

    local openedFromBnetTransition   = self._nextShowFromBnetTransition == true
    self._nextShowFromBnetTransition = false
    self._openedFromBnetTransition   = openedFromBnetTransition

    self.OrigEditBox                 = origEditBox

    -- Satisfy Blizzard code that expects the editbox to belong to a specific chatFrame.
    if origEditBox and origEditBox.chatFrame then
        self.OverlayEdit.chatFrame = origEditBox.chatFrame
        if self.ChannelLabel then
            self.ChannelLabel.chatFrame = origEditBox.chatFrame
        end
    end

    -- Determine chat mode and target
    -- Two paths exist in Blizzard's code:
    --   • BNet whisper: SetAttribute fires BEFORE Show (cache is populated)
    --   • WoW friend whisper: SendTellWithMessage → OpenChat → Show fires
    --     first, then OnUpdate defers SetText + ParseText which sets
    --     attributes one frame later.
    -- For the deferred case our SetAttribute hook performs a live update
    -- of the overlay when the attributes finally arrive (see
    -- HookBlizzardEditBox).  Here we just read whatever is available now.
    --
    -- Priority:
    --   1. SetAttribute cache (chatType, tellTarget, channelTarget)
    --      Only the cache is used — raw GetAttribute on the Blizzard box
    --      returns stale values from previous opens (e.g. a right-click
    --      whisper target that persists across show/hide cycles).
    --   2. LastUsed sticky
    --   3. "SAY"

    local cache     = self._attrCache[origEditBox] or {}
    local blizzType = cache.chatType
    local blizzTell = cache.tellTarget
    local blizzChan = cache.channelTarget
    local blizzLang = cache.language or (origEditBox and origEditBox.languageID)
    if not blizzLang and origEditBox and type(origEditBox.GetLanguageID) == "function" then
        blizzLang = origEditBox:GetLanguageID()
    end
    -- Normalise language to ensure we have a valid language ID
    if blizzLang and type(blizzLang) == "string" then
        blizzLang = YapperTable.Core:GetCharacterLanguage(blizzLang)
    end
    local blizzText = origEditBox and origEditBox.GetText and origEditBox:GetText()

    -- One-shot BN guard expiry: if we open normally a couple times without
    -- consuming this flag, treat it as stale and clear it.
    if self._ignoreNextBnetLiveUpdateFor then
        if blizzType ~= "BN_WHISPER" then
            self._ignoreNextBnetLiveUpdateOpenCount = (self._ignoreNextBnetLiveUpdateOpenCount or 0) + 1
            if self._ignoreNextBnetLiveUpdateOpenCount >= 2 then
                self._ignoreNextBnetLiveUpdateFor = nil
                self._ignoreNextBnetLiveUpdateOpenCount = 0
            end
        else
            self._ignoreNextBnetLiveUpdateOpenCount = 0
        end
    end

    self._attrCache[origEditBox] = {}

    local explicitChannel = self._explicitChannel
    if explicitChannel then
        self._explicitChannel = nil
        if not explicitChannel.chatType
            or (GetTime() - (explicitChannel.t or 0)) > 1 then
            explicitChannel = nil
        end
    end

    -- Did Blizzard open with a specific target?
    local blizzHasTarget         = ((blizzType == "WHISPER" or blizzType == "BN_WHISPER")
            and blizzTell and blizzTell ~= "")
        or (blizzType == "CHANNEL" and blizzChan and blizzChan ~= "")

    local incomingWhisperAffinity = self._incomingWhisperAffinity
    if incomingWhisperAffinity and incomingWhisperAffinity.t and GetTime
        and (GetTime() - incomingWhisperAffinity.t) > 5 then
        incomingWhisperAffinity = nil
        self._incomingWhisperAffinity = nil
    end

    local frameChatType, frameChatTarget, frameChannelName
    if origEditBox then
        local liveFrame = origEditBox.chatFrame
            or (origEditBox.GetParent and origEditBox:GetParent())
        if liveFrame then
            local liveType = liveFrame.chatType
            -- Only trust whisper frame context from true temporary whisper tabs.
            -- Non-temporary frames can momentarily report WHISPER after SendTell,
            -- which would incorrectly override tab/channel selection once.
            if (liveType == "WHISPER" or liveType == "BN_WHISPER")
                and not liveFrame.isTemporary then
                liveType = nil
            end
            frameChatType = liveType
            frameChatTarget = liveFrame.chatTarget
            if frameChatType == "CHANNEL" and frameChatTarget then
                frameChannelName = ResolveChannelName(tonumber(frameChatTarget))
            end
        end
    end

    -- Fallback for IM/undocked whisper windows: if attribute cache missed the
    -- target this frame, prefer the chatFrame's live chatType/chatTarget over
    -- LastUsed so active DM tabs don't collapse back to SAY.
    if not blizzHasTarget and origEditBox then
        local liveFrame = origEditBox.chatFrame
            or (origEditBox.GetParent and origEditBox:GetParent())
        if liveFrame then
            local liveType = liveFrame.chatType
            local liveTarget = liveFrame.chatTarget
            if (liveType == "WHISPER" or liveType == "BN_WHISPER")
                and liveFrame.isTemporary
                and liveTarget and liveTarget ~= "" then
                blizzType = liveType
                blizzTell = liveTarget
                blizzHasTarget = true
            elseif liveType == "CHANNEL" and liveTarget and liveTarget ~= "" then
                blizzType = "CHANNEL"
                blizzChan = liveTarget
                blizzHasTarget = true
            end
        end
    end

    -- Priority for picking the channel on open:
    --   0. Re-Whisper keybind — primed by our ReplyTell2 hook immediately before
    --      this Show fires. Consumed once and cleared.
    --   1. Blizzard explicitly provided a whisper/channel target (reply key,
    --      name-click, Contacts list, etc.) — always honour it.
    --   1b. Explicit channel selection (channel link / chat menu / typed slash) —
    --      overrides the LastUsed sticky for this open only.
    --   2. Lockdown draft — restore the channel the user was on mid-combat.
    --   3. LastUsed sticky — remember the last channel the user chose.
    --   4. Blizzard's editbox type (no specific target) or SAY as fallback.
    -- REMOVED: Pending re-whisper priority (was #1) - ReplyTell2 hook removed
    local lockSavedDraft = type(self._lockdown) == "table" and self._lockdown.savedDraft == true
    local policy = YapperTable.ChannelPolicy
    local resolvedSelection
    if policy and type(policy.ResolveOpenSelection) == "function" then
        resolvedSelection = policy:ResolveOpenSelection({
            pendingTabSwitch = pendingTabSwitch,
            explicitChannel = explicitChannel,
            lockSavedDraft = lockSavedDraft,
            blizzHasTarget = blizzHasTarget,
            blizzType = blizzType,
            blizzTell = blizzTell,
            blizzChan = blizzChan,
            blizzLang = blizzLang,
            lastUsed = self.LastUsed,
            frameChatType = frameChatType,
            frameChatTarget = frameChatTarget,
            frameChannelName = frameChannelName,
            incomingWhisperAffinity = incomingWhisperAffinity,
            now = GetTime and GetTime() or nil,
            existingSelection = {
                chatType = self.ChatType,
                target = self.Target,
                language = self.Language,
                channelName = self.ChannelName,
            },
        })
    end

    if incomingWhisperAffinity and resolvedSelection then
        local affinityTarget = incomingWhisperAffinity.target
        local isResolvedWhisper = (resolvedSelection.chatType == "WHISPER"
            or resolvedSelection.chatType == "BN_WHISPER")
        if isResolvedWhisper and affinityTarget and resolvedSelection.target == affinityTarget then
            self._incomingWhisperAffinity = nil
        end
    end

    if resolvedSelection then
        self.ChatType = resolvedSelection.chatType
        self.Language = resolvedSelection.language
        self.Target = resolvedSelection.target
        self.ChannelName = resolvedSelection.channelName
    elseif pendingTabSwitch and pendingTabSwitch.chatType then
        -- Fallback mirrors the existing priority path.
        self.ChatType = pendingTabSwitch.chatType
        self.Language = pendingTabSwitch.language
            or blizzLang or (self.LastUsed and self.LastUsed.language) or nil
        self.Target = pendingTabSwitch.target
        self.ChannelName = pendingTabSwitch.channelName
    else
        self.ChatType = (self.LastUsed and self.LastUsed.chatType)
            or blizzType
            or "SAY"
        self.Language = blizzLang
            or (self.LastUsed and self.LastUsed.language)
            or nil
        self.Target = (self.LastUsed and self.LastUsed.target)
            or blizzTell or blizzChan
            or nil
    end

    -- Safety net: non-target chat types must not carry stale whisper/channel targets.
    if self.ChatType ~= "WHISPER" and self.ChatType ~= "BN_WHISPER" and self.ChatType ~= "CHANNEL" then
        self.Target = nil
        self.ChannelName = nil
    end

    -- Smartly switch from Party/Raid to Instance if the Home group is missing.
    local resolvedCT = self:GetResolvedChatType(self.ChatType)
    if resolvedCT ~= self.ChatType then
        self.ChatType = resolvedCT
        self.Target   = nil
    end

    -- Safeguard: Never open in a whisper state without a target.
    if (self.ChatType == "WHISPER" or self.ChatType == "BN_WHISPER") and (not self.Target or self.Target == "") then
        self.ChatType = "SAY"
        self.Target   = nil
    end

    -- Validate channel availability (e.g. you left the party/raid/instance).
    if not self:IsChatTypeAvailable(self.ChatType) then
        self.ChatType = "SAY"
        self.Target   = nil
    end

    -- Validate channel (might have been removed since last session).
    if self.ChatType == "CHANNEL" and self.Target then
        local num = tonumber(self.Target)
        if num then
            local resolved = ResolveChannelName(num)
            if resolved then
                self.ChannelName = resolved
            else
                -- Channel gone — fall back to SAY.
                self.ChatType    = "SAY"
                self.Target      = nil
                self.ChannelName = nil
            end
        end
    end

    -- Position & size
    -- Position the overlay with absolute coordinates in the parent's space
    -- rather than anchoring directly to the original editbox. This mirrors
    -- the multiline editor's approach and avoids coordinate-space drift when
    -- ChatFrame1 or the chat editbox has a non-1 effective scale (e.g., 4K
    -- UI scaling, chat-frame addons).
    local overlay = self.Overlay
    local cfg = YapperTable.Config.EditBox or {}
    local wasShown = overlay:IsShown()
    local origWidth  = origEditBox:GetWidth() or 32
    local origHeight = origEditBox:GetHeight() or 32

    -- Track whether the overlay is currently anchored from its top edge
    -- (tall-font mode) so fullscreen-aware parent changes can re-anchor
    -- it correctly.
    local anchorTop = false
    overlay._yapperReposition = function()
        if self.Overlay and self.OrigEditBox then
            RepositionOverlay(self.Overlay, self.OrigEditBox, anchorTop)
        end
    end

    RepositionOverlay(overlay, origEditBox)
    overlay:SetWidth(origWidth)
    overlay:SetHeight(origHeight)
    overlay:Show()  -- ensure visible (CEBE may have hidden it on close)

    -- Font
    -- Config overrides Blizzard's font; otherwise inherit.
    local cfgFace  = cfg.FontFace
    local cfgSize  = cfg.FontSize or 0
    local cfgFlags = cfg.FontFlags or ""

    if cfgFace or cfgSize > 0 then
        -- Blend config values with Blizzard defaults.
        local baseFace, baseSize, baseFlags = origEditBox:GetFont()
        local face                          = cfgFace or baseFace
        local size                          = cfgSize > 0 and cfgSize or baseSize
        local flags                         = (cfgFlags ~= "") and cfgFlags or baseFlags
        self.OverlayEdit:SetFont(face, size, flags)
    else
        -- Inherit Blizzard's font exactly.
        local face, size, flags = origEditBox:GetFont()
        self.OverlayEdit:SetFont(face, size, flags)
    end

    -- Vertical scaling
    -- The overlay must be tall enough for the chosen font.
    local _, activeSize = self.OverlayEdit:GetFont()
    activeSize          = activeSize or 14
    local fontPad       = cfg.FontPad or 8
    local fontNeeded    = activeSize + fontPad
    local blizzH        = origEditBox:GetHeight() or 32
    local minH          = (cfg.MinHeight and cfg.MinHeight > 0) and cfg.MinHeight or blizzH
    local finalH        = math_max(minH, fontNeeded)
    if finalH > blizzH then
        overlay:ClearAllPoints()
        anchorTop = true
        RepositionOverlay(overlay, origEditBox, true)
        overlay:SetWidth(origWidth)
        overlay:SetHeight(finalH)
    end

    -- Stay on top of the original.
    local origLevel = origEditBox:GetFrameLevel() or 0
    overlay:SetFrameLevel(origLevel + 5)

    -- Proxy mode handling
    if cfg.UseBlizzardSkinProxy == true and cfg.UseLegacyCloneProxy ~= true then
        -- Proxy mode: keep the original Blizzard editbox visible underneath.
        pcall(function() self:ApplyProxyMode(origEditBox) end)
    else
        pcall(function()
            -- Legacy: clone Blizzard's textures onto Yapper's overlay.
            self:AttachBlizzardSkinProxy(origEditBox, finalH)
        end)

        -- Hide Blizzard's editbox when Yapper is open and not in proxy mode
        if cfg.HideBlizzardEditbox == true then
            if origEditBox and origEditBox.Hide then
                pcall(function() origEditBox:Hide() end)
            end
        end
    end

    -- Visual refresh.
    do
        local activeThemeOnShow = YapperTable.Theme and YapperTable.Theme:GetTheme()
        local borderOnShow      = activeThemeOnShow and activeThemeOnShow.border == true
        local padOnShow         = (borderOnShow and overlay.BorderPad) or 0
        if YapperTable.EditBoxHooksCore and YapperTable.EditBoxHooksCore.RefreshOverlayVisuals then
            YapperTable.EditBoxHooksCore.RefreshOverlayVisuals(self, cfg, borderOnShow, padOnShow)
        end
    end

    -- Text
    -- Restore draft if available, otherwise use Blizzard's text.
    local draftText
    local draftMultiline = false
    if (lockSavedDraft or not blizzHasTarget) and YapperTable.History then
        local text, draftType, draftTarget, isML = YapperTable.History:GetDraft()
        if text then
            draftText = text
            draftMultiline = isML or false
            if draftType then self.ChatType = draftType end
            if draftTarget then self.Target = draftTarget end
            YapperTable.History:MarkDirty(false)
            -- Lockdown drafts are one-shot recovery payloads.
            if lockSavedDraft and type(self._lockdown) == "table" then
                self._lockdown.savedDraft = false
            end
            YapperTable.Utils:VerbosePrint("Draft recovered: " ..
                #text .. " chars" .. (draftMultiline and " (multiline)" or "") .. ".")
        end
    end

    -- Carry over any text Blizzard pre-populated on the native editbox
    -- (e.g. chat links, whisper prefills from friend-list clicks).
    local externalText
    if blizzText and blizzText ~= "" then
        if not (blizzHasTarget and IsWhisperSlashPrefill(blizzText)) then
            local preTarget, preRemainder = ParseWhisperSlash(blizzText)
            if preTarget and not blizzHasTarget then
                self.ChatType = "WHISPER"
                self.Target = preTarget
                externalText = preRemainder
            else
                externalText = blizzText
            end
        end
    end

    -- Combine draft, existing overlay text, and external text
    local existingText = self.OverlayEdit:GetText() or ""
    local finalText = draftText or ""
    if existingText ~= "" then
        if not draftText then
            finalText = existingText
        elseif not string.find(draftText, existingText, 1, true) then
            finalText = existingText .. draftText
        end
    end

    if externalText and externalText ~= "" then
        if not draftText then
            finalText = externalText
        elseif not string.find(finalText, externalText, 1, true) then
            finalText = finalText .. externalText
        end
    end

    -- Clear the watchdog now that we've grabbed everything
    self._openingWatchdog = false

    -- Set the text: restore a draft if found, otherwise clear the box
    -- ONLY if we are coming from a hidden state. This prevents wipes
    -- when refocusing an already-visible overlay.
    if not wasShown then
        self.OverlayEdit:SetText(finalText)
    elseif draftText and existingText == "" then
        self.OverlayEdit:SetText(finalText)
    end

    if finalText then
        self.OverlayEdit:SetCursorPosition(#finalText)
    end
    self:RefreshLabel()

    -- If the recovered draft came from the multiline editor, transition
    -- directly into multiline so hard newlines are preserved.
    if draftMultiline and draftText and YapperTable.Multiline
        and type(YapperTable.Multiline.Enter) == "function" then
        YapperTable.Multiline:Enter(
            draftText, self.ChatType, nil, self.Target)
    end

    -- Clear Blizzard's backing editbox to avoid stale carryover on next open.
    if origEditBox and origEditBox.SetText then
        origEditBox:SetText("")
    end

    -- Clear stale bypass state so subsequent Shows don't short-circuit.
    if YapperTable.EditBoxHooksCore and YapperTable.EditBoxHooksCore.BypassEditBox then
        if YapperTable.EditBoxHooksCore.BypassEditBox() then
            YapperTable.EditBoxHooksCore.SetBypassEditBox(nil)
        end
    end

    -- Focus the overlay. If an external addon (e.g. Chattynator) aggressively
    -- steals focus back via DeactivateChat hooks, reclaim it on the next frame.
    if self.OverlayEdit and type(self.OverlayEdit.SetFocus) == "function" then
        self.OverlayEdit:SetFocus()
    end
    if State and not State:IsMultiline() then
        YapperAPI:SetState("EDITING")
    end

    -- API callback: notify external addons that editbox is shown.
    FireAPIEvent("EDITBOX_SHOW", self.ChatType, self.Target)

    local overlay = self.Overlay
    local overlayEdit = self.OverlayEdit
    local after = C_Timer and C_Timer.After
    if after then
        after(0, function()
            if overlay and overlay:IsShown()
                and overlayEdit and type(overlayEdit.HasFocus) == "function"
                and not overlayEdit:HasFocus() then
                if type(overlayEdit.SetFocus) == "function" then
                    overlayEdit:SetFocus()
                end
            end
        end)
    end

end

function EditBox:Hide(isHandoff)
    local prevOrig = self.OrigEditBox
    self._overlayUnfocused = false

    -- Proxy mode: restore the original Blizzard editbox to its
    -- pre-Yapper state (mouse, header visibility, shown/hidden).
    -- Safe to call when proxy mode wasn't active.
    if self.RestoreProxyMode then
        pcall(function() self:RestoreProxyMode() end)
    end

    -- Deactivate the Blizzard editbox so it clears text and stops accepting input.
    -- In IM mode this fades it out; in Classic mode this also hides it.
    if prevOrig and ChatFrameUtil and ChatFrameUtil.DeactivateChat then
        pcall(function() ChatFrameUtil.DeactivateChat(prevOrig) end)
    end

    -- NOTE: DetachBlizzardSkinProxy() is intentionally NOT called here.
    -- Proxy textures are children of the overlay frame; they hide automatically
    -- when the overlay hides and reappear when it shows again.  Calling Detach
    -- on every close would accumulate dead texture objects because WoW has no
    -- garbage collection for frame children.
    if self.Overlay then
        self.Overlay:Hide()
    end

    if self.GhostFS then
        self.GhostFS:Hide()
    end

    -- Save LastUsed for stickiness across show/hide.
    -- PersistLastUsed applies StickyChannel/StickyGroupChannel rules while
    -- still preserving per-tab channel memory via RecordTabChannel.
    if self.PersistLastUsed then
        self:PersistLastUsed()
    end

    -- The external-whisper episode (unit-frame right-click) ends on close.
    -- NOTE: self._externalWhisperTarget is intentionally NOT cleared here.
    -- PersistLastUsed (above) already consumed it, but the draft-save block
    -- below also needs it so an external whisper's channel binding isn't
    -- persisted into a draft. It is cleared after that block instead.

    -- Undo the chat attributes SyncAttributesToBlizzard pushed onto the Blizzard
    -- proxy editbox. Classic-style Deactivate() skips ResetChatTypeToSticky, so a
    -- whisper context would otherwise stay stuck on the live proxy frame and bleed
    -- into the next open. Skip during handoff (we're intentionally restoring the
    -- Blizzard box) and during lockdown (SetAttribute is unsafe in combat).
    if not isHandoff
        and self.ResetSyncedAttributes
        and not (YapperTable and YapperTable.Utils and YapperTable.Utils:IsChatOrCombatLockdown()) then
        pcall(function() self:ResetSyncedAttributes() end)
    end

    -- Auto-save draft on clean close (no text, or user pressed Escape).
    local text = self.OverlayEdit and self.OverlayEdit:GetText() or ""
    local trimmed = text:match("^%s*(.-)%s*$") or ""

    local history = YapperTable and YapperTable.History
    if not self._closedClean and trimmed ~= ""
        and type(history) == "table"
        and type(history.SaveDraft) == "function"
        and type(history.MarkDirty) == "function" then
        history:SaveDraft(self.OverlayEdit)
        history:MarkDirty(true)
    end

    -- The external-whisper episode (unit-frame right-click) ends on close.
    -- Cleared after the draft-save block so the draft gate above can see it.
    self._externalWhisperTarget = nil

    -- Clear lockdown draft flag on normal clean closes.
    -- Handoff closes should preserve the flag so next open can recover.
    if self._closedClean and not isHandoff and type(self._lockdown) == "table" then
        self._lockdown.savedDraft = nil
    end

    self._closedClean = false

    -- If we're in handoff mode, restore the draft to Blizzard's editbox.
    if isHandoff and prevOrig and type(prevOrig.SetText) == "function" then
        local draft = ""
        if type(history) == "table" and type(history.LoadDraft) == "function" then
            draft = history:LoadDraft() or ""
        end
        prevOrig:SetText(draft)
        if type(prevOrig.SetFocus) == "function" then
            prevOrig:SetFocus()
        end
    end

    -- EDITBOX_HIDE callback: notify external addons.
    FireAPIEvent("EDITBOX_HIDE")
end

--- Save draft, close overlay, and notify during lockdown.
--- @param silent boolean: if true, skip the user message
--- @param bypassOpen boolean: if true, skip opening Blizzard's editbox with the draft (default true)
--- @param isMultiline boolean: if true, draft was already saved by multiline mode, skip saving again
function EditBox:HandoffToBlizzard(silent, bypassOpen, isMultiline)
    -- Default bypassOpen to true: don't auto-open Blizzard's editbox during lockdown.
    -- The user can press Enter after lockdown ends to resume typing.
    if bypassOpen == nil then
        bypassOpen = true
    end
    if not self.Overlay or not self.Overlay:IsShown() then
        return
    end
    local text = self.OverlayEdit and self.OverlayEdit:GetText() or ""
    local trimmed = text:match("^%s*(.-)%s*$") or ""

    YapperAPI:SetState("LOCKDOWN")
    self:UpdateFocusOverride()

    -- Centralised lockdown cleanup (cancels timers/tickers).
    self:ClearLockdownState()

    -- Save as dirty draft for recovery on next open.
    -- Skip if isMultiline=true (draft already saved by Multiline:Exit with full multiline text).
    local history = YapperTable and YapperTable.History
    local lockdown = type(self._lockdown) == "table" and self._lockdown or nil
    if text ~= "" and type(history) == "table" and not isMultiline
        and type(history.SaveDraft) == "function"
        and type(history.MarkDirty) == "function" then
        history:SaveDraft(self.OverlayEdit)
        history:MarkDirty(true)
        -- Mark that this draft was saved due to lockdown so callers
        -- can decide whether to restore it to Blizzard's editbox.
        if lockdown then
            lockdown.savedDraft = true
        end
    elseif isMultiline and lockdown then
        -- Draft was already saved by multiline mode. Just mark it as a lockdown draft.
        lockdown.savedDraft = true
    end

    -- OnHide won't double-save because _closedClean is true.
    self._closedClean = true

    -- Close overlay and mark the draft as handed off to Blizzard's flow.
    if self.OverlayEdit then
        self.OverlayEdit:SetText("")
    end
    self:Hide(true)

    -- Optionally notify the user.
    if not silent and trimmed ~= "" then
        YapperTable.Utils:Print("info", "Draft saved. Press Enter after combat ends to resume.")
    end

    -- Optionally restore the draft to Blizzard's editbox immediately.
    if not bypassOpen and self.OrigEditBox and type(self.OrigEditBox.SetText) == "function" then
        local draft = ""
        if type(history) == "table" and type(history.LoadDraft) == "function" then
            draft = history:LoadDraft() or ""
        end
        self.OrigEditBox:SetText(draft)
        C_Timer.After(0, function()
            local eb = self.OrigEditBox
            if eb and type(eb.SetFocus) == "function" then eb:SetFocus() end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- External whisper routing
-- ---------------------------------------------------------------------------
-- Shared by the ChatFrameUtil.SendTell hook (non-menu callers: chat name
-- left-click, LFG, Professions, Communities, ItemRef) and the
-- UnitPopupWhisperButtonMixin override (all unit-popup menu whispers). One
-- implementation so the two entry points cannot drift apart or fight.

--- True only for Blizzard's native ChatFrameN editboxes (never our overlay).
function EditBox:IsNativeChatEditBox(eb)
    if not eb or eb == self.OverlayEdit or type(eb.GetName) ~= "function" then
        return false
    end
    local name = eb:GetName()
    return type(name) == "string" and name:match("^ChatFrame%d+EditBox$") ~= nil
end

--- Retarget the already-open overlay onto an external (transient) whisper.
--- Preconditions: the overlay must already be shown and `target` must be a
--- non-empty string.  Returns true on success, false if a precondition fails
--- so callers fail fast instead of silently doing nothing.
function EditBox:RetargetOpenWhisper(target, blizzBox)
    if not (self.Overlay and self.Overlay:IsShown()) then
        return false
    end
    if type(target) ~= "string" or target == "" then
        return false
    end

    local overlayText = (self.OverlayEdit and self.OverlayEdit:GetText()) or ""

    if self:IsNativeChatEditBox(blizzBox) then
        self:_IMPushActive(blizzBox)
        -- In Classic+IM tab mode SendTell can fire before the destination box
        -- has stable geometry; re-anchoring there risks snapping to the wrong
        -- host, so only reanchor outside IM mode.  Show() performs the
        -- tab/proxy swap.
        if blizzBox ~= self.OrigEditBox and GetCVar("chatStyle") ~= "im" then
            self:Show(blizzBox)
        end
    end

    self.ChatType = "WHISPER"
    self.Target = target
    self.ChannelName = nil
    -- Transient external whisper: must not become the global LastUsed sticky.
    self._externalWhisperTarget = target
    self:RefreshLabel()

    if overlayText ~= "" and self.OverlayEdit then
        self.OverlayEdit:SetText(overlayText)
        self.OverlayEdit:SetCursorPosition(#overlayText)
    end

    if self.OverlayEdit then
        self.OverlayEdit:SetFocus()
    end

    self:EnsureProxyBackgroundShown()
    self._openingWatchdog = false
    return true
end

--- Record a message sent through Blizzard's native editbox (lockdown / bypass /
--- handoff fallback) into Yapper's persistent history.  Wired to the
--- `ChatFrame.OnEditBoxPreSendText` EventRegistry event.  Only native
--- ChatFrameEditBoxMixin boxes fire that event; the overlay sends through
--- Yapper's own pipeline and never triggers it, so there is no double-record.
function EditBox:RecordFallbackSend(editBox)
    local History = YapperTable.History
    if not (History and type(History.AddChatHistory) == "function") then
        return
    end
    if not editBox or type(editBox.GetText) ~= "function" then
        return
    end

    local text = editBox:GetText()
    if type(text) ~= "string" or text == "" then
        return
    end

    local utils = YapperTable.Utils
    -- Never read, compare, or store secret values (BN tokens, obfuscated text).
    if utils and utils:IsSecret(text) then
        return
    end
    -- Mirror Blizzard's own send guard: only record when a non-space char exists
    -- (slash commands are already cleared by ParseText before this fires).
    if not text:find("%S") then
        return
    end

    -- Read channel context via the ChatFrameEditBoxBaseMixin getters.
    local chatType = (type(editBox.GetChatType) == "function") and editBox:GetChatType() or nil
    local target
    if chatType == "WHISPER" or chatType == "BN_WHISPER" then
        target = (type(editBox.GetTellTarget) == "function") and editBox:GetTellTarget() or nil
    elseif chatType == "CHANNEL" then
        target = (type(editBox.GetChannelTarget) == "function") and editBox:GetChannelTarget() or nil
    end

    -- Keep the message text but drop unstorable secret channel context.
    if target ~= nil and utils and utils:IsSecret(target) then
        chatType = nil
        target = nil
    end

    History:AddChatHistory(text, chatType, target)
end

--- Re-apply current config values to a live overlay if visible.
-- @param force boolean: when true, apply regardless of SettingsHaveChanged flag.
function EditBox:ApplyConfigToLiveOverlay(force)
    if not self.Overlay or not self.OverlayEdit then return end
    Utils:VerbosePrint("EditBox:ApplyConfigToLiveOverlay called (force=" .. tostring(force) .. ")")

    local localConf = _G.YapperLocalConf
    if type(localConf) ~= "table"
        or type(localConf.System) ~= "table"
        or (localConf.System.SettingsHaveChanged ~= true and not force) then
        return
    end

    local cfg = YapperTable.Config.EditBox or {}

    -- Font
    if cfg.FontFace or (cfg.FontSize and cfg.FontSize > 0) then
        local baseFace, baseSize, baseFlags
        if self.OrigEditBox and self.OrigEditBox.GetFont then
            baseFace, baseSize, baseFlags = self.OrigEditBox:GetFont()
        end

        local _, currentSize = self.OverlayEdit:GetFont()
        local face           = cfg.FontFace or baseFace
        local size           = cfg.FontSize > 0 and cfg.FontSize or baseSize or currentSize or 14
        local flags          = (cfg.FontFlags ~= "") and cfg.FontFlags or baseFlags or ""
        if face then
            self.OverlayEdit:SetFont(face, size, flags)
            if self.ChannelLabel then
                self.ChannelLabel:SetFont(face, size, flags)
            end
        end
    elseif self.OrigEditBox and self.OrigEditBox.GetFontObject then
        local fontObj = self.OrigEditBox:GetFontObject()
        if fontObj then
            self.OverlayEdit:SetFontObject(fontObj)
            if self.ChannelLabel then
                self.ChannelLabel:SetFontObject(fontObj)
            end
        end
    end

    -- Border
    local borderActive = cfg.BorderActive
    if borderActive ~= nil then
        if borderActive then
            self.Overlay.Border:Show()
        else
            self.Overlay.Border:Hide()
        end
    end

    -- Border colour
    local borderColour = cfg.BorderColour
    if borderColour and type(borderColour) == "table" then
        self.Overlay.Border:SetVertexColor(borderColour.r, borderColour.g, borderColour.b, borderColour.a or 1)
    end

    -- Border padding
    local borderPad = cfg.BorderPad
    if borderPad ~= nil then
        self.Overlay.BorderPad = borderPad
    end

    -- Single-pass visual refresh (fills, anchors, text colour, border)
    local pad = (borderActive and self.Overlay.BorderPad) or 0
    RefreshOverlayVisuals(self, cfg, borderActive, pad)

    self:RefreshLabel()
    localConf.System.SettingsHaveChanged = false
end
