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

    -- ---------------------------------------------------------------
    -- Proxy mode: the original Blizzard editbox is visible
    -- behind us (see EditBox:ApplyProxyMode). Hide every Yapper-supplied
    -- visual and only run the text/anchor positioning below.
    -- ---------------------------------------------------------------
    local isProxyMode = (cfg.UseBlizzardSkinProxy == true)
    if isProxyMode then
        if overlay._yapperSolidFill   then overlay._yapperSolidFill:Hide()   end
        if overlay._yapperRoundedFill then overlay._yapperRoundedFill:Hide() end
        if labelBg._yapperSolidFill   then labelBg._yapperSolidFill:Hide()   end
        if labelBg._yapperRoundedFill then labelBg._yapperRoundedFill:Hide() end
        if overlay.Border             then overlay.Border:Hide()             end
        if overlay._yapperShadowLayer then overlay._yapperShadowLayer:Hide() end

        -- Anchors: position labelBg + OverlayEdit but with zero pad (no Yapper border).
        labelBg:ClearAllPoints()
        local LEFT_MARGIN = 6
        labelBg:SetPoint("TOPLEFT", overlay, "TOPLEFT", LEFT_MARGIN, 0)
        labelBg:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", LEFT_MARGIN, 0)

        edit:ClearAllPoints()
        edit:SetPoint("TOPLEFT", labelBg, "TOPRIGHT", 0, 0)
        edit:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)

        if edit.SetTextColor then
            edit:SetTextColor(textCfg.r or 1, textCfg.g or 1, textCfg.b or 1, textCfg.a or 1)
        end

        -- Proxy mode: inherit the original editbox's text insets (top/bottom)
        -- so the text aligns with the native Blizzard skin.
        local origEB = editBox.OrigEditBox
        if origEB and origEB.GetTextInsets and edit.SetTextInsets then
            local _, _, origTop, origBottom = origEB:GetTextInsets()
            edit:SetTextInsets(1, 6, origTop or 0, origBottom or 0)
        end
        return
    end

    -- Non-proxy mode: restore Yapper's default text insets.
    if edit.SetTextInsets then
        edit:SetTextInsets(1, 6, 0, 0)
    end

    local shadCol     = cfg.ShadowColor or { r = 0, g = 0, b = 0, a = 0.5 }
    local shadSz      = cfg.ShadowSize or 4

    -- Input background fill + dynamic inset so it never bleeds outside the border.
    local fillR = inputBg.r or 0.05
    local fillG = inputBg.g or 0.05
    local fillB = inputBg.b or 0.05
    local fillA = inputBg.a or 1.0
    SetFrameFillColour(overlay, fillR, fillG, fillB, fillA, rounded)
    local activeFill = rounded and overlay._yapperRoundedFill or overlay._yapperSolidFill
    if activeFill then
        activeFill:Show()
        activeFill:ClearAllPoints()
        if pad > 0 then
            activeFill:SetPoint("TOPLEFT", overlay, "TOPLEFT", pad, -pad)
            activeFill:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -pad, pad)
        else
            activeFill:SetAllPoints(overlay)
        end
    end

    -- Label background fill + position (inset matches fill when border active).
    SetFrameFillColour(labelBg,
        labelCfg.r or 0.06, labelCfg.g or 0.06, labelCfg.b or 0.06, labelCfg.a or 1.0, false)
    local labFill = labelBg._yapperSolidFill
    if labFill then labFill:Show() end
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
    if overlay.Border then
        if borderActive then
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
            overlay._yapperShadowLayer:SetFrameLevel(math_max(0, overlay:GetFrameLevel() - 1))
            overlay._yapperShadowLayer:SetAllPoints(overlay)
            overlay._yapperShadows = {}
            for i = 1, 3 do
                local stex = overlay._yapperShadowLayer:CreateTexture(nil, "BACKGROUND")
                table_insert(overlay._yapperShadows, stex)
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
    local api = YapperTable and YapperTable.API
    if api and type(api.RunFilter) == "function" then
        local function DeepCopy(value)
            if type(value) ~= "table" then
                return value
            end
            local out = {}
            for k, v in pairs(value) do
                out[k] = DeepCopy(v)
            end
            return out
        end

        -- PRE_EDITBOX_LABEL is intentionally non-blocking:
        -- label resolution is a core UX path and must always produce a value.
        -- Filters may mutate payload.label, but cancellation is ignored.
        -- We snapshot the original payload and restore from it if a filter
        -- returns malformed/corrupted values.
        local filterPayload = {
            chatType = chatType,
            target = target,
            channelName = channelName,
            label = nil,
            unit = (chatType == "EMOTE") and "player" or nil,
        }
        local originalPayload = DeepCopy(filterPayload)
        local payload = api:RunFilter("PRE_EDITBOX_LABEL", filterPayload)

        if payload == false or type(payload) ~= "table" then
            payload = originalPayload
        else
            if payload.chatType ~= nil and type(payload.chatType) ~= "string" then
                payload.chatType = originalPayload.chatType
            end
            if payload.channelName ~= nil and type(payload.channelName) ~= "string" then
                payload.channelName = originalPayload.channelName
            end
            if payload.unit ~= nil and type(payload.unit) ~= "string" then
                payload.unit = originalPayload.unit
            end
        end

        -- Non-blocking label hook: ignore cancellation and fall back to default label logic.
        if type(payload.label) == "string" and payload.label ~= "" then
            label = payload.label
        end
    end

    if not label and chatType == "BN_WHISPER" and target then
        local display = target
        if YapperTable and YapperTable.Router and YapperTable.Router.ResolveBnetDisplay then
            display = YapperTable.Router:ResolveBnetDisplay(target) or target
        end
        label = "To " .. display .. ":"
    elseif not label and chatType == "WHISPER" and target then
        label = "To " .. target .. ":"
    elseif not label and chatType == "EMOTE" then
        label = UnitName and UnitName("player") or "You"
    elseif not label and chatType == "CHANNEL" then
        if channelName and channelName ~= "" then
            label = channelName
        elseif target then
            label = "Channel #" .. tostring(target)
        else
            label = "Channel"
        end
        label = label .. ":"
    elseif not label then
        local pretty = LABEL_PREFIXES[chatType]
        label = pretty or (chatType or "Say")
    end

    -- Colour from ChatTypeInfo.
    local r, g, b = 1, 0.82, 0 -- gold fallback
    if chatType and ChatTypeInfo then
        local info
        if chatType == "CHANNEL" and target then
            info = ChatTypeInfo["CHANNEL" .. tostring(target)]
        end
        if not info then
            info = ChatTypeInfo[chatType]
        end
        if info then
            r, g, b = info.r or r, info.g or g, info.b or b
        end
    end

    return label, r, g, b
end

local function GetLabelUsableWidth(self)
    if not self or not self.LabelBg then return 80 end
    local rawWidth = self.LabelBg:GetWidth() or 100
    return math_max(40, rawWidth - 10)
end

local function ResetLabelToBaseFont(self)
    if not self or not self.ChannelLabel then return end
    if self.OverlayEdit and self.OverlayEdit.GetFont then
        local face, size, flags = self.OverlayEdit:GetFont()
        if face and size then
            YapperTable.Utils:SetFontIfChanged(self.ChannelLabel, face, size, flags or "")
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

-- Memoisation for the label fit/truncate measurement loops. Both are pure
-- functions of (text, available width, base font), but measuring requires
-- SetFont/SetText + GetStringWidth churn on a live FontString every open.
-- The cache is wiped wholesale when it grows past the cap; label texts are
-- a small, recurring set (channel names) so hits dominate in practice.
local labelFitCache      = {}
local labelFitCacheCount = 0
local LABEL_FIT_CACHE_MAX = 128

local function LabelFitCacheKey(text, maxWidth, face, size, flags)
    return text .. "\1" .. maxWidth .. "\1" .. face .. "\1" .. size .. "\1" .. (flags or "")
end

local function LabelFitCachePut(key, value)
    if labelFitCacheCount >= LABEL_FIT_CACHE_MAX then
        labelFitCache = {}
        labelFitCacheCount = 0
    end
    labelFitCache[key] = value
    labelFitCacheCount = labelFitCacheCount + 1
end

local function TruncateLabelToWidth(fontString, text, maxWidth)
    if not fontString or type(text) ~= "string" then
        return text
    end

    local face, size, flags = fontString:GetFont()
    local key
    if face and size then
        key = "T" .. LabelFitCacheKey(text, maxWidth, face, size, flags)
        local cached = labelFitCache[key]
        if cached ~= nil then
            return cached
        end
    end

    local result
    fontString:SetText(text)
    if (fontString:GetStringWidth() or 0) <= maxWidth then
        result = text
    else
        local truncated = text
        while #truncated > 0 do
            truncated = truncated:sub(1, #truncated - 1)
            local candidate = truncated .. "..."
            fontString:SetText(candidate)
            if (fontString:GetStringWidth() or 0) <= maxWidth then
                result = candidate
                break
            end
        end
        result = result or "..."
    end

    if key then
        LabelFitCachePut(key, result)
    end
    return result
end

local function FitLabelFontToWidth(self, text, maxWidth)
    if not self or not self.ChannelLabel then return false end

    local fontString = self.ChannelLabel
    local face, size, flags = fontString:GetFont()

    local key
    if face and size then
        key = "F" .. LabelFitCacheKey(text, maxWidth, face, size, flags)
        local cached = labelFitCache[key]
        if cached == false then
            -- Reproduce the uncached failure state: the loop leaves the
            -- FontString at the minimum size, which the subsequent
            -- TruncateLabelToWidth measures against.
            fontString:SetFont(face, 8, flags or "")
            return false
        elseif type(cached) == "number" then
            -- Cached size that fit; apply without re-measuring.
            if cached ~= size then
                fontString:SetFont(face, cached, flags or "")
            end
            fontString:SetText(text)
            return true
        end
    end

    fontString:SetText(text)
    if (fontString:GetStringWidth() or 0) <= maxWidth then
        if key then LabelFitCachePut(key, size) end
        return true
    end

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
            if key then LabelFitCachePut(key, targetSize) end
            return true
        end
    end

    if key then LabelFitCachePut(key, false) end
    return false
end

-- ---------------------------------------------------------------------------
-- Overlay creation
-- ---------------------------------------------------------------------------

local MULTILINE_HINT_TEXT          = "Press Shift-Enter to go into multiline mode."
local MULTILINE_HINT_GAP           = 8
local MULTILINE_HINT_SCREEN_PAD    = 4
local MULTILINE_HINT_FADE_DURATION = 0.25

--- Cancel and hide the session-only multiline onboarding hint.
--- The session flag is intentionally preserved so re-opening the overlay does
--- not replay the hint after it has already been scheduled once.
function EditBox:HideMultilineHint()
    if self._multilineHintTimer and self._multilineHintTimer.Cancel then
        self._multilineHintTimer:Cancel()
    end
    self._multilineHintTimer = nil

    local hint = self.MultilineHint
    if not hint then return end

    if UIFrameFadeRemoveFrame then
        UIFrameFadeRemoveFrame(hint)
    end
    hint:Hide()
    hint:SetAlpha(1)
end

--- Create the non-interactive hint frame lazily, using UIParent as its parent
--- so its absolute screen-space position is independent of chat-frame scale.
function EditBox:CreateMultilineHint()
    if self.MultilineHint then return end

    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(10)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    frame:SetBackdropBorderColor(0.9, 0.75, 0.2, 1)
    frame:Hide()

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetText(MULTILINE_HINT_TEXT)
    frame._fs = text

    self.MultilineHint = frame

    if YapperTable.Core and type(YapperTable.Core.RegisterFrame) == "function" then
        YapperTable.Core:RegisterFrame("Overlay", "MultilineHint", frame)
    end
end

--- Show the onboarding hint once during the current session and let it fade
--- after the configured hold duration.
function EditBox:ShowMultilineHint()
    if self._multilineHintShown then return end
    if not self.Overlay or not self.Overlay:IsShown() then return end

    local multiline = YapperTable.Multiline
    if multiline and multiline.Frame and multiline.Frame:IsShown() then return end

    self._multilineHintShown = true
    self:CreateMultilineHint()

    local hint = self.MultilineHint
    local text = hint._fs
    if self.OverlayEdit and self.OverlayEdit.GetFont and text.SetFont then
        local face, size, flags = self.OverlayEdit:GetFont()
        if face and size then
            text:SetFont(face, size, flags or "")
        end
    end

    local hintWidth = math.ceil((text:GetStringWidth() or 0) + 12)
    local hintHeight = math_max(20, (text:GetStringHeight() or 0) + 8)
    hint:SetSize(hintWidth, hintHeight)

    local screenW = UIParent:GetWidth() or 1024
    local screenH = UIParent:GetHeight() or 768
    local overlayLeft = self.Overlay:GetLeft() or 0
    local overlayRight = self.Overlay:GetRight()
        or (overlayLeft + (self.Overlay:GetWidth() or 0))
    local overlayBottom = self.Overlay:GetBottom() or 0
    local overlayTop = self.Overlay:GetTop()
        or (overlayBottom + (self.Overlay:GetHeight() or 0))

    local x
    if overlayRight + MULTILINE_HINT_GAP + hintWidth
        <= screenW - MULTILINE_HINT_SCREEN_PAD then
        x = overlayRight + MULTILINE_HINT_GAP
    elseif overlayLeft - MULTILINE_HINT_GAP - hintWidth
        >= MULTILINE_HINT_SCREEN_PAD then
        x = overlayLeft - MULTILINE_HINT_GAP - hintWidth
    else
        -- Neither side has enough room; clamp the right-side preference to the
        -- viewport rather than allowing the hint to run off-screen.
        x = overlayRight + MULTILINE_HINT_GAP
        local maxX = screenW - hintWidth - MULTILINE_HINT_SCREEN_PAD
        if maxX < MULTILINE_HINT_SCREEN_PAD then
            maxX = MULTILINE_HINT_SCREEN_PAD
        end
        x = math_max(MULTILINE_HINT_SCREEN_PAD, math_min(x, maxX))
    end

    local y = overlayBottom + ((overlayTop - overlayBottom - hintHeight) / 2)
    local maxY = screenH - hintHeight - MULTILINE_HINT_SCREEN_PAD
    if maxY < MULTILINE_HINT_SCREEN_PAD then
        maxY = MULTILINE_HINT_SCREEN_PAD
    end
    y = math_max(MULTILINE_HINT_SCREEN_PAD, math_min(y, maxY))

    hint:ClearAllPoints()
    hint:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    hint:SetAlpha(0)
    hint:Show()
    if UIFrameFadeIn then
        UIFrameFadeIn(hint, 0.12, 0, 1)
    else
        hint:SetAlpha(1)
    end

    local cfg = YapperTable.Config and YapperTable.Config.EditBox or {}
    local holdDuration = tonumber(cfg.MultilineHintDuration) or 5
    if holdDuration < 0 then holdDuration = 0 end

    if not (C_Timer and C_Timer.NewTimer) then
        hint:Hide()
        hint:SetAlpha(1)
        return
    end

    local holdTimer
    holdTimer = C_Timer.NewTimer(holdDuration, function()
        if self._multilineHintTimer ~= holdTimer then return end
        self._multilineHintTimer = nil
        if not hint:IsShown() then return end

        if UIFrameFadeOut then
            UIFrameFadeOut(hint, MULTILINE_HINT_FADE_DURATION, hint:GetAlpha() or 1, 0)
        else
            hint:SetAlpha(0)
        end

        local fadeTimer
        fadeTimer = C_Timer.NewTimer(MULTILINE_HINT_FADE_DURATION, function()
            if self._multilineHintTimer ~= fadeTimer then return end
            self._multilineHintTimer = nil
            hint:Hide()
            hint:SetAlpha(1)
        end)
        self._multilineHintTimer = fadeTimer
    end)
    self._multilineHintTimer = holdTimer
end

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
    local padding  = math_max(2, math_min(basePad, headroom))
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
    if SetFrameFillColour then
        SetFrameFillColour(frame, inputBg.r or 0.05, inputBg.g or 0.05, inputBg.b or 0.05, inputBg.a or 1.0)
    end

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

    if YapperTable.Core and type(YapperTable.Core.RegisterFrame) == "function" then
        YapperTable.Core:RegisterFrame("Overlay", "Frame", frame)
        YapperTable.Core:RegisterFrame("Overlay", "EditBox", edit)
        YapperTable.Core:RegisterFrame("Overlay", "Label", labelFs)
        YapperTable.Core:RegisterFrame("Overlay", "LabelBg", labelBg)
    end
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

    -- A direct overlay hide also occurs when entering multiline mode, so keep
    -- the independent screen-space hint lifecycle tied to this frame.
    frame:HookScript("OnHide", function()
        self:HideMultilineHint()
    end)

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

                    self._lockdown.savedDuring = true
                end
            end)
        end
    end

    self:UpdateFocusOverride()
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
