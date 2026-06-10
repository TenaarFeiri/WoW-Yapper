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

    -- Proxy mode: the new approach keeps the original Blizzard editbox
    -- visible behind a transparent Yapper overlay (see EditBox:ApplyProxyMode).
    -- Texture cloning is deprecated and only runs when the legacy flag is set.
    if cfg.UseLegacyCloneProxy ~= true then
        -- Clean up any leftover clones from a previous legacy session.
        if self._skinProxyTextures then
            self:DetachBlizzardSkinProxy()
        end

        -- When proxy mode is enabled, immediately Show() the Blizzard editbox
        -- at deactivated opacity (0.35) to mimic Blizzard's IM mode behavior
        if origEditBox and origEditBox.Show then
            pcall(function() origEditBox:Show() end)
            local DEFAULT_DEACTIVATED_ALPHA = 0.35
            local ALPHA_TOLERANCE = 0.01
            local currentAlpha = origEditBox.GetAlpha and origEditBox:GetAlpha() or 1.0
            -- Only set alpha if current alpha is a default value
            if math_abs(currentAlpha - 1.0) < ALPHA_TOLERANCE or 
               math_abs(currentAlpha - DEFAULT_DEACTIVATED_ALPHA) < ALPHA_TOLERANCE then
                if origEditBox.SetAlpha then
                    pcall(function() origEditBox:SetAlpha(DEFAULT_DEACTIVATED_ALPHA) end)
                end
            end
        end

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

    local ebName = origEditBox.GetName and origEditBox:GetName() or "<unknown>"
    Log(string.format("AttachBlizzardSkinProxy: cfg=%s, eb=%s, overlayH=%.1f",
        tostring(cfg.UseBlizzardSkinProxy), ebName, overlayHeight or 0))

    local function IsRenderable(tex)
        if not tex then return false end
        local shown = true
        pcall(function() shown = tex:IsShown() end)
        if not shown then return false end
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
            -- Ensure all clones are actually shown (they may have been hidden)
            for i = 1, #self._skinProxyTextures do
                pcall(function() self._skinProxyTextures[i]:Show() end)
            end
            if overlay.Border then overlay.Border:Hide() end
            Log("Fast-path: reusing existing proxy textures.")
            return
        end
        -- Clones are stale — force a full rebuild below.
        Log("Fast-path: clones are stale, forcing rebuild.")
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
            local ok, objType = pcall(function() return region and region.GetObjectType and region:GetObjectType() end)
            if ok and objType == "Texture" then
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
    -- addonSkinDetected: Only true when Stage 1 found *visible* non-stock textures
    -- or visible Frame regions that have replaced the stock UI. Hidden stock textures
    -- alone must not block Stage 3.
    local addonSkinDetected = false
    if #regions > 0 and #clones == 0 then
        -- Check if any visible regions are non-Texture (e.g., Frame regions from addon skins)
        local hasVisibleNonTexture = false
        for i = 1, #regions do
            local region = regions[i]
            if region then
                local shown = false
                pcall(function() shown = region:IsShown() end)
                if shown then
                    local ok, objType = pcall(function() return region.GetObjectType and region:GetObjectType() end)
                    if ok and objType and objType ~= "Texture" then
                        hasVisibleNonTexture = true
                        break
                    end
                end
            end
        end
        addonSkinDetected = hasVisibleNonTexture
    end
    if #clones > 0 then
        Log(string.format("Stage 1 success: %d visible region(s) cloned.", #clones))
    elseif addonSkinDetected then
        Log(string.format("Stage 1: visible non-Texture regions found (addon skin detected), skipping Stage 3."))
    else
        Log("Stage 1: no cloneable regions — trying Stage 2.")
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
    -- Stage 3: Child frame regions + backdrop cloning.
    -- Handles addons (Prat, ElvUI, etc.) that attach textures to child frames
    -- or use BackdropTemplate backdrops. Child-frame texture cloning is skipped
    -- when addonSkinDetected: those child textures belong to the addon skin.
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
            -- No textures anywhere — try backdrop cloning for addons like Prat.
            local backdropSources = { origEditBox }
            for _, ch in ipairs(children) do backdropSources[#backdropSources + 1] = ch end

            for _, src in ipairs(backdropSources) do
                if #clones == 0 and src.GetBackdrop then
                    pcall(function()
                        local backdrop = src:GetBackdrop()
                        if backdrop and (backdrop.bgFile or backdrop.edgeFile) then
                            -- Copy the full backdrop to Yapper's overlay Border frame
                            if overlay.Border then
                                overlay.Border:SetBackdrop(backdrop)
                                local cr, cg, cb, ca = src:GetBackdropColor()
                                if cr then overlay.Border:SetBackdropColor(cr, cg, cb, ca) end
                                local br, bg, bb, ba = src:GetBackdropBorderColor()
                                if br then overlay.Border:SetBackdropBorderColor(br, bg, bb, ba) end
                                overlay.Border:Show()
                                -- Mark that we used backdrop cloning so RefreshOverlayVisuals doesn't hide it
                                overlay._yapperBackdropProxy = true
                                clones[#clones + 1] = overlay.Border  -- Track as a "clone" for cleanup
                                Log(string.format("Stage 3 backdrop cloning: bgFile=%s, edgeFile=%s",
                                    tostring(backdrop.bgFile), tostring(backdrop.edgeFile)))
                            end
                        elseif src.GetBackdropColor then
                            -- Fallback to solid color only (no backdrop defined)
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
                        end
                    end)
                end
            end

            if #clones == 0 then
                Log("Stage 3: no child regions or backdrop found.")
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

    Log(string.format("AttachBlizzardSkinProxy complete: %d clone(s) active.", #clones))

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

    -- Clear backdrop proxy flag and hide Border if it was used for backdrop cloning
    if self.Overlay then
        self.Overlay._yapperBackdropProxy = nil
        if self.Overlay.Border then
            pcall(function() self.Overlay.Border:SetBackdrop(nil) end)
            self.Overlay.Border:Hide()
        end
    end

    -- Re-show Yapper's own fill (RefreshOverlayVisuals will recolour it).
    if self.Overlay and self.Overlay._yapperSolidFill then
        self.Overlay._yapperSolidFill:Show()
    end
end

-- ---------------------------------------------------------------------------
-- Proxy mode: keep the original Blizzard editbox visible underneath
-- a transparent Yapper overlay so the addon-supplied skin renders natively.
-- ---------------------------------------------------------------------------

--- Names of Blizzard editbox sub-elements that show the channel header text.
--- Hidden by ApplyProxyMode so our own ChannelLabel is the only visible prefix.
local PROXY_HIDE_KEYS = { "header", "headerSuffix", "prompt", "NewcomerHint", "languageHeader" }

--- Activate proxy mode: keep the Blizzard editbox visible underneath.
--- Saves the editbox's pre-state on self._proxyPrevState so RestoreProxyMode
--- can put it back when Yapper closes.
function EditBox:ApplyProxyMode(origEditBox)
    if not origEditBox then return end

    -- Save pre-state so we can restore exactly what we changed.
    local prev = {
        wasShown        = origEditBox:IsShown(),
        mouseEnabled    = origEditBox.IsMouseEnabled and origEditBox:IsMouseEnabled() or nil,
        alpha           = origEditBox:GetAlpha(),
        alphaWasDefault = nil,  -- Track if alpha was a Blizzard default
        hidden          = {},
    }

    -- Check if current alpha matches Blizzard's default values (1.0 activated, 0.35 deactivated).
    -- Also include 0.0 as a default deactivated state (used by Prat/Chatter to hide editbox via alpha).
    -- If so, we can safely change it to mimic the activated state (since Yapper is now open).
    -- If not, assume an addon has overridden it and leave it alone.
    local DEFAULT_ACTIVATED_ALPHA = 1.0
    local DEFAULT_DEACTIVATED_ALPHA = 0.35
    local ALPHA_TOLERANCE = 0.01
    if math_abs(prev.alpha - DEFAULT_ACTIVATED_ALPHA) < ALPHA_TOLERANCE or 
       math_abs(prev.alpha - DEFAULT_DEACTIVATED_ALPHA) < ALPHA_TOLERANCE or
       math_abs(prev.alpha - 0.0) < ALPHA_TOLERANCE then
        prev.alphaWasDefault = true
        -- Mimic Blizzard's activated state (set alpha to 1.0) since Yapper is open
        if origEditBox.SetAlpha then
            pcall(function() origEditBox:SetAlpha(DEFAULT_ACTIVATED_ALPHA) end)
        end
    end

    -- Force-show the original so its skin (Blizzard / Prat / Chattynator / ElvUI) renders.
    -- This must happen BEFORE hiding headers: OnShow triggers UpdateHeader which
    -- re-shows header FontStrings, so we hide them after that side-effect runs.
    if not prev.wasShown and origEditBox.Show then
        pcall(function() origEditBox:Show() end)
    end

    -- Record which header/prompt FontStrings are visible (post-Show, so UpdateHeader
    -- has had a chance to run) and then hide them so our ChannelLabel is the only prefix.
    for _, key in ipairs(PROXY_HIDE_KEYS) do
        local part = origEditBox[key]
        if part and part.IsShown then
            local wasPartShown = part:IsShown()
            prev.hidden[key] = wasPartShown
            if wasPartShown then pcall(function() part:Hide() end) end
        end
    end

    -- Disable mouse so the original doesn't steal focus or clicks from our overlay.
    if origEditBox.EnableMouse then
        pcall(function() origEditBox:EnableMouse(false) end)
    end

    -- Clear any stale text on the original; we don't want it ghost-rendering content.
    if origEditBox.SetText then
        pcall(function() origEditBox:SetText("") end)
    end

    self._proxyPrevState = prev
    self._proxyOrigEditBox = origEditBox

    if YapperTable.Utils and YapperTable.Utils.VerbosePrint then
        YapperTable.Utils:VerbosePrint(string.format(
            "[ProxyMode] ApplyProxyMode on %s (wasShown=%s, mouse=%s, alphaWasDefault=%s).",
            (origEditBox.GetName and origEditBox:GetName()) or "<unknown>",
            tostring(prev.wasShown), tostring(prev.mouseEnabled), tostring(prev.alphaWasDefault)))
    end
end

--- Restore the original editbox to the state we found it in.
--- Idempotent: safe to call when proxy mode wasn't active.
function EditBox:RestoreProxyMode()
    local prev = self._proxyPrevState
    local origEditBox = self._proxyOrigEditBox
    self._proxyPrevState = nil
    self._proxyOrigEditBox = nil
    if not prev or not origEditBox then return end

    -- Re-enable mouse if it was on before.
    if prev.mouseEnabled and origEditBox.EnableMouse then
        pcall(function() origEditBox:EnableMouse(true) end)
    end

    -- Restore header/prompt visibility.
    for key, wasShown in pairs(prev.hidden) do
        local part = origEditBox[key]
        if part and wasShown then
            pcall(function() part:Show() end)
        end
    end

    -- Restore alpha only if it was a Blizzard default (1.0 or 0.35).
    -- If an addon had overridden it, leave it alone.
    if prev.alphaWasDefault and prev.alpha and origEditBox.SetAlpha then
        pcall(function() origEditBox:SetAlpha(prev.alpha) end)
    end

    -- Hide the frame if it was hidden before proxy mode opened.
    -- This handles chat reskinners that hide the editbox by default.
    if not prev.wasShown and origEditBox.Hide then
        pcall(function() origEditBox:Hide() end)
    end

    if YapperTable.Utils and YapperTable.Utils.VerbosePrint then
        YapperTable.Utils:VerbosePrint(string.format(
            "[ProxyMode] RestoreProxyMode on %s (wasShown=%s, alphaWasDefault=%s).",
            (origEditBox.GetName and origEditBox:GetName()) or "<unknown>",
            tostring(prev.wasShown), tostring(prev.alphaWasDefault)))
    end
end

-- Perform one-pass visual refresh (fills, anchors, colours, border). `pad` is 0 or overlay.BorderPad; call only from ShowOverlay/ApplyConfigToLiveOverlay.
