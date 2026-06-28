--[[
    EditBox/Keybinds.lua
    Keybind override system for Yapper.
    Replaces ChatFrameUtil.OpenChat hook with SetOverrideBinding for primary chat open path.
]]

local _, YapperTable = ...
local EditBox = YapperTable.EditBox
local Utils = YapperTable.Utils

-- Keybind module
local Keybinds = {}
EditBox.Keybinds = Keybinds

-- State tracking
Keybinds._registered = false
Keybinds._pendingRegistration = false
Keybinds._overrideBindings = {
    "OPENCHAT",
    "OPENCHATSLASH",
    "REPLYTELL2"
}

-- Lockdown state preservation (using Yapper's existing LastUsed system)
Keybinds._preLockdownLastUsed = nil

-- Secure buttons for each binding type
Keybinds._secureButtons = {}

-- Safe verbose printing helper
local function LogVerbose(msg)
    YapperTable.Utils:VerbosePrint(msg)
end

local function IsNativeChatEditBox(eb)
    if not eb or eb == EditBox.OverlayEdit or not eb.GetName then
        return false
    end
    local name = eb:GetName()
    return type(name) == "string" and name:match("^ChatFrame%d+EditBox$") ~= nil
end

-- ---------------------------------------------------------------------------
-- Secure Button Creation
-- ---------------------------------------------------------------------------

--- Sync Yapper's channel/target to Blizzard's editbox for lockdown handling.
local function SyncAttributesToBlizzard()
    local yapperChatType = EditBox.ChatType
    local yapperTarget = EditBox.Target
    local yapperLanguage = EditBox.Language
    
    if not yapperChatType then
        return
    end
    
    -- Get the default Blizzard editbox
    local blizzEditBox = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox or _G.ChatFrame1EditBox
    if not (blizzEditBox and blizzEditBox.SetAttribute) then
        return
    end
    
    -- Resolve chat type to override key if needed
    local overrideCT = yapperChatType
    if yapperChatType == "PARTY_LEADER" then
        overrideCT = "PARTY"
    elseif yapperChatType == "RAID_LEADER" then
        overrideCT = "RAID"
    end
    
    blizzEditBox:SetAttribute("chatType", overrideCT)
    
    if yapperChatType == "WHISPER" or yapperChatType == "BN_WHISPER" then
        if yapperTarget then
            blizzEditBox:SetAttribute("tellTarget", yapperTarget)
        end
        blizzEditBox:SetAttribute("channelTarget", nil)
    elseif yapperChatType == "CHANNEL" then
        if yapperTarget then
            blizzEditBox:SetAttribute("channelTarget", yapperTarget)
        end
        blizzEditBox:SetAttribute("tellTarget", nil)
    else
        blizzEditBox:SetAttribute("tellTarget", nil)
        blizzEditBox:SetAttribute("channelTarget", nil)
    end
    
    if yapperLanguage then
        blizzEditBox:SetAttribute("language", yapperLanguage)
    else
        blizzEditBox:SetAttribute("language", nil)
    end
end

--- Common handler for all keybind buttons.
--- @param bindingName string The binding that triggered this
--- @param prefillText string Optional text to pre-fill in the editbox
--- @param syncAttributes boolean Whether to sync attributes during lockdown
local function HandleKeybindClick(bindingName, prefillText, syncAttributes)
    if not (EditBox and EditBox.Show) then
        return
    end

    -- If the post queue is stalled and waiting for Enter to continue,
    -- progress the queue instead of opening Yapper.
    local Queue = YapperTable.Queue
    if Queue and Queue.TryContinue and Queue:TryContinue() then
        Queue:SendNext(true)
        return
    end

    -- Check for chat messaging lockdown before opening Yapper
    local inLockdown = Utils:IsChatLockdown()
    if inLockdown then
        -- Save Yapper's LastUsed state for restoration after lockdown
        if not Keybinds._preLockdownLastUsed and EditBox.LastUsed then
            Keybinds._preLockdownLastUsed = {
                chatType = EditBox.LastUsed.chatType,
                target = EditBox.LastUsed.target,
                language = EditBox.LastUsed.language
            }
        end

        -- Sync attributes if requested
        if syncAttributes then
            SyncAttributesToBlizzard()
        end

        if ChatFrameUtil and ChatFrameUtil.OpenChat then
            ChatFrameUtil.OpenChat()
        end
        return
    end
    
    -- Restore pre-lockdown LastUsed state if lockdown has ended
    if Keybinds._preLockdownLastUsed and not inLockdown then
        if EditBox.LastUsed then
            EditBox.LastUsed.chatType = Keybinds._preLockdownLastUsed.chatType
            EditBox.LastUsed.target = Keybinds._preLockdownLastUsed.target
            EditBox.LastUsed.language = Keybinds._preLockdownLastUsed.language
            -- Also restore current state for immediate use
            EditBox.ChatType = Keybinds._preLockdownLastUsed.chatType
            EditBox.Target = Keybinds._preLockdownLastUsed.target
            EditBox.Language = Keybinds._preLockdownLastUsed.language
        end
        Keybinds._preLockdownLastUsed = nil
    end

    -- Grab focus instantly on the hidden trap so no action-bar keybinds
    -- can leak through during the brief Show() window.  Do this as early
    -- as possible after lockdown check to capture any keystrokes that
    -- arrive before the overlay is ready.
    if EditBox._focusTrap then
        EditBox._focusTrap:SetFocus()
        -- Clear any stale text from previous opens
        EditBox._focusTrap:SetText("")
    end

    -- Don't show if already shown to prevent state thrashing
    if EditBox.Overlay and EditBox.Overlay:IsShown() then
        if EditBox.OverlayEdit then
            EditBox.OverlayEdit:SetFocus()
        end
        return
    end
    
    -- Fire PRE_EDITBOX_SHOW filter so external addons (CEBE, WIMBridge, etc.)
    -- can inspect and react before the overlay opens.  This mirrors the filter
    -- call in HookBlizzardEditBox so addons see a consistent activation path.
    if YapperTable.API then
        local filterCT = (EditBox.LastUsed and EditBox.LastUsed.chatType) or "SAY"
        local filterTarget = (EditBox.LastUsed and EditBox.LastUsed.target) or nil
        local result = YapperTable.API:RunFilter("PRE_EDITBOX_SHOW", {
            chatType = filterCT,
            target   = filterTarget,
        })
        if result == false then
            -- CRITICAL: Clear focus trap so user doesn't type into invisible void.
            -- A filter blocked the open; we must clean up.
            if EditBox._focusTrap then
                EditBox._focusTrap:ClearFocus()
                EditBox._focusTrap:SetText("")
            end
            EditBox._focusTrapText = ""
            return
        end
    end

    -- Prefer the currently active native chat editbox first; IM history can lag
    -- behind during whisper retarget/close sequences and reopen stale contexts.
    local activeWindow = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
        or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
    local targetEditBox = IsNativeChatEditBox(activeWindow) and activeWindow or nil
    if not targetEditBox and IsNativeChatEditBox(EditBox._lastActiveIMEditBox) then
        targetEditBox = EditBox._lastActiveIMEditBox
    end
    if not targetEditBox then
        targetEditBox = (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox) or _G.ChatFrame1EditBox
    end

    Utils:DebugPrint("Secure button clicked, showing Yapper overlay")
    local ok, err = pcall(function()
        EditBox:Show(targetEditBox)
    end)
    if not ok then
        -- Error in Show - print to chat so user can see it
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Yapper Error:|r " .. tostring(err))
        return
    end
    
    -- Pre-fill text if specified (applied immediately; Show() has already run)
    if prefillText and EditBox.OverlayEdit then
        if type(EditBox.ApplyProgrammaticPrefill) == "function" then
            EditBox:ApplyProgrammaticPrefill(prefillText, EditBox.OverlayEdit)
        else
            EditBox.OverlayEdit:SetText(prefillText)
        end
    end

    -- Transfer any keystrokes captured by the focus trap before overlay was ready
    if EditBox._focusTrapText and EditBox._focusTrapText ~= "" then
        local currentText = EditBox.OverlayEdit:GetText() or ""
        EditBox.OverlayEdit:SetText(currentText .. EditBox._focusTrapText)
        EditBox._focusTrapText = ""  -- Clear for next open
    end

    -- Use the proper Blizzard function to set focus override
    if EditBox.UpdateFocusOverride then
        EditBox:UpdateFocusOverride()
    end
end

--- Create a secure button for a specific binding type.
--- @param bindingName string The binding name this button handles
--- @param prefillText string Optional text to pre-fill when this binding is triggered
--- @param syncAttributes boolean Whether to sync attributes during lockdown
local function CreateSecureButtonForBinding(bindingName, prefillText, syncAttributes)
    local button = CreateFrame("Button", "YapperKeybindButton_" .. bindingName, nil, "SecureActionButtonTemplate")
    button:SetAttribute("type", "click")
    button:Hide() -- Hide the button, we only use it for keybind routing
    
    -- Use PostClick to run our insecure code after the secure click
    button:SetScript("PostClick", function()
        pcall(function()
            HandleKeybindClick(bindingName, prefillText, syncAttributes)
        end)
    end)
    
    LogVerbose("Secure button created for binding: " .. bindingName)
    return button
end

--- Create secure buttons for all override bindings.
function Keybinds:CreateSecureButtons()
    -- OPENCHAT - standard chat open, sync attributes for lockdown
    self._secureButtons["OPENCHAT"] = CreateSecureButtonForBinding("OPENCHAT", nil, true)
    
    -- OPENCHATSLASH - chat open with "/" pre-filled, sync attributes for lockdown
    self._secureButtons["OPENCHATSLASH"] = CreateSecureButtonForBinding("OPENCHATSLASH", "/", true)
    
    -- REPLYTELL2 - reply to last tell, no attribute sync (uses Blizzard's reply logic)
    self._secureButtons["REPLYTELL2"] = CreateSecureButtonForBinding("REPLYTELL2", nil, false)
end

-- ---------------------------------------------------------------------------
-- Override Registration
-- ---------------------------------------------------------------------------

--- Register keybind overrides to route chat opens to Yapper.
--- Must be called outside of combat/lockdown.
function Keybinds:RegisterOverrides()
    if self._registered then
        return
    end

    -- Ensure secure buttons exist for all bindings
    self:CreateSecureButtons()

    -- Check if we can set overrides (not in combat/lockdown)
    if InCombatLockdown and InCombatLockdown() then
        self._pendingRegistration = true
        LogVerbose("Keybinds:RegisterOverrides deferred - in combat")
        return
    end

    if Utils:IsChatLockdown() then
        self._pendingRegistration = true
        LogVerbose("Keybinds:RegisterOverrides deferred - in lockdown")
        return
    end

    -- Register overrides for each binding
    for _, bindingName in ipairs(self._overrideBindings) do
        if type(bindingName) == "string" and GetBindingKey then
            local button = self._secureButtons[bindingName]
            if not button then
                LogVerbose("Skipping " .. bindingName .. " - no secure button created")
            else
                local key1, key2 = GetBindingKey(bindingName)
                
                if type(key1) == "string" and key1 ~= "" then
                    local success, err = pcall(function()
                        SetOverrideBindingClick(button, false, key1, button:GetName())
                    end)
                    if success then
                        LogVerbose("Registered override for " .. bindingName .. " key1: " .. key1)
                    else
                        LogVerbose("Failed to register override for " .. bindingName .. " key1: " .. tostring(err))
                    end
                else
                    LogVerbose("Skipping " .. bindingName .. " key1 - no key")
                end
                
                if type(key2) == "string" and key2 ~= "" then
                    local success, err = pcall(function()
                        SetOverrideBindingClick(button, false, key2, button:GetName())
                    end)
                    if success then
                        LogVerbose("Registered override for " .. bindingName .. " key2: " .. key2)
                    else
                        LogVerbose("Failed to register override for " .. bindingName .. " key2: " .. tostring(err))
                    end
                else
                    LogVerbose("Skipping " .. bindingName .. " key2 - no key")
                end
            end
        else
            LogVerbose("Skipping " .. bindingName .. " - invalid binding name or GetBindingKey not available")
        end
    end

    self._registered = true
    self._pendingRegistration = false
    LogVerbose("Keybind overrides registered successfully")
end

--- Unregister keybind overrides.
--- Must be called outside of combat/lockdown.
function Keybinds:UnregisterOverrides()
    if not self._registered then
        return
    end

    -- Check if we can clear overrides (not in combat/lockdown)
    if InCombatLockdown and InCombatLockdown() then
        LogVerbose("Keybinds:UnregisterOverrides deferred - in combat")
        return
    end

    if Utils:IsChatLockdown() then
        LogVerbose("Keybinds:UnregisterOverrides deferred - in lockdown")
        return
    end

    -- Clear all overrides from all secure buttons
    for bindingName, button in pairs(self._secureButtons) do
        if button then
            local success, err = pcall(function()
                ClearOverrideBindings(button)
            end)
            if success then
                LogVerbose("Cleared overrides for " .. bindingName)
            else
                LogVerbose("Failed to clear overrides for " .. bindingName .. ": " .. tostring(err))
            end
        end
    end

    self._registered = false
    self._pendingRegistration = false
    LogVerbose("Keybind overrides unregistered")
end

--- Refresh overrides (e.g., after keybind changes).
--- Unregisters and re-registers all overrides.
function Keybinds:RefreshOverrides()
    if InCombatLockdown and InCombatLockdown() then
        self._pendingRegistration = true
        LogVerbose("Keybinds:RefreshOverrides deferred - in combat")
        return
    end

    if Utils:IsChatLockdown() then
        self._pendingRegistration = true
        LogVerbose("Keybinds:RefreshOverrides deferred - in lockdown")
        return
    end

    self:UnregisterOverrides()
    self:RegisterOverrides()
end

--- Check if overrides are currently registered.
--- @return boolean
function Keybinds:IsRegistered()
    return self._registered
end

--- Check if registration is pending (waiting for combat/lockdown to end).
--- @return boolean
function Keybinds:IsPendingRegistration()
    return self._pendingRegistration
end

--- Complete pending registration if combat/lockdown has ended.
--- Called by combat/lockdown end event handlers.
function Keybinds:CompletePendingRegistration()
    if self._pendingRegistration then
        self:RegisterOverrides()
    end
end

-- ---------------------------------------------------------------------------
-- Event Handlers
-- ---------------------------------------------------------------------------

--- Initialize keybind event listeners.
--- Called during addon boot.
function Keybinds:Init()
    -- Create the secure buttons
    self:CreateSecureButtons()
    -- Listen for keybind changes to refresh overrides
    if YapperTable.Events and YapperTable.Events.Register then
        YapperTable.Events:Register("PARENT_FRAME", "UPDATE_BINDINGS", function()
            if self._registered then
                LogVerbose("Keybinds detected UPDATE_BINDINGS, refreshing overrides")
                self:RefreshOverrides()
            end
        end)
    end

    -- Listen for combat/lockdown end to complete pending registration
    if YapperTable.Events and YapperTable.Events.Register then
        YapperTable.Events:Register("PARENT_FRAME", "PLAYER_REGEN_ENABLED", function()
            self:CompletePendingRegistration()
        end)
        
        YapperTable.Events:Register("PARENT_FRAME", "CHALLENGE_MODE_COMPLETED", function()
            self:CompletePendingRegistration()
        end)
    end
end
