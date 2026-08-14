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

    -- Check if current alpha matches Blizzard's default values (1.0 activated, 0.35 deactivated).
    -- Also include 0.0 as a default deactivated state (used by Prat/Chatter to hide editbox via alpha).
    -- If so, we can safely change it to mimic the activated state (since Yapper is now open).
    -- If not, assume an addon has overridden it and leave it alone.
    local DEFAULT_ACTIVATED_ALPHA = 1.0
    local DEFAULT_DEACTIVATED_ALPHA = 0.35
    local ALPHA_TOLERANCE = 0.01
    if math_abs(prev.alpha - DEFAULT_ACTIVATED_ALPHA) < ALPHA_TOLERANCE
        or math_abs(prev.alpha - DEFAULT_DEACTIVATED_ALPHA) < ALPHA_TOLERANCE
        or math_abs(prev.alpha - 0.0) < ALPHA_TOLERANCE
    then
        prev.alphaWasDefault = true
        -- Mimic Blizzard's activated state (set alpha to 1.0) since Yapper is open
        if origEditBox.SetAlpha then
            pcall(function() origEditBox:SetAlpha(DEFAULT_ACTIVATED_ALPHA) end)
        end
    end

    -- Force-show the original so its skin (Blizzard / Prat / Chattynator / ElvUI) renders.
    -- This must happen BEFORE hiding headers: OnShow triggers UpdateHeader which
    -- re-shows header FontStrings, so we hide them after that side-effect runs.
    -- In proxy mode the background MUST be visible, so always show it regardless
    -- of the pre-state we will restore later.
    if origEditBox.Show then
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
    -- This handles chat reskin addons that hide the editbox by default.
    if not prev.wasShown and origEditBox.Hide then
        pcall(function() origEditBox:Hide() end)
    end

    Utils:VerbosePrint(string_format(
        "[ProxyMode] RestoreProxyMode on %s (wasShown=%s, alphaWasDefault=%s).",
        (origEditBox.GetName and origEditBox:GetName()) or "<unknown>",
        tostring(prev.wasShown), tostring(prev.alphaWasDefault)))
end
