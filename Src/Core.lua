-- Define global addon tables and default settings.
local YapperName, YapperTable = ...

YapperTable.Debug = false -- True when debugging, false otherwise.
YapperTable.Core = {} -- Here is where the core functions live.

YapperTable.Defaults = { -- Create some default values for things.
    ID = {
        Frames = {
            ["Parent"] = "PARENT_FRAME"
        }
    },
    Chat = {
        CharacterLimit = 255 -- Blizzard's standard limit.
    }
}

-------------------------------------------------------------------------------------
-- FUNCTIONS --

-- get the addon version as a string.
function YapperTable.Core:GetYapperVersion()
    return C_AddOns.GetAddOnMetadata(YapperName, "Version")
end
