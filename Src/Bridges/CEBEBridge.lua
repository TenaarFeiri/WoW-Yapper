--[[
    CEBEBridge.lua
    Compatibility bridge for ChatEditBoxExtender (CEBE).

    When CEBE is loaded, this bridge completely suppresses the Blizzard editbox
    from being shown under any circumstances. It does this by dynamically hooking
    Yapper's EditBox methods to wrap the native editbox's Show/SetAlpha calls
    with guards that prevent the Blizzard editbox from appearing.
]]

local _, YapperTable = ...

local Bridge = {}
YapperTable.CEBEBridge = Bridge

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

-- Toggle between active hiding (forced Hide) and passive suppression (skip Show/Alpha)
-- Set to true to actively force origEditBox:Hide() when Yapper tries to show it
-- Set to false to only skip Yapper's Show/SetAlpha calls, letting CEBE manage
local CEBE_ACTIVE_HIDE = true

-- ---------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------

--- Check whether the CEBE addon is loaded in the environment.
--- @return boolean
function Bridge:IsLoaded()
    return _G.ChatEditBoxExtenderAddon ~= nil
end

--- Check whether CEBE's YapperCompat module is available.
--- @return boolean
function Bridge:IsYapperCompatAvailable()
    local ceb = _G.ChatEditBoxExtenderAddon
    return ceb and ceb.YapperCompat ~= nil
end

-- ---------------------------------------------------------------------------
-- Dynamic Hooking
-- ---------------------------------------------------------------------------

local hookedEditBoxes = {}

--- Wrap an editbox's Show method to suppress it when CEBE is active.
--- @param editBox table The Blizzard editbox to wrap
local function wrapEditBoxShow(editBox)
    if not editBox or not editBox.Show or hookedEditBoxes[editBox] then
        return
    end

    local originalShow = editBox.Show
    hookedEditBoxes[editBox] = true

    editBox.Show = function(self, ...)
        if Bridge:IsLoaded() then
            if CEBE_ACTIVE_HIDE then
                -- Active suppression: force hide instead of show
                if self.Hide then
                    pcall(function() self:Hide() end)
                end
            else
                -- Passive suppression: skip the show call entirely
                return
            end
        else
            -- CEBE not loaded, call original normally
            return originalShow(self, ...)
        end
    end
end

--- Wrap an editbox's SetAlpha method to suppress it when CEBE is active.
--- @param editBox table The Blizzard editbox to wrap
local function wrapEditBoxSetAlpha(editBox)
    if not editBox or not editBox.SetAlpha or hookedEditBoxes[editBox] then
        return
    end

    local originalSetAlpha = editBox.SetAlpha
    hookedEditBoxes[editBox] = true

    editBox.SetAlpha = function(self, alpha, ...)
        if Bridge:IsLoaded() then
            -- Suppress alpha changes when CEBE is active
            return
        else
            -- CEBE not loaded, call original normally
            return originalSetAlpha(self, alpha, ...)
        end
    end
end

--- Wrap both Show and SetAlpha methods on an editbox.
--- @param editBox table The Blizzard editbox to wrap
local function wrapEditBoxMethods(editBox)
    wrapEditBoxShow(editBox)
    wrapEditBoxSetAlpha(editBox)
end

--- Communicate with CEBE that Yapper's bridge is active.
local function communicateWithCEBE()
    local ceb = _G.ChatEditBoxExtenderAddon
    if ceb then
        ceb.yapperBridgeActive = true
        if ceb.YapperCompat then
            ceb.YapperCompat.suppressBlizzardEditBox = true
        end
    end
end

--- Hook Yapper's EditBox:ApplyProxyMode to wrap editbox methods.
local function hookApplyProxyMode()
    if not YapperTable.EditBox or not YapperTable.EditBox.ApplyProxyMode then
        return
    end

    local originalApplyProxyMode = YapperTable.EditBox.ApplyProxyMode

    YapperTable.EditBox.ApplyProxyMode = function(self, origEditBox, ...)
        -- Wrap the editbox's methods before Yapper's proxy logic runs
        if origEditBox then
            wrapEditBoxMethods(origEditBox)
        end

        -- Call the original Yapper function
        return originalApplyProxyMode(self, origEditBox, ...)
    end
end

--- Hook Yapper's EditBox:AttachBlizzardSkinProxy to wrap editbox methods.
local function hookAttachBlizzardSkinProxy()
    if not YapperTable.EditBox or not YapperTable.EditBox.AttachBlizzardSkinProxy then
        return
    end

    local originalAttach = YapperTable.EditBox.AttachBlizzardSkinProxy

    YapperTable.EditBox.AttachBlizzardSkinProxy = function(self, origEditBox, overlayHeight, ...)
        -- Wrap the editbox's methods before Yapper's skin attachment logic runs
        if origEditBox then
            wrapEditBoxMethods(origEditBox)
        end

        -- Call the original Yapper function
        return originalAttach(self, origEditBox, overlayHeight, ...)
    end
end

--- Hide all Blizzard chat editboxes when CEBE is active.
local function hideAllBlizzardEditBoxes()
    for i = 1, NUM_CHAT_WINDOWS do
        local editBox = _G["ChatFrame" .. i .. "EditBox"]
        if editBox and editBox.Hide then
            pcall(function() editBox:Hide() end)
        end
    end
end

--- Register CONFIG_CHANGED callback to intercept editbox visibility config changes.
--- When CEBE is loaded, force the editbox to stay hidden regardless of config.
local function registerConfigCallback()
    if not _G.YapperAPI then
        return
    end

    _G.YapperAPI:RegisterCallback("CONFIG_CHANGED", function(path, value)
        if not Bridge:IsLoaded() then
            return
        end

        -- Check if this is an editbox visibility setting
        if path == "EditBox.HideBlizzardEditbox" or path == "EditBox.UseBlizzardSkinProxy" then
            -- Force the config to hide and rehide all editboxes
            if YapperTable.Config and YapperTable.Config.EditBox then
                YapperTable.Config.EditBox.HideBlizzardEditbox = true
                YapperTable.Config.EditBox.UseBlizzardSkinProxy = false
            end
            hideAllBlizzardEditBoxes()
            
            if YapperTable.Utils and YapperTable.Utils.DebugPrint then
                YapperTable.Utils:DebugPrint("CEBEBridge: Overrode config change for " .. path .. " to keep editbox hidden")
            end
        end
    end)
end

--- Hook FCF_Tab_OnClick to hide editboxes when tabs are clicked.
local function hookTabClick()
    if not _G.FCF_Tab_OnClick then
        return
    end

    hooksecurefunc("FCF_Tab_OnClick", function(tab, button)
        if not Bridge:IsLoaded() then
            return
        end
        hideAllBlizzardEditBoxes()
        
        if YapperTable.Utils and YapperTable.Utils.DebugPrint then
            YapperTable.Utils:DebugPrint("CEBEBridge: Hid editboxes on tab click")
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Initialisation (called from Chat:Init)
-- ---------------------------------------------------------------------------

function Bridge:Init()
    if not self:IsLoaded() then
        return
    end

    -- Communicate with CEBE
    communicateWithCEBE()

    -- Hide all Blizzard editboxes immediately
    hideAllBlizzardEditBoxes()

    -- Hook Yapper's EditBox methods dynamically
    hookApplyProxyMode()
    hookAttachBlizzardSkinProxy()

    -- Register config change callback to override editbox visibility settings
    registerConfigCallback()

    -- Hook tab clicks to hide editboxes
    hookTabClick()

    if YapperTable.Utils and YapperTable.Utils.DebugPrint then
        YapperTable.Utils:DebugPrint("CEBEBridge: Initialized with CEBE_ACTIVE_HIDE=" .. tostring(CEBE_ACTIVE_HIDE))
    end
end
