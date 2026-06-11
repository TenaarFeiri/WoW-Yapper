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

    -- If we're legitimately opening, cancel ghost suppression flags.
    self._suppressPostSendReopen = nil
    self._ghostShowDetected = nil

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

    -- Did Blizzard open with a specific target?
    local blizzHasTarget         = ((blizzType == "WHISPER" or blizzType == "BN_WHISPER")
            and blizzTell and blizzTell ~= "")
        or (blizzType == "CHANNEL" and blizzChan and blizzChan ~= "")

    -- Priority for picking the channel on open:
    --   0. Re-Whisper keybind — primed by our ReplyTell2 hook immediately before
    --      this Show fires. Consumed once and cleared.
    --   1. Blizzard explicitly provided a whisper/channel target (reply key,
    --      name-click, Contacts list, etc.) — always honour it.
    --   2. Lockdown draft — restore the channel the user was on mid-combat.
    --   3. LastUsed sticky — remember the last channel the user chose.
    --   4. Blizzard's editbox type (no specific target) or SAY as fallback.
    -- REMOVED: Pending re-whisper priority (was #1) - ReplyTell2 hook removed
    if pendingTabSwitch and pendingTabSwitch.chatType then
        -- Highest priority: a tab was clicked while Yapper was closed
        -- (whisper tab via Blizzard chatTarget, or per-tab channel memory).
        self.ChatType    = pendingTabSwitch.chatType
        self.Language    = pendingTabSwitch.language
            or blizzLang or (self.LastUsed and self.LastUsed.language) or nil
        self.Target      = pendingTabSwitch.target
        self.ChannelName = pendingTabSwitch.channelName
    elseif blizzHasTarget and not self._lockdown.savedDraft then
        self.ChatType = blizzType
        self.Language = blizzLang or (self.LastUsed and self.LastUsed.language) or nil
        self.Target   = blizzTell or blizzChan or nil
    elseif (self.LastUsed and self.LastUsed.chatType) and not self._lockdown.savedDraft then
        self.ChatType = self.LastUsed.chatType
        self.Language = blizzLang or (self.LastUsed and self.LastUsed.language) or nil
        self.Target   = self.LastUsed.target or blizzTell or blizzChan or nil
    else
        self.ChatType = (self.LastUsed and self.LastUsed.chatType)
            or blizzType
            or "SAY"
        self.Language = blizzLang
            or (self.LastUsed and self.LastUsed.language)
            or nil
        self.Target   = (self.LastUsed and self.LastUsed.target)
            or blizzTell or blizzChan
            or nil
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
    -- Anchor directly on top of the original editbox so it looks identical.
    local overlay = self.Overlay
    local cfg = YapperTable.Config.EditBox or {}
    local chatParent = YapperTable.Utils:GetChatParent()
    overlay:SetParent(chatParent)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", origEditBox, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", origEditBox, "BOTTOMRIGHT", 0, 0)
    overlay:Show()  -- ensure visible (CEBE may have hidden it on close)

    -- Match scale for addons that resize chat frames.
    local parentScale = chatParent:GetEffectiveScale()
    if parentScale == 0 then parentScale = UIParent:GetEffectiveScale() end
    local scale = origEditBox:GetEffectiveScale() / parentScale
    overlay:SetScale(scale)

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

    -- Text
    -- Restore draft if available, otherwise use Blizzard's text.
    local text
    if YapperTable.History and YapperTable.History.HasDirtyDraft() then
        text = YapperTable.History:LoadDraft()
        YapperTable.History:MarkDirty(false)
        self._lockdown.savedDraft = nil
    else
        text = blizzText or ""
    end

    -- Handle whisper slash prefills (e.g., "/w name ").
    if IsWhisperSlashPrefill(text) then
        local parsed = ParseWhisperSlash(text)
        if parsed then
            self.ChatType = parsed.chatType
            self.Target   = parsed.target
            self.OverlayEdit:SetText(parsed.remaining)
            text          = parsed.remaining
        end
    end

    self.OverlayEdit:SetText(text)
    self.OverlayEdit:SetFocus()

    -- Shadow layer for autocomplete/ghost text.
    if self.GhostFS then
        self.GhostFS:Show()
    end

    -- Label
    self:RefreshLabel()

    -- API callback: notify external addons that editbox is shown.
    if YapperTable.API then
        YapperTable.API:Fire("EDITBOX_SHOW", self.ChatType, self.Target)
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
    if self.ChatType and self.ChatType ~= "" then
        self.LastUsed = {
            chatType = self.ChatType,
            target   = self.Target,
            language = self.Language,
        }
    end

    -- Auto-save draft on clean close (no text, or user pressed Escape).
    local text = self.OverlayEdit and self.OverlayEdit:GetText() or ""
    local trimmed = text:match("^%s*(.-)%s*$") or ""

    if not self._closedClean and trimmed ~= "" and YapperTable.History then
        YapperTable.History:SaveDraft(self.OverlayEdit)
        YapperTable.History:MarkDirty(true)
    end

    -- Clear lockdown draft flag on clean close.
    if self._closedClean then
        self._lockdown.savedDraft = nil
    end

    self._closedClean = false

    -- If we're in handoff mode, restore the draft to Blizzard's editbox.
    if isHandoff and prevOrig and prevOrig.SetText then
        local draft = YapperTable.History and YapperTable.History:LoadDraft() or ""
        prevOrig:SetText(draft)
        if prevOrig.SetFocus then
            prevOrig:SetFocus()
        end
    end

    -- EDITBOX_HIDE callback: notify external addons.
    if YapperTable.API then
        YapperTable.API:Fire("EDITBOX_HIDE")
    end
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
    if text ~= "" and YapperTable.History and not isMultiline then
        YapperTable.History:SaveDraft(self.OverlayEdit)
        YapperTable.History:MarkDirty(true)
        -- Mark that this draft was saved due to lockdown so callers
        -- can decide whether to restore it to Blizzard's editbox.
        self._lockdown.savedDraft = true
    elseif isMultiline then
        -- Draft was already saved by multiline mode. Just mark it as a lockdown draft.
        self._lockdown.savedDraft = true
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
    if not bypassOpen and self.OrigEditBox and self.OrigEditBox.SetText then
        local draft = YapperTable.History and YapperTable.History:LoadDraft() or ""
        self.OrigEditBox:SetText(draft)
        C_Timer.After(0, function()
            local eb = self.OrigEditBox
            if eb and eb.SetFocus then eb:SetFocus() end
        end)
    end
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
        local face  = cfg.FontFace
        local size  = cfg.FontSize or 0
        local flags = cfg.FontFlags or ""
        if size > 0 then
            self.OverlayEdit:SetFont(face, size, flags)
        end
    end

    -- Fill colour
    local fill = cfg.FillColour
    if fill and type(fill) == "table" then
        self.OverlayEdit:SetTextColor(fill.r, fill.g, fill.b, fill.a or 1)
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
