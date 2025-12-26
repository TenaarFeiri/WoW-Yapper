-- Parent frame for YapperTable. Initialises and gets passed into the primary table.
local YapperName, YapperTable = ...

local Frames = {} -- Functions for frame management.
local Container = {} -- Our frame container.
YapperTable.Frames = Frames
YapperTable.Frames.Container = Container

-------------------------------------------------------------------------------------
-- LOCAL FUNCTIONS --

local function SetFrameDefaultSettings(FrameIdentifier)
    -- Set defaults when creating a Frame.
    local Frame = Container[FrameIdentifier]
    if not Frame then
        -- complain if we can't find it.
        YapperTable.Error:PrintError("FRAME_ID_ABSENT", FrameIdentifier)
        return
    end
    -- Various code here to set defaults if we need them later.
end

-------------------------------------------------------------------------------------
-- GLOBAL FUNCTIONS --

function Frames:Init()
    -- This is our main Frame. It is pretty much where all the magic happens.
    -- First we need to make sure that we have loaded Yapper Events.
    if not YapperTable.Events then
        -- Abort!
        YapperTable.Error:Throw("MISSING_EVENTS")
        return
    end
    
    -- Create the main Event-listening Frame.
    local ParentName = YapperTable.Config.System.FRAME_ID_PARENT
    Container[ParentName] = CreateFrame("Frame", YapperName .. "EventFrame", UIParent)
end

function Frames:MakeNewFrame(FrameIdentifier, FrameName, Parent, Width, Height)
    -- If we don't have an ID, we can't track it. Complain.
    if not FrameIdentifier then
        YapperTable.Error:Throw("NO_FRAME_ID", FrameName or "Unknown")
        return
    end
    
    -- Create the Frame.
    local Frame = CreateFrame("Frame", FrameName, Parent)
    Frame:SetSize(Width, Height)
    Frame:SetPoint("CENTER", 0, 0)
    Frame:Show()
    
    Container[FrameIdentifier] = Frame
    SetFrameDefaultSettings(FrameIdentifier) -- Apply defaults.
    return Frame
end

function Frames:SetHooks(FrameIdentifier, Hooks, Secure)
    local Frame = Container[FrameIdentifier]
    
    if not Frame then
        -- Also check if it's a global Frame name like a ChatBox.
        if type(FrameIdentifier) == "string" and _G[FrameIdentifier] then
            Frame = _G[FrameIdentifier]
        else
            -- Frame doesn't exist. This doesn't necessarily mean it's a bug, but it's a bit suspicious.
            YapperTable.Error:PrintError("FRAME_ID_ABSENT", tostring(FrameIdentifier))
            return
        end
    end

    -- If Hooks isn't a table, we can't do anything.
    if type(Hooks) ~= "table" then
        YapperTable.Error:Throw("HOOKS_NOT_TABLE", tostring(FrameIdentifier))
        return
    end

    -- Set the Hooks.
    for HookName, HookFunction in pairs(Hooks) do
        -- If it's not a function, skip it.
        if type(HookFunction) ~= "function" then
            YapperTable.Error:Throw("HOOK_NOT_FUNCTION", tostring(FrameIdentifier), HookName)
        else
            if Secure then
                hooksecurefunc(Frame, HookName, HookFunction)
            else
                Frame:SetScript(HookName, HookFunction)
            end
        end
    end
end

--- Hides the main event-listening Frame.
function Frames:HideParent()
    local ParentName = YapperTable.Config.System.FRAME_ID_PARENT
    local Frame = Container[ParentName]
    if Frame then
        Frame:Hide()
    end
end
