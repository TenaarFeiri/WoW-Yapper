-- Bridges Yapper into Simply_RP_Typing_Tracker.
-- Because Yapper replaces the native EditBox, the original addon's hooks
-- never fire, so we drive its public API (StartTyping/StopTyping) directly
-- from Yapper's overlay focus/channel events.

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

local COMM_PREFIX  = "SRPTypingTracker"
local lastChatType = nil

local function IsLoaded()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("Simply_RP_Typing_Tracker")
    end
    ---@diagnostic disable-next-line: undefined-field
    return _G.SRPTypingTracker ~= nil
end

local function GetAPI()
    return _G.SRPTypingTracker and _G.SRPTypingTracker.API
end

-- ---------------------------------------------------------------------------
-- Signalling (via Simply_RP_Typing_Tracker's public API)
-- ---------------------------------------------------------------------------

local function SignalTyping(chatType)
    if not IsLoaded() then return end

    if YapperTable.Config.System.EnableTypingTrackerBridge == false then
        return
    end

    -- Override provided chatType if the overlay is active.
    if YapperTable.EditBox and YapperTable.EditBox.ChatType then
        chatType = YapperTable.EditBox.ChatType
    end

    chatType = chatType or "SAY"

    local api = GetAPI()
    if not api then return end

    -- Avoid redundant API calls if state hasn't changed.
    if Bridge._isTyping and lastChatType == chatType then
        return
    end

    YapperTable.Utils:VerbosePrint("TypingTrackerBridge: api.StartTyping -> " .. chatType)
    api.StartTyping("Yapper", chatType)
    Bridge._isTyping = true
    lastChatType = chatType
end

local function SignalNotTyping()
    if not IsLoaded() then return end

    local api = GetAPI()

    if YapperTable.Config.System.EnableTypingTrackerBridge == false then
        if api then api.StopTyping("Yapper") end
        Bridge._isTyping = false
        lastChatType = nil
        return
    end

    if Bridge._isTyping or lastChatType ~= nil then
        YapperTable.Utils:VerbosePrint("TypingTrackerBridge: api.StopTyping")
        Bridge._isTyping = false
        if api then api.StopTyping("Yapper") end
        lastChatType = nil
    end
end

local function SignalChannelChanged(newChatType)
    if not IsLoaded() then return end
    if InCombatLockdown() then SignalNotTyping() return end

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

    local api = GetAPI()
    if api and Bridge._isTyping then
        api.StartTyping("Yapper", newChatType)
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

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, addonName)
    if event == "PLAYER_LOGIN" or addonName == "Simply_RP_Typing_Tracker" then
        Bridge:UpdateState(nil)
    end
end)

-- ---------------------------------------------------------------------------
-- Debug Listener
-- ---------------------------------------------------------------------------
-- When debug mode is active, we listen to the SRPTypingTracker prefix to
-- monitor the actual network traffic (including what the external API sends).
local function OnCommReceived(prefix, message, distribution, sender)
    if YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        YapperTable.Utils:DebugPrint(string_format("TT Bridge (RECV from %s): %s", sender, message))
    end
end

if IsLoaded() then
    local AceComm = LibStub("AceComm-3.0", true)
    if AceComm then
        AceComm:RegisterComm(COMM_PREFIX, OnCommReceived)
    end
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
