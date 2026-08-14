--[[
    CEBEBridge.lua
    Compatibility bridge for ChatEditBoxExtender (CEBE).

    CEBE adopted Yapper's public API shortly before Yapper entered a major
    refactor window. This bridge keeps that existing integration working without
    requiring the CEBE implementation to be rewritten: it translates CEBE's
    native-editbox suppression and typing-indicator ownership onto Yapper's
    current overlay/show lifecycle.

    When CEBE is loaded, the bridge suppresses the Blizzard editbox from being
    shown underneath CEBE's editor by wrapping the native editbox's Show and
    SetAlpha calls, including editboxes adopted through Yapper's current Show
    and proxy paths.

    Ideally CEBE should update its implementation for Yapper 2.x eventually,
    but this bridge maintains compatibility in the interim.
]]

local _, YapperTable = ...

local Bridge = {}
YapperTable.CEBEBridge = Bridge
Bridge._initialised = false

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

local hookedEditBoxes = setmetatable({}, { __mode = "k" })

local function GetHookState(editBox)
    local state = hookedEditBoxes[editBox]
    if not state then
        state = {}
        hookedEditBoxes[editBox] = state
    end
    return state
end

--- Wrap an editbox's Show method to suppress it when CEBE is active.
--- @param editBox table The Blizzard editbox to wrap
local function wrapEditBoxShow(editBox)
    if not editBox or not editBox.Show then
        return
    end

    local state = GetHookState(editBox)
    if state.show then return end

    local originalShow = editBox.Show
    state.show = true

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
    if not editBox or not editBox.SetAlpha then
        return
    end

    local state = GetHookState(editBox)
    if state.alpha then return end

    local originalSetAlpha = editBox.SetAlpha
    state.alpha = true

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

--- Hook Yapper's normal Show path so CEBE suppression also covers the
--- non-proxy mode used by CEBE. The legacy SkinProxy attachment hook used to
--- provide this integration point before the native proxy refactor.
local function hookEditBoxShow()
    local editBox = YapperTable.EditBox
    if not editBox or type(editBox.Show) ~= "function" or Bridge._showHooked then
        return
    end

    local originalShow = editBox.Show
    if editBox.OrigEditBox then
        wrapEditBoxMethods(editBox.OrigEditBox)
    end

    editBox.Show = function(self, origEditBox, ...)
        if Bridge:IsLoaded() and origEditBox then
            wrapEditBoxMethods(origEditBox)
        end
        return originalShow(self, origEditBox, ...)
    end
    Bridge._showHooked = true
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

--- Reconcile Yapper's live proxy state with CEBE's ownership of the native box.
local function reconcileYapperProxyState()
    local editBox = YapperTable.EditBox
    local cfg = YapperTable.Config and YapperTable.Config.EditBox
    if not cfg then return end

    if cfg.UseBlizzardSkinProxy == true and editBox then
        if type(editBox.RestoreProxyMode) == "function" then
            editBox:RestoreProxyMode()
        end
        cfg.UseBlizzardSkinProxy = false
    end
    cfg.HideBlizzardEditbox = true
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
            -- Force the config to hide and rehide all editboxes.
            reconcileYapperProxyState()
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
-- Initialisation
-- ---------------------------------------------------------------------------

function Bridge:Init()
    if self._initialised then
        return
    end
    if not self:IsLoaded() then
        return
    end
    self._initialised = true

    -- Communicate with CEBE
    communicateWithCEBE()

    -- CEBE owns typing indicators while its Yapper compatibility mode is active.
    local tracker = YapperTable.TypingTrackerBridge
    if tracker and type(tracker.SetExternalOwner) == "function" then
        tracker:SetExternalOwner("ChatEditBoxExtender.YapperCompat")
    end

    -- Reconcile any saved proxy state before CEBE takes over the native box.
    reconcileYapperProxyState()

    -- Hide all Blizzard editboxes immediately
    hideAllBlizzardEditBoxes()

    -- Hook Yapper's normal Show path and exceptional proxy path.
    hookEditBoxShow()
    hookApplyProxyMode()

    -- Register config change callback to override editbox visibility settings
    registerConfigCallback()

    -- Hook tab clicks to hide editboxes
    hookTabClick()

    if YapperTable.Utils and YapperTable.Utils.DebugPrint then
        YapperTable.Utils:DebugPrint("CEBEBridge: Initialized with CEBE_ACTIVE_HIDE=" .. tostring(CEBE_ACTIVE_HIDE))
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" or Bridge:IsLoaded() then
        Bridge:Init()
    end
end)
