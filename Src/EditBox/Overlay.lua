--[[
    EditBox/Overlay.lua
    Overlay visual refresh (fills, text colors, borders, shadows),
    channel name resolution, label sizing/font fitting, and the main
    CreateOverlay function that builds the overlay frame hierarchy.
]]

local _, YapperTable = ...
local EditBox        = YapperTable.EditBox

-- Re-localise shared helpers from hub.
local SetFrameFillColour = EditBox.SetFrameFillColour
local LABEL_PREFIXES     = EditBox._LABEL_PREFIXES

-- Re-localise Lua globals.
local type       = type
local pairs      = pairs
local tostring   = tostring
local tonumber   = tonumber
local math_max   = math.max
local math_min   = math.min
local math_floor = math.floor
local strmatch   = string.match
local strlower   = string.lower
local table_insert = table.insert

local function RefreshOverlayVisuals(editBox, cfg, borderActive, pad)
    local overlay = editBox.Overlay
    local labelBg = editBox.LabelBg
    local edit    = editBox.OverlayEdit
    if not overlay or not labelBg or not edit then return end

    local inputBg     = cfg.InputBg or {}
    local labelCfg    = cfg.LabelBg or {}
    local borderCfg   = cfg.BorderColor or {}
    local textCfg     = cfg.TextColor or {}
    local activeTheme = YapperTable.Theme and YapperTable.Theme:GetTheme()
    local rounded     = cfg.RoundedCorners == true
    local shadow      = cfg.Shadow == true

    if activeTheme then
        if activeTheme.allowRoundedCorners == false then rounded = false end
        if activeTheme.allowDropShadow == false then shadow = false end
    end

    -- Blizzard skin proxy overrides visual customizations
    if cfg.UseBlizzardSkinProxy == true then
        rounded = false
        shadow = false
    end

    local shadCol     = cfg.ShadowColor or { r = 0, g = 0, b = 0, a = 0.5 }
    local shadSz      = cfg.ShadowSize or 4

    -- When the Blizzard skin proxy is active, make the overlay background fully
    -- transparent so the cloned skin textures show through.
    local proxyActive = editBox._skinProxyTextures
    local fillR, fillG, fillB, fillA
    if proxyActive then
        fillR, fillG, fillB, fillA = 0, 0, 0, 0
        -- Re-tint cloned textures with the user's backdrop colour so live
        -- config changes are reflected immediately.
        editBox:TintSkinProxyTextures(inputBg.r, inputBg.g, inputBg.b, inputBg.a)
    else
        fillR = inputBg.r or 0.05
        fillG = inputBg.g or 0.05
        fillB = inputBg.b or 0.05
        fillA = inputBg.a or 1.0
    end

    -- Input background fill + dynamic inset so it never bleeds outside the border.
    SetFrameFillColour(overlay, fillR, fillG, fillB, fillA, rounded)
    local activeFill = rounded and overlay._yapperRoundedFill or overlay._yapperSolidFill
    if activeFill then
        if proxyActive then
            -- Keep hidden; cloned skin textures replace the solid fill.
            activeFill:Hide()
        else
            activeFill:Show()
            activeFill:ClearAllPoints()
            if pad > 0 then
                activeFill:SetPoint("TOPLEFT", overlay, "TOPLEFT", pad, -pad)
                activeFill:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -pad, pad)
            else
                activeFill:SetAllPoints(overlay)
            end
        end
    end

    -- Label background fill + position (inset matches fill when border active).
    -- Hidden when skin proxy is active so cloned skin textures show.
    if proxyActive then
        SetFrameFillColour(labelBg, 0, 0, 0, 0, rounded)
        if labelBg._yapperSolidFill then labelBg._yapperSolidFill:Hide() end
        if labelBg._yapperRoundedFill then labelBg._yapperRoundedFill:Hide() end
    else
        -- Force labelBg to use solid fill for better readability and reliable rendering.
        SetFrameFillColour(labelBg,
            labelCfg.r or 0.06, labelCfg.g or 0.06, labelCfg.b or 0.06, labelCfg.a or 1.0, false)
        local labFill = labelBg._yapperSolidFill
        if labFill then labFill:Show() end
    end
    labelBg:ClearAllPoints()
    local LEFT_MARGIN = 6 -- fixed inset from the overlay's left edge
    labelBg:SetPoint("TOPLEFT", overlay, "TOPLEFT", pad + LEFT_MARGIN, -pad)
    labelBg:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", pad + LEFT_MARGIN, pad)

    -- EditBox anchors: left edge follows label; right edge inset to avoid border.
    edit:ClearAllPoints()
    edit:SetPoint("TOPLEFT", labelBg, "TOPRIGHT", 0, 0)
    edit:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -pad, pad)

    -- Text colour.
    if edit.SetTextColor then
        edit:SetTextColor(textCfg.r or 1, textCfg.g or 1, textCfg.b or 1, textCfg.a or 1)
    end

    -- Border visibility and colour.
    -- Hidden when Blizzard skin proxy is active (the cloned skin provides the border).
    if overlay.Border then
        if proxyActive then
            overlay.Border:Hide()
        elseif borderActive then
            overlay.Border:SetBackdropBorderColor(
                borderCfg.r or 0.4, borderCfg.g or 0.4, borderCfg.b or 0.4, borderCfg.a or 1)
            overlay.Border:Show()
        else
            overlay.Border:Hide()
        end
    end

    -- Shadow Generation
    if shadow then
        if not overlay._yapperShadowLayer then
            overlay._yapperShadowLayer = CreateFrame("Frame", nil, overlay)
            -- Push it strictly behind the overlay background to prevent bleed-over
            overlay._yapperShadowLayer:SetFrameLevel(math.max(0, overlay:GetFrameLevel() - 1))
            overlay._yapperShadowLayer:SetAllPoints(overlay)
            overlay._yapperShadows = {}
            for i = 1, 3 do
                local stex = overlay._yapperShadowLayer:CreateTexture(nil, "BACKGROUND")
                table.insert(overlay._yapperShadows, stex)
            end
        end
        overlay._yapperShadowLayer:Show()

        for i, stex in ipairs(overlay._yapperShadows) do
            local offset = (i / 3) * shadSz
            stex:ClearAllPoints()
            stex:SetPoint("TOPLEFT", overlay, "TOPLEFT", -offset, offset)
            stex:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", offset + (pad / 2), -offset - (pad / 2))
            local alphaBase = shadCol.a or 0.5
            local falloff = { 0.5, 0.3, 0.15 }
            stex:SetColorTexture(shadCol.r or 0, shadCol.g or 0, shadCol.b or 0, alphaBase * (falloff[i] or 0.1))
        end
    else
        if overlay._yapperShadowLayer then
            overlay._yapperShadowLayer:Hide()
        end
    end
end


-- Resolve a numeric channel ID to its display name, or nil.
local function ResolveChannelName(id)
    id = tonumber(id)
    if not id or id == 0 then return nil end
    if not GetChannelName then return nil end

    local cid, cname = GetChannelName(id)
    if tonumber(cid) == 0 then return nil end
    if type(cname) == "string" and cname ~= "" then
        -- community channels are reported as "Community:<clubId>:<streamId>";
        -- let Blizzard turn that into a user-friendly name if it can.
        if ChatFrameUtil and ChatFrameUtil.ResolveChannelName then
            -- ResolveChannelName expects the raw community channel string.
            local resolved = ChatFrameUtil.ResolveChannelName(cname)
            if resolved and resolved ~= cname then
                return resolved
            end
        end

        -- Fallback: mimic old logic that manually queries C_Club for a name.
        if YapperTable and YapperTable.Router then
            local isClub, clubId, streamId = YapperTable.Router:DetectCommunityChannel(id)
            if isClub and clubId then
                local display = "Community"
                if _G.C_Club and _G.C_Club.GetClubInfo then
                    local info = _G.C_Club.GetClubInfo(clubId)
                    if info and info.name and info.name ~= "" then
                        display = info.name
                    end
                end
                if streamId then
                    display = display .. " #" .. streamId
                end
                return display
            end
        end
        return cname
    end
    return nil
end

-- Build the label string and colour for a given chat mode.
local function BuildLabelText(chatType, target, channelName)
    local label
    if chatType == "BN_WHISPER" and target then
        local display = target
        if YapperTable and YapperTable.Router and YapperTable.Router.ResolveBnetDisplay then
            display = YapperTable.Router:ResolveBnetDisplay(target) or target
        end
        label = "To " .. display .. ":"
    elseif chatType == "WHISPER" and target then
        label = "To " .. target .. ":"
    elseif chatType == "EMOTE" then
        -- Show the player's character name for emotes.
        local name = UnitName and UnitName("player") or "You"
        label = name
    elseif chatType == "CHANNEL" then
        if channelName and channelName ~= "" then
            label = channelName
        elseif target then
            label = "Channel #" .. tostring(target)
        else
            label = "Channel"
        end
        label = label .. ":"
    else
        local pretty = LABEL_PREFIXES[chatType]
        label = pretty or (chatType or "Say")
    end

    -- Colour from ChatTypeInfo.
    local r, g, b = 1, 0.82, 0 -- gold fallback
    if chatType and ChatTypeInfo and ChatTypeInfo[chatType] then
        local info = ChatTypeInfo[chatType]
        r, g, b = info.r or r, info.g or g, info.b or b
    end

    return label, r, g, b
end

local function GetLabelUsableWidth(self)
    if not self or not self.LabelBg then return 80 end
    local rawWidth = self.LabelBg:GetWidth() or 100
    return math.max(40, rawWidth - 10)
end

local function ResetLabelToBaseFont(self)
    if not self or not self.ChannelLabel then return end
    if self.OverlayEdit and self.OverlayEdit.GetFont then
        local face, size, flags = self.OverlayEdit:GetFont()
        if face and size then
            self.ChannelLabel:SetFont(face, size, flags or "")
            return
        end
    end

    if self.OrigEditBox and self.OrigEditBox.GetFontObject then
        local fontObj = self.OrigEditBox:GetFontObject()
        if fontObj then
            self.ChannelLabel:SetFontObject(fontObj)
        end
    end
end

local function TruncateLabelToWidth(fontString, text, maxWidth)
    if not fontString or type(text) ~= "string" then
        return text
    end

    fontString:SetText(text)
    if (fontString:GetStringWidth() or 0) <= maxWidth then
        return text
    end

    local truncated = text
    while #truncated > 0 do
        truncated = truncated:sub(1, #truncated - 1)
        local candidate = truncated .. "..."
        fontString:SetText(candidate)
        if (fontString:GetStringWidth() or 0) <= maxWidth then
            return candidate
        end
    end

    return "..."
end

local function FitLabelFontToWidth(self, text, maxWidth)
    if not self or not self.ChannelLabel then return false end

    local fontString = self.ChannelLabel
    fontString:SetText(text)

    if (fontString:GetStringWidth() or 0) <= maxWidth then
        return true
    end

    local face, size, flags = fontString:GetFont()
    if not face or not size then
        return false
    end

    local minSize = 8
    local targetSize = math.floor(size)
    while targetSize > minSize do
        targetSize = targetSize - 1
        fontString:SetFont(face, targetSize, flags or "")
        fontString:SetText(text)
        if (fontString:GetStringWidth() or 0) <= maxWidth then
            return true
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Overlay creation
-- ---------------------------------------------------------------------------

local function UpdateLabelBackgroundForText(self, text)
    if not self or not self.LabelBg or not self.ChannelLabel then return end
    local cfg = YapperTable.Config.EditBox or {}
    local ebWidth = (self.OrigEditBox and self.OrigEditBox.GetWidth and self.OrigEditBox:GetWidth())
        or (self.Overlay and self.Overlay.GetWidth and self.Overlay:GetWidth())
        or 350
    local maxAllowed = math.floor(ebWidth * 0.28)
    local basePad = (cfg.LabelPadding and tonumber(cfg.LabelPadding)) or 20
    -- Temporarily set text to measure raw width using current font settings.
    self.ChannelLabel:SetText(text)
    local rawWidth = (self.ChannelLabel:GetStringWidth() or 0)
    -- pad label dynamically.
    local headroom = maxAllowed - rawWidth
    -- allow the padding to shrink very small so the edit text is close
    -- to the box when there's very little label text
    local padding  = math.max(2, math.min(basePad, headroom))
    local labelW   = math.ceil(rawWidth + padding)
    -- cap by configuration and available space
    if labelW > maxAllowed then labelW = maxAllowed end
    if labelW > (ebWidth - 80) then labelW = ebWidth - 80 end
    -- only a tiny floor so the bg doesn't fully disappear
    if labelW < 8 then labelW = 8 end
    self.LabelBg:SetWidth(labelW)
end


function EditBox:CreateOverlay()
    if self.Overlay then return end

    local cfg = YapperTable.Config.EditBox or {}
    local inputBg = cfg.InputBg or {}
    local labelCfg = cfg.LabelBg or {}

    -- Container frame — matches position/size of the original editbox.
    local frame = CreateFrame("Frame", "YapperOverlayFrame", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- Border frame (separate element so themes can recolour it independently).
    -- Hidden by default; shown/hidden in ApplyConfigToLiveOverlay when the active
    -- theme opts into a border.
    local BORDER_PAD = 6
    local borderFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    borderFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    borderFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    borderFrame:SetBackdrop({
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 8,
        insets = { left = BORDER_PAD, right = BORDER_PAD, top = BORDER_PAD, bottom = BORDER_PAD },
    })
    borderFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    borderFrame:Hide()           -- hidden until ApplyConfigToLiveOverlay decides based on active theme
    frame.Border    = borderFrame
    frame.BorderPad = BORDER_PAD -- read by ApplyConfigToLiveOverlay for fill inset

    -- Container background fill — always on the outer frame so ApplyConfigToLiveOverlay
    -- has a single predictable target.  Anchor is adjusted dynamically when the border
    -- is active (inset) vs hidden (full bleed).
    SetFrameFillColour(frame, inputBg.r or 0.05, inputBg.g or 0.05, inputBg.b or 0.05, inputBg.a or 1.0)

    -- ── Label background (left portion) ──────────────────────────────
    local labelBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    -- Initial anchors at zero inset; RefreshOverlayVisuals repositions on first show.
    labelBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    labelBg:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    labelBg:SetWidth(100) -- will be recalculated on show

    local labelFs = labelBg:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    labelFs:SetPoint("CENTER", labelBg, "CENTER", 0, 0)
    labelFs:SetJustifyH("CENTER")

    -- ── Input EditBox (right portion) ────────────────────────────────
    local edit = CreateFrame("EditBox", "YapperOverlayEditBox", frame)
    if edit.SetPropagateKeyboardInput then
        edit:SetPropagateKeyboardInput(false)
    end
    edit:SetFontObject(ChatFontNormal)
    edit:SetAutoFocus(false)
    edit:SetMultiLine(false)
    edit:SetMaxLetters(0)
    edit:SetMaxBytes(0)

    local tc = cfg.TextColor or {}
    edit:SetTextColor(tc.r or 1, tc.g or 1, tc.b or 1, tc.a or 1)
    edit:SetTextInsets(1, 6, 0, 0)

    -- Initial anchors at zero inset; RefreshOverlayVisuals repositions on first show.
    edit:SetPoint("TOPLEFT", labelBg, "TOPRIGHT", 0, 0)
    edit:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    -- Store references.
    self.Overlay       = frame
    self.OverlayEdit   = edit
    self.ChannelLabel  = labelFs
    self.LabelBg       = labelBg
    -- Also attach to the frame so external theming APIs can find them via the frame object.
    frame.OverlayEdit  = edit
    frame.ChannelLabel = labelFs
    frame.LabelBg      = labelBg

    -- make sure the overlay follows fullscreen-parent changes
    if YapperTable.Utils then
        YapperTable.Utils:MakeFullscreenAware(frame)
    end


    -- ── Wire up scripts ──────────────────────────────────────────────
    self:SetupOverlayScripts()

    if YapperTable.Spellcheck and type(YapperTable.Spellcheck.Bind) == "function" then
        YapperTable.Spellcheck:Bind(edit, frame)
    end

    -- Hook into SendChatMessage so we can capture and propagate chatType, language and target
    -- to Yapper for synchronisity.
    if not self._cChatInfoSendHooked then
        self._cChatInfoSendHooked = true
        if C_ChatInfo and C_ChatInfo.SendChatMessage then
            hooksecurefunc(C_ChatInfo, "SendChatMessage", function(message, chatType, language, target)
                if not chatType or chatType == "BN_WHISPER" then return end
                if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
                    -- Update the LastUsed vars
                    self.LastUsed.chatType = chatType
                    self.LastUsed.target = target
                    self.LastUsed.language = language

                    self.ChatType = chatType
                    self.Target = target
                    self.Language = language
                    if chatType == "CHANNEL" and target then
                        local num = tonumber(target)
                        if num then
                            self.ChannelName = ResolveChannelName(num)
                        else
                            self.ChannelName = nil
                        end
                    else
                        self.ChannelName = nil
                    end

                    self._lastSavedDuringLockdown = true
                end
            end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Script handlers
-- ---------------------------------------------------------------------------


-- Export visual/label locals for Hooks.lua & Handlers.lua.
EditBox._RefreshOverlayVisuals     = RefreshOverlayVisuals
EditBox._ResolveChannelName        = ResolveChannelName
EditBox._BuildLabelText            = BuildLabelText
EditBox._GetLabelUsableWidth       = GetLabelUsableWidth
EditBox._ResetLabelToBaseFont      = ResetLabelToBaseFont
EditBox._TruncateLabelToWidth      = TruncateLabelToWidth
EditBox._FitLabelFontToWidth       = FitLabelFontToWidth
EditBox._UpdateLabelBackgroundForText = UpdateLabelBackgroundForText
