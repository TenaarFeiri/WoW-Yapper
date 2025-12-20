--[[
    Yapper by Sara Schulze Øverby, aka Tenaar Feiri, Arru/Arruh and a whole bunch of other names...
    Licence: Use, modify, distribute however you like, but give attribution. Thanks <3
    
    Yapper is meant to be a simple, no-interface works-out-of-the-box replacement for addons like EmoteSplitter.
    This is the main entry point where we kick things off.
]]

local YapperName, YapperTable = ...

-- Check for YapperTable. Something went wrong if it's not here.
if not YapperTable then
    -- Abort! Abort!
    return
end

-------------------------------------------------------------------------------------
-- INITIALISATION --

-- This runs once the player enters the world. 
-- We finish setting up the chat hooks here.
local function OnPlayerEnteringWorld()
    -- Initialise chat frame hooks.
    YapperTable.Chat:Init()
    
    if YapperTable.Debug then
        print("|cff00ff00" .. YapperName .. "|r: v" .. YapperTable.Core:GetYapperVersion() .. " loaded and ready. Happy RP-ing!")
    end
end

-- Create the main event-listening frame so the magic can happen.
YapperTable.Frames:Init()

-- Register for entering world so we can finalise everything.
YapperTable.Events:Register("PARENT_FRAME", "PLAYER_ENTERING_WORLD", OnPlayerEnteringWorld)
