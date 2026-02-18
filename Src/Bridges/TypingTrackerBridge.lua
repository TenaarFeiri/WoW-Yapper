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
YapperTable.Utils:DebugPrint("TypingTrackerBridge: Bridge registered on YapperTable")

local COMM_PREFIX        = "SRPTypingTracker"
local KEEPALIVE_INTERVAL = 3.1 -- For some reason 3.1 seconds is the one most consistently producing the message.
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

local function GetZoneID()
    -- Use map ID as ZoneID (matches TT logic usually, or fallback)
    return C_Map.GetBestMapForUnit("player")
end

local function GetCoords(mapID)
    if not mapID then return nil, nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if pos then
        return pos:GetXY()
    end
    return nil, nil
end

local function SendSignal(isTyping, chatType)
    if not IsLoaded() then return end

    -- Retrieve the addon object to use its SendCommMessage mixin
    -- For once I'm glad that we've got an embedded Ace here lol
    local TTAddon = LibStub("AceAddon-3.0"):GetAddon("SRPTypingTracker", true)
    if not TTAddon then return end

    -- Get common player info.
    local playerGUID = UnitGUID("player") or "PRIEST" -- fallback
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
    if not x or not y then
        YapperTable.Utils:DebugPrint("TypingTrackerBridge: No Coords found for Zone " .. zoneID)
        return
    end

    local isTypingNum  = isTyping and 1 or 0
    local isGroup      = (IsInGroup() or IsInRaid()) and 1 or 0
    local neighborhood = "" -- Look, we're not doing housing. This is an
    -- experimental, hacky integration for an addon
    -- that was never designed to integrate.
    -- Not gonna tackle more than I need to, to make it work.

    -- Format: guid,name,rpname,guild,isTyping,chatType,zoneID,x,y,isGroup,neighborhood
    local msg          = string.format("%s,%s,%s,%s,%d,%s,%d,%f,%f,%d,%s",
        playerGUID, playerName, rpName, guildName,
        isTypingNum, chatType, zoneID, x, y,
        isGroup, neighborhood
    )

    -- Determine channel
    -- "SAY", "YELL", "EMOTE" -> Public (CHANNEL)
    -- "PARTY", "RAID" -> Group
    -- "WHISPER" -> TT suppresses, so we do too (don't send)

    if chatType == "WHISPER" or chatType == "BN_WHISPER" then
        return
    end

    if chatType == "PARTY" or chatType == "RAID" or chatType == "INSTANCE_CHAT" then
        -- Send to group channel if in group
        local distrib = IsInRaid() and "RAID" or "PARTY"
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then distrib = "INSTANCE_CHAT" end

        TTAddon:SendCommMessage(COMM_PREFIX, msg, distrib)
        YapperTable.Utils:DebugPrint("TypingTrackerBridge: Sent (Group) -> " .. msg)
    else
        -- Public channels (SAY, YELL, EMOTE)
        -- To send to "CHANNEL", we need the channel ID.
        -- TT joins "SRPChannel<ZoneID>".
        -- We can try to send to "CHANNEL" with that name?
        -- SendCommMessage("CHANNEL", target=channelName) logic.

        local channelName = "SRPChannel" .. zoneID
        local channelID = GetChannelName(channelName)

        if channelID and channelID > 0 then
            TTAddon:SendCommMessage(COMM_PREFIX, msg, "CHANNEL", tostring(channelID))
            YapperTable.Utils:DebugPrint("TypingTrackerBridge: Sent (Public) -> " .. msg)
        else
            -- If we aren't in the channel (maybe TT failed to join?), we can't send publicly.
            -- Too bad.
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

    if chatType == lastChatType and Bridge._isTyping then
        -- Already typing in this channel, ensure ticker is running and bail.
        StartTicker()
        return
    end

    YapperTable.Utils:DebugPrint("TypingTrackerBridge: SignalTyping → " .. chatType)

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
        return
    end

    local wasTyping = Bridge._isTyping or lastChatType ~= nil

    if wasTyping then
        YapperTable.Utils:DebugPrint("TypingTrackerBridge: SignalNotTyping")
        Bridge._isTyping = false
        lastChatType = nil

        -- Stop ticker
        StopTicker()

        -- Send one final "Not Typing" signal
        SendSignal(false, "SAY") -- Channel matters less for stopping
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

    lastChatType = newChatType

    -- If we were already typing, send an update immediately
    if Bridge._isTyping then
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
