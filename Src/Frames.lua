--[[
    Frames.lua — Yapper 1.0.0
    Lightweight frame factory and container.
]]

local YapperName, YapperTable = ...

local Frames    = {}
local Container = {}

YapperTable.Frames           = Frames
YapperTable.Frames.Container = Container

--- Create the main hidden event-listening frame.
function Frames:Init()
    if not YapperTable.Events then
        YapperTable.Error:Throw("MISSING_EVENTS")
        return
    end
    local id = YapperTable.Config.System.FRAME_ID_PARENT
    Container[id] = CreateFrame("Frame", YapperName .. "EventFrame", UIParent)
end

--- Create and register an arbitrary frame.
function Frames:MakeNewFrame(id, name, parent, w, h)
    if not id then
        YapperTable.Error:Throw("NO_FRAME_ID", name or "Unknown")
        return
    end
    local f = CreateFrame("Frame", name, parent)
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:Show()
    Container[id] = f
    return f
end

--- Hide the main event frame (used during override/disable).
function Frames:HideParent()
    local f = Container[YapperTable.Config.System.FRAME_ID_PARENT]
    if f then f:Hide() end
end
