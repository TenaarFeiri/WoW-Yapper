-- Replicates the Simply_RP_Typing_Tracker network protocol.
-- Because Yapper replaces the native EditBox, the original addon's hooks
-- never fire. We manually broadcast CSV signals via the SRPTypingTracker
-- AceComm prefix to maintain compatibility.
-- Payload: guid,name,rpname,guild,isTyping(0/1),chatType,zoneID,x,y,inGroup(0/1),neighborhood

local _, YapperTable            = ...
local Bridge                    = {
    ["Exists"] = true, -- Just so we don't have an empty bridge table.
}
YapperTable.TypingTrackerBridge = Bridge

-- Localise Lua globals for performance
local string_format = string.format
local tostring      = tostring
local type          = type
YapperTable.Utils:DebugPrint("TypingTrackerBridge: Bridge registered on YapperTable")

local COMM_PREFIX        = "SRPTypingTracker"
local KEEPALIVE_INTERVAL = 2.0 -- More aggressive keepalive to ensure continuity for others and local display.
local keepaliveTicker    = nil
local lastChatType       = nil

local function IsLoaded()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("Simply_RP_Typing_Tracker")
    end
    ---@diagnostic disable-next-line: undefined-field
    return _G.SRPTypingTracker ~= nil
end

local function GetRPName(unitName)
    if _G.RPNames and _G.RPNames[unitName] then
        return _G.RPNames[unitName]
    end
    return unitName
end

local function GetAPI()
    return _G.SRPTypingTracker and _G.SRPTypingTracker.API
end

local function GetHousingContext()
    if _G.SRPTypingTracker and _G.SRPTypingTracker.GetHousingContextForPlayer then
        return _G.SRPTypingTracker.GetHousingContextForPlayer()
    end

    -- Fallback for older versions or if method is missing
    local guid = nil
    if C_Housing and C_Housing.GetCurrentNeighborhoodGUID then
        guid = C_Housing.GetCurrentNeighborhoodGUID()
    end
    guid = (guid ~= "") and guid or nil

    return {
        neighborhoodGUID = guid,
        houseInstanceKey = nil,
    }
end

local function GetZoneID()
    -- Use the addon's effective zone ID if available, it handles housing interiors better.
    if _G.SRPTypingTracker and _G.SRPTypingTracker.GetEffectiveZoneID then
        return _G.SRPTypingTracker.GetEffectiveZoneID()
    end

    -- Normal outdoor/interior maps
    local zoneID = C_Map.GetBestMapForUnit("player")
    if zoneID then return zoneID end

    -- Fallback: housing interior
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType == "interior" then
        if C_Housing and C_Housing.GetCurrentNeighborhoodGUID and C_Housing.GetUIMapIDForNeighborhood then
            local neighborhoodGUID = C_Housing.GetCurrentNeighborhoodGUID()
            if neighborhoodGUID and neighborhoodGUID ~= "" then
                local uiMapID = C_Housing.GetUIMapIDForNeighborhood(neighborhoodGUID)
                if uiMapID and uiMapID > 0 then
                    return uiMapID
                end
            end
        end
    end

    return nil
end

local function GetCoords(mapID)
    if not mapID then return 0, 0 end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if pos then
        return pos:GetXY()
    end
    return 0, 0
end

local function UpdateLocalStatus(isTyping, chatType, zoneID, x, y, housingContext)
    local TTAddon = LibStub("AceAddon-3.0"):GetAddon("SRPTypingTracker", true)
    if not TTAddon or not TTAddon.GetTypingPlayers then return end

    local playerGUID = UnitGUID("player")
    if not playerGUID then return end

    local typingPlayers = TTAddon:GetTypingPlayers()
    if not typingPlayers then return end

    -- Check if we should display self typing
    local options = _G.SRPTypingTracker and _G.SRPTypingTracker.GetOptions and _G.SRPTypingTracker.GetOptions()
    if not options or not options.displaySelfTyping or chatType == "WHISPER" or chatType == "BN_WHISPER" then
        if typingPlayers[playerGUID] then
            typingPlayers[playerGUID] = nil
            TTAddon:SendMessage("TYPING_STATUS_UPDATED")
        end
        return
    end

    if not isTyping then
        if typingPlayers[playerGUID] then
            typingPlayers[playerGUID] = nil
            TTAddon:SendMessage("TYPING_STATUS_UPDATED")
        end
        return
    end

    local playerName = UnitName("player")
    local rpName     = GetRPName(playerName)
    local guildName  = GetGuildInfo("player") or ""

    local isPublic = false
    if _G.SRPTypingTracker and _G.SRPTypingTracker.PublicChannels then
        isPublic = _G.SRPTypingTracker.PublicChannels[chatType] or chatType == "CHANNEL"
    end

    -- Update the table manually since the addon ignores our network messages.
    typingPlayers[playerGUID] = {
        name = playerName,
        rpName = rpName,
        guild = guildName,
        isTyping = true,
        chatType = chatType,
        zoneID = zoneID or 0,
        x = x,
        y = y,
        isTypingPlayerPublic = isPublic and true or false,
        neighborhoodGUID = housingContext.neighborhoodGUID,
        houseInstanceKey = housingContext.houseInstanceKey,
        timeLastMessageReceived = GetTime(),
    }

    TTAddon:SendMessage("TYPING_STATUS_UPDATED")
end

local function SendSignal(isTyping, chatType)
    if not IsLoaded() then return end

    -- Retrieve the addon object to use its SendCommMessage mixin
    local TTAddon = LibStub("AceAddon-3.0"):GetAddon("SRPTypingTracker", true)
    if not TTAddon then return end

    -- Get common player info.
    local playerGUID = UnitGUID("player")
    if not playerGUID then return end
    local playerName = UnitName("player")
    local rpName     = GetRPName(playerName)
    local guildName  = GetGuildInfo("player") or ""

    -- Get the zone's ID, TT needs it.
    local zoneID     = GetZoneID()
    if not zoneID then
        YapperTable.Utils:DebugPrint("TypingTrackerBridge: No ZoneID found")
        return
    end

    -- where are we on the map
    local x, y = GetCoords(zoneID)
    -- Housing context
    local housingContext = GetHousingContext()
    local neighborhood   = housingContext.neighborhoodGUID or ""
    local houseKey       = housingContext.houseInstanceKey or ""

    local isTypingNum    = isTyping and 1 or 0
    local isGroup        = (IsInGroup() or IsInRaid()) and 1 or 0

    -- Format: guid,name,rpname,guild,isTyping,chatType,zoneID,x,y,isGroup,neighborhood,houseKey
    local msg            = string_format("%s,%s,%s,%s,%d,%s,%d,%f,%f,%d,%s,%s",
        playerGUID, playerName, rpName, guildName,
        isTypingNum, chatType, zoneID, x, y,
        isGroup, neighborhood, houseKey
    )

    -- Update local state so we can see ourselves typing
    UpdateLocalStatus(isTyping, chatType, zoneID, x, y, housingContext)

    -- Determine channel
    if chatType == "WHISPER" or chatType == "BN_WHISPER" then
        return
    end

    if chatType == "PARTY" or chatType == "RAID" or chatType == "INSTANCE_CHAT" then
        -- Only send group signals if we are actually in a group/raid/instance.
        local inGroup = IsInGroup() or IsInRaid() or IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
        if not inGroup then
            YapperTable.Utils:DebugPrint("TypingTrackerBridge: Skipping group send - not in a group/raid.")
            return
        end

        -- Determine correct distribution for the current group type.
        local distrib
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
            distrib = "INSTANCE_CHAT"
        elseif IsInRaid() then
            distrib = "RAID"
        else
            distrib = "PARTY"
        end

        -- v3.20 uses C_ChatInfo.SendAddonMessage for groups
        C_ChatInfo.SendAddonMessage(COMM_PREFIX, msg, distrib)
        YapperTable.Utils:DebugPrint("TypingTrackerBridge: Sent (Group via C_ChatInfo) -> " .. msg)
    else
        -- Public channels (SAY, YELL, EMOTE) via "CHANNEL"
        local channelName = "SRPChannel" .. zoneID
        local channelID = GetChannelName(channelName)

        if channelID and channelID > 0 then
            TTAddon:SendCommMessage(COMM_PREFIX, msg, "CHANNEL", channelID)
            YapperTable.Utils:DebugPrint("TypingTrackerBridge: Sent (Public via AceComm) -> " .. msg)
        else
            YapperTable.Utils:DebugPrint("TypingTrackerBridge: Cannot send public signal - not in channel " ..
                channelName)
        end
    end
end

local function StartTicker()
    if keepaliveTicker then return end
    keepaliveTicker = C_Timer.NewTicker(KEEPALIVE_INTERVAL, function()
        local chatType = lastChatType
        -- if the overlay is visible and has a different chatType (via slash command), sync to it.
        if YapperTable.EditBox and YapperTable.EditBox.ChatType then
            chatType = YapperTable.EditBox.ChatType
        end
        SendSignal(true, chatType)
    end)
end

local function StopTicker()
    if keepaliveTicker then
        keepaliveTicker:Cancel()
        keepaliveTicker = nil
    end
end

local function SignalTyping(chatType)
    if not IsLoaded() then return end
    if InCombatLockdown() then return end

    if YapperTable.Config.System.EnableTypingTrackerBridge == false then
        return
    end

    -- Override provided chatType if the overlay is active.
    if YapperTable.EditBox and YapperTable.EditBox.ChatType then
        chatType = YapperTable.EditBox.ChatType
    end

    chatType = chatType or "SAY"
    
    -- GUARD: Avoid repeated calls if state hasn't changed.
    -- Moved above the API check to prevent spamming the external API and network.
    if Bridge._isTyping and lastChatType == chatType then
        if not GetAPI() then
            StartTicker() -- Ensure manual ticker is running if not using API
        end
        return
    end

    local api = GetAPI()
    if api then
        -- Use official API if available
        YapperTable.Utils:VerbosePrint("TypingTrackerBridge: api.StartTyping -> " .. chatType)
        api.StartTyping("Yapper", chatType)
        Bridge._isTyping = true
        lastChatType = chatType
        StopTicker() -- API handles its own keepalives
        return
    end

    YapperTable.Utils:VerbosePrint("TypingTrackerBridge: SignalTyping → " .. chatType)

    lastChatType = chatType
    Bridge._isTyping = true

    -- Start our manual ticker
    StartTicker()

    -- Send first signal
    SendSignal(true, chatType)
end

local function SignalNotTyping()
    if not IsLoaded() then return end
    if InCombatLockdown() then return end

    if YapperTable.Config.System.EnableTypingTrackerBridge == false then
        StopTicker()
        local api = GetAPI()
        if api then api.StopTyping("Yapper") end
        return
    end

    local wasTyping = Bridge._isTyping or lastChatType ~= nil

    if wasTyping then
        YapperTable.Utils:VerbosePrint("TypingTrackerBridge: SignalNotTyping (wasTyping=true)")
        Bridge._isTyping = false

        local api = GetAPI()
        if api then
            YapperTable.Utils:VerbosePrint("TypingTrackerBridge: api.StopTyping")
            api.StopTyping("Yapper")
            StopTicker()
        else
            -- Send one final "Not Typing" signal to the last used channel
            -- to ensure group members/nearby players see us stop immediately.
            local stopChatType = lastChatType or "SAY"
            SendSignal(false, stopChatType)

            -- Stop ticker
            StopTicker()
        end

        lastChatType = nil
    end
end

local function SignalChannelChanged(newChatType)
    if not IsLoaded() then return end
    if InCombatLockdown() then return end

    if YapperTable.Config.System.EnableTypingTrackerBridge == false then
        return
    end

    if YapperTable.EditBox and YapperTable.EditBox.ChatType then
        newChatType = YapperTable.EditBox.ChatType
    end

    if newChatType == lastChatType then return end

    YapperTable.Utils:DebugPrint("TypingTrackerBridge: Channel switch " ..
        (lastChatType or "nil") .. " -> " .. newChatType)

    local prevChatType = lastChatType
    lastChatType = newChatType

    local api = GetAPI()
    if api then
        if Bridge._isTyping then
            api.StartTyping("Yapper", newChatType)
        end
        return
    end

    -- If we were already typing, we MUST clear the old channel indicator
    -- and start the new one immediately.
    if Bridge._isTyping then
        if prevChatType then
            SendSignal(false, prevChatType)
        end
        SendSignal(true, newChatType)
    end
end

--- Called by Interface when the toggle is changed.
--- @param val boolean|nil  The new value, or nil to read from config.
function Bridge:UpdateState(val)
    local enabled
    if val ~= nil then
        enabled = (val == true)
    else
        enabled = (YapperTable.Config.System.EnableTypingTrackerBridge == true)
    end

    self.Enabled = enabled

    if not enabled then
        -- If we were typing, send one last "Stop" signal so we don't get stuck until timeout
        if Bridge._isTyping or lastChatType then
            YapperTable.Utils:DebugPrint("TypingTrackerBridge: Disabled - sending final Stop signal.")
            SignalNotTyping()
        end

        -- Force stop everything
        StopTicker()
        lastChatType = nil
        Bridge._isTyping = false
        YapperTable.Utils:VerbosePrint("TypingTrackerBridge: Disabled by user setting.")
    else
        YapperTable.Utils:VerbosePrint("TypingTrackerBridge: Enabled by user setting.")

        -- Kickstart if overlay is open
        if YapperTable.EditBox and YapperTable.EditBox.Overlay and YapperTable.EditBox.Overlay:IsShown() then
            local currentChatType = YapperTable.EditBox.ChatType
            YapperTable.Utils:DebugPrint("TypingTrackerBridge: Re-enabled while active - restarting signal.")
            SignalTyping(currentChatType)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Bridge Callbacks
-- ---------------------------------------------------------------------------

function Bridge:OnOverlayFocusGained(chatType)
    SignalTyping(chatType)
end

function Bridge:OnOverlayFocusLost()
    SignalNotTyping()
end

function Bridge:OnOverlaySent()
    -- Stop typing immediately upon send
    SignalNotTyping()
end

function Bridge:OnChannelChanged(newChatType)
    SignalChannelChanged(newChatType)
end

-- ---------------------------------------------------------------------------
-- API self-registration
-- ---------------------------------------------------------------------------
-- Register as a callback consumer via the public API so the bridge is driven
-- entirely through the event system rather than hardcoded calls.
-- The direct calls from EditBox are kept as a legacy path; this registration
-- is the forward-looking pattern.

if _G.YapperAPI then
    _G.YapperAPI:RegisterCallback("STATE_CHANGED", function(newState, oldState, chatType)
        if not Bridge.Enabled then return end

        local State = YapperTable.State
        if State:IsInputActive() then
            -- Use the chatType passed during transition, or fall back to overlay state, or default.
            local effectiveChatType = chatType or (YapperTable.EditBox and YapperTable.EditBox.ChatType) or "SAY"
            Bridge:OnOverlayFocusGained(effectiveChatType)
        elseif newState == "SENDING" or newState == "IDLE" then
            Bridge:OnOverlayFocusLost()
        end
    end)

    _G.YapperAPI:RegisterCallback("EDITBOX_CHANNEL_CHANGED", function(chatType)
        if Bridge.Enabled then Bridge:OnChannelChanged(chatType) end
    end)
end
