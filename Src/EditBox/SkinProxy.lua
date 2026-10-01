--[[
    EditBox/SkinProxy.lua
    Keep Blizzard's editbox visible under the Yapper overlay so Blizzard- and
    addon-provided chat skins render natively.
]]

local _, YapperTable = ...
local EditBox        = YapperTable.EditBox
local Utils          = YapperTable.Utils

-- Re-localise Lua globals.
local ipairs    = ipairs
local pairs     = pairs
local math_abs  = math.abs
local tostring  = tostring
local string_format = string.format

-- Names of Blizzard editbox sub-elements that show the channel header text.
-- Hidden by ApplyProxyMode so our own ChannelLabel is the only visible prefix.
local PROXY_HIDE_KEYS = { "header", "headerSuffix", "prompt", "NewcomerHint", "languageHeader" }

--- Re-hide Blizzard header/prompt elements that UpdateHeader may re-show.
--- Safe to call repeatedly while proxy mode is active.
function EditBox:EnsureProxyHeaderHidden(origEditBox)
    local cfg = YapperTable.Config and YapperTable.Config.EditBox
    if not (cfg and cfg.UseBlizzardSkinProxy == true) then return end

    local eb = origEditBox or self._proxyOrigEditBox or self.OrigEditBox
    if not eb then return end

    for _, key in ipairs(PROXY_HIDE_KEYS) do
        local part = eb[key]
        if part and part.IsShown and part:IsShown() then
            pcall(function() part:Hide() end)
        end
    end
end

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

    -- Only touch alpha when it's a Blizzard default (1.0 active, 0.35
    -- inactive; Prat/Chatter also use 0.0 to hide). Otherwise an addon has
    -- overridden it -- leave it alone.
    local DEFAULT_ACTIVATED_ALPHA = 1.0
    local DEFAULT_DEACTIVATED_ALPHA = 0.35
    local ALPHA_TOLERANCE = 0.01
    if math_abs(prev.alpha - DEFAULT_ACTIVATED_ALPHA) < ALPHA_TOLERANCE
        or math_abs(prev.alpha - DEFAULT_DEACTIVATED_ALPHA) < ALPHA_TOLERANCE
        or math_abs(prev.alpha - 0.0) < ALPHA_TOLERANCE
    then
        prev.alphaWasDefault = true
        -- Show activated (alpha 1.0) while Yapper is open.
        if origEditBox.SetAlpha then
            pcall(function() origEditBox:SetAlpha(DEFAULT_ACTIVATED_ALPHA) end)
        end
    end

    -- Force-show so its skin (Blizzard / Prat / Chattynator / ElvUI)
    -- renders regardless of the saved pre-state. Must run BEFORE hiding
    -- headers: OnShow triggers UpdateHeader which re-shows them.
    if origEditBox.Show then
        pcall(function() origEditBox:Show() end)
    end

    -- Record + hide visible header FontStrings (post-Show, so UpdateHeader
    -- has run) so our ChannelLabel is the only prefix.
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

    -- Clear stale text so it doesn't ghost-render under the overlay.
    if origEditBox.SetText then
        pcall(function() origEditBox:SetText("") end)
    end

    self._proxyPrevState = prev
    self._proxyOrigEditBox = origEditBox

    Utils:VerbosePrint(string_format(
        "[ProxyMode] ApplyProxyMode on %s (wasShown=%s, mouse=%s, alphaWasDefault=%s).",
        (origEditBox.GetName and origEditBox:GetName()) or "<unknown>",
        tostring(prev.wasShown), tostring(prev.mouseEnabled), tostring(prev.alphaWasDefault)))
end

--- Restore the original editbox to the state we found it in.
--- Idempotent: safe to call when proxy mode wasn't active.
function EditBox:RestoreProxyMode()
    local prev = self._proxyPrevState
    local origEditBox = self._proxyOrigEditBox
    self._proxyPrevState = nil
    self._proxyOrigEditBox = nil
    if not prev or not origEditBox then return end

    if prev.mouseEnabled and origEditBox.EnableMouse then
        pcall(function() origEditBox:EnableMouse(true) end)
    end

    for key, wasShown in pairs(prev.hidden) do
        local part = origEditBox[key]
        if part and wasShown then
            pcall(function() part:Show() end)
        end
    end

    -- Restore alpha only when it was a Blizzard default; leave addon
    -- overrides alone.
    if prev.alphaWasDefault and prev.alpha and origEditBox.SetAlpha then
        pcall(function() origEditBox:SetAlpha(prev.alpha) end)
    end

    -- Hide the frame if it was hidden before proxy mode opened.
    -- This handles chat reskin addons that hide the editbox by default.
    if not prev.wasShown and origEditBox.Hide then
        pcall(function() origEditBox:Hide() end)
    end

    Utils:VerbosePrint(string_format(
        "[ProxyMode] RestoreProxyMode on %s (wasShown=%s, alphaWasDefault=%s).",
        (origEditBox.GetName and origEditBox:GetName()) or "<unknown>",
        tostring(prev.wasShown), tostring(prev.alphaWasDefault)))
end
