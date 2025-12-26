--[[
    Yapper by Sara Schulze Øverby, aka Tenaar Feiri, Arru/Arruh and a whole bunch of other names...
    Licence: Use, modify, distribute however you like, but give attribution. Thanks <3
    
    Yapper is meant to be a simple, no-interface works-out-of-the-box replacement for addons like EmoteSplitter.
    This is the main entry point where we kick things off.
]]

local YapperName, YapperTable = ...

-- This should never happen, but IF IT DOES, then it means we're dead
-- in the water. Without YapperTable, we can't do anything, and it means
-- something went very, very wrong during loading.
if not YapperTable then
    error((YapperName or "Yapper") .. ": YapperTable is missing. Yapper is disabled. Please report this to the developer.")
end

-- check for errors
if not YapperTable.Error then
    error((YapperName or "Yapper") .. ": YapperTable.Error is missing. Yapper needs error handling to function, and is therefore disabled.")
end

-- Check for compat lib, but we can work without it.
if not YapperTable.CompatLib then
    YapperTable.Error:PrintError("MISSING_COMPATLIB")
end

if not YapperTable.Config then
    YapperTable.Error:Throw("MISSING_CONFIG")
end

if not YapperTable.Events then
    YapperTable.Error:Throw("MISSING_EVENTS")
end

if not YapperTable.Frames then
    YapperTable.Error:Throw("MISSING_FRAMES")
end

-------------------------------------------------------------------------------------
-- INITIALISATION --

-- This runs once the player enters the world. 
-- We finish setting up the chat hooks here.
local function OnPlayerEnteringWorld()
    -- Initialise chat frame hooks.
    YapperTable.Chat:Init()
    if _G.YAPPER_UTILS then
        _G.YAPPER_UTILS:Print("v" .. C_AddOns.GetAddOnMetadata(YapperName, "Version") .. " loaded. Happy roleplaying!")
    end
end

-- Create the main event-listening frame so the magic can happen.
YapperTable.Frames:Init()

-- Register for entering world so we can finalise everything.
YapperTable.Events:Register("PARENT_FRAME", "PLAYER_ENTERING_WORLD", OnPlayerEnteringWorld)

function YapperTable:OverrideYapper(Bool)
    if type(Bool) ~= "boolean" then
            YapperTable.Error:PrintError("BAD_ARG", "OverrideYapper expected a boolean, got " .. type(Bool))
        return
    end
    YapperTable.YAPPER_DISABLED = Bool
    if Bool then
        -- If overridden then we unset and unregister everything and hand control back to Blizz.
        YapperTable.Events:UnregisterAll()
        YapperTable.Chat:DropPendingMessages()
        YapperTable.Chat:RestoreBlizzardDefaults()
        YapperTable.Frames:HideParent()
        if _G.YAPPER_UTILS then
            _G.YAPPER_UTILS:Print("|cffff0000Overridden|r. Control returned to Blizzard.")
        end
    else
        -- Re-initialise everything.
        YapperTable.Frames:Init()
        YapperTable.Chat:Init()
        if _G.YAPPER_UTILS then
            _G.YAPPER_UTILS:Print("|cff00ff00Enabled|r. Yapper is back in control.")
        end
    end
end

