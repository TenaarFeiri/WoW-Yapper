--[[
    Taint-free overlay that replaces Blizzard's chat input.

    Since WoW 12.0.0 any addon touching the default EditBox taints it,
    which blocks SendChatMessage during encounters.  We sidestep this by
    hooking Show() (taint-safe), hiding Blizzard's box, and presenting
    our own overlay in the same spot.  The overlay was never part of the
    protected hierarchy so it can send freely even in combat.
    We then defer back to Blizzard's own editbox under lockdown.
]]

local _, YapperTable           = ...

local EditBox                  = {}
YapperTable.EditBox            = EditBox

-- User bypass flag
local UserBypassingYapper      = false
local BypassEditBox            = nil



-- Overlay widgets (created lazily).
EditBox.Overlay                = nil
EditBox.OverlayEdit            = nil
EditBox.ChannelLabel           = nil
EditBox.LabelBg                = nil

-- State.
EditBox.HookedBoxes            = {}
EditBox.OrigEditBox            = nil
EditBox.ChatType               = nil
EditBox.Language               = nil
EditBox.Target                 = nil
EditBox.ChannelName            = nil
EditBox.LastUsed               = {}
EditBox.HistoryIndex           = nil
EditBox.HistoryCache           = nil
EditBox.PreShowCheck           = nil
EditBox._attrCache             = {}
EditBox._lockdownTicker        = nil
EditBox._lockdownHandedOff     = false
-- Reply queue for recent whisper targets (most-recent at index 1)
EditBox.ReplyQueue             = {}
local REPLY_QUEUE_MAX          = 20

-- Reply-queue helpers
-- Reply-queue helpers

function EditBox:AddReplyTarget(name, kind)
    if not name or name == "" then return end
    -- Is it a secret? Then don't add it.
    if YapperTable and YapperTable.Utils and type(YapperTable.Utils.IsSecret) == "function" then
        if YapperTable.Utils:IsSecret(name) then return end
    end
    kind = kind or "WHISPER"
    -- Normalize short kinds
    if kind == "BN" then kind = "BN_WHISPER" end

    -- Remove existing matching entry (same name & kind) to avoid duplicates
    for i = #self.ReplyQueue, 1, -1 do
        local e = self.ReplyQueue[i]
        if e and e.name == name and e.kind == kind then
            table.remove(self.ReplyQueue, i)
            break
        end
    end

    -- Insert at front
    table.insert(self.ReplyQueue, 1, { name = name, kind = kind })

    -- Trim tail
    while #self.ReplyQueue > REPLY_QUEUE_MAX do
        table.remove(self.ReplyQueue)
    end
end

function EditBox:RemoveReplyTarget(name, kind)
    if not name or name == "" then return end
    for i = #self.ReplyQueue, 1, -1 do
        local e = self.ReplyQueue[i]
        if e and e.name == name and (not kind or e.kind == kind) then
            table.remove(self.ReplyQueue, i)
        end
    end
end

-- Get next reply target given current name and direction.
-- Behaviour: if current equals queue front, advance by direction (wrap).
-- Otherwise select front. Returns name, kind or nil.
function EditBox:NextReplyTarget(currentName, direction)
    if not self.ReplyQueue or #self.ReplyQueue == 0 then return nil end
    direction = direction or 1
    local q = self.ReplyQueue
    if currentName and q[1] and q[1].name == currentName then
        -- advance from front
        local idx = 1 + (direction or 1)
        if idx < 1 then idx = #q end
        if idx > #q then idx = 1 end
        return q[idx].name, q[idx].kind
    end
    -- Default: pick most recent
    return q[1].name, q[1].kind
end

-- Slash command → chatType.
local SLASH_MAP                = {
    s           = "SAY",
    say         = "SAY",
    y           = "YELL",
    yell        = "YELL",
    e           = "EMOTE",
    em          = "EMOTE",
    emote       = "EMOTE",
    me          = "EMOTE",
    p           = "PARTY",
    party       = "PARTY",
    i           = "INSTANCE_CHAT",
    instance    = "INSTANCE_CHAT",
    g           = "GUILD",
    guild       = "GUILD",
    o           = "OFFICER",
    officer     = "OFFICER",
    ra          = "RAID",
    raid        = "RAID",
    rw          = "RAID_WARNING",
    raidwarning = "RAID_WARNING",
}

-- Tab-cycle order.
local TAB_CYCLE                = {
    "SAY", "EMOTE", "YELL", "PARTY", "INSTANCE_CHAT",
    "RAID", "RAID_WARNING", "GUILD", "OFFICER",
}

-- Pretty names for the channel label.
local LABEL_PREFIXES           = {
    SAY           = "Say:",
    EMOTE         = "Emote",
    YELL          = "Yell:",
    PARTY         = "Party:",
    PARTY_LEADER  = "Party Leader:",
    RAID          = "Raid:",
    RAID_LEADER   = "Raid Leader:",
    RAID_WARNING  = "Raid Warning:",
    INSTANCE_CHAT = "Instance:",
    GUILD         = "Guild:",
    OFFICER       = "Officer:",
    WHISPER       = "Whisper",
    CHANNEL       = "Channel",
}

-- Hot-path locals
local strmatch                 = string.match
local strlower                 = string.lower
local strbyte                  = string.byte

-- Chat types that are always sticky when in a group, even if StickyChannel is off.
local GROUP_CHAT_TYPES         = {
    PARTY         = true,
    PARTY_LEADER  = true,
    INSTANCE_CHAT = true,
    RAID          = true,
    RAID_LEADER   = true,
    RAID_WARNING  = true,
}

local CHATTYPE_TO_OVERRIDE_KEY = {
    SAY = "SAY",
    YELL = "YELL",
    PARTY = "PARTY",
    PARTY_LEADER = "PARTY",
    WHISPER = "WHISPER",
    BN_WHISPER = "BN_WHISPER",
    INSTANCE_CHAT = "INSTANCE_CHAT",
    RAID = "RAID",
    RAID_LEADER = "RAID",
    RAID_WARNING = "RAID_WARNING",
    CHANNEL = "CHANNEL",
    CLUB = "CLUB",
}

local function IsWhisperSlashPrefill(text)
    if type(text) ~= "string" then return false end
    local trimmed = text:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then return false end
    local cmd = trimmed:match("^/([%w_]+)%s+")
    if not cmd then return false end
    cmd = strlower(cmd)
    return cmd == "w" or cmd == "whisper" or cmd == "tell" or cmd == "t"
        or cmd == "cw" or cmd == "send" or cmd == "charwhisper"
end

local function ParseWhisperSlash(text)
    if type(text) ~= "string" then return nil end
    local cmd, rest = text:match("^%s*/([%w_]+)%s+(.*)")
    if not cmd then return nil end
    cmd = strlower(cmd)
    if cmd ~= "w" and cmd ~= "whisper" and cmd ~= "tell" and cmd ~= "t"
        and cmd ~= "cw" and cmd ~= "send" and cmd ~= "charwhisper" then
        return nil
    end
    local target, remainder = (rest or ""):match("^(%S+)%s*(.*)")
    if not target or target == "" then return nil end
    return target, remainder or ""
end

local function GetLastTellTargetInfo()
    local lastTell = nil
    if ChatEdit_GetLastTellTarget then
        lastTell = ChatEdit_GetLastTellTarget()
    end
    if not lastTell or lastTell == "" then
        return nil, nil
    end

    local lastType = nil
    if ChatEdit_GetLastTellTargetType then
        lastType = ChatEdit_GetLastTellTargetType()
    end
    if lastType ~= "BN_WHISPER" then
        -- If the last tell is actually a BNet friend, switch to BN_WHISPER.
        if YapperTable and YapperTable.Router and YapperTable.Router.ResolveBnetTarget then
            local presenceID, bnetAccountID = YapperTable.Router:ResolveBnetTarget(lastTell)
            if bnetAccountID or presenceID then
                lastType = "BN_WHISPER"
                lastTell = bnetAccountID or presenceID
            else
                lastType = "WHISPER"
            end
        else
            lastType = "WHISPER"
        end
    end

    return lastType, lastTell
end
------------------------------------------------
--- Bypass Yapper and go straight to Blizzard's editbox.
------------------------------------------------
function EditBox:OpenBlizzardChat()
    UserBypassingYapper = true
    local eb = self.OrigEditBox or _G.ChatFrame1EditBox
    BypassEditBox = eb and eb.GetName and eb:GetName() or nil

    -- Ensure any overlay state is handed off and saved first.
    if self.Overlay and self.Overlay:IsShown() then
        self:HandoffToBlizzard()
    end

    -- Defer the actual opening to the next frame so our Show-hook
    -- observes `UserBypassingYapper` and lets Blizzard's editbox win.
    C_Timer.After(0, function()
        -- Prefer using Blizzard's ChatFrame_OpenChat so Blizzard/ChatFrameUtil
        -- callbacks (focus gained, etc.) run and other addons (e.g. Chattery)
        -- can observe the editbox properly.
        if ChatFrame_OpenChat then
            pcall(ChatFrame_OpenChat, "", eb)
            if eb and eb.SetFocus then eb:SetFocus() end
        else
            if eb and eb.Show then eb:Show() end
            if eb and eb.SetFocus then eb:SetFocus() end
        end
    end)
end
------------------------------------------------
local function IsWIMFocusActive()
    ---@diagnostic disable-next-line: undefined-field
    local wim = _G.WIM or nil
    if not wim then
        return false
    end
    local focus = wim.EditBoxInFocus or nil
    if not focus then
        return false
    end

    local shown = focus.IsShown and focus:IsShown()
    local visible = focus.IsVisible and focus:IsVisible()
    local focused = focus.HasFocus and focus:HasFocus()
    return shown == true or visible == true or focused == true
end

local function SetFrameFillColor(frame, r, g, b, a)
    if not frame then return end
    if not frame._yapperSolidFill then
        local tex = frame:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints(frame)
        frame._yapperSolidFill = tex
    end
    frame._yapperSolidFill:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
end

--- Copy every texture from Blizzard’s editbox onto our overlay so it
--- wears the same skin; afterwards the original box can simply hide.
--- @param origEditBox table  The Blizzard ChatFrameNEditBox.
--- @param overlayHeight number|nil  Resolved overlay height.
function EditBox:AttachBlizzardSkinProxy(origEditBox, overlayHeight)
    local cfg = YapperTable.Config.EditBox or {}
    if cfg.UseBlizzardSkinProxy == false then
        -- Config toggled off: clean up any existing proxy so Yapper's own
        -- fill can re-appear, then bail.
        if self._skinProxyTextures then
            self:DetachBlizzardSkinProxy()
        end
        return
    end
    if not self.Overlay or not origEditBox then
        return
    end

    -- Textures already exist for this exact source editbox.
    -- The overlay was just hidden and re-shown, so the textures are already
    -- children of the overlay frame and came back visible with it.
    -- Nothing to rebuild — just refresh the tint in case config changed.
    if self._skinProxyTextures and self._skinProxySourceEB == origEditBox then
        local inputBg = cfg.InputBg or {}
        self:TintSkinProxyTextures(inputBg.r, inputBg.g, inputBg.b, inputBg.a)
        -- Ensure our own fill/border stay suppressed.
        if self.Overlay._yapperSolidFill then self.Overlay._yapperSolidFill:Hide() end
        if self.Overlay.Border then self.Overlay.Border:Hide() end
        return
    end

    -- Source editbox changed (e.g. ChatFrame2) or first attach: rebuild.
    self:DetachBlizzardSkinProxy()

    local overlay = self.Overlay
    local clones  = {}

    -- When our overlay is taller than Blizzard’s editbox we compute two
    -- scales.  One keeps anchor points aligned to the real ratio, the
    -- other grows texture heights with a margin so the skin’s corner caps
    -- aren’t squashed and text doesn’t spill past the inset.
    local origH  = origEditBox:GetHeight() or 0
    local vScaleAnchors = 1
    local vScaleSize    = 1
    if origH > 0 and overlayHeight and overlayHeight > 0 then
        local baseScale = overlayHeight / origH
        vScaleAnchors = math.max(1, baseScale)
        -- Extra margin: 50% of the growth beyond 1× for texture sizes.
        local margin = math.max(0, (baseScale - 1) * 0.5)
        vScaleSize = math.max(1, baseScale + margin)
    end

    -- Reattach every anchor from the original box to our overlay; y offsets
    -- are scaled by the true height ratio while texture size uses the
    -- boosted scale so visuals keep up.
    local function mirrorAnchors(tex, region)
        tex:ClearAllPoints()
        local numPoints = region:GetNumPoints() or 0
        if numPoints == 0 then
            -- No anchors at all, fall back to stretching.
            tex:SetAllPoints(overlay)
            return
        end
        for pi = 1, numPoints do
            local point, relTo, relPoint, xOfs, yOfs = region:GetPoint(pi)
            if relTo == origEditBox then
                relTo = overlay   -- remap to our overlay
            end
            -- Scale Y offsets by the real ratio so anchors track the
            -- actual frame size -- not the boosted texture size.
            local scaledYOfs = yOfs
            if vScaleAnchors > 1 then
                scaledYOfs = yOfs * vScaleAnchors
            end
            tex:SetPoint(point, relTo, relPoint, xOfs, scaledYOfs)
        end
    end

    -- Clone each visible Texture region from the editbox onto our overlay.
    local regions = { origEditBox:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then
            local ok = pcall(function()
                -- Preserve sub-layer ordering within the same draw layer.
                local drawLayer, subLevel = region:GetDrawLayer()
                local tex = overlay:CreateTexture(nil, drawLayer or "BACKGROUND", nil, subLevel or 0)

                -- Copy atlas or file texture.
                local atlas = region.GetAtlas and region:GetAtlas()
                if atlas and atlas ~= "" then
                    tex:SetAtlas(atlas, region.IsAtlasUsingSize and region:IsAtlasUsingSize() or false)
                else
                    local file = region.GetTexture and region:GetTexture()
                    if file then
                        tex:SetTexture(file)
                        pcall(function()
                            tex:SetTexCoord(region:GetTexCoord())
                        end)
                    end
                end

                -- Always use white (SAY) vertex colour so the proxy skin
                -- isn't tinted by whatever chat type was active at snapshot.
                tex:SetVertexColor(1, 1, 1, 1)

                -- Copy alpha.
                pcall(function()
                    tex:SetAlpha(region:GetAlpha())
                end)

                -- Copy blend mode.
                pcall(function()
                    local blend = region:GetBlendMode()
                    if blend then tex:SetBlendMode(blend) end
                end)

                -- Copy explicit size.  Heights are scaled by the boosted
                -- factor so the skin visually covers beyond the frame edge.
                pcall(function()
                    local w, h = region:GetSize()
                    if w and w > 0 then tex:SetWidth(w) end
                    if h and h > 0 then tex:SetHeight(h * vScaleSize) end
                end)

                -- Mirror anchor points: remap editbox references → overlay.
                mirrorAnchors(tex, region)

                tex:Show()
                clones[#clones + 1] = tex
            end)
            -- If a single region fails, skip it and keep going.
        end
    end

    if #clones == 0 then
        return  -- nothing to adopt
    end

    self._skinProxyTextures = clones
    self._skinProxySourceEB  = origEditBox

    -- Apply user's backdrop colour as a tint over the cloned textures.
    local inputBg = cfg.InputBg or {}
    self:TintSkinProxyTextures(inputBg.r, inputBg.g, inputBg.b, inputBg.a)

    -- Suppress Yapper's own solid fill and border so the cloned skin shows.
    if overlay._yapperSolidFill then
        overlay._yapperSolidFill:Hide()
    end
    if overlay.Border then
        overlay.Border:Hide()
    end
end

--- Tint all cloned skin proxy textures with the given colour.
--- Passing nil/default values preserves the original Blizzard appearance;
--- non-default values blend multiplicatively with the base texture.
--- @param r number|nil  Red   (0-1, default = Blizzard original)
--- @param g number|nil  Green (0-1, default = Blizzard original)
--- @param b number|nil  Blue  (0-1, default = Blizzard original)
--- @param a number|nil  Alpha (0-1, default = Blizzard original)
function EditBox:TintSkinProxyTextures(r, g, b, a)
    local clones = self._skinProxyTextures
    if not clones then return end

    -- Only tint if the user has set a non-default colour.
    -- Default InputBg is ~0.05/0.05/0.05/1.0 which is near-black;
    -- detect change by checking if any channel deviates
    -- from the factory defaults significantly.
    local defR, defG, defB, defA = 0.05, 0.05, 0.05, 1.0
    r = r or defR
    g = g or defG
    b = b or defB
    a = a or defA

    local isDefault = (math.abs(r - defR) < 0.01)
                  and (math.abs(g - defG) < 0.01)
                  and (math.abs(b - defB) < 0.01)
                  and (math.abs(a - defA) < 0.01)
    if isDefault then
        return  -- leave the original Blizzard tint as-is
    end

    for i = 1, #clones do
        pcall(function()
            clones[i]:SetVertexColor(r, g, b)
            clones[i]:SetAlpha(a)
        end)
    end
end

--- Remove cloned Blizzard skin textures and restore Yapper's own fills.
--- Use this only when the source editbox changes, the proxy is disabled via
--- config, or font size changes require a rescale.  Do NOT call from Hide():
--- textures are children of the overlay and hide/show with it automatically,
--- so calling Detach on every close would accumulate orphaned texture objects
function EditBox:DetachBlizzardSkinProxy()
    local clones = self._skinProxyTextures
    if not clones then return end

    for i = 1, #clones do
        pcall(function()
            clones[i]:Hide()
            clones[i]:SetTexture(nil)
        end)
    end
    self._skinProxyTextures = nil
    self._skinProxySourceEB = nil

    -- Re-show Yapper's own fill (RefreshOverlayVisuals will recolour it).
    if self.Overlay and self.Overlay._yapperSolidFill then
        self.Overlay._yapperSolidFill:Show()
    end
end

-- Perform one-pass visual refresh (fills, anchors, colours, border). `pad` is 0 or overlay.BorderPad; call only from ShowOverlay/ApplyConfigToLiveOverlay.
local function RefreshOverlayVisuals(editBox, cfg, borderActive, pad)
    local overlay = editBox.Overlay
    local labelBg = editBox.LabelBg
    local edit    = editBox.OverlayEdit
    if not overlay or not labelBg or not edit then return end

    local inputBg   = cfg.InputBg    or {}
    local labelCfg  = cfg.LabelBg    or {}
    local borderCfg = cfg.BorderColor or {}
    local textCfg   = cfg.TextColor   or {}

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
    SetFrameFillColor(overlay, fillR, fillG, fillB, fillA)
    if overlay._yapperSolidFill then
        if proxyActive then
            -- Keep hidden; cloned skin textures replace the solid fill.
            overlay._yapperSolidFill:Hide()
        else
            overlay._yapperSolidFill:Show()
            overlay._yapperSolidFill:ClearAllPoints()
            if pad > 0 then
                overlay._yapperSolidFill:SetPoint("TOPLEFT",     overlay, "TOPLEFT",      pad, -pad)
                overlay._yapperSolidFill:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -pad,  pad)
            else
                overlay._yapperSolidFill:SetAllPoints(overlay)
            end
        end
    end

    -- Label background fill + position (inset matches fill when border active).
    -- Hidden when skin proxy is active so cloned skin textures show.
    if proxyActive then
        SetFrameFillColor(labelBg, 0, 0, 0, 0)
        if labelBg._yapperSolidFill then labelBg._yapperSolidFill:Hide() end
    else
        SetFrameFillColor(labelBg,
            labelCfg.r or 0.06, labelCfg.g or 0.06, labelCfg.b or 0.06, labelCfg.a or 1.0)
        if labelBg._yapperSolidFill then labelBg._yapperSolidFill:Show() end
    end
    labelBg:ClearAllPoints()
    local LEFT_MARGIN = 6  -- fixed inset from the overlay's left edge
    labelBg:SetPoint("TOPLEFT",    overlay, "TOPLEFT",    pad + LEFT_MARGIN, -pad)
    labelBg:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", pad + LEFT_MARGIN,  pad)

    -- EditBox anchors: left edge follows label; right edge inset to avoid border.
    edit:ClearAllPoints()
    edit:SetPoint("TOPLEFT",     labelBg, "TOPRIGHT",    0,    0)
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
    local labelW = math.ceil(rawWidth + padding)
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
    borderFrame:Hide()  -- hidden until ApplyConfigToLiveOverlay decides based on active theme
    frame.Border     = borderFrame
    frame.BorderPad  = BORDER_PAD  -- read by ApplyConfigToLiveOverlay for fill inset

    -- Container background fill — always on the outer frame so ApplyConfigToLiveOverlay
    -- has a single predictable target.  Anchor is adjusted dynamically when the border
    -- is active (inset) vs hidden (full bleed).
    SetFrameFillColor(frame, inputBg.r or 0.05, inputBg.g or 0.05, inputBg.b or 0.05, inputBg.a or 1.0)

    -- ── Label background (left portion) ──────────────────────────────
    local labelBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    -- Initial anchors at zero inset; RefreshOverlayVisuals repositions on first show.
    labelBg:SetPoint("TOPLEFT",    frame, "TOPLEFT",    0, 0)
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
    edit:SetAutoFocus(true)
    edit:SetMultiLine(false)
    edit:SetMaxLetters(0)
    edit:SetMaxBytes(0)

    local tc = cfg.TextColor or {}
    edit:SetTextColor(tc.r or 1, tc.g or 1, tc.b or 1, tc.a or 1)
    edit:SetTextInsets(1, 6, 0, 0)

    -- Initial anchors at zero inset; RefreshOverlayVisuals repositions on first show.
    edit:SetPoint("TOPLEFT",     labelBg, "TOPRIGHT",    0, 0)
    edit:SetPoint("BOTTOMRIGHT", frame,   "BOTTOMRIGHT", 0, 0)

    -- Store references.
    self.Overlay      = frame
    self.OverlayEdit  = edit
    self.ChannelLabel = labelFs
    self.LabelBg      = labelBg
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

function EditBox:SetupOverlayScripts()
    local edit         = self.OverlayEdit
    local frame        = self.Overlay

    -- When true, we're changing text programmatically (skip OnTextChanged).
    local updatingText = false

    -- ── OnTextChanged: slash-command channel switches ──────────────────
    edit:SetScript("OnTextChanged", function(box, isUserInput)
        if updatingText then return end

        if YapperTable.Spellcheck and type(YapperTable.Spellcheck.OnTextChanged) == "function" then
            YapperTable.Spellcheck:OnTextChanged(box, isUserInput)
        end
        -- If a suggestion was just applied via numeric hotkey, the engine may
        -- also inject the numeric character into the editbox. Remove it here
        -- before further processing.
        if YapperTable.Spellcheck and YapperTable.Spellcheck._suppressNextChar then
            local sc = YapperTable.Spellcheck
            local textNow = box:GetText() or ""
            if sc._expectedText and sc._suppressChar and textNow == (sc._expectedText .. sc._suppressChar) then
                updatingText = true
                box:SetText(sc._expectedText)
                if sc._expectedCursor then box:SetCursorPosition(sc._expectedCursor) end
                updatingText = false
                sc._suppressNextChar = nil
                sc._suppressChar = nil
                sc._expectedText = nil
                sc._expectedCursor = nil
                return
            else
                sc._suppressNextChar = nil
                sc._suppressChar = nil
                sc._expectedText = nil
                sc._expectedCursor = nil
            end
        end
        if not isUserInput then return end

        local text = box:GetText() or ""

        if strbyte(text, 1) ~= 47 then -- '/'
            self.HistoryIndex = nil
            self.HistoryCache = nil
            return
        end

        -- Bare numeric channel: "/2 message"
        local num, rest = strmatch(text, "^/(%d+)%s+(.*)")
        if num then
            local resolved = ResolveChannelName(tonumber(num))
            if resolved then
                self.ChatType    = "CHANNEL"
                self.Target      = num
                self.ChannelName = resolved
                self.Language    = nil
                updatingText     = true
                box:SetText(rest or "")
                updatingText = false
                self:RefreshLabel()
                box:SetCursorPosition(#(rest or ""))
            end
            return
        end

        -- "/cmd rest" — need a space before we act.
        local cmd, rest2 = strmatch(text, "^/([%w_]+)%s+(.*)")
        if not cmd then return end
        cmd = strlower(cmd)

        -- /c, /channel — wait for a space after the channel ID too,
        -- so we don't fire while the user is still typing it.
        if cmd == "c" or cmd == "channel" then
            local ch, remainder = strmatch(rest2 or "", "^(%S+)%s+(.*)")
            if ch then
                local chNum = tonumber(ch)
                if chNum then
                    local resolved = ResolveChannelName(chNum)
                    if not resolved then return end
                    self.ChatType    = "CHANNEL"
                    self.Target      = tostring(chNum)
                    self.ChannelName = resolved
                else
                    self.ChatType    = "CHANNEL"
                    self.Target      = ch
                    self.ChannelName = nil
                end
                self.Language = nil
                updatingText = true
                box:SetText(remainder or "")
                updatingText = false
                self:RefreshLabel()
                box:SetCursorPosition(#(remainder or ""))
            end
            return
        end

        if cmd == "w" or cmd == "whisper" or cmd == "tell" or cmd == "t"
            or cmd == "cw" or cmd == "send" or cmd == "charwhisper" then
            local target, remainder = strmatch(rest2 or "", "^(%S+)%s+(.*)")
            if target then
                self.ChatType = "WHISPER"
                self.Target   = target
                self.Language = nil
                updatingText  = true
                box:SetText(remainder or "")
                updatingText = false
                self:RefreshLabel()
                box:SetCursorPosition(#(remainder or ""))
            end
            return
        end

        if cmd == "r" or cmd == "reply" then
            local lastType, lastTell = GetLastTellTargetInfo()
            if lastTell and lastTell ~= "" then
                self.ChatType = lastType
                self.Target   = lastTell
                self.Language = nil
                updatingText  = true
                box:SetText(rest2 or "")
                updatingText = false
                self:RefreshLabel()
                box:SetCursorPosition(#(rest2 or ""))
            end
            return
        end

        if SLASH_MAP[cmd] then
            local ct = SLASH_MAP[cmd]
            
            -- Intelligent Fallbacks for group types (Mirror Blizzard behavior)
            if ct == "INSTANCE_CHAT" then
                -- Target Instance Chat: Fallback to Raid or Party if not in Instance Category.
                if not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
                    if IsInRaid(LE_PARTY_CATEGORY_HOME) then
                        ct = "RAID"
                    elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
                        ct = "PARTY"
                    end
                end
            elseif ct == "PARTY" or ct == "PARTY_LEADER" then
                -- Target Party: Fallback to Instance if not in Home Party.
                if not IsInGroup(LE_PARTY_CATEGORY_HOME) and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
                    ct = "INSTANCE_CHAT"
                end
            elseif ct == "RAID" or ct == "RAID_LEADER" then
                -- Target Raid: Fallback to Instance if not in Home Raid.
                if not IsInRaid(LE_PARTY_CATEGORY_HOME) and IsInRaid(LE_PARTY_CATEGORY_INSTANCE) then
                    ct = "INSTANCE_CHAT"
                end
            end

            self.ChatType = ct
            self.Target   = nil
            self.Language = nil
            updatingText  = true
            box:SetText(rest2 or "")
            updatingText = false
            self:RefreshLabel()
            box:SetCursorPosition(#(rest2 or ""))
            return
        end
    end)

    edit:SetScript("OnEnterPressed", function(box)
        if YapperTable.Spellcheck and YapperTable.Spellcheck._justAppliedSuggestion then
            return
        end
        local text = box:GetText() or ""
        local trimmed = strmatch(text, "^%s*(.-)%s*$") or ""

        if trimmed == "" then
            if self._openedFromBnetTransition
                and self.ChatType
                and self.ChatType ~= "BN_WHISPER" then
                self._preferStickyAfterBnet = true
            end
            self._closedClean = true
            if YapperTable.History then
                YapperTable.History:ClearDraft(box)
            end
            self:PersistLastUsed()
            self:Hide()
            return
        end

        -- Slash commands: some (/w Name, /r) won't have been consumed by
        -- OnTextChanged because it waits for a trailing space. Handle
        -- those here before forwarding anything unrecognised to Blizzard.
        if strbyte(trimmed, 1) == 47 then -- '/'
            local enterCmd, enterRest = strmatch(trimmed, "^/([%w_]+)%s*(.*)")
            if enterCmd then
                enterCmd = strlower(enterCmd)

                if enterCmd == "w" or enterCmd == "whisper"
                    or enterCmd == "tell" or enterCmd == "t"
                    or enterCmd == "cw" or enterCmd == "send" or enterCmd == "charwhisper" then
                    local target = strmatch(enterRest or "", "^(%S+)")
                    if target then
                        self.ChatType = "WHISPER"
                        self.Target   = target
                        self.Language = nil
                        -- Fix: Use self.OrigEditBox (eb was undefined here).
                        -- This suppresses the Blizzard UI 'ghost' when switching to whisper modes.
                        local eb      = self.OrigEditBox
                        if eb and eb.Hide and eb:IsShown() then
                            eb:Hide()
                        end
                        box:SetText("")
                        updatingText = false
                        self:RefreshLabel()
                        -- Don't close — user now has an empty whisper box.
                        return
                    end
                end

                if enterCmd == "r" or enterCmd == "reply" then
                    local lastType, lastTell = GetLastTellTargetInfo()
                    if lastTell and lastTell ~= "" then
                        self.ChatType = lastType
                        self.Target   = lastTell
                        self.Language = nil
                        updatingText  = true
                        box:SetText(enterRest or "")
                        updatingText = false
                        self:RefreshLabel()
                        box:SetCursorPosition(#(enterRest or ""))
                        return
                    end
                end

                if enterCmd == "c" or enterCmd == "channel" then
                    local ch = strmatch(enterRest or "", "^(%S+)")
                    if ch then
                        local chNum = tonumber(ch)
                        if chNum then
                            local resolved = ResolveChannelName(chNum)
                            if resolved then
                                self.ChatType    = "CHANNEL"
                                self.Target      = tostring(chNum)
                                self.ChannelName = resolved
                                self.Language    = nil
                                updatingText     = true
                                box:SetText("")
                                updatingText = false
                                self:RefreshLabel()
                                return
                            end
                        else
                            self.ChatType    = "CHANNEL"
                            self.Target      = ch
                            self.ChannelName = nil
                            self.Language    = nil
                            updatingText     = true
                            box:SetText("")
                            updatingText = false
                            self:RefreshLabel()
                            return
                        end
                    end
                end

                if SLASH_MAP[enterCmd] then
                    local ct = SLASH_MAP[enterCmd]
                    
                    -- Intelligent Fallbacks for group types (Mirror Blizzard behavior)
                    if ct == "INSTANCE_CHAT" then
                        if not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
                            if IsInRaid(LE_PARTY_CATEGORY_HOME) then
                                ct = "RAID"
                            elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
                                ct = "PARTY"
                            end
                        end
                    elseif ct == "PARTY" or ct == "PARTY_LEADER" then
                        if not IsInGroup(LE_PARTY_CATEGORY_HOME) and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
                            ct = "INSTANCE_CHAT"
                        end
                    elseif ct == "RAID" or ct == "RAID_LEADER" then
                        if not IsInRaid(LE_PARTY_CATEGORY_HOME) and IsInRaid(LE_PARTY_CATEGORY_INSTANCE) then
                            ct = "INSTANCE_CHAT"
                        end
                    end

                    self.ChatType = ct
                    self.Target   = nil
                    self.Language = nil
                    updatingText  = true
                    box:SetText(enterRest or "")
                    updatingText = false
                    self:RefreshLabel()
                    box:SetCursorPosition(#(enterRest or ""))
                    if (enterRest or "") == "" then
                        return
                    end
                    -- Text after the command — fall through to send.
                end
            end

            if strbyte(trimmed, 1) == 47 then -- '/'
                self._closedClean = true
                if YapperTable.History then
                    YapperTable.History:ClearDraft(box)
                    -- Add regular slash commands to history (no channel context).
                    YapperTable.History:AddChatHistory(trimmed, nil, nil)
                end
                self:ForwardSlashCommand(trimmed)
                self:Hide()
                return
            end
        end

        -- If chat is locked down (combat/m+ lockdown), save draft and handoff
        -- ALSO hand off to blizz if we are manually sidestepping.
        if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
            self:HandoffToBlizzard()
            return
        end

        -- If user is manually bypassing Yapper, hand off to Blizzard
        if UserBypassingYapper then
            UserBypassingYapper = false
            self:HandoffToBlizzard()
            return
        end

        -- If a suggestion is open or was just applied, accept the
        -- suggestion instead of sending. Spellcheck may apply the
        -- suggestion in OnKeyDown, which hides the frame immediately;
        -- we therefore also check the transient _justAppliedSuggestion
        -- flag as a final safety guard.
        if YapperTable.Spellcheck and type(YapperTable.Spellcheck.IsSuggestionOpen) == "function" then
            local sc = YapperTable.Spellcheck
            if sc:IsSuggestionOpen() or sc._justAppliedSuggestion then
                local idx = sc.ActiveIndex or 1
                if type(sc.ApplySuggestion) == "function" then
                    sc:ApplySuggestion(idx)
                end
                sc._justAppliedSuggestion = nil
                return
            end
        end

        if self.OnSend then
            self.OnSend(trimmed, self.ChatType or "SAY", self.Language, self.Target)
        else
            if C_ChatInfo and C_ChatInfo.SendChatMessage then
                C_ChatInfo.SendChatMessage(trimmed, self.ChatType or "SAY", self.Language, self.Target)
            end
        end

        -- Track outgoing whispers as reply targets too (move to front).
        if (self.ChatType == "WHISPER" or self.ChatType == "BN_WHISPER") and self.Target and self.Target ~= "" then
            self:AddReplyTarget(self.Target, self.ChatType)
        end

        if self.OrigEditBox then
            self.OrigEditBox:AddHistoryLine(text)
        end

        self._closedClean = true
        if YapperTable.History then
            YapperTable.History:ClearDraft(box)
        end
        self:PersistLastUsed()
        if YapperTable.TypingTrackerBridge and YapperTable.TypingTrackerBridge.Enabled then
            YapperTable.TypingTrackerBridge:OnOverlaySent()
        end
        self:Hide()
    end)

    edit:SetScript("OnEscapePressed", function(box)
        -- If spell suggestions are open, close them only and keep the
        -- overlay active. This prevents ESC from accidentally closing
        -- the whole overlay when the user expected to dismiss hints.
        if YapperTable.Spellcheck and type(YapperTable.Spellcheck.IsSuggestionOpen) == "function"
            and YapperTable.Spellcheck:IsSuggestionOpen() then
            YapperTable.Spellcheck:HideSuggestions()
            return
        end
        local text = box:GetText() or ""
        local cfg = YapperTable.Config and YapperTable.Config.EditBox or {}
        local recoverOnEscape = (cfg.RecoverOnEscape == true)
        if text == "" then
            self._closedClean = true
            if YapperTable.History then
                YapperTable.History:ClearDraft(box)
            end
        else
            if recoverOnEscape then
                -- User bailed with text in the box
                -- Draft is saved in OnHide below.
                self._closedClean = false
            else
                -- Save to history, but do not keep a draft.
                if YapperTable.History then
                    YapperTable.History:AddChatHistory(text, self.ChatType, self.Target)
                    YapperTable.History:MarkDirty(false)
                end
                self._closedClean = true
            end
        end
        box:SetText("")
        self:Hide()
    end)

    edit:SetScript("OnCursorChanged", function(box)
        if YapperTable.Spellcheck and type(YapperTable.Spellcheck.OnCursorChanged) == "function" then
            YapperTable.Spellcheck:OnCursorChanged(box)
        end
    end)

    -- Intercept OnChar to remove numeric hotkey characters appended after
    -- applying a suggestion. This ensures pressing '1'..'4' to select a
    -- suggestion does not also insert the digit into the editbox.
    edit:HookScript("OnChar", function(box, char)
        if YapperTable.Spellcheck and YapperTable.Spellcheck._suppressNextChar then
            local sc = YapperTable.Spellcheck
            if sc._suppressChar == char then
                -- Immediately restore expected text/cursor and clear flags.
                local expected = sc._expectedText or (box:GetText() or "")
                local cursor = sc._expectedCursor
                box:SetText(expected)
                if cursor then box:SetCursorPosition(cursor) end
                sc._suppressNextChar = nil
                sc._suppressChar = nil
                sc._expectedText = nil
                sc._expectedCursor = nil
                return
            end
        end
    end)

    edit:HookScript("OnKeyDown", function(box, key)
        if YapperTable.Spellcheck and type(YapperTable.Spellcheck.HandleKeyDown) == "function" then
            if YapperTable.Spellcheck:HandleKeyDown(key) then
                return
            end
        end
        if key == "TAB" then
            -- If ALT is held we should not cycle chat targets; spellcheck
            -- already owns Alt+Tab behavior, so let it (or other handlers)
            -- handle the key instead.
            if IsAltKeyDown() then
                return
            end
            self:CycleChat(IsShiftKeyDown() and -1 or 1)
        elseif key == "UP" then
            self:NavigateHistory(-1)
        elseif key == "DOWN" then
            self:NavigateHistory(1)
        end
    end)

    frame:SetScript("OnHide", function()
        self.HistoryIndex = nil
        self.HistoryCache = nil

        if YapperTable.Spellcheck and type(YapperTable.Spellcheck.OnOverlayHide) == "function" then
            YapperTable.Spellcheck:OnOverlayHide()
        end

        if not self._closedClean and YapperTable.History then
            local eb = self.OverlayEdit
            if eb then
                local text = eb:GetText() or ""
                if text ~= "" then
                    YapperTable.History:SaveDraft(eb)
                    -- Normal (non-lockdown) saves should not be treated
                    -- as lockdown drafts.
                    self._lastSavedDraftIsLockdown = false
                end
                YapperTable.History:MarkDirty(true)
            end
        end
        self._closedClean = false
        if YapperTable.TypingTrackerBridge and YapperTable.TypingTrackerBridge.Enabled then
            YapperTable.TypingTrackerBridge:OnOverlayFocusLost()
        end
    end)

    -- Combat lockdown detection
    -- When InChatMessagingLockdown becomes true mid-typing, hand the
    -- overlay state back to Blizzard's secure editbox.
    -- Lockdown may activate slightly AFTER PLAYER_REGEN_DISABLED, so
    -- we poll briefly via a ticker if the first check is negative.
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("CHALLENGE_MODE_START")
    frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    -- Track incoming whispers so we can cycle reply targets.
    frame:RegisterEvent("CHAT_MSG_WHISPER")
    frame:RegisterEvent("CHAT_MSG_BN_WHISPER")

    -- Also we want to watch for when the user shows or hides their UI, to close our editbox.
    UIParent:HookScript("OnHide", function()
        -- housing editor hides UIParent; don't close if the editor is active.
        if C_HouseEditor and C_HouseEditor.IsHouseEditorActive
            and C_HouseEditor.IsHouseEditorActive() then
            return
        end
        -- Make sure we're hidden.
        if EditBox.Overlay and EditBox.Overlay:IsShown() then
            EditBox:Hide()
        end
    end)

    frame:HookScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_REGEN_DISABLED" or event == "CHALLENGE_MODE_START" then
            -- Immediate check.
            if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
                self:HandoffToBlizzard()
                return
            end
            -- Not in lockdown yet — poll briefly.
            if self._lockdownTicker then
                self._lockdownTicker:Cancel()
            end
            local ticks = 0
            self._lockdownTicker = C_Timer.NewTicker(0.1, function(ticker)
                ticks = ticks + 1
                if not self.Overlay or not self.Overlay:IsShown() then
                    ticker:Cancel()
                    self._lockdownTicker = nil
                    return
                end
                if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
                    self:HandoffToBlizzard()
                    ticker:Cancel()
                    self._lockdownTicker = nil
                    return
                end
                if ticks >= 20 then -- 2 seconds
                    ticker:Cancel()
                    self._lockdownTicker = nil
                end
            end)
        elseif event == "PLAYER_REGEN_ENABLED" or event == "CHALLENGE_MODE_COMPLETED" then
            -- Combat / M+ over — cancel polling if still running.
            if self._lockdownTicker then
                self._lockdownTicker:Cancel()
                self._lockdownTicker = nil
            end
            -- If we saved a draft during lockdown, poll until lockdown
            -- is truly over (checks every 1s for up to 5s).
            if self._lockdownHandedOff then
                local checks = 0
                C_Timer.NewTicker(1, function(ticker)
                    checks = checks + 1
                    if not (YapperTable.Utils and YapperTable.Utils:IsChatLockdown()) then
                        self._lockdownHandedOff = false
                        -- If Blizzard sends during lockdown changed the channel,
                        -- persist that sticky choice now.
                        if self._lastSavedDuringLockdown then
                            self:PersistLastUsed()
                            self._lastSavedDuringLockdown = nil
                        end
                        -- Allow Show-hook lockdown logic to run again after lockdown.
                        self._lockdownShowHandled = false
                        YapperTable.Utils:Print("info", "Lockdown ended — press Enter to resume typing.")
                        ticker:Cancel()
                        return
                    end
                    if checks >= 5 then
                        ticker:Cancel()
                    end
                end)
            end
        elseif event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then
            -- Incoming whisper: arg2 is sender name for both events.
            local sender = select(2, ...)
            if sender and sender ~= "" then
                if event == "CHAT_MSG_BN_WHISPER" then
                    self:AddReplyTarget(sender, "BN_WHISPER")
                else
                    self:AddReplyTarget(sender, "WHISPER")
                end
            end
        end
    end)
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
    if blizzHasTarget and not self._lastSavedDraftIsLockdown then
        self.ChatType = blizzType
        self.Language = blizzLang or nil
        self.Target   = blizzTell or blizzChan or nil
    elseif (self.LastUsed and self.LastUsed.chatType) and not self._lastSavedDraftIsLockdown then
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
    local finalH        = math.max(minH, fontNeeded)
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

    if YapperTable.TypingTrackerBridge and YapperTable.TypingTrackerBridge.Enabled then
        YapperTable.TypingTrackerBridge:OnOverlayFocusGained(self.ChatType)
    end
end

function EditBox:Hide()
    local prevOrig = self.OrigEditBox

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
end

--- Save draft, close overlay, and notify during lockdown.
function EditBox:HandoffToBlizzard()
    if not self.Overlay or not self.Overlay:IsShown() then return end
    local text = self.OverlayEdit and self.OverlayEdit:GetText() or ""

    -- Save as dirty draft for recovery on next open.
    if text ~= "" and YapperTable.History then
        YapperTable.History:SaveDraft(self.OverlayEdit)
        YapperTable.History:MarkDirty(true)
        -- Mark that this draft was saved due to lockdown so callers
        -- can decide whether to restore it to Blizzard's editbox.
        self._lastSavedDraftIsLockdown = true
    end

    -- OnHide won't double-save because _closedClean is true.
    self._closedClean = true

    -- Close overlay and mark the draft as handed off to Blizzard's flow.
    if self.OverlayEdit then
        self.OverlayEdit:SetText("")
    end
    self:Hide()

    self._lockdownHandedOff = true
    YapperTable.Utils:Print("info",
        "Chat in lockdown — your post has been saved. Press Enter after lockdown ends to continue.")

    -- Cancel the polling ticker if one is running.
    if self._lockdownTicker then
        self._lockdownTicker:Cancel()
        self._lockdownTicker = nil
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

    local cfg = YapperTable.Config.EditBox or {}

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
        local finalH        = math.max(minH, fontNeeded)
        local resolvedH     = finalH > blizzH and finalH or blizzH

        self.Overlay:ClearAllPoints()
        self.Overlay:SetPoint("TOPLEFT", self.OrigEditBox, "TOPLEFT", 0, 0)
        self.Overlay:SetPoint("RIGHT", self.OrigEditBox, "RIGHT", 0, 0)
        self.Overlay:SetHeight(resolvedH)

        -- Re-clone proxy textures at the new overlay height so left/right
        -- caps scale okay-ish when font size changes.
        if self._skinProxyTextures and self.OrigEditBox then
            self:DetachBlizzardSkinProxy()
            pcall(function()
                self:AttachBlizzardSkinProxy(self.OrigEditBox, resolvedH)
            end)
        end
    end

    -- Single-pass visual refresh (fills, anchors, text colour, border)
    local activeTheme  = YapperTable.Theme and YapperTable.Theme:GetTheme()
    local borderActive = activeTheme and activeTheme.border == true
    local pad          = (borderActive and self.Overlay.BorderPad) or 0
    RefreshOverlayVisuals(self, cfg, borderActive, pad)

    self:RefreshLabel()
    localConf.System.SettingsHaveChanged = false

    -- Invoke theme only for font/OnApply. Colours/borders come from config; skip if skin proxy active.
    local proxyActiveOnApply = self._skinProxyTextures
    if not proxyActiveOnApply
        and YapperTable.Theme and type(YapperTable.Theme.ApplyToFrame) == "function"
        and self.Overlay then
        pcall(function() YapperTable.Theme:ApplyToFrame(self.Overlay) end)
    end
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
                and math.abs((userColor.r or 0) - (defColors.r or 0)) < 0.01
                and math.abs((userColor.g or 0) - (defColors.g or 0)) < 0.01
                and math.abs((userColor.b or 0) - (defColors.b or 0)) < 0.01 then
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
        local msg = string.format("RefreshLabel: eff=%s ct=%s tgt=%s -> resolved=(%.2f,%.2f,%.2f) master=%s override=%s whisper=(%s) bn=(%s)",
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
            return math.abs((a or 0) - (b or 0)) < 0.02
        end
        -- standard whisper magenta heuristic
        if approxEqual(resolvedR, 1.0) and approxEqual(resolvedG, 0.5) and approxEqual(resolvedB, 1.0) then
            local defaults = YapperTable.Core and YapperTable.Core.GetDefaults and YapperTable.Core:GetDefaults()
            local defBN = defaults and defaults.EditBox and defaults.EditBox.ChannelTextColors and defaults.EditBox.ChannelTextColors.BN_WHISPER
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
            self.ChatType = kind or "WHISPER"
            self.Target   = name
            -- ChannelName not used for whispers
            self.ChannelName = nil
            self:RefreshLabel()
            if YapperTable.TypingTrackerBridge and YapperTable.TypingTrackerBridge.Enabled then
                YapperTable.TypingTrackerBridge:OnChannelChanged(self.ChatType)
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
            if YapperTable.TypingTrackerBridge and YapperTable.TypingTrackerBridge.Enabled then
                YapperTable.TypingTrackerBridge:OnChannelChanged(self.ChatType)
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
    newIdx = math.max(1, math.min(newIdx, #cache + 1))

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
    local overrideCT = CHATTYPE_TO_OVERRIDE_KEY[chosenCT] or chosenCT
    self.OrigEditBox:SetAttribute("chatType", overrideCT)
    if overrideCT == "WHISPER" or overrideCT == "BN_WHISPER" then
        self.OrigEditBox:SetAttribute("tellTarget", self.Target)
        self.OrigEditBox:SetAttribute("channelTarget", nil)
    elseif overrideCT == "CHANNEL" then
        self.OrigEditBox:SetAttribute("channelTarget", self.Target)
        self.OrigEditBox:SetAttribute("tellTarget", nil)
    else
        self.OrigEditBox:SetAttribute("tellTarget", nil)
        self.OrigEditBox:SetAttribute("channelTarget", nil)
    end
    if self.Language then
        self.OrigEditBox:SetAttribute("language", self.Language)
    else
        self.OrigEditBox:SetAttribute("language", nil)
    end

    self.OrigEditBox:SetText(text)
    ChatEdit_SendText(self.OrigEditBox)

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

                if not self._lastSavedDraftIsLockdown then
                    self.LastUsed.chatType = ct
                    self.LastUsed.target = target
                    self.LastUsed.language = lang
                    -- Persist after lockdown ends if we are still locked.
                    if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
                        self._lastSavedDuringLockdown = true
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
                    if IsWIMFocusActive() then
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

        -- ── Live update: attributes arrived after we already showed ────
        if self.OrigEditBox == eb and self.Overlay and self.Overlay:IsShown() then
            local ct = c.chatType
            local tt = c.tellTarget
            local ch = c.channelTarget

            if (ct == "WHISPER" or ct == "BN_WHISPER") and tt and tt ~= "" then
                self.ChatType = ct
                self.Target   = tt
                self:RefreshLabel()
                -- Clear stale draft (user can't have typed in one frame).
                if self.OverlayEdit then
                    self.OverlayEdit:SetText("")
                end
            elseif ct == "CHANNEL" and ch and ch ~= "" then
                self.ChatType    = "CHANNEL"
                self.Target      = ch
                self.ChannelName = ResolveChannelName(tonumber(ch))
                self:RefreshLabel()
                if self.OverlayEdit then
                    self.OverlayEdit:SetText("")
                end
            end
        end
    end)

    -- mirror Blizzard's SetText while we're overlaid so slash / prefill works
    hooksecurefunc(blizzEditBox, "SetText", function(eb, text)
        if self.OrigEditBox == eb and self.Overlay and self.Overlay:IsShown()
            and self.OverlayEdit then
            local cur = self.OverlayEdit:GetText() or ""
            if text and text ~= "" and text ~= cur then
                self.OverlayEdit:SetText(text)
                self.OverlayEdit:SetCursorPosition(#text)
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

        if UserBypassingYapper then
            if not BypassEditBox then
                BypassEditBox = ebName
            end
            if BypassEditBox == ebName then
                UserBypassingYapper = false
                return
            end
        end

        -- While bypass session is active for this editbox, never overlay it.
        if BypassEditBox and BypassEditBox == ebName then
            return
        end
        
        if self.Overlay and self.Overlay:IsShown() then
            return
        end

        -- If the user Escaped out of a BNet whisper, don't re-open ours.
        if self._bnetDismissed then
            self._bnetDismissed = false
            return
        end

        -- In lockdown Blizzard's untainted box can still send; leave it alone.
        if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
            if not self._lockdownShowHandled then
                self._lockdownShowHandled = true
                local chosenCT = self.ChatType or (self.LastUsed and self.LastUsed.chatType) or "SAY"
                chosenCT = self:GetResolvedChatType(chosenCT)
                eb:SetAttribute("chatType", chosenCT)
                if chosenCT == "WHISPER" then
                    eb:SetAttribute("tellTarget", self.Target)
                    eb:SetAttribute("channelTarget", nil)
                elseif chosenCT == "CHANNEL" then
                    eb:SetAttribute("channelTarget", self.Target)
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
            end
            return
        end


        -- If WIM currently owns chat focus, do not present Yapper overlay.
        if IsWIMFocusActive() then
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
        if BypassEditBox == ebName then
            BypassEditBox = nil
            UserBypassingYapper = false
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
            if BypassEditBox == eb:GetName() then
                BypassEditBox = nil
                UserBypassingYapper = false
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
function EditBox:SetOnSend(fn)
    self.OnSend = fn
end

--- If fn(blizzEditBox) returns true, the overlay is suppressed.
--- Used by Queue to consume hardware events for send continuation.
function EditBox:SetPreShowCheck(fn)
    self.PreShowCheck = fn
end
