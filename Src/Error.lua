--[[
    Error.lua — Yapper 1.0.0
    Centralised error codes, formatted printing, and fatal throws.
]]

local YapperName, YapperTable = ...

local Error = {}
YapperTable.Error = Error

-- ---------------------------------------------------------------------------
-- Error code catalogue
-- ---------------------------------------------------------------------------
local CODE = {
    -- Arguments
    BAD_STRING = "String is malformed and cannot be posted: %s",
    BAD_ARG    = "Function %s expected a %s, but received a %s.",

    -- Frames / events
    EVENT_REGISTER_MISSING_FRAME   = "Tried to register event %s on frame %s, but it doesn't exist.",
    EVENT_UNREGISTER_MISSING_FRAME = "Tried to unregister event %s on frame %s, but it doesn't exist.",
    EVENT_HANDLER_NOT_FUNCTION     = "Handler for event %s is not a function.",
    MISSING_UTILS   = "YapperTable.Utils is missing — did it fail to load?",
    MISSING_CONFIG  = "YapperTable.Config is missing — did it fail to load?",
    MISSING_EVENTS  = "YapperTable.Events is missing — did it fail to load?",
    MISSING_FRAMES  = "YapperTable.Frames is missing — did it fail to load?",

    -- Frames
    NO_FRAME_ID     = "No frame identifier provided for new frame %s.",
    FRAME_ID_ABSENT = "Frame ID %s does not exist.",
    HOOKS_NOT_TABLE    = "Hooks were not a table for frame %s.",
    HOOK_NOT_FUNCTION  = "Hook %s for frame %s is not a function.",

    -- Patches
    BAD_PATCH               = "Failed to apply patch for %s.",
    PATCH_MISSING_COMPATLIB = "CompatLib missing — patches will not work.",
    YAPPER_MISSING_COMPATLIB = "CompatLib not found; compatibility patches disabled.",

    -- Chat
    CHAT_WHISPER_TRUNCATED = "Whisper truncated to %s characters. Recover via chat history (Alt+Up).",

    -- Generic
    UNKNOWN = "Unknown error. String: %s || Detail: %s",
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Pad/trim variadic args to match the number of %s placeholders in `str`.
local function FormatSafe(str, ...)
    local args = { ... }
    local count = select(2, str:gsub("%%s", ""))

    -- Too many args — concatenate extras into the last slot.
    if #args > count and count > 0 then
        local extras = {}
        for i = count + 1, #args do extras[#extras + 1] = tostring(args[i]) end
        args[count] = (args[count] or "") .. " " .. table.concat(extras, " ")
        for i = #args, count + 1, -1 do args[i] = nil end
    end

    -- Too few args — pad with "".
    while #args < count do args[#args + 1] = "" end

    return string.format(str, unpack(args))
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Print a formatted error without halting execution.
function Error:PrintError(code, ...)
    local template = CODE[code] or CODE.UNKNOWN
    local msg = FormatSafe(template, ...)
    if code == "UNKNOWN" and debug then
        msg = msg .. " — " .. (debug.traceback(nil, 2) or "")
    end
    _G.YAPPER_UTILS:Print("|cFFFF4444Error:|r " .. msg)
end

--- Print a formatted error AND halt execution (error()).
function Error:Throw(code, ...)
    self:PrintError(code, ...)
    local template = CODE[code] or CODE.UNKNOWN
    local msg = FormatSafe(template, ...)
    if code == "UNKNOWN" and debug then
        msg = msg .. "\n" .. (debug.traceback("Traceback:", 2) or "")
    end
    error(msg)
end
