--[[
    Interface/Config.lua
    Configuration getters/setters, minimap button helpers, theme override
    checks, and config sanitisation.
]]

local _, YapperTable = ...
local Interface      = YapperTable.Interface

-- Re-localise shared helpers from hub.
local JoinPath              = Interface.JoinPath
local GetPathValue          = Interface.GetPathValue
local SetPathValue          = Interface.SetPathValue
local NormalizeChatMarkers  = Interface.NormalizeChatMarkers
local Clamp01               = Interface.Clamp01
local TrimString            = Interface.TrimString
local PruneUnknown          = Interface.PruneUnknown
local IsAnchorPoint         = Interface.IsAnchorPoint
local IsColourTable         = Interface.IsColourTable
local CopyColour            = Interface.CopyColour
local COLOUR_KEYS           = Interface._COLOUR_KEYS
local FRIENDLY_LABELS       = Interface._FRIENDLY_LABELS
local SETTING_TOOLTIPS      = Interface._SETTING_TOOLTIPS

-- Re-localise Lua globals.
local type     = type
local tonumber = tonumber
local math_rad = math.rad
local math_cos = math.cos
local math_sin = math.sin
local math_deg = math.deg
local math_atan2 = math.atan2 or math.atan

function Interface:GetLocalConfigRoot()
    if type(_G.YapperLocalConf) ~= "table" then
        _G.YapperLocalConf = {}
    end
    return _G.YapperLocalConf
end

function Interface:GetDefaultsRoot()
    if YapperTable.Core and YapperTable.Core.GetDefaults then
        return YapperTable.Core:GetDefaults()
    end
    return nil
end

function Interface:GetRenderCacheContainer()
    if type(_G.YapperDB) ~= "table" then
        _G.YapperDB = {}
    end
    if type(_G.YapperDB.InterfaceUI) ~= "table" then
        _G.YapperDB.InterfaceUI = {}
    end
    return _G.YapperDB.InterfaceUI
end

-- Drop cached schema so it rebuilds from current defaults/local values.
function Interface:PurgeRenderCache()
    local cache = self:GetRenderCacheContainer()
    cache.schema = nil
    cache.dirty = false
end

function Interface:SetDirty(flag)
    local cache = self:GetRenderCacheContainer()
    cache.dirty = (flag == true)
end

function Interface:IsDirty()
    local cache = self:GetRenderCacheContainer()
    return cache.dirty == true
end

function Interface:SetSettingsChanged(flag)
    local root = self:GetLocalConfigRoot()
    if type(root.System) ~= "table" then
        root.System = {}
    end
    root.System.SettingsHaveChanged = (flag == true)
end

function Interface:GetConfigPath(path)
    local localVal = GetPathValue(self:GetLocalConfigRoot(), path)
    if localVal ~= nil then
        return localVal
    end
    return GetPathValue(YapperTable.Config, path)
end

function Interface:GetDefaultPath(path)
    return GetPathValue(self:GetDefaultsRoot(), path)
end

function Interface:UpdateOverrideTextColorCheckboxState()
    return
end

function Interface:SetLocalPath(path, value)
    local normalizedValue = NormalizeChatMarkers(path, value)

    if type(normalizedValue) == "table"
        and #path >= 2
        and (path[1] == "EditBox" or path[1] == "Spellcheck")
        and COLOUR_KEYS[path[2]] then
        normalizedValue = {
            r = Clamp01(normalizedValue.r, 1),
            g = Clamp01(normalizedValue.g, 1),
            b = Clamp01(normalizedValue.b, 1),
            a = Clamp01(normalizedValue.a, 1),
        }
    end

    local localConf = self:GetLocalConfigRoot()
    local targetRoot = localConf
    local isGlobal = localConf.System and localConf.System.UseGlobalProfile == true

    -- Exceptions: certain settings should ALWAYS stay character-local.
    local fullPath = JoinPath(path)
    if fullPath == "System.UseGlobalProfile"
        or fullPath:match("^FrameSettings%.MainWindowPosition")
        or fullPath:match("^System%._")
        or fullPath == "System.SettingsHaveChanged" then
        isGlobal = false
    end

    if isGlobal then
        targetRoot = _G.YapperDB or localConf
    end

    local syncedChatDelineator = nil
    local syncedChatPrefix = nil

    if #path == 2 and path[1] == "Chat"
        and (path[2] == "DELINEATOR" or path[2] == "PREFIX")
        and type(normalizedValue) == "string" then
        local marker = TrimString(normalizedValue)
        if marker == "" then
            syncedChatDelineator = ""
            syncedChatPrefix = ""
        else
            syncedChatDelineator = " " .. marker
            syncedChatPrefix = marker .. " "
        end

        local dKey = (path[2] == "DELINEATOR") and syncedChatDelineator or syncedChatPrefix
        normalizedValue = dKey

        SetPathValue(targetRoot, { "Chat", "DELINEATOR" }, syncedChatDelineator)
        SetPathValue(targetRoot, { "Chat", "PREFIX" }, syncedChatPrefix)

        if isGlobal then
            -- Clear local overrides so inheritance takes over.
            SetPathValue(localConf, { "Chat", "DELINEATOR" }, nil)
            SetPathValue(localConf, { "Chat", "PREFIX" }, nil)
        end
    else
        SetPathValue(targetRoot, path, normalizedValue)
        if isGlobal then
            -- Clear local overrides so inheritance takes over.
            SetPathValue(localConf, path, nil)
        end
    end

    -- If the user is explicitly editing a top-level EditBox colour, mark it
    -- as an explicit override so theme changes won't stomp the user's choice.
    if type(normalizedValue) == "table"
        and #path >= 2
        and path[1] == "EditBox"
        and COLOUR_KEYS[path[2]] then
        if type(localConf._themeOverrides) ~= "table" then localConf._themeOverrides = {} end
        localConf._themeOverrides[path[2]] = true
        _G.YapperLocalConf = localConf
    end

    if type(YapperTable.Config) == "table" and YapperTable.Config ~= targetRoot then
        if syncedChatDelineator and syncedChatPrefix then
            SetPathValue(YapperTable.Config, { "Chat", "DELINEATOR" }, syncedChatDelineator)
            SetPathValue(YapperTable.Config, { "Chat", "PREFIX" }, syncedChatPrefix)
        else
            SetPathValue(YapperTable.Config, path, normalizedValue)
        end
    end
    
    -- Special case for Global Profile toggle itself: trigger a UI refresh notice
    -- if it looks weird, but otherwise just update the live state.
    if fullPath == "System.UseGlobalProfile" then
        if YapperTable.Utils then
            YapperTable.Utils:Print("Global Profile " .. (normalizedValue and "Enabled" or "Disabled") .. ". Refreshing UI...")
        end
        self:BuildConfigUI()
    end

    self:SetSettingsChanged(true)

    if JoinPath(path) == "FrameSettings.MouseWheelStepRate" and type(normalizedValue) == "number" then
        Interface.MouseWheelStepRate = normalizedValue
    elseif JoinPath(path) == "FrameSettings.EnableMinimapButton" then
        Interface:ApplyMinimapButtonVisibility()
    elseif JoinPath(path) == "FrameSettings.MinimapButtonOffset" then
        Interface:PositionMinimapButton()
    elseif JoinPath(path):match("^Spellcheck%.") then
        if JoinPath(path) == "Spellcheck.Enabled" and normalizedValue == false then
            StaticPopup_Show("YAPPER_CONFIRM_DICTIONARY_PURGE")
        end
        if YapperTable.Spellcheck and type(YapperTable.Spellcheck.OnConfigChanged) == "function" then
            YapperTable.Spellcheck:OnConfigChanged()
        end
    elseif JoinPath(path) == "System.EnableGopherBridge" then
        if YapperTable.GopherBridge and YapperTable.GopherBridge.UpdateState then
            YapperTable.GopherBridge:UpdateState(normalizedValue)
        end
    elseif JoinPath(path) == "System.EnableTypingTrackerBridge" then
        if YapperTable.TypingTrackerBridge and YapperTable.TypingTrackerBridge.UpdateState then
            YapperTable.TypingTrackerBridge:UpdateState(normalizedValue)
        end
    elseif (JoinPath(path) == "EditBox.StickyChannel" or JoinPath(path) == "EditBox.StickyGroupChannel")
        and YapperTable.EditBox
        and YapperTable.EditBox.PersistLastUsed then
        -- Apply the new stickiness rules to LastUsed immediately so the next
        -- open reflects the change without needing an open/close cycle first.
        YapperTable.EditBox:PersistLastUsed()
    end

    if path[1] == "EditBox"
        and YapperTable.EditBox
        and YapperTable.EditBox.ApplyConfigToLiveOverlay then
        YapperTable.EditBox:ApplyConfigToLiveOverlay(true)
    end

    -- Also refresh the multiline frame visuals if it is currently open.
    if path[1] == "EditBox"
        and YapperTable.Multiline
        and YapperTable.Multiline.Frame
        and type(YapperTable.Multiline.ApplyTheme) == "function" then
        pcall(function() YapperTable.Multiline:ApplyTheme() end)
    end

    -- Apply active theme immediately when changed.
    if JoinPath(path) == "System.ActiveTheme" then
        if YapperTable.Theme and type(YapperTable.Theme.SetTheme) == "function" then
            pcall(function()
                YapperTable.Theme:SetTheme(value)
            end)
        end
        if YapperTable.EditBox and YapperTable.EditBox.ApplyConfigToLiveOverlay then
            pcall(function()
                YapperTable.EditBox:ApplyConfigToLiveOverlay(true)
            end)
        end
    end

    self:SetDirty(true)
    -- CONFIG_CHANGED callback: notify external addons.
    if YapperTable.API then
        YapperTable.API:Fire("CONFIG_CHANGED", JoinPath(path), normalizedValue)
    end
    return normalizedValue
end

function Interface:GetLauncherTooltipLines()
    return {
        "Left-Click: Toggle Settings",
        "Left-Click (on Help): Go to General",
        "Right-Click: Open Help page",
    }
end

function Interface:GetMinimapButtonSettings()
    if type(_G.YapperDB) ~= "table" then
        _G.YapperDB = {}
    end
    if type(_G.YapperDB.minimapbutton) ~= "table" then
        _G.YapperDB.minimapbutton = { hide = false, angle = 220 }
    end
    if _G.YapperDB.minimapbutton.angle == nil then
        _G.YapperDB.minimapbutton.angle = 220
    end
    return _G.YapperDB.minimapbutton
end

function Interface:GetMinimapButtonOffset()
    return tonumber(self:GetConfigPath({ "FrameSettings", "MinimapButtonOffset" })) or 0
end

function Interface:PositionMinimapButton()
    if not self.MinimapButton or not _G.Minimap then return end
    local minimapCfg = self:GetMinimapButtonSettings()
    local angle = tonumber(minimapCfg.angle) or 220
    local radius = ((_G.Minimap:GetWidth() or 140) / 2) + 10 + self:GetMinimapButtonOffset()
    local rad = math_rad(angle)
    local x = math_cos(rad) * radius
    local y = math_sin(rad) * radius
    self.MinimapButton:ClearAllPoints()
    self.MinimapButton:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
end

function Interface:UpdateMinimapButtonAngleFromCursor()
    if not _G.Minimap then return end
    local mx, my = _G.Minimap:GetCenter()
    if not mx or not my then return end
    local cx, cy = GetCursorPosition()
    local scale = _G.Minimap:GetEffectiveScale()
    cx = cx / scale
    cy = cy / scale
    local dx = cx - mx
    local dy = cy - my
    local angleRad = (math.atan2 and math_atan2(dy, dx)) or math_atan2(dy, dx)
    local angle = math_deg(angleRad)
    local minimapCfg = self:GetMinimapButtonSettings()
    minimapCfg.angle = angle
    self:PositionMinimapButton()
end

function Interface:ApplyMinimapButtonVisibility()
    local enabled = self:GetConfigPath({ "FrameSettings", "EnableMinimapButton" }) ~= false
    local minimapCfg = self:GetMinimapButtonSettings()
    minimapCfg.hide = not enabled

    if self.DBIcon and self.MinimapLDBObject then
        if enabled then
            self.DBIcon:Show(YapperName)
        else
            self.DBIcon:Hide(YapperName)
        end
    end

    if self.MinimapButton then
        if enabled then
            self.MinimapButton:Show()
            self:PositionMinimapButton()
        else
            self.MinimapButton:Hide()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Theme Override Helpers
-- ---------------------------------------------------------------------------

function Interface:IsPathDisabledByTheme(path)
    -- Blizzard skin proxy acts as a high-priority visual override
    if self:GetConfigPath({ "EditBox", "UseBlizzardSkinProxy" }) == true then
        local full = JoinPath(path)
        if full == "EditBox.RoundedCorners" or full == "EditBox.Shadow" or
            full == "EditBox.ShadowSize" or full == "EditBox.ShadowColor" then
            return true
        end
    end

    local activeTheme = YapperTable.Theme and YapperTable.Theme:GetTheme()
    if not activeTheme then return false end

    local full = JoinPath(path)
    if full == "EditBox.RoundedCorners" and activeTheme.allowRoundedCorners == false then
        return true
    end
    if (full == "EditBox.Shadow" or full == "EditBox.ShadowSize" or full == "EditBox.ShadowColor")
        and activeTheme.allowDropShadow == false then
        return true
    end

    return false
end

function Interface:GetFriendlyLabel(item)
    if not item then return "" end
    local baseLabel = ""
    if item.kind == "section" then
        baseLabel = FRIENDLY_LABELS["SECTION." .. item.full] or item.key
    else
        baseLabel = FRIENDLY_LABELS[item.full] or item.key
    end

    -- Blizzard skin proxy overrides
    if self:GetConfigPath({ "EditBox", "UseBlizzardSkinProxy" }) == true then
        if item.full == "EditBox.RoundedCorners" or item.full == "EditBox.Shadow" then
            return baseLabel .. " |cFF888888(Disabled by Blizzard Skin)|r"
        end
    end

    -- Theme-level overrides
    local activeTheme = YapperTable.Theme and YapperTable.Theme:GetTheme()
    if activeTheme then
        if item.full == "EditBox.RoundedCorners" and activeTheme.allowRoundedCorners == false then
            return baseLabel .. " |cFF888888(Disabled by theme)|r"
        elseif item.full == "EditBox.Shadow" and activeTheme.allowDropShadow == false then
            return baseLabel .. " |cFF888888(Disabled by theme)|r"
        end
    end

    return baseLabel
end

function Interface:SanitizeLocalConfig()
    local defaults = self:GetDefaultsRoot()
    local localConf = self:GetLocalConfigRoot()
    if type(defaults) ~= "table" then return end

    PruneUnknown(localConf, defaults)
end
