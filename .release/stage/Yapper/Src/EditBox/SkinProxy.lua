--[[
    EditBox/SkinProxy.lua
    Clone Blizzard's editbox textures onto the overlay so the user sees
    their theme skin. Supports live tinting and detachment.
]]

local _, YapperTable = ...
local EditBox        = YapperTable.EditBox

-- Re-localise Lua globals.
local type       = type
local pairs      = pairs
local math_max   = math.max
local math_min   = math.min
local math_abs   = math.abs

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

    local overlay       = self.Overlay
    local clones        = {}

    -- When our overlay is taller than Blizzard’s editbox we compute two
    -- scales.  One keeps anchor points aligned to the real ratio, the
    -- other grows texture heights with a margin so the skin’s corner caps
    -- aren’t squashed and text doesn’t spill past the inset.
    local origH         = origEditBox:GetHeight() or 0
    local vScaleAnchors = 1
    local vScaleSize    = 1
    if origH > 0 and overlayHeight and overlayHeight > 0 then
        local baseScale = overlayHeight / origH
        vScaleAnchors = math_max(1, baseScale)
        -- Extra margin: 50% of the growth beyond 1× for texture sizes.
        local margin = math_max(0, (baseScale - 1) * 0.5)
        vScaleSize = math_max(1, baseScale + margin)
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
                relTo = overlay -- remap to our overlay
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
        return -- nothing to adopt
    end

    self._skinProxyTextures = clones
    self._skinProxySourceEB = origEditBox

    -- Apply user's backdrop colour as a tint over the cloned textures.
    local inputBg           = cfg.InputBg or {}
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

    local isDefault = (math_abs(r - defR) < 0.01)
        and (math_abs(g - defG) < 0.01)
        and (math_abs(b - defB) < 0.01)
        and (math_abs(a - defA) < 0.01)
    if isDefault then
        return -- leave the original Blizzard tint as-is
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
