--[[
    Utils.lua — Yapper 1.0.0
    Small utility belt: printing, string helpers.
]]

local YapperName, YapperTable = ...

local Utils = {}
YapperTable.Utils = Utils

local PREFIX = "|cFF00FF00" .. tostring(YapperName) .. "|r"

-- ---------------------------------------------------------------------------
-- Printing
-- ---------------------------------------------------------------------------

function Utils:Print(...)
    local args = { ... }
    for i = 1, #args do args[i] = tostring(args[i]) end
    print(PREFIX .. ": " .. table.concat(args, " "))
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
