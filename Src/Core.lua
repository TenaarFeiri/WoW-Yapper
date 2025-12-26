-- Define global addon tables and default settings.
local YapperName, YapperTable = ...

YapperTable.Debug = false -- True when debugging, false otherwise.
YapperTable.Core = {} -- Here is where the core functions live.
YapperTable.Configs = {
    Yapper = {
        VERBOSE = false
    }
    Chat = {
        USE_DELINEATORS = true   
    }
}
YapperTable.Defaults = { -- Create some default values for things.
    ID = {
        Frames = {
            ["Parent"] = "PARENT_FRAME"
        }
    },
    Chat = {
        CharacterLimit = 255,
        MaxHistoryLines = 15
    }
}

-------------------------------------------------------------------------------------
-- FUNCTIONS --

-- get the addon version as a string.
function YapperTable.Core:GetYapperVersion()
    return C_AddOns.GetAddOnMetadata(YapperName, "Version")
end

-- Different settings for things.
--- Set whether Yapper will be verbose or not!
function YapperTable.Core:SetVerbose(Bool)
    if type(Bool) ~= "boolean" then
        if YapperTable.Error then
            YapperTable.Error:PrintError("BAD_TYPE", "SetVerbose expected a boolean, got " .. type(Bool))
        else
            print("Yapper: SetVerbose expected a boolean, got " .. type(Bool))
        end
        return
    end
    YapperTable.Configs.Yapper.VERBOSE = Bool
end

function YapperTable.Core:GetVerbose()
    return YapperTable.Configs.Yapper.VERBOSE
end
