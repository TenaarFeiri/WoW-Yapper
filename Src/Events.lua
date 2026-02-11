--[[
    Events.lua — Yapper 1.0.0
    Simple event bus: register/unregister handlers per Blizzard event.
]]

local YapperName, YapperTable = ...

local Events = {}
YapperTable.Events = Events

-- ---------------------------------------------------------------------------
-- Register / unregister
-- ---------------------------------------------------------------------------

--- Register a handler for a Blizzard event on a named frame.
function Events:Register(frameName, event, fn, handlerId)
    local frame = YapperTable.Frames.Container[frameName]
    if not frame then
        YapperTable.Error:Throw("EVENT_REGISTER_MISSING_FRAME", event, frameName)
        return
    end

    if not Events[event] then
        Events[event] = { Handlers = {} }
        frame:RegisterEvent(event)
        if not frame:GetScript("OnEvent") then
            frame:SetScript("OnEvent", function(_, e, ...)
                Events:Dispatch(e, ...)
            end)
        end
    end

    if handlerId then
        Events[event].Handlers[handlerId] = fn
    else
        table.insert(Events[event].Handlers, fn)
    end
end

--- Unregister all handlers for an event on a frame.
function Events:Unregister(frameName, event)
    local frame = YapperTable.Frames.Container[frameName]
    if not frame then return end
    if not Events[event] then return end
    frame:UnregisterEvent(event)
    Events[event] = nil
end

--- Unregister every event from every frame.
function Events:UnregisterAll()
    for event, data in pairs(Events) do
        if type(data) == "table" and data.Handlers then
            for _, frame in pairs(YapperTable.Frames.Container) do
                if frame.IsEventRegistered and frame:IsEventRegistered(event) then
                    frame:UnregisterEvent(event)
                end
            end
            Events[event] = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- Dispatch
-- ---------------------------------------------------------------------------

function Events:Dispatch(event, ...)
    local entry = Events[event]
    if not entry or not entry.Handlers then return end
    for _, handler in pairs(entry.Handlers) do
        if type(handler) == "function" then
            handler(...)
        end
    end
end
