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
        if self._skinProxyTextures then
            self:DetachBlizzardSkinProxy()
        end
        return
    end
    if not self.Overlay or not origEditBox then
        return
    end

    -- -----------------------------------------------------------------------
    -- Helpers
    -- -----------------------------------------------------------------------
    local function IsRenderable(tex)
        if not tex then return false end
        local ok, atlas = pcall(tex.GetAtlas, tex)
        if ok and atlas and atlas ~= "" then return true end
        local ok2, file = pcall(tex.GetTexture, tex)
        if ok2 and file and file ~= "" then return true end
        -- ColorTexture: no atlas/file, but has non-zero vertex alpha.
        local ok3, _, _, _, a = pcall(tex.GetVertexColor, tex)
        if ok3 and a and a > 0 then return true end
        return false
    end

    local function AnyRenderable(clones)
        if not clones then return false end
        for i = 1, #clones do
            if IsRenderable(clones[i]) then return true end
        end
        return false
    end

    -- -----------------------------------------------------------------------
    -- Fast-path with stale-proxy guard
    -- -----------------------------------------------------------------------
    if self._skinProxyTextures and self._skinProxySourceEB == origEditBox then
        if AnyRenderable(self._skinProxyTextures) then
            local inputBg = cfg.InputBg or {}
            self:TintSkinProxyTextures(inputBg.r, inputBg.g, inputBg.b, inputBg.a)
            if self.Overlay._yapperSolidFill then self.Overlay._yapperSolidFill:Hide() end
            if self.Overlay.Border then self.Overlay.Border:Hide() end
            return
        end
        -- Clones are dead (source textures destroyed or reskinned). Force rebuild.
        self:DetachBlizzardSkinProxy()
    end

    -- -----------------------------------------------------------------------
    -- Rebuild
    -- -----------------------------------------------------------------------
    self:DetachBlizzardSkinProxy()

    local overlay       = self.Overlay
    local clones        = {}

    local origH         = origEditBox:GetHeight() or 0
    local vScaleAnchors = 1
    local vScaleSize    = 1
    if origH > 0 and overlayHeight and overlayHeight > 0 then
        local baseScale = overlayHeight / origH
        vScaleAnchors = math_max(1, baseScale)
        local margin = math_max(0, (baseScale - 1) * 0.5)
        vScaleSize = math_max(1, baseScale + margin)
    end

    local function mirrorAnchors(tex, region)
        tex:ClearAllPoints()
        local numPoints = region:GetNumPoints() or 0
        if numPoints == 0 then
            tex:SetAllPoints(overlay)
            return
        end
        for pi = 1, numPoints do
            local point, relTo, relPoint, xOfs, yOfs = region:GetPoint(pi)
            if relTo == origEditBox then
                relTo = overlay
            end
            local scaledYOfs = yOfs
            if vScaleAnchors > 1 then
                scaledYOfs = yOfs * vScaleAnchors
            end
            tex:SetPoint(point, relTo, relPoint, xOfs, scaledYOfs)
        end
    end

    --- Clone a single Texture region onto the overlay.
    local function CloneRegion(region)
        local ok = pcall(function()
            local drawLayer, subLevel = region:GetDrawLayer()
            local tex = overlay:CreateTexture(nil, drawLayer or "BACKGROUND", nil, subLevel or 0)

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
                else
                    -- ColorTexture fallback (Chattynator Dark, etc.)
                    local r, g, b, a = region:GetVertexColor()
                    tex:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
                end
            end

            tex:SetVertexColor(1, 1, 1, 1)
            pcall(function()
                tex:SetAlpha(region:GetAlpha())
            end)
            pcall(function()
                local blend = region:GetBlendMode()
                if blend then tex:SetBlendMode(blend) end
            end)
            pcall(function()
                local w, h = region:GetSize()
                if w and w > 0 then tex:SetWidth(w) end
                if h and h > 0 then tex:SetHeight(h * vScaleSize) end
            end)
            mirrorAnchors(tex, region)
            tex:Show()

            -- Discard clones that failed to acquire any texture data.
            if IsRenderable(tex) then
                clones[#clones + 1] = tex
            else
                tex:Hide()
                tex:SetTexture(nil)
            end
        end)
    end

    -- Phase 1: Direct child regions of the editbox.
    local regions = { origEditBox:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then
            CloneRegion(region)
        end
    end

    -- Phase 2: Named global textures (reparented but not destroyed).
    if #clones == 0 then
        local name = origEditBox.GetName and origEditBox:GetName()
        if name then
            for _, suffix in ipairs({"Left", "Right", "Mid", "FocusLeft", "FocusRight", "FocusMid"}) do
                local tex = _G[name .. suffix]
                if tex and tex.GetObjectType and tex:GetObjectType() == "Texture" then
                    CloneRegion(tex)
                end
            end
        end
    end

    -- Phase 3: Generic addon replacement detection
    -- GetChildren() returns child Frames (e.g. ElvUI's `backdrop` frame).
    -- Recurse one level: clone any Texture regions belonging to those children,
    -- and read their backdrop colour as a final fallback.
    if #clones == 0 then
        local children = { origEditBox:GetChildren() }
        for i = 1, #children do
            local child = children[i]
            if child and child.GetRegions then
                local subRegions = { child:GetRegions() }
                for j = 1, #subRegions do
                    local r = subRegions[j]
                    if r and r.GetObjectType and r:GetObjectType() == "Texture" then
                        CloneRegion(r)
                    end
                end
                if #clones == 0 and child.GetBackdropColor then
                    pcall(function()
                        local cr, cg, cb, ca = child:GetBackdropColor()
                        if ca and ca > 0 then
                            local tex = overlay:CreateTexture(nil, "BACKGROUND")
                            tex:SetColorTexture(cr, cg, cb, ca)
                            tex:SetAllPoints(overlay)
                            tex:Show()
                            clones[#clones + 1] = tex
                        end
                    end)
                end
            end
        end
    end

    -- Phase 4: Fallback to backdrop color if no textures were found.
    -- Many addons only change the backdrop color instead of creating new textures.
    if #clones == 0 and origEditBox.GetBackdropColor then
        pcall(function()
            local r, g, b, a = origEditBox:GetBackdropColor()
            -- Only use the backdrop color if it's sensible (non-zero alpha).
            if a and a > 0 then
                local tex = overlay:CreateTexture(nil, "BACKGROUND")
                tex:SetColorTexture(r or 0.1, g or 0.1, b or 0.1, a or 0.8)
                tex:SetAllPoints(overlay)
                tex:Show()
                clones[#clones + 1] = tex
            end
        end)
    end

    -- -----------------------------------------------------------------------
    -- Hardened fallback: nothing usable found → clear proxy state entirely
    -- so RefreshOverlayVisuals falls back to Yapper's own solid fill.
    -- -----------------------------------------------------------------------
    if #clones == 0 then
        self:DetachBlizzardSkinProxy()
        return
    end

    self._skinProxyTextures = clones
    self._skinProxySourceEB = origEditBox

    local inputBg = cfg.InputBg or {}
    self:TintSkinProxyTextures(inputBg.r, inputBg.g, inputBg.b, inputBg.a)

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
