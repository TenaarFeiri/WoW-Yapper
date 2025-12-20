-- Parent frame for YapperTable. Initialises and gets passed into the primary table.
local YapperName, YapperTable = ...

local Frames = {} -- Functions for frame management.
local Container = {} -- Our frame container.
YapperTable.Frames = Frames
YapperTable.Frames.Container = Container

-------------------------------------------------------------------------------------
-- LOCAL FUNCTIONS --

local function SetFrameDefaultSettings(frameIdentifier)
    -- Set defaults when creating a frame.
    local frame = Container[frameIdentifier]
    if not frame then
        -- complain if we can't find it.
        YapperTable.Error:PrintError("FRAME_ID_ABSENT", frameIdentifier)
        return
    end
    -- Various code here to set defaults if we need them later.
end

-------------------------------------------------------------------------------------
-- GLOBAL FUNCTIONS --

function Frames:Init()
    -- This is our main frame. It is pretty much where all the magic happens.
    -- First we need to make sure that we have loaded Yapper Events.
    if not YapperTable.Events then
        -- Abort!
        YapperTable.Error:PrintError("NO_EVENTS")
        return
    end
    
    -- Create the main event-listening frame.
    local parentName = YapperTable.Defaults.ID.Frames["Parent"]
    Container[parentName] = CreateFrame("Frame", YapperName .. "EventFrame", UIParent)
end

function Frames:MakeNewFrame(frameIdentifier, frameName, parent, width, height)
    -- If we don't have an ID, we can't track it. Complain.
    if not frameIdentifier then
        YapperTable.Error:PrintError("NO_FRAME_ID", frameName or "Unknown")
        return
    end
    
    -- Create the frame.
    local frame = CreateFrame("Frame", frameName, parent)
    frame:SetSize(width, height)
    frame:SetPoint("CENTER", 0, 0)
    frame:Show()
    
    Container[frameIdentifier] = frame
    SetFrameDefaultSettings(frameIdentifier) -- Apply defaults.
    return frame
end

function Frames:SetHooks(frameIdentifier, hooks, secure)
    secure = secure or false -- If true, we are hooking secure functions.
    local frame = Container[frameIdentifier]
    
    if not frame then
        -- Also check if it's a global frame name like a ChatBox.
        if type(frameIdentifier) == "string" and _G[frameIdentifier] then
            frame = _G[frameIdentifier]
        else
            -- Frame doesn't exist. Complain.
            YapperTable.Error:PrintError("FRAME_ID_ABSENT", tostring(frameIdentifier))
            return
        end
    end

    -- If hooks isn't a table, we can't do anything.
    if type(hooks) ~= "table" then
        YapperTable.Error:PrintError("HOOKS_NOT_TABLE", tostring(frameIdentifier))
        return
    end

    -- Set the hooks.
    for hookName, hookFunction in pairs(hooks) do
        -- If it's not a function, skip it.
        if type(hookFunction) ~= "function" then
            YapperTable.Error:PrintError("HOOK_NOT_FUNCTION", tostring(frameIdentifier), hookName)
        else
            if secure then
                hooksecurefunc(frame, hookName, hookFunction)
            else
                frame:SetScript(hookName, hookFunction)
            end
        end
    end
end
