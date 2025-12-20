local YapperName, YapperTable = ...
local Error = {}
YapperTable.Error = Error

local ErrorCode = {
    -- String errors
    ["BAD_STRING"] = "String is malformed and cannot be posted: %s",

    -- Frame Errors
    ["EVENT_REGISTER_MISSING_FRAME"] = "Attempted to register event %s to frame %s, but it does not exist.",
    ["EVENT_UNREGISTER_MISSING_FRAME"] = "Attempted to unregister event %s to frame %s, but it does not exist.",
    
    -- Bad variables
    ["NO_FRAME_ID"] = "No frame identifier provided for new frame %s",
    ["FRAME_ID_ABSENT"] = "Frame ID %s does not exist.",
    ["HOOKS_NOT_TABLE"] = "Frame hooks were not presented in table format for %s.",
    ["HOOK_NOT_FUNCTION"] = "Hook %s for frame %s is not a function.",

    -- Generic errors
    ["UNKNOWN"] = "Yapper encountered an unknown error. String: %s || Error: %s",
    ["NO_EVENTS"] = "Missing YapperTable.Events. Is it loaded?"
}

-------------------------------------------------------------------------------------
-- FUNCTIONS --

-- something's wrong
function Error:PrintError(errCode, ...)
    if not ErrorCode[errCode] then
        -- but we apparently don't know what
        errCode = "UNKNOWN"
    end
    -- but if we do, print it in red.
    print("|cFFFF0000" .. YapperName .. " Error:|r " .. string.format(ErrorCode[errCode], ...))
end
