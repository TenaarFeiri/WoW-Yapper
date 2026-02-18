--[[
    Small utility belt: printing, string helpers.
]]

local YapperName, YapperTable = ...

local Utils = {}
YapperTable.Utils = Utils

-- ---------------------------------------------------------------------------

local SENDER_PRESETS = {
    info    = "FFFFAA00",
    warn    = "FFFF4444",
    success = "FF00FF00",
    white   = "FFFFFFFF",
}

function Utils:SenderTag(preset)
    local color = SENDER_PRESETS[preset] or SENDER_PRESETS.white
    return ("|c%s%s:|r "):format(color, YapperName)
end

function Utils:Print(...)
    local args = { ... }

    -- Optional preset as first arg: Utils:Print("info", "message...")
    local prefix = YapperTable.Config.System.PREFIX and (YapperTable.Config.System.PREFIX .. ": ") or
        (YapperName .. ": ")
    if type(args[1]) == "string" and SENDER_PRESETS[args[1]] then
        local preset = table.remove(args, 1)
        prefix = ("|c%s%s:|r "):format(SENDER_PRESETS[preset], YapperName)
    end

    for i = 1, #args do args[i] = tostring(args[i]) end
    print(prefix .. table.concat(args, " "))
end

function Utils:VerbosePrint(...)
    if YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.VERBOSE then
        self:Print(...)
    end
end

function Utils:DebugPrint(...)
    if YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        self:Print("DEBUG:", ...)
    end
end

-- Expose globally — other addons and compat patches may use this.
_G.YAPPER_UTILS = Utils

-- ---------------------------------------------------------------------------
-- String helpers
-- ---------------------------------------------------------------------------

--- Strip leading and trailing whitespace.
function Utils:Trim(s)
    if type(s) ~= "string" then
        YapperTable.Error:PrintError("BAD_ARG", "Trim", "string", type(s))
        return ""
    end
    return s:match("^%s*(.-)%s*$")
end

--- Return the byte position of the start of the last word in `s`.
function Utils:FindLastWord(s)
    if type(s) ~= "string" then
        YapperTable.Error:PrintError("BAD_ARG", "FindLastWord", "string", type(s))
        return nil
    end
    return s:find("[^%s]+$")
end
