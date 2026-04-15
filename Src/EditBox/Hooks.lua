--[[
    EditBox/Hooks.lua
    Show/Hide lifecycle, Blizzard handoff, live config application,
    label refresh, channel cycling, history navigation, slash forwarding,
    and the Blizzard editbox hook integration (HookBlizzardEditBox,
    HookAllChatFrames).
]]

local _, YapperTable = ...
local EditBox        = YapperTable.EditBox

-- Re-localise shared helpers from hub.
local SLASH_MAP                = EditBox._SLASH_MAP
local TAB_CYCLE                = EditBox._TAB_CYCLE
local LABEL_PREFIXES           = EditBox._LABEL_PREFIXES
local GROUP_CHAT_TYPES         = EditBox._GROUP_CHAT_TYPES
local CHATTYPE_TO_OVERRIDE_KEY = EditBox._CHATTYPE_TO_OVERRIDE_KEY
local IsWhisperSlashPrefill    = EditBox.IsWhisperSlashPrefill
local ParseWhisperSlash        = EditBox.ParseWhisperSlash
local GetLastTellTargetInfo    = EditBox.GetLastTellTargetInfo
local SetFrameFillColour       = EditBox.SetFrameFillColour

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
    self:CreateOverlay()

    local openedFromBnetTransition   = self._nextShowFromBnetTransition == true
    self._nextShowFromBnetTransition = false
    self._openedFromBnetTransition   = openedFromBnetTransition

    self.OrigEditBox                 = origEditBox

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

    local cache                      = self._attrCache[origEditBox] or {}
    local blizzType                  = cache.chatType
    local blizzTell                  = cache.tellTarget
    local blizzChan                  = cache.channelTarget
    local blizzLang                  = cache.language or (origEditBox and origEditBox.languageID)
    local blizzText                  = origEditBox and origEditBox.GetText and origEditBox:GetText()

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
    local blizzHasTarget = ((blizzType == "WHISPER" or blizzType == "BN_WHISPER")
            and blizzTell and blizzTell ~= "")
        or (blizzType == "CHANNEL" and blizzChan and blizzChan ~= "")

    -- Priority for picking the channel on open:
    --   1. Blizzard explicitly provided a whisper/channel target (reply key,
    --      name-click, Contacts list, etc.) — always honour it.
    --   2. Lockdown draft — restore the channel the user was on mid-combat.
    --   3. LastUsed sticky — remember the last channel the user chose.
    --   4. Blizzard's editbox type (no specific target) or SAY as fallback.
    if blizzHasTarget and not self._lockdown.savedDraft then
        self.ChatType = blizzType
        self.Language = blizzLang or nil
        self.Target   = blizzTell or blizzChan or nil
    elseif (self.LastUsed and self.LastUsed.chatType) and not self._lockdown.savedDraft then
        self.ChatType = self.LastUsed.chatType
        self.Language = blizzLang or self.LastUsed.language or nil
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

    -- Label width: dynamically size to fit the label text but cap at
    -- ~28% of the editbox.  Leave a minimum typing area of 80px.
    local ebWidth = origEditBox:GetWidth() or 350
    local labelText = BuildLabelText(self.ChatType, self.Target, self.ChannelName)
    UpdateLabelBackgroundForText(self, labelText)

    -- If you're looking for text colour here, it's set by RefreshLabel() to match the active channel.
    -- CTFL+F, friend.

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
    pcall(function()
        -- Wear Blizzard's skin.
        self:AttachBlizzardSkinProxy(origEditBox, finalH)
    end)

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
    if not blizzHasTarget and YapperTable.History then
        local text, draftType, draftTarget = YapperTable.History:GetDraft()
        if text then
            draftText = text
            if draftType then self.ChatType = draftType end
            if draftTarget then self.Target = draftTarget end
            YapperTable.History:MarkDirty(false)
            YapperTable.Utils:VerbosePrint("Draft recovered: " .. #text .. " chars.")
        end
    end

    -- Carry over any text Blizzard pre-populated (chat links, etc.).
    -- We also store any raw text passed through ChatFrameUtil.OpenChat in case
    -- Blizzard doesn't set it on the editbox immediately.
    local pending = self._pendingOpenChatText
    self._pendingOpenChatText = nil

    if not draftText and pending and pending ~= "" then
        if not (blizzHasTarget and IsWhisperSlashPrefill(pending)) then
            local preTarget, preRemainder = ParseWhisperSlash(pending)
            if preTarget and not blizzHasTarget then
                self.ChatType = "WHISPER"
                self.Target = preTarget
                draftText = preRemainder
            else
                draftText = pending
            end
        end
    elseif not draftText and blizzText and blizzText ~= "" then
        if not (blizzHasTarget and IsWhisperSlashPrefill(blizzText)) then
            local preTarget, preRemainder = ParseWhisperSlash(blizzText)
            if preTarget and not blizzHasTarget then
                self.ChatType = "WHISPER"
                self.Target = preTarget
                draftText = preRemainder
            else
                draftText = blizzText
            end
        end
    end

    self.OverlayEdit:SetText(draftText or "")
    if draftText then
        self.OverlayEdit:SetCursorPosition(#draftText)
    end
    self:RefreshLabel()
    overlay:Show()
    self.OverlayEdit:SetFocus()

    -- Clear Blizzard's backing editbox to avoid stale carryover on next open.
    if origEditBox and origEditBox.SetText then
        origEditBox:SetText("")
    end

    if YapperTable.API then
        YapperTable.API:Fire("EDITBOX_SHOW", self.ChatType, self.Target)
    end
end

function EditBox:Hide()
    local prevOrig = self.OrigEditBox
    self._overlayUnfocused = false

    -- NOTE: DetachBlizzardSkinProxy() is intentionally NOT called here.
    -- Proxy textures are children of the overlay frame; they hide automatically
    -- when the overlay hides and reappear when it shows again.  Calling Detach
    -- on every close would accumulate dead texture objects because WoW has no
    -- texture-destroy API — each DetachBlizzardSkinProxy call nil-refs the Lua
    -- table but the C-side texture objects remain on the frame forever.

    if self.Overlay then
        self.Overlay:Hide()
    end
    self.OverlayEdit:ClearFocus()
    self.OrigEditBox = nil

    -- Clean up any active lockdown timers to prevent "ghost" handoffs
    -- if the user finished their post normally or escaped out.
    self:ClearLockdownState()
    self._lockdown.handedOff = false

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

    -- EDITBOX_HIDE callback: notify external addons.
    if YapperTable.API then
        YapperTable.API:Fire("EDITBOX_HIDE")
    end
end

--- Save draft, close overlay, and notify during lockdown.
function EditBox:HandoffToBlizzard(silent)
    if not self.Overlay or not self.Overlay:IsShown() then
        YapperTable.Utils:DebugPrint("HandoffToBlizzard called but overlay hidden. Skipping.")
        return
    end
    YapperTable.Utils:DebugPrint("Executing HandoffToBlizzard...")
    local text = self.OverlayEdit and self.OverlayEdit:GetText() or ""

    -- Centralised lockdown cleanup (cancels timers/tickers).
    self:ClearLockdownState()

    -- Save as dirty draft for recovery on next open.
    if text ~= "" and YapperTable.History then
        YapperTable.History:SaveDraft(self.OverlayEdit)
        YapperTable.History:MarkDirty(true)
        -- Mark that this draft was saved due to lockdown so callers
        -- can decide whether to restore it to Blizzard's editbox.
        self._lockdown.savedDraft = true
    end

    -- OnHide won't double-save because _closedClean is true.
    self._closedClean = true

    -- Close overlay and mark the draft as handed off to Blizzard's flow.
    if self.OverlayEdit then
        self.OverlayEdit:SetText("")
    end
    self:Hide()

    self._lockdown.handedOff = true
    if not silent then
        YapperTable.Utils:Print("info",
            "Chat in lockdown — your post has been saved. Press Enter after lockdown ends to continue.")
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
    local overrides = cfg.ChannelColorOverrides
    local channelColors = cfg.ChannelTextColors

    if currentKey and type(channelColors) == "table"
        and type(channelColors[currentKey]) == "table" then
        local own = channelColors[currentKey]
        if type(own.r) == "number" and type(own.g) == "number" and type(own.b) == "number" then
            resolvedR, resolvedG, resolvedB = own.r, own.g, own.b
        end
    end

    if currentKey and type(masterKey) == "string" and type(overrides) == "table"
        and masterKey ~= "" and currentKey ~= masterKey and overrides[currentKey] == true then
        if type(channelColors) == "table"
            and type(channelColors[masterKey]) == "table"
            and type(channelColors[masterKey].r) == "number"
            and type(channelColors[masterKey].g) == "number"
            and type(channelColors[masterKey].b) == "number" then
            resolvedR = channelColors[masterKey].r
            resolvedG = channelColors[masterKey].g
            resolvedB = channelColors[masterKey].b
        elseif ChatTypeInfo and ChatTypeInfo[masterKey] then
            local info = ChatTypeInfo[masterKey]
            resolvedR = info.r or resolvedR
            resolvedG = info.g or resolvedG
            resolvedB = info.b or resolvedB
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
    if theme and type(theme.channelTextColors) == "table" and currentKey then
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
end

--- Save selection for stickiness across show/hide.
function EditBox:PersistLastUsed()
    -- Don't make YELL sticky — but don't clear LastUsed either,
    -- so we restore to whatever was sticky before YELL.
    if self.ChatType == "YELL" then
        return
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
            return
        end
    end

    self.LastUsed.chatType = self.ChatType
    self.LastUsed.target   = self.Target
    self.LastUsed.language = self.Language
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
        self.OrigEditBox:Hide()
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
        if key == "chatType" and value ~= "BN_WHISPER"
            and (not self.Overlay or not self.Overlay:IsShown())
            and eb:IsShown() then
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

                    if savedEB and savedEB.Hide and savedEB:IsShown() then
                        savedEB:Hide()
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
        if self.OrigEditBox == eb and self.Overlay and self.Overlay:IsShown() then
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

    -- mirror Blizzard's SetText while we're overlaid so slash / prefill works
    hooksecurefunc(blizzEditBox, "SetText", function(eb, text)
        if self.OrigEditBox == eb and self.Overlay and self.Overlay:IsShown()
            and self.OverlayEdit and not self._ignoreSetText then
            local cur = self.OverlayEdit:GetText() or ""
            if text and text ~= "" and text ~= cur then
                self.OverlayEdit:Insert(text)
            end
        end
    end)

    -- Mirror language changes made via the chat menu button (SetGameLanguage
    -- stores on .languageID)
    if blizzEditBox.SetGameLanguage then
        hooksecurefunc(blizzEditBox, "SetGameLanguage", function(eb, language, languageId)
            if self.OrigEditBox == eb then
                self.Language = languageId or language or nil
                self.LastUsed.language = self.Language
            end
        end)
    end

    hooksecurefunc(blizzEditBox, "Show", function(eb)
        local ebName = eb:GetName()
        if self._suppressNextShowFor == ebName then
            self._suppressNextShowFor = nil
            return
        end

        if UserBypassingYapper() then
            if not BypassEditBox() then
                SetBypassEditBox(ebName)
            end
            if BypassEditBox() == ebName then
                SetUserBypassingYapper(false)
                return
            end
        end

        -- While bypass session is active for this editbox, never overlay it.
        if BypassEditBox() and BypassEditBox() == ebName then
            return
        end

        if self.Overlay and self.Overlay:IsShown() then
            -- Overlay already visible — suppress Blizzard's editbox and
            -- reclaim focus if the overlay was in unfocused (game-passthrough)
            -- mode. The Enter keypress that triggered Blizzard's Show is
            -- consumed here; it never reaches our OnEnterPressed.
            if self._overlayUnfocused and self.OverlayEdit then
                self.OverlayEdit:SetFocus()
            end
            C_Timer.After(0, function()
                if eb and eb.Hide and eb:IsShown() then eb:Hide() end
            end)
            return
        end

        -- If the user Escaped out of a BNet whisper, don't re-open ours.
        if self._bnetDismissed then
            self._bnetDismissed = false
            return
        end

        -- In lockdown Blizzard's untainted box can still send; leave it alone.
        -- In DEBUG mode, we only bypass Yapper if the handoff has actually occurred.
        local isLockdown = YapperTable.Utils and YapperTable.Utils:IsChatLockdown()
        local isDebugBypass = YapperTable.Config.System.DEBUG and self._lockdown.handedOff

        if isLockdown or isDebugBypass then
            if not self._lockdown.showHandled then
                self._lockdown.showHandled = true
                local chosenCT = self.ChatType or (self.LastUsed and self.LastUsed.chatType) or "SAY"
                chosenCT = self:GetResolvedChatType(chosenCT)

                local currentTell = eb:GetAttribute("tellTarget")
                local diffTell = true
                pcall(function() diffTell = (currentTell ~= self.Target) end)

                local diffChannel = (eb:GetAttribute("channelTarget") ~= self.Target)

                eb:SetAttribute("chatType", chosenCT)
                if chosenCT == "WHISPER" or chosenCT == "BN_WHISPER" then
                    if diffTell then
                        if YapperTable.Utils and YapperTable.Utils:IsSecret(self.Target) then
                            eb:SetAttribute("chatType", "SAY")
                            eb:SetAttribute("tellTarget", nil)
                            eb:SetAttribute("channelTarget", nil)
                            self._ignoreSetText = true
                            eb:SetText("/r " .. (self.OverlayEdit:GetText() or ""))
                            self._ignoreSetText = false
                            return
                        end
                        eb:SetAttribute("tellTarget", self.Target)
                    end
                    eb:SetAttribute("channelTarget", nil)
                elseif chosenCT == "CHANNEL" then
                    eb:SetAttribute("tellTarget", nil)
                    if diffChannel then
                        eb:SetAttribute("channelTarget", self.Target)
                    end
                else
                    eb:SetAttribute("tellTarget", nil)
                    eb:SetAttribute("channelTarget", nil)
                end
                if self.Language then
                    eb:SetAttribute("language", self.Language)
                else
                    eb:SetAttribute("language", nil)
                end
            end
            return
        end


        -- Seed LastUsed from Blizzard's editbox so the lockdown fallback
        -- opens on the correct channel. Only seeds when LastUsed is empty —
        -- once the user has made an explicit choice (send or Tab-cycle) we
        -- never overwrite it from here.
        local c = self._attrCache[eb] or {}
        local ct = c.chatType or (eb.GetAttribute and eb:GetAttribute("chatType"))
        if ct and not self.LastUsed.chatType then
            local lastTarget = nil
            if ct == "WHISPER" or ct == "BN_WHISPER" then
                lastTarget = c.tellTarget or (eb.GetAttribute and eb:GetAttribute("tellTarget"))
            elseif ct == "CHANNEL" then
                lastTarget = c.channelTarget or (eb.GetAttribute and eb:GetAttribute("channelTarget"))
            end
            local lastLang         = c.language or eb.languageID or (eb.GetAttribute and eb:GetAttribute("language"))
            self.LastUsed.chatType = ct
            self.LastUsed.target   = lastTarget
            self.LastUsed.language = lastLang
        end

        -- PreShowCheck: lets Queue suppress the overlay to grab the event.
        if self.PreShowCheck and self.PreShowCheck(eb) then
            C_Timer.After(0, function()
                if eb and eb.Hide and eb:IsShown() then
                    eb:Hide()
                end
            end)
            return
        end

        -- PRE_EDITBOX_SHOW filter: external addons (including WIMBridge)
        -- can inspect the pending open and cancel it.
        if YapperTable.API then
            local cache = self._attrCache[eb] or {}
            local filterCT = cache.chatType or (eb.GetAttribute and eb:GetAttribute("chatType"))
            local filterTarget = cache.tellTarget or cache.channelTarget
            local result = YapperTable.API:RunFilter("PRE_EDITBOX_SHOW", {
                chatType = filterCT,
                target   = filterTarget,
            })
            if result == false then
                return
            end
        end

        -- Fix for tab-switching causing overlay to activate.
        -- Defer one frame so we can check HasFocus; only overlay
        -- when the user actually pressed Enter to chat.
        C_Timer.After(0, function()
            if not eb or not eb:IsShown() then return end
            if not eb.HasFocus or not eb:HasFocus() then return end
            if self.Overlay and self.Overlay:IsShown() then return end

            self:Show(eb)

            -- Hide Blizzard's editbox next frame.
            C_Timer.After(0, function()
                if eb and eb.IsShown and eb:IsShown() and eb.Hide then
                    eb:Hide()
                end
            end)
        end)
    end)

    -- Track when the user Escapes out of a BNet whisper so we don't
    -- immediately re-open Yapper when Blizzard re-shows the editbox.
    hooksecurefunc(blizzEditBox, "Hide", function(eb)
        -- Bypass session ends when Blizzard's editbox closes.
        local ebName = eb:GetName()
        if BypassEditBox() == ebName then
            SetBypassEditBox(nil)
            SetUserBypassingYapper(false)
        end

        if self._bnetEditBox == eb then
            self._bnetEditBox   = nil
            self._bnetDismissed = true
            -- Clear on next frame so only the immediately-following Show
            -- is suppressed, not future ones.
            C_Timer.After(0, function()
                self._bnetDismissed = false
            end)
        end
    end)

    -- clear bypass if focus leaves the bypassed editbox without a Hide.
    if blizzEditBox and blizzEditBox.HookScript then
        blizzEditBox:HookScript("OnEditFocusLost", function(eb)
            if BypassEditBox() == eb:GetName() then
                SetBypassEditBox(nil)
                SetUserBypassingYapper(false)
            end
        end)
    end
end

--- Hook all NUM_CHAT_WINDOWS editboxes.  Call once on init.
function EditBox:HookAllChatFrames()
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
        hooksecurefunc(ChatFrameUtil, "OpenChat", function(text, ...)
            if type(text) == "string" and text ~= "" then
                -- Store on the instance so EditBox:Show can prefer it.
                self._pendingOpenChatText = text
            end
        end)
        -- NOTE: Do NOT replace ChatFrameUtil.OpenChat with a tainted wrapper.
        -- Doing so taints the arguments passed to Blizzard's secure code,
        -- causing strlenutf8 / UpdateHeader failures post-combat.
        -- The UIParent guard is already applied in EditBox:Show() and the
        -- UIParent OnHide hook in SetupOverlayScripts.
        self._openChatHooked = true
    end
end

-- ---------------------------------------------------------------------------
-- Public callbacks
-- ---------------------------------------------------------------------------

--- Called when the user sends a non-slash message (Enter).
--- Signature: fn(text, chatType, language, target)
