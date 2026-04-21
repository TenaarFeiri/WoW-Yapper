--[[
    Frames.lua
    Lightweight frame factory and container.
]]

local YapperName, YapperTable = ...

local Frame = {
    defined = true, -- Marker to prevent nil indexing when the module fails to load.
} -- Container for methods.
local EventFrames    = {}

local Container = {
    Events = {}
}

YapperTable.Frame = Frame
YapperTable.EventFrames           = EventFrames
YapperTable.EventFrames.Container = Container.Events -- Expose event frames externally

--- Create the main hidden event-listening frame.
function EventFrames:Init()
    if not YapperTable.Events then
        YapperTable.Error:Throw("MISSING_EVENTS")
        return
    end
    local id = YapperTable.Config.System.FRAME_ID_PARENT
    Container.Events[id] = CreateFrame("Frame", YapperName .. "EventFrame", UIParent)
end

--- Hide the main event frame (used during override/disable).
function EventFrames:HideParent()
    local f = Container.Events[YapperTable.Config.System.FRAME_ID_PARENT]
    if f then f:Hide() end
end

