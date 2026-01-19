-- Do event handlers, registration, and execution.
local YapperName, YapperTable = ...
local Events = {}
YapperTable.Events = Events

-------------------------------------------------------------------------------------
-- FUNCTIONS --

--- Register an event handler.
--- Throws an error and stops execution if the Frame doesn't exist.
--- @param FrameName string The key in YapperTable.Frames.Container to register the Event for.
--- @param Event string The Event to register.
--- @param Func function The function to call when the Event is triggered.
--- @param HandlerId string|boolean Optional! The ID of the handler.
function Events:Register(FrameName, Event, Func, HandlerId)
    local Frame = YapperTable.Frames.Container[FrameName]
    if not Frame then
        -- If the Frame doesn't exist, stop execution.
        YapperTable.Error:Throw("EVENT_REGISTER_MISSING_FRAME", Event, FrameName)
        return
    end

    if not Events[Event] then
        -- First time seeing this Event? Let's get it set up.
        Events[Event] = { Handlers = {} }
        Frame:RegisterEvent(Event)
        
        -- Set up the main OnEvent handler if it doesn't exist yet.
        if not Frame:GetScript("OnEvent") then
            Frame:SetScript("OnEvent", function(f, e, ...)
                Events:DoEvent(e, ...)
            end)
        end
    end

    -- Stick our new handler in the list.
    if HandlerId then
        Events[Event].Handlers[HandlerId] = Func
    else
        table.insert(Events[Event].Handlers, Func)
    end
end

--- Unregister handlers for an Event. Simple.
--- @param FrameName string
--- @param Event string
function Events:Unregister(FrameName, Event)
    local Frame = YapperTable.Frames.Container[FrameName]
    if not Frame then
        -- Complain if we can't find it.
        YapperTable.Error:PrintError("EVENT_UNREGISTER_MISSING_FRAME", Event, FrameName)
        return
    end

    if not Events[Event] then
        -- Nope.
        return
    end
    
    Frame:UnregisterEvent(Event)
    Events[Event] = nil
end

--- Unregister ALL events from ALL frames.
function Events:UnregisterAll()
    for Event, Data in pairs(Events) do
        if type(Data) == "table" and Data.Handlers then
            -- We need to find which frame registered this.
            -- In Yapper, most events are on the PARENT_FRAME.
            for FrameName, Frame in pairs(YapperTable.Frames.Container) do
                if Frame:IsEventRegistered(Event) then
                    Frame:UnregisterEvent(Event)
                end
            end
            Events[Event].Handlers = nil -- BREAK the chain fully
            Events[Event] = nil -- And remove the event itself from our list.
        end
    end
end

--- Execute events when triggered. 
--- This goes through and lets everyone registered know what happened.
--- @param Event string The Event to trigger.
--- @param ... any Arguments passed by WoW.
function Events:DoEvent(Event, ...)
    -- Does anyone care?
    if not Events[Event] or not Events[Event].Handlers then
        -- Nobody cares, do nothing.
        return
    end
    
    -- Call all the registered Event handlers one by one.
    for _, Handler in pairs(Events[Event].Handlers) do
        if type(Handler) == "function" then
            Handler(...) -- pass on the Arguments from Blizzard.
        else
            YapperTable.Error:PrintError("EVENT_HANDLER_NOT_FUNCTION", Event, Handler)
        end
    end
end

-------------------------------------------------------------------------------------
-- POST QUEUE VERIFICATION (v0.8.3+) --
-- These handlers listen for chat events and verify that our messages arrived
-- in the correct order by matching the text content.

--- Handler for chat message events. Verifies message arrived in expected order.
--- @param text string The message text
--- @param playerName string Sender name  
--- @param ... any Additional arguments from the chat event
local function OnChatMsgReceived(text, playerName, ...)
    -- Pass to Chat module for verification
    -- The event name tells us the chat type (SAY, EMOTE, etc.)
    if YapperTable.Chat and YapperTable.Chat.OnChatMessageReceived then
        -- Extract chat type from event name (e.g., "CHAT_MSG_SAY" -> "SAY")
        -- We'll get the actual event name from the last registered context
        YapperTable.Chat:OnChatMessageReceived(text, nil, playerName)
    end
end

--- Registers handlers for all chat types we support.
--- Called during addon init.
function Events:RegisterChatVerificationHandlers()
    -- All the chat types Yapper can split messages for.
    local chatTypes = {
        "CHAT_MSG_SAY",
        "CHAT_MSG_YELL",
        "CHAT_MSG_PARTY",
        "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID",
        "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_EMOTE",
        "CHAT_MSG_GUILD"
    }
    
    for _, eventName in ipairs(chatTypes) do
        Events:Register("PARENT_FRAME", eventName, OnChatMsgReceived, "YAPPER_QUEUE_VERIFY")
    end
    
    YapperTable.Utils:VerbosePrint("Chat verification handlers registered.")
end

--- Cleanup handler for logout/reload.
--- @param ... any Arguments from PLAYER_LEAVING_WORLD
local function OnPlayerLeavingWorld(...)
    -- Clear the queue to prevent ghost posts on re-login.
    if YapperTable.Chat then
        YapperTable.Chat:ClearOutboundQueue()
    end
    YapperTable.Utils:VerbosePrint("Player leaving world, queue cleared.")
end

--- Registers the logout cleanup handler.
function Events:RegisterLogoutHandler()
    Events:Register("PARENT_FRAME", "PLAYER_LEAVING_WORLD", OnPlayerLeavingWorld, "YAPPER_LOGOUT_CLEANUP")
end
