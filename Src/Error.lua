local YapperName, YapperTable = ...
local Error = {}
YapperTable.Error = Error

local ErrorCode = {
    -- Argument errors
    ["BAD_STRING"] = "String is malformed and cannot be posted: %s",
    ["BAD_ARG"] = "Function %s expected a %s, but received a %s.",

    -- Frame Errors
    ["EVENT_REGISTER_MISSING_FRAME"] = "Attempted to register event %s to frame %s, but it does not exist.",
    ["EVENT_UNREGISTER_MISSING_FRAME"] = "Warning: Attempted to unregister event %s to frame %s, but it does not exist. This is not a bug or an important problem, but probably means something else unregistered it unexpectedly, which *could* be one.",
    ["EVENT_HANDLER_NOT_FUNCTION"] = "Handler %s for event %s is not a function.",
    ["MISSING_UTILS"] = "Missing YapperTable.Utils. This shouldn't be missing. Did it fail to load?",
    ["MISSING_CONFIG"] = "Missing YapperTable.Config. This shouldn't be missing. Did it fail to load?",
    ["MISSING_EVENTS"] = "Missing YapperTable.Events. This shouldn't be missing. Did it fail to load?",
    ["MISSING_FRAMES"] = "Missing YapperTable.Frames. This shouldn't be missing. Did it fail to load?",
    
    -- Bad variables
    ["NO_FRAME_ID"] = "No frame identifier provided for new frame %s",
    ["FRAME_ID_ABSENT"] = "Frame ID %s does not exist.",
    ["HOOKS_NOT_TABLE"] = "Frame hooks were not presented in table format for %s.",
    ["HOOK_NOT_FUNCTION"] = "Hook %s for frame %s is not a function.",
    
    -- Patching errors
    ["BAD_PATCH"] = "Failed to apply patch for %s.",

    -- Missing files
    ["PATCH_MISSING_COMPATLIB"] = "Missing YapperTable.CompatLib. This shouldn't be missing. Did it fail to load? CompatLib.lua must be loaded before any patches.",
    ["YAPPER_MISSING_COMPATLIB"] = "Yapper could not find CompatLib. This is most likely a bug, but just means compatibility patches for other addons will not be applied or work.",

    -- Chat errors
    ["CHAT_WHISPER_TRUNCATED"] = "Whisper message was truncated to %s characters due to being too long. You may recover the full post in your chat history (open chatbox & hit alt+up by default).",

    -- Generic errors
    ["UNKNOWN"] = "Yapper encountered an unknown error. String: %s || Error: %s"
}

-------------------------------------------------------------------------------------
-- FUNCTIONS --

local function PadMissingArgs(Str, ...)
    local Args = {...}
    local PlaceholderNum = select(2, string.gsub(Str, "%%s", ""))
    
    if #Args > PlaceholderNum then
        -- Too many Args: concatenate Extras into the last placeholder
        local Extras = {}
        for i = PlaceholderNum + 1, #Args do
            table.insert(Extras, tostring(Args[i]))
        end
        if PlaceholderNum > 0 then
            Args[PlaceholderNum] = (Args[PlaceholderNum] or "") .. " " .. table.concat(Extras, " ")
        end
        -- Trim Args to match placeholders
        for i = #Args, PlaceholderNum + 1, -1 do
            Args[i] = nil
        end
    end
    
    -- Pad missing Args with empty strings
    while #Args < PlaceholderNum do
        table.insert(Args, "")
    end
    
    return string.format(Str, unpack(Args))
end

--- Throws a formatted error and stops execution.
--- @param ErrCode string The key from the ErrorCode table.
--- @param ... any Arguments to be formatted into the error message.
function Error:Throw(ErrCode, ...)
    if not ErrorCode[ErrCode] then
        ErrCode = "UNKNOWN"
    end
    -- Print an error message (includes traceback for UNKNOWN codes)
    self:PrintError(ErrCode, ...)
    local msg = PadMissingArgs(ErrorCode[ErrCode], ...)
    if ErrCode == "UNKNOWN" then
        msg = msg .. "\n" .. (debug and debug.traceback("Traceback (most recent call):", 2) or "")
    end
    error(msg)
end

--- Prints a formatted error message to the chat frame without stopping execution.
--- @param ErrCode string The key from the ErrorCode table.
--- @param ... any Arguments to be formatted into the error message.
function Error:PrintError(ErrCode, ...)
    if not ErrorCode[ErrCode] then
        ErrCode = "UNKNOWN"
    end
    local formatted = PadMissingArgs(ErrorCode[ErrCode], ...)
    -- If UNKNOWN is used, append a short traceback to help locate the caller.
    if ErrCode == "UNKNOWN" and debug then
        formatted = formatted .. " -- " .. (debug.traceback(nil, 2) or "")
    end
    _G.YAPPER_UTILS:Print("Error: " .. formatted)
end

