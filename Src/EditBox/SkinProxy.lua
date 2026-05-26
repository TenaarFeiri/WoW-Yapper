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

    local overlay = self.Overlay

    -- -----------------------------------------------------------------------
    -- Helpers
    -- -----------------------------------------------------------------------
    local function Log(msg)
        if YapperTable.Utils and YapperTable.Utils.VerbosePrint then
            YapperTable.Utils:VerbosePrint("[SkinProxy] " .. msg)
        elseif YapperTable.Utils and YapperTable.Utils.DebugPrint then
            YapperTable.Utils:DebugPrint("[SkinProxy] " .. msg)
        end
    end

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
    -- Fast-path: existing proxy is still valid — just ensure border is hidden.
    -- -----------------------------------------------------------------------
    if self._skinProxyTextures and self._skinProxySourceEB == origEditBox then
        if AnyRenderable(self._skinProxyTextures) then
            if overlay.Border then overlay.Border:Hide() end
            return
        end
        -- Clones are stale — force a full rebuild below.
        self:DetachBlizzardSkinProxy()
    end

    -- -----------------------------------------------------------------------
    -- Phase 0: Reset overlay to a clean slate.
    -- Remove stale clones and hide the border; the InputBg solid fill is left
    -- in place (RefreshOverlayVisuals manages its colour) and acts as the base
    -- background layer behind whatever the stages produce.
    -- -----------------------------------------------------------------------
    self:DetachBlizzardSkinProxy()
    if overlay.Border then overlay.Border:Hide() end

    -- -----------------------------------------------------------------------
    -- Scale helpers for mirroring source anchors/sizes onto the overlay.
    -- -----------------------------------------------------------------------
    local origH = origEditBox:GetHeight() or 0
    local vScaleAnchors = 1
    local vScaleSize    = 1
    if origH > 0 and overlayHeight and overlayHeight > 0 then
        local baseScale = overlayHeight / origH
        vScaleAnchors = math_max(1, baseScale)
        local margin  = math_max(0, (baseScale - 1) * 0.5)
        vScaleSize    = math_max(1, baseScale + margin)
    end

    -- Maps source texture regions to their corresponding clones so that
    -- sibling anchors (e.g. Mid anchored to Left's TOPRIGHT) can be remapped
    -- to the already-created clone rather than falling back to SetAllPoints.
    -- Populated inside CloneRegion as each clone is successfully created.
    local cloneMap = {}

    --- Mirrors source region anchors onto `tex`, remapping origEditBox -> overlay
    --- and known sibling source regions -> their clones via cloneMap.
    --- Returns true only when a truly unknown relTo forced a SetAllPoints fallback.
    local function mirrorAnchors(tex, region)
        tex:ClearAllPoints()
        local numPoints = region:GetNumPoints() or 0
        if numPoints == 0 then
            -- No anchors set on the source — intentional full-coverage texture.
            tex:SetAllPoints(overlay)
            return false
        end
        local remapped = {}
        for pi = 1, numPoints do
            local point, relTo, relPoint, xOfs, yOfs = region:GetPoint(pi)
            local mappedRelTo
            if relTo == origEditBox then
                mappedRelTo = overlay
            else
                mappedRelTo = cloneMap[relTo]  -- sibling clone already created?
            end
            if mappedRelTo then
                local scaledYOfs = yOfs
                if vScaleAnchors > 1 then scaledYOfs = yOfs * vScaleAnchors end
                remapped[#remapped + 1] = { point, mappedRelTo, relPoint, xOfs, scaledYOfs }
            else
                -- Truly unknown relTo — safe SetAllPoints fallback.
                tex:SetAllPoints(overlay)
                return true
            end
        end
        for _, p in ipairs(remapped) do
            tex:SetPoint(p[1], p[2], p[3], p[4], p[5])
        end
        return false
    end

    --- Attempt to clone a single Texture region. Returns the new texture or nil.
    local function CloneRegion(region)
        if not region then return nil end

        -- Gather all properties from the source BEFORE creating anything.
        local drawLayer, subLevel
        pcall(function() drawLayer, subLevel = region:GetDrawLayer() end)

        local atlas
        pcall(function() atlas = region.GetAtlas and region:GetAtlas() end)

        local file
        pcall(function() file = region.GetTexture and region:GetTexture() end)

        local tL, tT, tR, tB, bL, bT, bR, bB
        local hasTexCoords = false
        pcall(function()
            if region.GetTexCoord then
                tL, tT, tR, tB, bL, bT, bR, bB = region:GetTexCoord()
                if tL then hasTexCoords = true end
            end
        end)

        local vr, vg, vb, va
        pcall(function()
            if region.GetVertexColor then vr, vg, vb, va = region:GetVertexColor() end
        end)

        local alpha = 1
        pcall(function() if region.GetAlpha then alpha = region:GetAlpha() end end)

        local blendMode
        pcall(function() if region.GetBlendMode then blendMode = region:GetBlendMode() end end)

        local w, h = 0, 0
        pcall(function() if region.GetSize then w, h = region:GetSize() end end)

        -- Validate: must have an atlas, a texture file, or non-zero-alpha color data.
        local isColorTex = (not atlas or atlas == "") and (not file or file == "") and (va and va > 0)
        if not ((atlas and atlas ~= "") or (file and file ~= "") or isColorTex) then
            return nil
        end

        -- Skip neutral white ColorTextures (no atlas/file, all vertex channels ≥ 0.95,
        -- fully opaque).  These are dynamic backgrounds that addon skins tint at runtime
        -- via SetVertexColor; cloning them at their default white state would paint a
        -- white/grey rectangle over our dark fill instead of inheriting the intended colour.
        if isColorTex
            and (vr or 1) >= 0.95 and (vg or 1) >= 0.95 and (vb or 1) >= 0.95
            and (alpha or 1) >= 0.95
        then
            Log("Skipping neutral white ColorTexture (dynamic background — not cloned).")
            return nil, false
        end

        -- Create the clone and apply all gathered properties.
        local tex
        local usedFallbackAnchor = false
        local ok = pcall(function()
            tex = overlay:CreateTexture(nil, drawLayer or "BACKGROUND", nil, subLevel or 0)
            if not tex then error("CreateTexture returned nil") end

            if atlas and atlas ~= "" then
                tex:SetAtlas(atlas, region.IsAtlasUsingSize and region:IsAtlasUsingSize() or false)
            elseif file and file ~= "" then
                tex:SetTexture(file)
                if hasTexCoords then
                    tex:SetTexCoord(tL, tT, tR, tB, bL, bT, bR, bB)
                end
            else
                tex:SetColorTexture(vr or 0, vg or 0, vb or 0, va or 1)
            end

            -- Prevent tiling from causing repeat artefacts at the edges.
            pcall(function() tex:SetHorizTile(false) end)
            pcall(function() tex:SetVertTile(false) end)

            tex:SetVertexColor(vr or 1, vg or 1, vb or 1, va or 1)
            tex:SetAlpha(alpha)
            if blendMode then tex:SetBlendMode(blendMode) end
            if w and w > 0 then tex:SetWidth(w) end
            if h and h > 0 then tex:SetHeight(h * vScaleSize) end
            usedFallbackAnchor = mirrorAnchors(tex, region)
            tex:Show()
        end)

        if ok and tex and IsRenderable(tex) then
            cloneMap[region] = tex  -- register so sibling textures can remap to this clone
            return tex, usedFallbackAnchor
        end
        -- Something went wrong — destroy the half-built texture to avoid white boxes.
        if tex then pcall(function() tex:Hide(); tex:SetTexture(nil) end) end
        return nil, false
    end

    --- Clone all Texture regions in `list` that are currently visible (IsShown).
    --- When the result contains both properly-anchored and sibling-fallback clones,
    --- the fallback ones are discarded: the _yapperSolidFill provides the background
    --- for the gap between cap textures (prevents the "dark middle" artefact).
    local function CloneVisibleRegions(list)
        local entries = {}  -- { tex, fallback }
        local hasProper = false
        for i = 1, #list do
            local region = list[i]
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                local shown = true
                pcall(function() shown = region:IsShown() end)
                if shown then
                    local clone, fallback = CloneRegion(region)
                    if clone then
                        entries[#entries + 1] = { tex = clone, fallback = fallback }
                        if not fallback then hasProper = true end
                    end
                end
            end
        end
        -- If any properly-anchored clone exists, drop sibling-fallback ones.
        local result = {}
        for _, e in ipairs(entries) do
            if not (hasProper and e.fallback) then
                result[#result + 1] = e.tex
            else
                Log("Discarding sibling-fallback clone (properly-anchored clone exists).")
                pcall(function() e.tex:Hide(); e.tex:SetTexture(nil) end)
            end
        end
        return result
    end

    local clones = {}

    -- -----------------------------------------------------------------------
    -- Stage 1: Direct child regions (GetRegions) — primary stage.
    -- Sees the *actual* visible state of the editbox, so addon skins that hide
    -- the Blizzard textures and add their own are handled automatically via the
    -- IsShown() filter inside CloneVisibleRegions.
    -- -----------------------------------------------------------------------
    local regions = { origEditBox:GetRegions() }
    clones = CloneVisibleRegions(regions)
    -- addonSkinDetected: Stage 1 found regions but couldn't clone any of them.
    -- This signals the editbox was modified by an addon skin.  Used below to
    -- prevent Stage 2 (named globals) and Stage 3 (child frame textures) from
    -- incorrectly applying Blizzard or unrelated child textures over the skin.
    local addonSkinDetected = (#regions > 0 and #clones == 0)
    if #clones > 0 then
        Log(string.format("Stage 1 success: %d visible region(s) cloned.", #clones))
    elseif addonSkinDetected then
        Log(string.format("Stage 1: %d region(s) found but all skipped (addon skin detected).", #regions))
    else
        Log("Stage 1: no regions on editbox — trying Stage 2.")
    end

    -- -----------------------------------------------------------------------
    -- Stage 2: Named global textures — fallback only when GetRegions() returned
    -- zero regions (truly unmodified editbox, e.g. vanilla Blizzard edge case).
    -- Uses origEditBox:GetName() so it works for any ChatFrame editbox.
    -- -----------------------------------------------------------------------
    if #clones == 0 and #regions == 0 then
        local ebName = origEditBox.GetName and origEditBox:GetName()
        if ebName then
            local namedList = {}
            for _, suffix in ipairs({"Left", "Right", "Mid", "FocusLeft", "FocusRight", "FocusMid"}) do
                local t = _G[ebName .. suffix]
                if t then namedList[#namedList + 1] = t end
            end
            if #namedList > 0 then
                clones = CloneVisibleRegions(namedList)
                if #clones > 0 then
                    Log(string.format("Stage 2 success: %d named texture(s) cloned.", #clones))
                else
                    Log("Stage 2: named globals exist but none are visible/renderable.")
                end
            else
                Log("Stage 2: no named globals found — trying Stage 3.")
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- Stage 3: Child frame regions + backdrop color fallback.
    -- Handles addons (ElvUI, etc.) that attach textures to child frames rather
    -- than directly on the editbox.  Also reads GetBackdropColor() from the
    -- editbox and its children as a last-resort solid-colour clone.
    -- Child-frame texture cloning is skipped when addonSkinDetected: those
    -- child textures belong to the addon skin and look wrong on our overlay.
    -- -----------------------------------------------------------------------
    if #clones == 0 then
        local children = { origEditBox:GetChildren() }
        if not addonSkinDetected then
            for i = 1, #children do
                local child = children[i]
                if child and child.GetRegions then
                    local subRegions = { child:GetRegions() }
                    local childClones = CloneVisibleRegions(subRegions)
                    for _, c in ipairs(childClones) do clones[#clones + 1] = c end
                end
            end
        end

        if #clones > 0 then
            Log(string.format("Stage 3 success: %d region(s) cloned from child frames.", #clones))
        else
            -- No textures anywhere — try backdrop color as a plain solid clone.
            local backdropSources = { origEditBox }
            for _, ch in ipairs(children) do backdropSources[#backdropSources + 1] = ch end

            for _, src in ipairs(backdropSources) do
                if #clones == 0 and src.GetBackdropColor then
                    pcall(function()
                        local cr, cg, cb, ca = src:GetBackdropColor()
                        if ca and ca > 0 then
                            local t = overlay:CreateTexture(nil, "BACKGROUND")
                            t:SetColorTexture(cr, cg, cb, ca)
                            t:SetAllPoints(overlay)
                            t:Show()
                            clones[#clones + 1] = t
                            Log(string.format("Stage 3 backdrop color: r=%.2f g=%.2f b=%.2f a=%.2f",
                                cr, cg, cb, ca))
                        end
                    end)
                end
            end

            if #clones == 0 then
                Log("Stage 3: no child regions or backdrop color found.")
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- Stage 4: Fallback — all stages exhausted.
    -- Leave proxy detached; RefreshOverlayVisuals restores Yapper config fill.
    -- -----------------------------------------------------------------------
    if #clones == 0 then
        Log("Stage 4: all stages exhausted — using Yapper config fill.")
        return
    end

    -- -----------------------------------------------------------------------
    -- Post-build: tint atlas/file clones with the source editbox's backdrop
    -- colour (if available).  Addon skins like Chattynator rely on their
    -- backdrop colour for the actual dark appearance; without this the cloned
    -- neutral/white textures appear grey over our dark fill.
    -- -----------------------------------------------------------------------
    do
        local bdR, bdG, bdB, bdA
        local bdSources = { origEditBox }
        pcall(function()
            for _, ch in ipairs({ origEditBox:GetChildren() }) do
                bdSources[#bdSources + 1] = ch
            end
        end)
        for _, src in ipairs(bdSources) do
            if not bdA and src.GetBackdropColor then
                pcall(function()
                    local r, g, b, a = src:GetBackdropColor()
                    if a and a > 0 then bdR, bdG, bdB, bdA = r, g, b, a end
                end)
            end
        end
        if bdA and bdA > 0 then
            Log(string.format("Tinting %d clone(s) with backdrop color r=%.2f g=%.2f b=%.2f a=%.2f.",
                #clones, bdR, bdG, bdB, bdA))
            for _, clone in ipairs(clones) do
                pcall(function()
                    local hasContent = false
                    local ok1, at = pcall(clone.GetAtlas, clone)
                    if ok1 and at and at ~= "" then hasContent = true end
                    if not hasContent then
                        local ok2, fi = pcall(clone.GetTexture, clone)
                        if ok2 and fi and fi ~= "" then hasContent = true end
                    end
                    if hasContent then
                        clone:SetVertexColor(bdR, bdG, bdB, bdA)
                    end
                end)
            end
        end
    end

    self._skinProxyTextures = clones
    self._skinProxySourceEB = origEditBox
    Log(string.format("Proxy attached with %d clone(s) active.", #clones))
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
