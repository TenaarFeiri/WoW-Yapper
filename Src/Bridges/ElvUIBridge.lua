--[[
    Bridges/ElvUIBridge.lua
    When both the Blizzard skin proxy AND ElvUI are present, override Yapper's
    overlay colours with ElvUI's own colour scheme so the two UIs look consistent.

    Colour sources (all in E.media, each is a {r,g,b,a} table with both named
    and numeric indices kept in sync by ElvUI's VerifyColorTable):
        E.media.backdropcolor      — main frame background (default: 0.1/0.1/0.1/1)
        E.media.backdropfadecolor  — faded/transparent variant  (default: 0.06/0.06/0.06/0.8)
        E.media.bordercolor        — border / edge colour  (default: 0/0/0/1)

    When activated the bridge:
      1. Snapshots the current overlay colours and active theme name.
      2. Registers/updates an "ElvUI" theme with the current E.media values.
      3. Calls Theme:SetLiveTheme("ElvUI") — applies colours without overwriting
         the user's saved theme preference (_appliedTheme).

    When deactivated (proxy toggled off, or ElvUI not available on login) the
    bridge restores the snapshotted config and theme name so nothing persists.

    ElvUI's 'StaggeredUpdate' callback fires whenever the user changes colours
    in ElvUI options.  The bridge hooks it to keep the overlay in sync without
    requiring a reload.
]]

local _, YapperTable = ...

local ElvUIBridge        = {}
YapperTable.ElvUIBridge  = ElvUIBridge

-- Re-localise state machine for internal guards
local State         = YapperTable.State

-- Re-localise Lua globals.
local type   = type
local pcall  = pcall
local pairs  = pairs

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Return the ElvUI core object, or nil.
local function GetE()
    local tbl = _G.ElvUI
    if type(tbl) == "table" then
        return tbl[1]
    end
    return nil
end

--- Read r/g/b/a from an ElvUI color table safely.
--- Prefers named keys (.r .g .b .a); falls back to numeric indices.
local function ReadColor(c, defR, defG, defB, defA)
    if type(c) ~= "table" then
        return defR or 0, defG or 0, defB or 0, defA or 1
    end
    local r = (type(c.r) == "number") and c.r or (type(c[1]) == "number" and c[1]) or defR or 0
    local g = (type(c.g) == "number") and c.g or (type(c[2]) == "number" and c[2]) or defG or 0
    local b = (type(c.b) == "number") and c.b or (type(c[3]) == "number" and c[3]) or defB or 0
    local a = (type(c.a) == "number") and c.a or (type(c[4]) == "number" and c[4]) or defA or 1
    return r, g, b, a
end

--- Build a Yapper theme table from the current ElvUI media colours.
local function BuildTheme(E)
    local media = E.media or {}

    -- Background: use the main backdrop colour.
    local bgR, bgG, bgB, bgA = ReadColor(media.backdropcolor,     0.10, 0.10, 0.10, 1.0)
    -- Label background: use the faded/transparent variant.
    local lbR, lbG, lbB, lbA = ReadColor(media.backdropfadecolor, 0.06, 0.06, 0.06, 0.8)
    -- Border: ElvUI uses a very dark/black border by default.
    local bdR, bdG, bdB, bdA = ReadColor(media.bordercolor,       0.0,  0.0,  0.0,  1.0)

    return {
        name        = "ElvUI",
        description = "Mirrors your ElvUI colour scheme (managed automatically by Yapper).",
        inputBg     = { r = bgR, g = bgG, b = bgB, a = bgA },
        labelBg     = { r = lbR, g = lbG, b = lbB, a = lbA },
        textColor   = { r = 1,   g = 1,   b = 1,   a = 1   },
        borderColor = { r = bdR, g = bdG, b = bdB, a = bdA  },
        border      = true,
        -- ElvUI uses thin pixel-art borders; rounded corners and drop shadows
        -- are not part of the ElvUI aesthetic.
        allowRoundedCorners = false,
        allowDropShadow     = false,
        font = { path = nil, flags = "" },
    }
end

--- Take a shallow copy of the colour-relevant fields from EditBox config.
local function SnapshotColors(editCfg)
    local function copyColor(c)
        if type(c) ~= "table" then return nil end
        return { r = c.r, g = c.g, b = c.b, a = c.a }
    end
    return {
        InputBg     = copyColor(editCfg.InputBg),
        LabelBg     = copyColor(editCfg.LabelBg),
        TextColor   = copyColor(editCfg.TextColor),
        BorderColor = copyColor(editCfg.BorderColor),
    }
end

-- ---------------------------------------------------------------------------
-- Activation / deactivation
-- ---------------------------------------------------------------------------

ElvUIBridge.active = false

--- Activate the ElvUI colour override.
--- Registers the "ElvUI" theme and applies it as a live (non-persisted) override.
--- Returns true if the override was applied.
function ElvUIBridge:Activate()
    -- Require the skin proxy to be enabled.
    local cfg = YapperTable.Config and YapperTable.Config.EditBox or {}
    if cfg.UseBlizzardSkinProxy == false then return false end

    local E = GetE()
    if not E or not E.media then return false end

    local th = YapperTable.Theme
    if not th then return false end

    -- Snapshot current state so we can restore it on deactivation.
    local localConf = _G.YapperLocalConf or {}
    local useGlobal = localConf.System and localConf.System.UseGlobalProfile == true and type(_G.YapperDB) == "table"
    local profileRoot = useGlobal and _G.YapperDB or localConf
    local editCfg   = (type(profileRoot) == "table" and profileRoot.EditBox) or {}
    self._savedThemeName    = th._current
    self._savedAppliedTheme = (type(profileRoot) == "table" and profileRoot._appliedTheme) or nil
    self._savedColors       = SnapshotColors(editCfg)

    -- Register (or update) the ElvUI theme with current colours.
    local theme = BuildTheme(E)
    th:RegisterTheme("ElvUI", theme)

    -- Apply as a live override (does not touch _appliedTheme).
    local ok = th:SetLiveTheme("ElvUI")
    if not ok then
        -- Couldn't apply — clear the snapshot so Deactivate is a no-op.
        self._savedThemeName    = nil
        self._savedAppliedTheme = nil
        self._savedColors       = nil
        return false
    end

    self.active = true
    pcall(function()
        if YapperTable.Utils then
            YapperTable.Utils:VerbosePrint("ElvUIBridge: activated — ElvUI colour scheme applied.")
        end
    end)
    return true
end

--- Deactivate the ElvUI colour override and restore the previous state.
function ElvUIBridge:Deactivate()
    if not self.active then return end
    self.active = false

    local th        = YapperTable.Theme
    local localConf = _G.YapperLocalConf or {}
    local useGlobal = localConf.System and localConf.System.UseGlobalProfile == true and type(_G.YapperDB) == "table"
    local targetRoot = useGlobal and _G.YapperDB or localConf

    -- Restore config colours from the snapshot.
    if type(targetRoot) == "table" and type(self._savedColors) == "table" then
        if type(targetRoot.EditBox) ~= "table" then targetRoot.EditBox = {} end
        for key, val in pairs(self._savedColors) do
            targetRoot.EditBox[key] = val and { r = val.r, g = val.g, b = val.b, a = val.a } or nil
            if useGlobal and type(localConf.EditBox) == "table" then
                localConf.EditBox[key] = nil
            end
        end
        targetRoot._appliedTheme = self._savedAppliedTheme
        if useGlobal then
            localConf._appliedTheme = nil
        end
        _G.YapperLocalConf = localConf
    end

    -- Restore Theme._current so GetCurrentTheme() reflects the right name.
    if th and self._savedThemeName then
        th._current = self._savedThemeName
    end

    -- Refresh the live overlay with the restored config.
    if YapperTable.EditBox and type(YapperTable.EditBox.ApplyConfigToLiveOverlay) == "function" then
        pcall(function() YapperTable.EditBox:ApplyConfigToLiveOverlay(true) end)
    end

    -- Refresh multiline frame if it is currently open.
    if YapperTable.Multiline and State:IsMultiline()
            and type(YapperTable.Multiline.ApplyTheme) == "function" then
        pcall(function() YapperTable.Multiline:ApplyTheme() end)
    end

    if YapperTable.API then
        YapperTable.API:Fire("THEME_CHANGED", self._savedThemeName)
    end

    self._savedThemeName    = nil
    self._savedAppliedTheme = nil
    self._savedColors       = nil

    pcall(function()
        if YapperTable.Utils then
            YapperTable.Utils:VerbosePrint("ElvUIBridge: deactivated — previous colour scheme restored.")
        end
    end)
end

--- Re-read ElvUI colours and update the running theme.
--- Called when ElvUI fires its 'StaggeredUpdate' callback (e.g. after the
--- user changes colours in ElvUI options).
function ElvUIBridge:RefreshColors()
    if not self.active then return end
    local E = GetE()
    if not E or not E.media then return end
    local th = YapperTable.Theme
    if not th then return end

    -- Update the registered theme data with current ElvUI colours.
    local theme = BuildTheme(E)
    th:RegisterTheme("ElvUI", theme)

    -- Re-apply via SetLiveTheme so the overlay refreshes immediately.
    pcall(function() th:SetLiveTheme("ElvUI") end)
end

-- ---------------------------------------------------------------------------
-- Auto-detection and proxy toggle wiring
-- ---------------------------------------------------------------------------

--- Check conditions and activate or deactivate the bridge as appropriate.
function ElvUIBridge:Sync()
    local cfg        = YapperTable.Config and YapperTable.Config.EditBox or {}
    local proxyOn    = cfg.UseBlizzardSkinProxy == true
    local elvuiHere  = GetE() ~= nil

    if proxyOn and elvuiHere then
        if not self.active then
            self:Activate()
        end
    else
        if self.active then
            self:Deactivate()
        end
    end
end

-- Wire up to the CONFIG_CHANGED callback so toggling the proxy setting
-- instantly enables/disables the ElvUI colour override.
local function OnConfigChanged(path, _value)
    if path == "EditBox.UseBlizzardSkinProxy" then
        ElvUIBridge:Sync()
    end
end

-- Wire up on PLAYER_LOGIN (all addons loaded).
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    loader:UnregisterEvent("PLAYER_LOGIN")
    loader:SetScript("OnEvent", nil)

    ElvUIBridge:Sync()

    -- Hook ElvUI's StaggeredUpdate callback to refresh colours when the
    -- user changes ElvUI settings without a reload.
    local E = GetE()
    if E and E.callbacks and type(E.callbacks.RegisterCallback) == "function" then
        pcall(function()
            E.callbacks:RegisterCallback("StaggeredUpdate", function()
                ElvUIBridge:RefreshColors()
            end)
        end)
    end
end)

-- Register the config-change listener.  YapperAPI may not exist yet at file
-- load time (bridges load before Core finishes wiring), so use a deferred
-- registration via the same PLAYER_LOGIN gate already used above, or fall
-- back to a direct callback registration if YapperAPI is already live.
local function WireConfigListener()
    if _G.YapperAPI and type(_G.YapperAPI.RegisterCallback) == "function" then
        _G.YapperAPI:RegisterCallback("CONFIG_CHANGED", OnConfigChanged)
    end
end
-- YapperAPI is loaded before bridges (see Yapper.toc), so this always succeeds.
WireConfigListener()
