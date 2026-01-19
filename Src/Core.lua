-- Define global addon tables and default settings.
local YapperName, YapperTable = ...

YapperTable.Core = {} -- Here is where the core functions live.

-- Centralised configuration table
YapperTable.Config = {
    System = {
        VERBOSE = false,
        FRAME_ID_PARENT = "PARENT_FRAME",
        RUN_ALL_PATCHES = true -- If true, all compatibility patches are run on EditBox show.
    },
    Chat = {
        USE_DELINEATORS = true,
        CHARACTER_LIMIT = 255,
        MAX_HISTORY_LINES = 15,
        DELINEATOR = " >>",
        PREFIX = ">> ",
        MIN_POST_INTERVAL = 1.0, -- Seconds between posts (anti-spam throttle).
        POST_TIMEOUT = 2,        -- Seconds to wait for server confirmation before giving up.
        -- Batching for SAY/YELL (need hardware events)
        BATCH_SIZE = 3,          -- Max chunks per Enter press for SAY/YELL
        BATCH_THROTTLE = 2.0,    -- Minimum seconds between SAY/YELL batch sends
        -- EMOTE queue (confirmation-based)
        STALL_TIMEOUT = 1.0      -- Seconds before showing continue prompt for EMOTE
    }
}

-------------------------------------------------------------------------------------
-- FUNCTIONS --

-- get the addon version as a string.
function YapperTable.Core:GetYapperVersion()
    return C_AddOns.GetAddOnMetadata(YapperName, "Version")
end

-------------------------------------------------------------------------------------
-- Settings Functions --

--- Set whether Yapper will be verbose or not!
function YapperTable.Core:SetVerbose(Bool)
    if type(Bool) ~= "boolean" then
            YapperTable.Error:PrintError("BAD_ARG", "SetVerbose", "boolean", type(Bool))
        return
    end
    YapperTable.Config.System.VERBOSE = Bool
    YapperTable.Utils:Print("Verbose mode " .. (Bool and "enabled." or "disabled."))
end
