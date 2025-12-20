-- do event handlers, registration, and execution
local YapperName, YapperTable = ...
local Events = {}
YapperTable.Events = Events

-------------------------------------------------------------------------------------
-- FUNCTIONS --

--- Register an event handler.
--- @param frameName string The key in YapperTable.Frames.Container to register the event for.
--- @param event string The event to register.
--- @param func function The function to call when the event is triggered.
--- @param handlerId string|boolean Optional! The ID of the handler.
function Events:Register(frameName, event, func, handlerId)
    local frame = YapperTable.Frames.Container[frameName]
    if not frame then
        -- If the frame doesn't exist, do nothing but complain.
        YapperTable.Error:PrintError("EVENT_REGISTER_MISSING_FRAME", event, frameName)
        return
    end

    if not Events[event] then
        -- First time seeing this event? Let's get it set up.
        Events[event] = { handlers = {} }
        frame:RegisterEvent(event)
        
        -- Set up the main OnEvent handler if it doesn't exist yet.
        if not frame:GetScript("OnEvent") then
            frame:SetScript("OnEvent", function(f, e, ...)
                Events:DoEvent(e, ...)
            end)
        end
    end

    -- Stick our new handler in the list.
    if handlerId then
        Events[event].handlers[handlerId] = func
    else
        table.insert(Events[event].handlers, func)
    end
end

--- Unregister handlers for an event. Simple.
--- @param frameName string
--- @param event string
function Events:Unregister(frameName, event)
    local frame = YapperTable.Frames.Container[frameName]
    if not frame then
        -- complain if we can't find it.
        YapperTable.Error:PrintError("EVENT_UNREGISTER_MISSING_FRAME", event, frameName)
        return
    end

    if not Events[event] then
        -- nope
        return
    end
    
    frame:UnregisterEvent(event)
    -- Clean up handlers table
    if Events[event] and Events[event].handlers then
        for k, _ in pairs(Events[event].handlers) do
            Events[event].handlers[k] = nil
        end
    end
    Events[event] = nil
end

--- Execute events when triggered. 
--- This goes through and lets everyone registered know what happened.
--- @param event string The event to trigger.
--- @param ... any Arguments passed by WoW.
function Events:DoEvent(event, ...)
    -- does anyone care?
    if not Events[event] or not Events[event].handlers then
        -- nobody cares, do fuck-all
        return
    end
    
    -- call all the registered event handlers one by one.
    for _, handler in pairs(Events[event].handlers) do
        if type(handler) == "function" then
            handler(...) -- pass on the arguments from Blizzard.
        end
    end
end
