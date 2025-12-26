-- Define global addon tables and default settings.
local YapperName, YapperTable = ...

YapperTable.Debug = false -- True when debugging, false otherwise.
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
        MIN_POST_INTERVAL = 0.5,
        INSTANT_SEND_LIMIT = 3 -- Maximum number of posts to send immediately. 3 is safe,
                               -- any more and we risk rate limit or desyncing.
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
    _G.YAPPER_UTILS:Print("Verbose mode " .. (Bool and "enabled." or "disabled."))
end
