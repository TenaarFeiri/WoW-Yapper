--[[
    EditBox/Hooks.lua
    Show/Hide lifecycle, Blizzard handoff, live config application,
    label refresh, channel cycling, history navigation, slash forwarding,
    and the Blizzard editbox hook integration (HookBlizzardEditBox,
    HookAllChatFrames).
]]

local _, YapperTable               = ...
local EditBox                      = YapperTable.EditBox
local State                        = YapperTable.State

-- Re-localise shared helpers from hub.
local SLASH_MAP                    = EditBox._SLASH_MAP
local TAB_CYCLE                    = EditBox._TAB_CYCLE
local LABEL_PREFIXES               = EditBox._LABEL_PREFIXES
local GROUP_CHAT_TYPES             = EditBox._GROUP_CHAT_TYPES
local CHATTYPE_TO_OVERRIDE_KEY     = EditBox._CHATTYPE_TO_OVERRIDE_KEY
local IsWhisperSlashPrefill        = EditBox.IsWhisperSlashPrefill
local ParseWhisperSlash            = EditBox.ParseWhisperSlash
local GetLastTellTargetInfo        = EditBox.GetLastTellTargetInfo
local GetLastToldTargetInfo        = EditBox.GetLastToldTargetInfo
local SetFrameFillColour           = EditBox.SetFrameFillColour

-- Resolve locals from Overlay.lua (loaded before us).
local RefreshOverlayVisuals        = EditBox._RefreshOverlayVisuals
local ResolveChannelName           = EditBox._ResolveChannelName
local BuildLabelText               = EditBox._BuildLabelText
local GetLabelUsableWidth          = EditBox._GetLabelUsableWidth
local ResetLabelToBaseFont         = EditBox._ResetLabelToBaseFont
local TruncateLabelToWidth         = EditBox._TruncateLabelToWidth
local FitLabelFontToWidth          = EditBox._FitLabelFontToWidth
local UpdateLabelBackgroundForText = EditBox._UpdateLabelBackgroundForText

-- Closure accessors for mutable hub-scoped locals.
local function UserBypassingYapper() return EditBox._UserBypassingYapper() end
local function SetUserBypassingYapper(v) EditBox._SetUserBypassingYapper(v) end
local function BypassEditBox() return EditBox._BypassEditBox() end
local function SetBypassEditBox(v) EditBox._SetBypassEditBox(v) end

-- Re-localise Lua globals.
local type       = type
local pairs      = pairs
local ipairs     = ipairs
local tostring   = tostring
local tonumber   = tonumber
local math_max   = math.max
local math_min   = math.min
local math_abs   = math.abs
local math_floor = math.floor
local strmatch   = string.match
local strlower   = string.lower


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
        self.ChannelLabel:SetFont(face, size, flags)
    else
        local fontObj = origEditBox:GetFontObject()
        if fontObj then
            self.OverlayEdit:SetFontObject(fontObj)
            self.ChannelLabel:SetFontObject(fontObj)
        end
    end

    -- Label sizing, width, and colour are handled by RefreshLabel() below
    -- in one pass. Skipping the redundant early call avoids an extra
    -- GetStringWidth() (an expensive text-layout force) per open.

    -- Vertical scaling
    -- The overlay must be tall enough for the chosen font.  If the font
    -- size (+ padding) exceeds the Blizzard editbox height, grow.
    -- A configured MinHeight also serves as a floor.
    local _, activeSize = self.OverlayEdit:GetFont()
    activeSize          = activeSize or 14
    local fontPad       = cfg.FontPad or 8
    local fontNeeded    = activeSize + fontPad
    local blizzH        = origEditBox:GetHeight() or 32
    local minH          = (cfg.MinHeight and cfg.MinHeight > 0) and cfg.MinHeight or blizzH
    local finalH        = math_max(minH, fontNeeded)
    if finalH > blizzH then
        overlay:ClearAllPoints()
        overlay:SetPoint("TOPLEFT", origEditBox, "TOPLEFT", 0, 0)
        overlay:SetPoint("RIGHT", origEditBox, "RIGHT", 0, 0)
        overlay:SetHeight(finalH)
    end

    -- Stay on top of the original.
    local origLevel = origEditBox:GetFrameLevel() or 0
    overlay:SetFrameLevel(origLevel + 5)
    if YapperTable.Utils and YapperTable.Utils.DebugPrint then
        YapperTable.Utils:DebugPrint("Show: overlay frameLevel=" .. overlay:GetFrameLevel() .. ", orig frameLevel=" .. origLevel)
    end
    if cfg.UseBlizzardSkinProxy == true and cfg.UseLegacyCloneProxy ~= true then
        -- Proxy mode: keep the original Blizzard editbox visible underneath.
        -- If a multiline draft is pending, Multiline:Enter (called at the end of Show)
        -- will Hide() the original editbox within the same Lua callback, so the user
        -- never sees it flicker visible. _proxyPrevState remains intact so Multiline:Exit
        -- can re-show it when the user returns to the single-line overlay.
        pcall(function() self:ApplyProxyMode(origEditBox) end)
    else
        pcall(function()
            -- Legacy: clone Blizzard's textures onto Yapper's overlay.
            self:AttachBlizzardSkinProxy(origEditBox, finalH)
        end)
        if not self._skinProxyTextures and cfg.UseBlizzardSkinProxy == true then
            if YapperTable.Utils and YapperTable.Utils.DebugPrint then
                YapperTable.Utils:DebugPrint("Show: AttachBlizzardSkinProxy failed (no textures attached despite config=true)")
            end
        end

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
        RefreshOverlayVisuals(self, cfg, borderOnShow, padOnShow)
    end

    -- Final setup
    self._closedClean = false

    -- Draft recovery: restore if the last close was dirty.
    -- Skip if Blizzard set a target (e.g. Friends-list whisper).
    local draftText
    local draftMultiline = false
    if not blizzHasTarget and YapperTable.History then
        local text, draftType, draftTarget, isML = YapperTable.History:GetDraft()
        if text then
            draftText = text
            draftMultiline = isML or false
            if draftType then self.ChatType = draftType end
            if draftTarget then self.Target = draftTarget end
            YapperTable.History:MarkDirty(false)
            YapperTable.Utils:VerbosePrint("Draft recovered: " ..
                #text .. " chars" .. (draftMultiline and " (multiline)" or "") .. ".")
        end
    end

    -- Carry over any text Blizzard pre-populated on the native editbox
    -- (e.g. chat links, whisper prefills from friend-list clicks).
    -- ForwardTextToYapper handles most of these asynchronously, but blizzText
    -- covers the case where Show() is called before OnUpdate has fired.
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
    if existingText ~= "" then
        if not draftText then
            draftText = existingText
        elseif not string.find(draftText, existingText, 1, true) then
            -- Avoid prefixing if the existing text is already at the start of the draft
            draftText = existingText .. draftText
        end
    end

    if externalText and externalText ~= "" then
        if not draftText then
            draftText = externalText
        elseif not string.find(draftText, externalText, 1, true) then
            -- If external text is already part of the draft (avoid duplicates from re-opens)
            draftText = draftText .. externalText
        end
    end

    -- Clear the watchdog now that we've grabbed everything
    self._openingWatchdog = false

    -- Set the text: restore a draft if found, otherwise clear the box
    -- ONLY if we are coming from a hidden state. This prevents wipes
    -- when refocusing an already-visible overlay.
    if not overlay:IsShown() then
        self.OverlayEdit:SetText(draftText or "")
    elseif draftText then
        self.OverlayEdit:SetText(draftText)
    end

    if draftText then
        self.OverlayEdit:SetCursorPosition(#draftText)
    end
    self:RefreshLabel()

    -- Clear stale bypass state so subsequent Shows don't short-circuit.
    if BypassEditBox() then
        SetBypassEditBox(nil)
    end

    -- Focus the overlay. If an external addon (e.g. Chattynator) aggressively
    -- steals focus back via DeactivateChat hooks, reclaim it on the next frame.
    self.OverlayEdit:SetFocus()
    C_Timer.After(0, function()
        if self.Overlay and self.Overlay:IsShown() and not self.OverlayEdit:HasFocus() then
            self.OverlayEdit:SetFocus()
        end
    end)

    -- If the recovered draft came from the multiline editor, transition
    -- directly into multiline so hard newlines are preserved.  The overlay
    -- is briefly shown above (needed for anchoring), then Multiline:Enter
    -- hides it and takes over.
    if draftMultiline and draftText and YapperTable.Multiline
        and type(YapperTable.Multiline.Enter) == "function" then
        YapperTable.Multiline:Enter(
            draftText, self.ChatType, nil, self.Target)
    end

    -- Clear Blizzard's backing editbox to avoid stale carryover on next open.
    if origEditBox and origEditBox.SetText then
        origEditBox:SetText("")
    end

    if State and not State:IsMultiline() then
        YapperAPI:SetState("EDITING")
    end

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
    -- texture-destroy API — each DetachBlizzardSkinProxy call nil-refs the Lua
    -- table but the C-side texture objects remain on the frame forever.

    if self.Overlay then
        self.Overlay:Hide()
    end

    -- Sync Yapper's final state to Blizzard's editbox so it has correct
    -- attributes if it needs to show (e.g., during handoff or user bypass).
    -- This is a transition sync, not a continuous one - we only sync when
    -- Yapper hides, not on every RefreshLabel like the old parasite pattern.
    -- IMPORTANT: Only sync when explicitly handing off to Blizzard (isHandoff=true).
    -- Normal hide operations (send complete, escape) should NOT sync, as this
    -- interferes with external addons like TRP3 that may do post-send cleanup.
    if isHandoff and prevOrig and not (InCombatLockdown and InCombatLockdown()) then
        local chosenCT = self.ChatType or "SAY"
        local overrideCT = CHATTYPE_TO_OVERRIDE_KEY[chosenCT] or chosenCT

        if prevOrig:GetAttribute("chatType") ~= overrideCT then
            prevOrig:SetAttribute("chatType", overrideCT)
        end

        if overrideCT == "WHISPER" or overrideCT == "BN_WHISPER" then
            if self.Target and self.Target ~= "" then
                if prevOrig:GetAttribute("tellTarget") ~= self.Target then
                    prevOrig:SetAttribute("tellTarget", self.Target)
                end
            end
            prevOrig:SetAttribute("channelTarget", nil)
        elseif overrideCT == "CHANNEL" then
            if self.Target then
                if prevOrig:GetAttribute("channelTarget") ~= self.Target then
                    prevOrig:SetAttribute("channelTarget", self.Target)
                end
            end
            prevOrig:SetAttribute("tellTarget", nil)
        else
            prevOrig:SetAttribute("tellTarget", nil)
            prevOrig:SetAttribute("channelTarget", nil)
        end
        if self.Language then
            prevOrig:SetAttribute("language", self.Language)
        else
            prevOrig:SetAttribute("language", nil)
        end
    end
    self.OverlayEdit:ClearFocus()
    -- Defensive: if the focus trap somehow still holds focus, clear it.
    if self._focusTrap and self._focusTrap:HasFocus() then
        self._focusTrap:ClearFocus()
    end
    self.OrigEditBox = nil

    -- Clean up any active lockdown timers to prevent "ghost" handoffs
    -- if the user finished their post normally or escaped out.
    self:ClearLockdownState()
    self._lockdown.handedOff = false

    -- Clear CHAT_FOCUS_OVERRIDE when closing Yapper
    if ChatFrameUtil and ChatFrameUtil.ClearChatFocusOverride then
        ChatFrameUtil.ClearChatFocusOverride()
    end

    -- Suppress one immediate Blizzard Show for the same editbox to avoid
    -- hide/show contention on outside-click dismissals.
    -- Store the frame name (string) rather than the frame reference to avoid
    -- producing a tainted secure pointer that causes "secret boolean" errors
    -- when compared inside hooksecurefunc callbacks.
    if prevOrig then
        local prevOrigName = prevOrig.GetName and prevOrig:GetName() or nil
        self._suppressNextShowFor = prevOrigName
        C_Timer.After(0, function()
            if self._suppressNextShowFor == prevOrigName then
                self._suppressNextShowFor = nil
            end
        end)
    end

    -- Transition to IDLE state, but only if we're not busy (sending, stalled, lockdown).
    if not State:IsBusy() then
        YapperAPI:SetState("IDLE")
    end

    -- Prevent Enter/Escape keybind propagation from immediately re-opening the
    -- overlay in the same frame/tick.
    self._justClosed = true
    C_Timer.After(0, function()
        self._justClosed = nil
    end)

    -- Suppress phantom Blizzard reopens that fire ~1s after close.
    -- External addons (e.g. TRP3's FocusActiveWindow) can trigger Blizzard's
    -- sticky-chat restore, which re-shows the editbox + calls OpenChat(nil,nil).
    -- _justClosed only lasts one frame, so this longer guard catches the deferred ghost.
    -- Skip suppression when handoff to Blizzard (isHandoff=true) since that's an
    -- intentional transition, not a close that should trigger ghost suppression.
    if not isHandoff then
        self._suppressPostSendReopen = true
        C_Timer.After(2, function()
            self._suppressPostSendReopen = nil
        end)

        -- Re-set CHAT_FOCUS_OVERRIDE next frame so the user's next open routes
        -- through the focusOverrideIntercepted path (calls Show() directly),
        -- which is distinguishable from the ghost pattern (Shows before OpenChat).
        C_Timer.After(0, function()
            if not (YapperTable.Utils and YapperTable.Utils:IsChatLockdown()) then
                self:UpdateFocusOverride()
            end
        end)
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

    self._lockdown.handedOff = true
    if not silent then
        YapperTable.Utils:Print("info",
            "Chat in lockdown — your post has been saved. Press Enter after lockdown ends to continue.")
    end

    -- If there's an active draft and we are not bypassing the open,
    -- immediately hand it off to Blizzard's editbox so the user can continue typing.
    if trimmed ~= "" and not bypassOpen then
        local eb = self.OrigEditBox or _G.ChatFrame1EditBox
        C_Timer.After(0, function()
            -- Sync attributes before opening Blizzard's editbox
            local chosenCT = self.ChatType or "SAY"
                local overrideCT = CHATTYPE_TO_OVERRIDE_KEY[chosenCT] or chosenCT

            if eb:GetAttribute("chatType") ~= overrideCT then
                eb:SetAttribute("chatType", overrideCT)
            end

            if overrideCT == "WHISPER" or overrideCT == "BN_WHISPER" then
                if self.Target and self.Target ~= "" then
                    if eb:GetAttribute("tellTarget") ~= self.Target then
                        eb:SetAttribute("tellTarget", self.Target)
                    end
                end
                eb:SetAttribute("channelTarget", nil)
            elseif overrideCT == "CHANNEL" then
                if self.Target then
                    if eb:GetAttribute("channelTarget") ~= self.Target then
                        eb:SetAttribute("channelTarget", self.Target)
                    end
                end
                eb:SetAttribute("tellTarget", nil)
            else
                eb:SetAttribute("tellTarget", nil)
                eb:SetAttribute("channelTarget", nil)
            end
            if self.Language then
                eb:SetAttribute("language", self.Language)
            else
                eb:SetAttribute("language", nil)
            end

            if ChatFrame_OpenChat then
                pcall(ChatFrame_OpenChat, "", eb)
                if eb and eb.SetFocus then eb:SetFocus() end
            else
                if eb and eb.Show then eb:Show() end
                if eb and eb.SetFocus then eb:SetFocus() end
            end
        end)
    end
end

--- Re-apply current config values to a live overlay if visible.
-- @param force boolean: when true, apply regardless of SettingsHaveChanged flag.
function EditBox:ApplyConfigToLiveOverlay(force)
    if not self.Overlay or not self.OverlayEdit then return end
    pcall(function()
        if YapperTable and YapperTable.Utils and YapperTable.Utils.VerbosePrint then
            YapperTable.Utils:VerbosePrint("EditBox:ApplyConfigToLiveOverlay called (force=" .. tostring(force) .. ")")
        end
    end)

    local localConf = _G.YapperLocalConf
    if type(localConf) ~= "table"
        or type(localConf.System) ~= "table"
        or (localConf.System.SettingsHaveChanged ~= true and not force) then
        return
    end

    local cfg          = YapperTable.Config.EditBox or {}
    local activeTheme  = YapperTable.Theme and YapperTable.Theme:GetTheme()
    local borderActive = activeTheme and activeTheme.border == true

    -- Apply theme baseline first (so user config can override it below)
    if not self._skinProxyTextures
        and YapperTable.Theme and type(YapperTable.Theme.ApplyToFrame) == "function"
        and self.Overlay then
        pcall(function() YapperTable.Theme:ApplyToFrame(self.Overlay) end)
    end


    -- Font update (before visuals so height calc reflects new size)
    local cfgFace  = cfg.FontFace
    local cfgSize  = cfg.FontSize or 0
    local cfgFlags = cfg.FontFlags or ""

    if cfgFace or cfgSize > 0 then
        local baseFace, baseSize, baseFlags
        if self.OrigEditBox and self.OrigEditBox.GetFont then
            baseFace, baseSize, baseFlags = self.OrigEditBox:GetFont()
        end

        local _, currentSize = self.OverlayEdit:GetFont()
        local face           = cfgFace or baseFace
        local size           = cfgSize > 0 and cfgSize or baseSize or currentSize or 14
        local flags          = (cfgFlags ~= "") and cfgFlags or baseFlags or ""
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

    -- Height recalculation
    if self.Overlay and self.Overlay:IsShown() and self.OrigEditBox then
        local _, activeSize = self.OverlayEdit:GetFont()
        activeSize          = activeSize or 14
        local fontPad       = cfg.FontPad or 8
        local fontNeeded    = activeSize + fontPad
        local blizzH        = self.OrigEditBox:GetHeight() or 32
        local minH          = (cfg.MinHeight and cfg.MinHeight > 0) and cfg.MinHeight or blizzH
        local finalH        = math_max(minH, fontNeeded)
        local resolvedH     = finalH > blizzH and finalH or blizzH

        self.Overlay:ClearAllPoints()
        self.Overlay:SetPoint("TOPLEFT", self.OrigEditBox, "TOPLEFT", 0, 0)
        self.Overlay:SetPoint("RIGHT", self.OrigEditBox, "RIGHT", 0, 0)
        self.Overlay:SetHeight(resolvedH)

        -- Synchronize skin proxy state with config on the fly.
        if self.OrigEditBox then
            pcall(function()
                self:AttachBlizzardSkinProxy(self.OrigEditBox, resolvedH)
            end)
            if not self._skinProxyTextures and cfg.UseBlizzardSkinProxy == true then
                if YapperTable.Utils and YapperTable.Utils.DebugPrint then
                    YapperTable.Utils:DebugPrint("ApplyConfigToLiveOverlay: AttachBlizzardSkinProxy failed (no textures attached despite config=true)")
                end
            end
        end
    end

    -- Single-pass visual refresh (fills, anchors, text colour, border)
    local pad = (borderActive and self.Overlay.BorderPad) or 0
    RefreshOverlayVisuals(self, cfg, borderActive, pad)

    self:RefreshLabel()
    localConf.System.SettingsHaveChanged = false
end

-- ---------------------------------------------------------------------------
-- Label
-- ---------------------------------------------------------------------------

function EditBox:RefreshLabel()
    local cfg = YapperTable.Config.EditBox or {}

    -- Detect BN targets: Blizzard may present a plain WHISPER chatType
    -- even when the target is a BNet friend (presence/account ID). When
    -- that is the case prefer BN_WHISPER for label and colour selection
    -- so the overlay uses the Battle.net defaults/config by default.
    local effectiveType = self.ChatType
    local currentKey = CHATTYPE_TO_OVERRIDE_KEY[self.ChatType]
    if currentKey == "WHISPER" and self.Target and YapperTable.Router
        and type(YapperTable.Router.ResolveBnetTarget) == "function" then
        local presenceID, bnetAccountID = YapperTable.Router:ResolveBnetTarget(self.Target)
        if presenceID or bnetAccountID then
            effectiveType = "BN_WHISPER"
            currentKey = "BN_WHISPER"
        end
    end

    local label, r, g, b = BuildLabelText(effectiveType, self.Target, self.ChannelName)
    local resolvedR, resolvedG, resolvedB = r, g, b

    -- Prefer user-defined channel text colours for the effective type
    -- (e.g. BN_WHISPER) so user-configured colours always take precedence.
    local channelColors = cfg.ChannelTextColors
    if channelColors and effectiveType and type(channelColors[effectiveType]) == "table" then
        local ucol = channelColors[effectiveType]
        if type(ucol.r) == "number" and type(ucol.g) == "number" and type(ucol.b) == "number" then
            resolvedR, resolvedG, resolvedB = ucol.r, ucol.g, ucol.b
        end
    end

    -- If a theme provides channel text colours and the config doesn't override,
    -- prefer the theme values so themes can style channel labels consistently.
    local theme
    if YapperTable.Theme and type(YapperTable.Theme.GetTheme) == "function" then
        theme = YapperTable.Theme:GetTheme()
    end

    if currentKey == nil then
        currentKey = CHATTYPE_TO_OVERRIDE_KEY[self.ChatType]
    end
    if (currentKey == "CHANNEL" or self.ChatType == "CHANNEL") and self.Target and YapperTable.Router
        and YapperTable.Router.DetectCommunityChannel then
        local isClub = YapperTable.Router:DetectCommunityChannel(self.Target)
        if isClub == true then
            currentKey = "CLUB"
        end
    end
    local masterKey = cfg.ChannelColorMaster
    local colorMode = cfg.ChannelColorMode
    local channelColors = cfg.ChannelTextColors
    local modeResolved = false

    -- Check channel colour mode
    if currentKey and type(colorMode) == "table" and type(colorMode[currentKey]) == "string" then
        local mode = colorMode[currentKey]

        if mode == "blizzard" then
            -- Blizzard mode: use ChatTypeInfo (absolute precedence)
            if currentKey == "CHANNEL" and self.Target then
                local info = ChatTypeInfo and ChatTypeInfo["CHANNEL" .. tostring(self.Target)]
                if info and type(info.r) == "number" then
                    resolvedR, resolvedG, resolvedB = info.r, info.g, info.b
                    modeResolved = true
                end
            elseif currentKey == "CLUB" and self.Target then
                -- Community channels use CHANNEL# ChatTypeInfo
                local info = ChatTypeInfo and ChatTypeInfo["CHANNEL" .. tostring(self.Target)]
                if info and type(info.r) == "number" then
                    resolvedR, resolvedG, resolvedB = info.r, info.g, info.b
                    modeResolved = true
                end
            else
                local info = ChatTypeInfo and ChatTypeInfo[currentKey]
                if info and type(info.r) == "number" then
                    resolvedR, resolvedG, resolvedB = info.r, info.g, info.b
                    modeResolved = true
                end
            end
        elseif mode == "master" and currentKey and type(masterKey) == "string"
            and masterKey ~= "" and currentKey ~= masterKey then
            -- Master mode: follow master channel's colour
            if type(channelColors) == "table"
                and type(channelColors[masterKey]) == "table"
                and type(channelColors[masterKey].r) == "number"
                and type(channelColors[masterKey].g) == "number"
                and type(channelColors[masterKey].b) == "number" then
                resolvedR = channelColors[masterKey].r
                resolvedG = channelColors[masterKey].g
                resolvedB = channelColors[masterKey].b
                modeResolved = true
            elseif ChatTypeInfo and ChatTypeInfo[masterKey] then
                local info = ChatTypeInfo[masterKey]
                resolvedR = info.r or resolvedR
                resolvedG = info.g or resolvedG
                resolvedB = info.b or resolvedB
                modeResolved = true
            end
        end
    end

    -- Custom mode (or no mode set, or mode resolution failed): use ChannelTextColors
    if not modeResolved and currentKey and type(channelColors) == "table"
        and type(channelColors[currentKey]) == "table" then
        local own = channelColors[currentKey]
        if type(own.r) == "number" and type(own.g) == "number" and type(own.b) == "number" then
            resolvedR, resolvedG, resolvedB = own.r, own.g, own.b
        end
    end

    UpdateLabelBackgroundForText(self, label)

    local usableWidth = GetLabelUsableWidth(self)
    if self.ChannelLabel.SetWidth then
        self.ChannelLabel:SetWidth(usableWidth)
    end

    ResetLabelToBaseFont(self)

    if cfg.AutoFitLabel == true then
        local fitOk = FitLabelFontToWidth(self, label, usableWidth)
        if not fitOk then
            label = TruncateLabelToWidth(self.ChannelLabel, label, usableWidth)
        end
    else
        label = TruncateLabelToWidth(self.ChannelLabel, label, usableWidth)
    end

    self.ChannelLabel:SetText(label)

    -- Use theme colour *only* when the user's per‑channel config still equals the defaults
    -- (i.e. they haven't overridden that channel).  Otherwise stick with the configured value.
    -- Skip this entirely when mode is "blizzard" or "master" since those have absolute precedence.
    if not modeResolved and theme and type(theme.channelTextColors) == "table" and currentKey then
        local tcol = theme.channelTextColors[effectiveType] or theme.channelTextColors[currentKey]
        if tcol and type(tcol.r) == "number" and type(tcol.g) == "number" and type(tcol.b) == "number" then
            -- Only use theme colour when user's config colour matches defaults.
            local defaults = YapperTable.Core and YapperTable.Core.GetDefaults
                and YapperTable.Core:GetDefaults()
            local defColors = defaults and defaults.EditBox
                and defaults.EditBox.ChannelTextColors
                and defaults.EditBox.ChannelTextColors[currentKey]
            local userColor = channelColors and channelColors[currentKey]
            if defColors and userColor
                and math_abs((userColor.r or 0) - (defColors.r or 0)) < 0.01
                and math_abs((userColor.g or 0) - (defColors.g or 0)) < 0.01
                and math_abs((userColor.b or 0) - (defColors.b or 0)) < 0.01 then
                resolvedR, resolvedG, resolvedB = tcol.r, tcol.g, tcol.b
            end
        end
    end

    -- Debugging aid: log effective type, target, and chosen colours when DEBUG enabled.
    if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        local whisperCol = (channelColors and channelColors.WHISPER) or nil
        local bnetCol = (channelColors and channelColors.BN_WHISPER) or nil
        local masterKey = cfg.ChannelColorMaster or ""
        local overrideFlag = (cfg.ChannelColorOverrides and cfg.ChannelColorOverrides[currentKey]) or false
        local msg = string.format(
            "RefreshLabel: eff=%s ct=%s tgt=%s -> resolved=(%.2f,%.2f,%.2f) master=%s override=%s whisper=(%s) bn=(%s)",
            tostring(effectiveType), tostring(self.ChatType), tostring(self.Target or ""),
            tonumber(resolvedR) or 0, tonumber(resolvedG) or 0, tonumber(resolvedB) or 0,
            tostring(masterKey), tostring(overrideFlag),
            (whisperCol and string.format("%.2f,%.2f,%.2f", whisperCol.r, whisperCol.g, whisperCol.b) or "nil"),
            (bnetCol and string.format("%.2f,%.2f,%.2f", bnetCol.r, bnetCol.g, bnetCol.b) or "nil"))
        if YapperTable.Utils and YapperTable.Utils.DebugPrint then
            YapperTable.Utils:DebugPrint(msg)
        elseif YapperTable.Utils and YapperTable.Utils.VerbosePrint then
            YapperTable.Utils:VerbosePrint(msg)
        else
            print(msg)
        end
    end

    -- Safety fallback: if this is a BN_WHISPER and the resolved colour
    -- currently matches the standard WHISPER magenta (or was pulled from
    -- ChatTypeInfo), prefer the BN default so BNet whispers show teal by
    -- default. This guards against stale SavedVariables or Blizzard fallbacks.
    if effectiveType == "BN_WHISPER" then
        local function approxEqual(a, b)
            return math_abs((a or 0) - (b or 0)) < 0.02
        end
        -- standard whisper magenta heuristic
        if approxEqual(resolvedR, 1.0) and approxEqual(resolvedG, 0.5) and approxEqual(resolvedB, 1.0) then
            local defaults = YapperTable.Core and YapperTable.Core.GetDefaults and YapperTable.Core:GetDefaults()
            local defBN = defaults and defaults.EditBox and defaults.EditBox.ChannelTextColors and
                defaults.EditBox.ChannelTextColors.BN_WHISPER
            if defBN and type(defBN.r) == "number" then
                resolvedR, resolvedG, resolvedB = defBN.r, defBN.g, defBN.b
            end
        end
    end

    self.ChannelLabel:SetTextColor(resolvedR, resolvedG, resolvedB)

    -- Labels stay channel-coloured. Input text uses channel colour, or master override.
    if self.OverlayEdit then
        self.OverlayEdit:SetTextColor(resolvedR, resolvedG, resolvedB)
    end

    if YapperTable.API then
        YapperTable.API:Fire("EDITBOX_LABEL_UPDATED", label, resolvedR, resolvedG, resolvedB)
    end

    -- As a first-class citizen frame (CHAT_FOCUS_OVERRIDE), Yapper is the
    -- authoritative editbox — no need to sync state back to Blizzard's box.
    -- ForwardSlashCommand sets attributes explicitly when forwarding commands,
    -- and lockdown handoff preserves state through drafts, not attribute sync.

    -- Proxy mode exception: addons like Prat hook ChatEdit_UpdateHeader
    -- to recolour the editbox border per channel. Since the original Blizzard
    -- editbox is now visible underneath Yapper, mirror our chat type onto it
    -- (outside combat) so those hooks fire and the skin reflects the channel.
    if cfg.UseBlizzardSkinProxy == true and cfg.UseLegacyCloneProxy ~= true
        and self.OrigEditBox and not (InCombatLockdown and InCombatLockdown()) then
        local overrideCT = CHATTYPE_TO_OVERRIDE_KEY[self.ChatType] or self.ChatType
        pcall(function()
            if self.OrigEditBox:GetAttribute("chatType") ~= overrideCT then
                self.OrigEditBox:SetAttribute("chatType", overrideCT)
            end
            if overrideCT == "WHISPER" or overrideCT == "BN_WHISPER" then
                if self.Target and self.Target ~= ""
                    and self.OrigEditBox:GetAttribute("tellTarget") ~= self.Target then
                    self.OrigEditBox:SetAttribute("tellTarget", self.Target)
                end
            elseif overrideCT == "CHANNEL" then
                if self.Target
                    and self.OrigEditBox:GetAttribute("channelTarget") ~= self.Target then
                    self.OrigEditBox:SetAttribute("channelTarget", self.Target)
                end
            end
        end)
    end
end

--- Record the current channel for the active tab (session-only).
--- Skips whisper tabs, which are handled by Blizzard's chatTarget.
--- @param entry table|nil  Explicit values to store; defaults to current state.
function EditBox:RecordTabChannel(entry)
    local chatFrame = self.OrigEditBox and self.OrigEditBox.chatFrame
        or DEFAULT_CHAT_FRAME
    if not (chatFrame and chatFrame.GetName) then return end
    local key = chatFrame:GetName()
    if not key then return end

    local ct = entry and entry.chatType or self.ChatType
    -- Whisper tabs are restored from Blizzard's chatTarget; don't record them.
    if ct == "WHISPER" or ct == "BN_WHISPER" then return end

    self._tabChannelMemory[key] = {
        chatType    = ct,
        target      = entry and entry.target or self.Target,
        channelName = entry and entry.channelName or self.ChannelName,
        language    = entry and entry.language or self.Language,
    }
end

--- Save selection for stickiness across show/hide.
function EditBox:PersistLastUsed()
    -- Don't make YELL sticky — but don't clear LastUsed either,
    -- so we restore to whatever was sticky before YELL.
    if self.ChatType == "YELL" then
        return
    end

    if self.ChatType == "WHISPER" or self.ChatType == "BN_WHISPER" then
        if not self.Target or self.Target == nil or self.Target == "" then
            return
        end
    end

    local cfg = YapperTable.Config.EditBox or {}
    if cfg.StickyChannel == false then
        -- Group channels stay sticky unless StickyGroupChannel is also off.
        if not GROUP_CHAT_TYPES[self.ChatType]
            or cfg.StickyGroupChannel == false then
            -- Stickiness is off for this channel type.
            -- Actively reset to SAY so the next open doesn't inherit a
            -- stale channel (e.g. if the user disabled sticky mid-session
            -- or the Show-hook seeded LastUsed from Blizzard's editbox).
            self.LastUsed.chatType = "SAY"
            self.LastUsed.target   = nil
            self.LastUsed.language = nil
            -- Mirror the reset into per-tab memory so the tab doesn't
            -- resurrect a stale channel either.
            self:RecordTabChannel({ chatType = "SAY" })
            return
        end
    end

    self.LastUsed.chatType = self.ChatType
    self.LastUsed.target   = self.Target
    self.LastUsed.language = self.Language

    -- Session-only per-tab channel memory (non-whisper tabs).
    self:RecordTabChannel()
end

-- ---------------------------------------------------------------------------
-- Tab cycling
-- ---------------------------------------------------------------------------

function EditBox:CycleChat(direction)
    local current = self.ChatType or "SAY"

    -- If we're in whisper mode, cycle reply targets instead of channels.
    if current == "WHISPER" or current == "BN_WHISPER" then
        local curTarget = self.Target or ""
        local name, kind = self:NextReplyTarget(curTarget, direction)
        if name and name ~= "" then
            self.ChatType    = kind or "WHISPER"
            self.Target      = name
            -- ChannelName not used for whispers
            self.ChannelName = nil
            self:RefreshLabel()
            if YapperTable.API then
                YapperTable.API:Fire("EDITBOX_CHANNEL_CHANGED", self.ChatType, self.Target)
            end
        end
        return
    end

    local idx = 1
    for i, ct in ipairs(TAB_CYCLE) do
        if ct == current then
            idx = i
            break
        end
    end

    -- Skip unavailable modes.
    for _ = 1, #TAB_CYCLE do
        idx = idx + direction
        if idx < 1 then idx = #TAB_CYCLE end
        if idx > #TAB_CYCLE then idx = 1 end

        local candidate = TAB_CYCLE[idx]
        if self:IsChatTypeAvailable(candidate) then
            self.ChatType    = candidate
            self.Target      = nil
            self.ChannelName = nil
            self:RefreshLabel()
            if YapperTable.API then
                YapperTable.API:Fire("EDITBOX_CHANNEL_CHANGED", self.ChatType, nil)
            end
            return
        end
    end
end

function EditBox:IsChatTypeAvailable(chatType)
    if chatType == "SAY" or chatType == "EMOTE" or chatType == "YELL" then
        return true
    end
    if chatType == "PARTY" or chatType == "PARTY_LEADER" then
        return IsInGroup(LE_PARTY_CATEGORY_HOME)
    end
    if chatType == "RAID" or chatType == "RAID_LEADER" then
        return IsInRaid(LE_PARTY_CATEGORY_HOME)
    end
    if chatType == "RAID_WARNING" then
        return IsInRaid()
    end
    if chatType == "INSTANCE_CHAT" then
        return IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    end
    if chatType == "GUILD" or chatType == "OFFICER" then
        return IsInGuild()
    end
    return true
end

function EditBox:GetResolvedChatType(ct)
    if ct == "INSTANCE_CHAT" then
        if not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
            if IsInRaid(LE_PARTY_CATEGORY_HOME) then
                return "RAID"
            elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
                return "PARTY"
            end
        end
    elseif ct == "PARTY" or ct == "PARTY_LEADER" then
        if not IsInGroup(LE_PARTY_CATEGORY_HOME) and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
            return "INSTANCE_CHAT"
        end
    elseif ct == "RAID" or ct == "RAID_LEADER" then
        if not IsInRaid(LE_PARTY_CATEGORY_HOME) and IsInRaid(LE_PARTY_CATEGORY_INSTANCE) then
            return "INSTANCE_CHAT"
        end
    end
    return ct
end

-- ---------------------------------------------------------------------------
-- History navigation
-- ---------------------------------------------------------------------------

function EditBox:NavigateHistory(direction)
    -- Build history snapshot on first press.
    if not self.HistoryCache then
        self.HistoryCache = {}
        if YapperTable.History and YapperTable.History.GetChatHistory then
            self.HistoryCache = YapperTable.History:GetChatHistory() or {}
        elseif _G.YapperLocalHistory and _G.YapperLocalHistory.chatHistory then
            local saved = _G.YapperLocalHistory.chatHistory
            if type(saved) == "table" then
                if saved.global then
                    for _, v in ipairs(saved.global) do
                        self.HistoryCache[#self.HistoryCache + 1] = v
                    end
                else
                    for _, v in ipairs(saved) do
                        self.HistoryCache[#self.HistoryCache + 1] = v
                    end
                end
            end
        end
        self.HistoryIndex = #self.HistoryCache + 1
    end

    local cache = self.HistoryCache
    if #cache == 0 then return end

    local newIdx = (self.HistoryIndex or (#cache + 1)) + direction
    newIdx = math_max(1, math_min(newIdx, #cache + 1))

    if newIdx == self.HistoryIndex then return end
    self.HistoryIndex = newIdx

    if newIdx > #cache then
        self.OverlayEdit:SetText("")
    else
        local item = cache[newIdx]
        local text = ""
        local chatType = nil
        local target = nil

        if type(item) == "table" then
            text = item.text or ""
            chatType = item.chatType
            target = item.target
        else
            text = item or ""
        end

        self.OverlayEdit:SetText(text)
        self.OverlayEdit:SetCursorPosition(#text)

        -- Context switching: restore channel if recorded.
        if chatType then
            self.ChatType = chatType
            self.Target = target

            if chatType == "CHANNEL" and target then
                local num = tonumber(target)
                if num then
                    self.ChannelName = ResolveChannelName(num)
                end
            else
                self.ChannelName = nil
            end
            self:RefreshLabel()
        end
        -- If no chatType (legacy or slash command), keep current channel.
    end
end

-- ---------------------------------------------------------------------------
-- Slash command forwarding
-- ---------------------------------------------------------------------------

--- Forward an unrecognised slash command to Blizzard.
function EditBox:ForwardSlashCommand(text)
    if not self.OrigEditBox then return end

    -- If chat is locked down (combat/m+ lockdown), save draft and handoff
    if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
        self:HandoffToBlizzard()
        return
    end

    local chosenCT = self:GetResolvedChatType(self.ChatType)
    local eb = self.OrigEditBox
    local overrideCT = CHATTYPE_TO_OVERRIDE_KEY[chosenCT] or chosenCT

    local currentTell = eb:GetAttribute("tellTarget")
    local diffTell = true
    pcall(function() diffTell = (currentTell ~= self.Target) end)

    local diffChannel = (eb:GetAttribute("channelTarget") ~= self.Target)

    eb:SetAttribute("chatType", overrideCT)
    if overrideCT == "WHISPER" or overrideCT == "BN_WHISPER" then
        if diffTell then
            if YapperTable.Utils and YapperTable.Utils:IsSecret(self.Target) then
                -- Bypass SetAttribute taint by letting Blizzard cleanly parse the target.
                eb:SetAttribute("chatType", "SAY")
                eb:SetAttribute("tellTarget", nil)
                eb:SetAttribute("channelTarget", nil)
                self._ignoreSetText = true
                eb:SetText("/r " .. text)
                self._ignoreSetText = false
                ChatEdit_SendText(eb)
                return
            end
            eb:SetAttribute("tellTarget", self.Target)
        end
        eb:SetAttribute("channelTarget", nil)
    elseif overrideCT == "CHANNEL" then
        eb:SetAttribute("tellTarget", nil)
        if diffChannel then
            eb:SetAttribute("channelTarget", self.Target)
        end
    else
        eb:SetAttribute("tellTarget", nil)
        eb:SetAttribute("channelTarget", nil)
    end
    if self.Language then
        self.OrigEditBox:SetAttribute("language", self.Language)
    else
        self.OrigEditBox:SetAttribute("language", nil)
    end

    self._ignoreSetText = true
    eb:SetText(text)
    self._ignoreSetText = false
    ChatEdit_SendText(eb)

    -- Clean up in case ChatEdit_SendText didn't close it.
    if self.OrigEditBox:IsShown() then
        self.OrigEditBox:SetText("")
        self.OrigEditBox:Deactivate()
    end
end

-- ---------------------------------------------------------------------------
-- Hook into Blizzard editboxes (taint-free)
-- ---------------------------------------------------------------------------

function EditBox:HookBlizzardEditBox(blizzEditBox)
    if self.HookedBoxes[blizzEditBox] then return end
    self.HookedBoxes[blizzEditBox] = true
    self._attrCache[blizzEditBox] = {}

    -- Capture chatType / tellTarget / channelTarget as they're set.
    -- BNet whisper: attributes arrive BEFORE Show.
    -- WoW whisper:  attributes arrive one frame AFTER Show (deferred).
    -- The live-update path below handles the deferred case.
    hooksecurefunc(blizzEditBox, "SetAttribute", function(eb, key, value)
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
        -- it no longer syncs back to Blizzard's editbox.
        if self.OrigEditBox == eb
            and self.Overlay and self.Overlay:IsShown() then
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
                if not isInsert and IsWhisperSlashPrefill(text) then
                    local preTarget, preRemainder = ParseWhisperSlash(text)
                    if preTarget then
                        self._ignoreSetText = nil
                        self.ChatType = "WHISPER"
                        self.Target   = preTarget
                        self._ignoreSetText = true
                        targetBox:SetText(preRemainder or "")
                        self._ignoreSetText = nil
                        eb:SetText("")
                        self:RefreshLabel()
                        return
                    end
                end

                local cur = targetBox:GetText() or ""
                if text ~= cur then
                    targetBox:SetText(text)
                end
            end
            -- Wipe the Blizzard source box so it doesn't hold stale data
            eb:SetText("")
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
                return
            end
            if UserBypassingYapper() then
                return
            end
            if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
                return
            end
            if not blizzEditBox:IsShown() then
                return
            end

            -- PRE_EDITBOX_SHOW filter: external addons (including WIMBridge)
            -- can inspect the pending open and cancel it.
            if YapperTable.API then
                local filterCT = blizzEditBox.GetAttribute and blizzEditBox:GetAttribute("chatType") or "SAY"
                local filterTarget
                if filterCT == "WHISPER" and blizzEditBox.GetAttribute then
                    filterTarget = blizzEditBox:GetAttribute("tellTarget")
                elseif filterCT == "CHANNEL" and blizzEditBox.GetAttribute then
                    filterTarget = blizzEditBox:GetAttribute("channelTarget")
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
                    return
                end
            end

            -- Open Yapper's overlay
            self:Show(blizzEditBox)
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
            if self._justClosed then
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
            local overlayAlreadyShown = (self.Overlay and self.Overlay:IsShown())
                and (chatFrame == nil)

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

                -- Ghost pattern: Blizzard's sticky-chat restore fires Shows on
                -- the editbox BEFORE OpenChat.  A user pressing Enter fires
                -- OpenChat directly (CHAT_FOCUS_OVERRIDE routes it without a
                -- preceding Show).  If we saw a Show while overlay was hidden,
                -- this OpenChat is part of the ghost — suppress it.
                if self._ghostShowDetected and not overlayAlreadyShown then
                    self._ghostShowDetected = nil
                    self._openingWatchdog = false
                    return
                end

                if overlayAlreadyShown then
                    -- Overlay already shown (TRP3 case): just reclaim focus immediately
                    if self.OverlayEdit then
                        self.OverlayEdit:SetFocus()
                    end
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

            -- For all other cases (slash-starting text, specific chatFrame opens, etc.)
            -- just signal the watchdog so ForwardTextToYapper can route to the overlay
            -- while it isn't shown yet. Do NOT call Show() or pre-populate
            -- _pendingOpenChatText here — the blizzard editbox Show() hook handles
            -- opening the overlay on the next frame, by which point the physical key
            -- char has already been consumed by the blizzard editbox, not ours.
            --
            -- Exception: tab clicks (chatFrame ~= nil) should NOT open Yapper if it's closed.
            -- If Yapper is already open, we still set the watchdog so text routing works.
            if chatFrame ~= nil then
                -- Tab click case
                if self.Overlay and self.Overlay:IsShown() then
                    -- Yapper is open: allow text routing via watchdog
                    self._openingWatchdog = true
                else
                    -- Yapper is closed: suppress the open
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
                editBox.ChatType    = switch.chatType
                editBox.Target      = switch.target
                editBox.ChannelName = switch.channelName
                if switch.language then editBox.Language = switch.language end
                local newEditBox = chatFrame.editBox
                if newEditBox and newEditBox ~= editBox.OrigEditBox then
                    -- Swap proxy target if in proxy mode
                    local cfg = YapperTable.Config and YapperTable.Config.EditBox
                    local isProxy = cfg and cfg.UseBlizzardSkinProxy == true and cfg.UseLegacyCloneProxy ~= true

                    if isProxy and editBox.RestoreProxyMode then
                        pcall(function() editBox:RestoreProxyMode() end)
                    end

                    editBox.OrigEditBox = newEditBox
                    
                    if isProxy and editBox.ApplyProxyMode then
                        pcall(function() editBox:ApplyProxyMode(newEditBox) end)
                    end
                    
                    if newEditBox.chatFrame then
                        editBox.OverlayEdit.chatFrame = newEditBox.chatFrame
                        if editBox.ChannelLabel then
                            editBox.ChannelLabel.chatFrame = newEditBox.chatFrame
                        end
                    end
                end
                editBox:RefreshLabel()
                YapperTable.Utils:VerbosePrint("Applied tab switch immediately: chatType="..tostring(switch.chatType).." target="..tostring(switch.target))
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
                -- Non-whisper tab: restore from session-only per-tab memory.
                local key = chatFrame.GetName and chatFrame:GetName()
                local mem = key and editBox._tabChannelMemory[key]
                if mem and mem.chatType then
                    ApplyOrStashSwitch(chatFrame, {
                        chatType    = mem.chatType,
                        target      = mem.target,
                        channelName = mem.channelName,
                        language    = mem.language,
                    })
                end
            end
        end)
        self._tabClickHooked = true
    end
end

-- ---------------------------------------------------------------------------
-- Public callbacks
-- ---------------------------------------------------------------------------

--- Called when the user sends a non-slash message (Enter).
--- Signature: fn(text, chatType, language, target)
