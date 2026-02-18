--[[
    Theme.lua
    Lightweight theme registry for EditBox styling.

    This module provides a non-invasive API for registering and applying
    visual themes to frames. It intentionally does NOT hook into the
    EditBox or Interface yet — that integration will be done separately.
]]

local YapperName, YapperTable = ...

local Theme = {}
YapperTable.Theme = Theme

-- Registry of themes: name -> theme table
Theme._registry = {}
Theme._current = nil

-- Public API ------------------------------------------------------------

--- Register a theme.
-- @param name string
-- @param data table
function Theme:RegisterTheme(name, data)
    if type(name) ~= "string" or type(data) ~= "table" then return false end
    self._registry[name] = data
    return true
end

function Theme:GetTheme(name)
    if name == nil then name = self._current end
    return (type(name) == "string") and self._registry[name] or nil
end

function Theme:GetRegisteredNames()
    local out = {}
    for k in pairs(self._registry) do table.insert(out, k) end
    table.sort(out)
    return out
end

--- Set the active theme name (does not apply it to frames).
function Theme:SetTheme(name)
    if type(name) ~= "string" or not self._registry[name] then return false end
    self._current = name
    pcall(function()
        if YapperTable and YapperTable.Utils and YapperTable.Utils.VerbosePrint then
            YapperTable.Utils:VerbosePrint("Theme:SetTheme -> " .. tostring(name))
        end
    end)
    -- Attempt to apply the theme immediately to any live overlay.
    -- Also reflect theme colours into local per-character config unless the
    -- user has explicitly overridden those values via the UI.
    pcall(function()
        local localConf = _G.YapperLocalConf or {}
        if type(localConf.EditBox) ~= "table" then localConf.EditBox = {} end
        if type(localConf._themeOverrides) ~= "table" then localConf._themeOverrides = {} end
        local theme = self._registry[name]
        if type(theme) == "table" then
            local function applyIfNotOverridden(key, themeField)
                if localConf._themeOverrides[key] == true then return end
                if type(theme[themeField]) == "table" then
                    localConf.EditBox[key] = {
                        r = theme[themeField].r or 1,
                        g = theme[themeField].g or 1,
                        b = theme[themeField].b or 1,
                        a = theme[themeField].a ~= nil and theme[themeField].a or 1,
                    }
                end
            end
            applyIfNotOverridden("InputBg", "inputBg")
            applyIfNotOverridden("LabelBg", "labelBg")
            applyIfNotOverridden("TextColor", "textColor")
            applyIfNotOverridden("BorderColor", "borderColor")
            -- Remember which theme we last applied programmatically.
            localConf._appliedTheme = name
            _G.YapperLocalConf = localConf
        end
    end)

    if YapperTable and YapperTable.EditBox and type(YapperTable.EditBox.ApplyConfigToLiveOverlay) == "function" then
        pcall(function()
            YapperTable.EditBox:ApplyConfigToLiveOverlay(true)
        end)
    end
    return true
end

--- Apply a theme to a frame.
-- This attempts only non-invasive visual calls and wraps them in pcall
-- to avoid hard failures. Returns true on success.
function Theme:ApplyToFrame(frame, name)
    if type(frame) ~= "table" then return false end
    local theme = self:GetTheme(name)
    if not theme then return false end

    -- Diagnostic: verbose only, not spammy.
    pcall(function()
        if YapperTable and YapperTable.Utils and YapperTable.Utils.VerbosePrint then
            YapperTable.Utils:VerbosePrint("Theme:ApplyToFrame '" .. tostring(name or self._current) .. "'")
        end
    end)

    -- NOTE: inputBg / labelBg / textColor / borderColor are intentionally NOT
    -- applied here.  ApplyConfigToLiveOverlay is the single place that reads
    -- those from config and writes them to the frame, so there is no fighting.
    -- ApplyToFrame handles only font overrides and the optional OnApply hook.

    -- Font application helper: apply to known sub-elements if possible.
    if type(theme.font) == "table" then
        local f = theme.font
        if type(frame.OverlayEdit) == "table" and type(frame.OverlayEdit.SetFont) == "function" then
            pcall(function()
                if f.path and f.size then
                    frame.OverlayEdit:SetFont(f.path, f.size, f.flags)
                elseif f.size then
                    -- Try to preserve face when only size provided.
                    local face, _, flags = frame.OverlayEdit:GetFont()
                    frame.OverlayEdit:SetFont(face or f.path, f.size, f.flags or flags)
                end
            end)
        end
        if type(frame.ChannelLabel) == "table" and type(frame.ChannelLabel.SetFont) == "function" then
            pcall(function()
                if f.path and f.size then
                    frame.ChannelLabel:SetFont(f.path, f.size, f.flags)
                end
            end)
        end
    end

    -- Call optional OnApply hook provided by theme authors.
    if type(theme.OnApply) == "function" then
        pcall(function() theme.OnApply(frame) end)
    end

    return true
end

-- Diagnostics: verbose report of what elements Theme:ApplyToFrame can see.
local function _logThemeApply(frame)
    if not YapperTable or not YapperTable.Utils or not YapperTable.Utils.VerbosePrint then return end
    local hasInputBg = type(frame._yapperSolidFill) == "table" and type(frame._yapperSolidFill.SetColorTexture) == "function"
    local hasLabelBg = type(frame.LabelBg) == "table" and type(frame.LabelBg._yapperSolidFill) == "table"
    local hasOverlayEdit = type(frame.OverlayEdit) == "table" and type(frame.OverlayEdit.SetTextColor) == "function"
    local hasChannelLabel = type(frame.ChannelLabel) == "table" and type(frame.ChannelLabel.SetTextColor) == "function"
    local msg = string.format("Theme:ApplyToFrame diagnostics — inputBg=%s, labelBg=%s, overlayEdit=%s, channelLabel=%s",
        tostring(hasInputBg), tostring(hasLabelBg), tostring(hasOverlayEdit), tostring(hasChannelLabel))
    YapperTable.Utils:VerbosePrint(msg)
end

-- Wrap original ApplyToFrame to emit diagnostics when Verbose logging is enabled.
local _origApply = Theme.ApplyToFrame
function Theme:ApplyToFrame(frame, name)
    local ok, res = pcall(_origApply, self, frame, name)
    if ok then
        pcall(_logThemeApply, frame)
    else
        if YapperTable and YapperTable.Utils and YapperTable.Utils.Print then
            YapperTable.Utils:Print("error", "Theme:ApplyToFrame failed: " .. tostring(res))
        end
    end
    return ok and res or false
end

-- Convenience aliases on the global Yapper table for external addons.
function YapperTable:RegisterTheme(name, data) return Theme:RegisterTheme(name, data) end
function YapperTable:SetTheme(name) return Theme:SetTheme(name) end
function YapperTable:GetRegisteredThemes() return Theme:GetRegisteredNames() end

-- Register a sane default so the system is immediately usable.
-- Derive defaults from existing EditBox/Interface config values.
local defaultTheme = {
    name = "Yapper Default",
    description = "Matches current Yapper overlay defaults (flat fill, label bar, default font).",
    -- Backdrop left nil because Yapper uses a solid texture fill by default.
    backdrop = nil,
    -- These match `DEFAULTS.EditBox` values used in `Src/Core.lua` / `EditBox.lua`.
    inputBg = { r = 0.05, g = 0.05, b = 0.05, a = 1.0 },
    labelBg = { r = 0.06, g = 0.06, b = 0.06, a = 0.9 },
    textColor = { r = 1, g = 1, b = 1, a = 1 },
    border = false,
    borderColor = { r = 0.0, g = 0.0, b = 0.0, a = 0 },
    channelTextColors = {
        SAY = { r = 1.00, g = 1.00, b = 1.00, a = 1 },
        YELL = { r = 1.00, g = 0.25, b = 0.25, a = 1 },
        PARTY = { r = 0.67, g = 0.67, b = 1.00, a = 1 },
        WHISPER = { r = 1.00, g = 0.50, b = 1.00, a = 1 },
        INSTANCE_CHAT = { r = 1.00, g = 0.50, b = 0.00, a = 1 },
        RAID = { r = 1.00, g = 0.50, b = 0.00, a = 1 },
        RAID_WARNING = { r = 1.00, g = 0.28, b = 0.03, a = 1 },
    },
    font = { path = nil, size = 14, flags = "" },
}
Theme:RegisterTheme(defaultTheme.name, defaultTheme)
Theme._current = defaultTheme.name

YapperTable.Utils:VerbosePrint("Theme: lightweight registry initialised.")

return Theme
